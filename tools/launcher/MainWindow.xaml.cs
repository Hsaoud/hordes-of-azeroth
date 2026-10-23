using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace HordesOfAzeroth.Launcher
{
    public partial class MainWindow : Window
    {
        const string NewIssueUrl = "https://github.com/jonhaldors/hordes-of-azeroth/issues/new";
        const string DiscordUrl = "https://discord.gg/zpYfsqh6Dn";
        static readonly TimeSpan UpdateInterval = TimeSpan.FromMinutes(15);
        static readonly TimeSpan MenuReopenGuard = TimeSpan.FromMilliseconds(300);
        const string FullRepairText = "The launcher checks every game file, puts back the ones that are missing or damaged and reloads the world. Your characters and unlocks are backed up first and stay as they are.";
        const string QuickRepairText = "Some game files were missing or damaged, so the launcher puts them back. Your characters and unlocks stay as they are.";

        enum LauncherState { Missing, NotInstalled, Installing, Ready, UpdateAvailable, Starting, Playing, Stopping }

        readonly GameFolder m_folder = GameFolder.Find();
        readonly LocalServer m_server;
        readonly GameClient m_game;
        readonly UpdateCheck m_updates;
        readonly LauncherSettings m_settings;
        readonly Installer m_installer;
        readonly NavBuilder m_nav;
        CancellationTokenSource m_background;
        NavProgress m_backgroundProgress;
        readonly DispatcherTimer m_updateTimer = new DispatcherTimer();
        readonly System.Drawing.Icon m_icon;
        System.Windows.Forms.NotifyIcon m_tray;
        LauncherState m_state;
        Manifest m_latest;
        List<ReleaseNote> m_notes = new List<ReleaseNote>();
        int m_notePage;
        bool m_quitting;
        CancellationTokenSource m_installCancel;
        bool m_updating;
        bool m_repairing;
        CoopSession m_coop;
        CancellationTokenSource m_coopCancel;

        public MainWindow()
        {
            InitializeComponent();
            m_server = new LocalServer(m_folder);
            m_game = new GameClient(m_folder);
            m_updates = new UpdateCheck(m_folder);
            m_settings = LauncherSettings.Load(m_folder);
            m_installer = new Installer(m_folder, m_server);
            m_nav = new NavBuilder(m_folder);
            m_icon = WindowNative.LoadOwnIcon(64);
            Icon = WindowNative.ToImageSource(m_icon);
            SourceInitialized += (s, e) => WindowNative.UseDarkTitleBar(this, Color.FromRgb(0x0C, 0x09, 0x09));
            Loaded += OnLoaded;
            Closing += OnClosing;
        }

        async void OnLoaded(object sender, RoutedEventArgs e)
        {
            Installer.RemoveOldLauncher();
            ClientFonts.Load(m_folder);
            TitleText.FontFamily = ClientFonts.Title;
            Tagline.FontFamily = ClientFonts.Body;
            LoadArt();
            CreateTray();

            m_latest = m_updates.LoadCached();
            ShowNotes(m_latest?.Notes);
            RefreshState();

            m_updateTimer.Interval = UpdateInterval;
            m_updateTimer.Tick += async (s, a) => await CheckForUpdatesAsync(false);
            m_updateTimer.Start();
            await CheckForUpdatesAsync(false);

            if (m_game.IsRunning)
                await WatchRunningGameAsync();
            else
                StartBackgroundBuild();
        }

        void LoadArt()
        {
            foreach (string candidate in new[] { Path.Combine(m_folder.LauncherData, "launcher-art.jpg"), Path.Combine(m_folder.LauncherData, "launcher-art.png") })
            {
                if (!File.Exists(candidate))
                    continue;
                BitmapImage image = new BitmapImage();
                image.BeginInit();
                image.CacheOption = BitmapCacheOption.OnLoad;
                image.UriSource = new Uri(candidate);
                image.EndInit();
                Art.Source = image;
                return;
            }
            Art.Source = new BitmapImage(new Uri("pack://application:,,,/art/background.jpg"));
        }

        void CreateTray()
        {
            m_tray = new System.Windows.Forms.NotifyIcon { Icon = m_icon, Text = "Hordes of Azeroth", Visible = true };
            m_tray.MouseClick += (s, e) =>
            {
                if (e.Button == System.Windows.Forms.MouseButtons.Left)
                    ShowFromTray();
            };
            System.Windows.Forms.ContextMenuStrip menu = new System.Windows.Forms.ContextMenuStrip();
            menu.Items.Add("Open launcher", null, (s, e) => ShowFromTray());
            menu.Items.Add("Quit", null, (s, e) => Dispatcher.Invoke(QuitFromTray));
            m_tray.ContextMenuStrip = menu;
        }

        public void ShowFromTray()
        {
            Dispatcher.Invoke(() =>
            {
                Show();
                if (WindowState == WindowState.Minimized)
                    WindowState = WindowState.Normal;
                Activate();
            });
        }

        void QuitFromTray()
        {
            if (m_state == LauncherState.Playing || m_state == LauncherState.Starting)
            {
                ShowFromTray();
                MessageBox.Show(this, "Close the game first. The launcher keeps the game's server running until then.", "Hordes of Azeroth");
                return;
            }
            m_quitting = true;
            Close();
        }

        void OnClosing(object sender, CancelEventArgs e)
        {
            if (m_quitting)
            {
                Shutdown();
                return;
            }
            if (m_state == LauncherState.Installing)
            {
                if (MessageBox.Show(this, "Stop installing? The launcher carries on where it stopped next time.", "Hordes of Azeroth", MessageBoxButton.YesNo) != MessageBoxResult.Yes)
                {
                    e.Cancel = true;
                    return;
                }
                m_installCancel?.Cancel();
            }
            if (m_state == LauncherState.Starting || m_state == LauncherState.Playing || m_state == LauncherState.Stopping)
            {
                e.Cancel = true;
                Hide();
                m_tray.ShowBalloonTip(4000, "Hordes of Azeroth", "The launcher keeps running in the tray while you play.", System.Windows.Forms.ToolTipIcon.None);
                return;
            }
            Shutdown();
        }

        void Shutdown()
        {
            m_coopCancel?.Cancel();
            m_coop?.Dispose();
            m_updateTimer.Stop();
            m_background?.Cancel();
            if (m_tray != null)
            {
                m_tray.Visible = false;
                m_tray.Dispose();
                m_tray = null;
            }
            Application.Current.Shutdown();
        }

        void RefreshState()
        {
            GameVersion installed = m_folder.InstalledVersion;
            InstalledText.Text = installed != null ? installed.PatchName + " installed" : "Not installed";

            if (m_state == LauncherState.Starting || m_state == LauncherState.Playing || m_state == LauncherState.Stopping || m_state == LauncherState.Installing)
                return;

            if (!m_folder.HasClient)
            {
                SetState(LauncherState.Missing, "Can't find World of Warcraft", "Put the launcher in your World of Warcraft 1.12.1 folder, next to WoW.exe.");
                return;
            }
            if (!IsInstalled())
            {
                if (!Installer.IsStockClient(m_folder))
                    SetState(LauncherState.Missing, "This client can't be used", "Hordes of Azeroth needs the English World of Warcraft 1.12.1 (build 5875) WoW.exe.");
                else if (m_installer.IsComplete)
                    SetState(LauncherState.NotInstalled, "Some game files are missing", "press Repair to put them back");
                else if (m_installer.CompletedSteps.Count > 0)
                    SetState(LauncherState.NotInstalled, "The install isn't finished", "press Continue to carry on where it stopped");
                else
                    SetState(LauncherState.NotInstalled, "Ready to install", "the first install takes a few minutes");
                return;
            }
            if (!m_updates.IsStandaloneCoop && m_latest?.Version != null && (m_latest.Version.IsNewerThan(installed) || m_installer.ChangedPackages(m_latest).Count > 0))
            {
                string size = m_latest.DownloadSize > 0 ? $"{m_latest.DownloadSize / 1048576.0:0.0} MB · " : "";
                SetState(LauncherState.UpdateAvailable, m_latest.Version.PatchName + " is ready", size + "your characters and unlocks stay");
                return;
            }
            SetState(LauncherState.Ready, "Ready to play", "");
            ShowBackgroundProgress();
        }

        bool IsInstalled()
        {
            if (m_folder.InstalledVersion == null || !File.Exists(m_folder.GameExe) || !File.Exists(Path.Combine(m_folder.ServerRun, "mangosd.exe")))
                return false;
            bool installedByLauncher = File.Exists(Path.Combine(m_folder.LauncherData, "install-steps.txt"));
            if (installedByLauncher && !m_installer.IsComplete)
                return false;
            NavGroup first = m_latest?.NavGroups.FirstOrDefault();
            return first == null || m_nav.IsGroupBuilt(first);
        }

        void SetState(LauncherState state, string status, string detail)
        {
            m_state = state;
            CoopChoices.IsEnabled = state == LauncherState.Ready;
            if (state == LauncherState.Playing)
                CancelCoopButton.IsEnabled = false;
            StatusText.Text = status;
            StatusText.Foreground = (Brush)FindResource(state == LauncherState.Missing ? "Problem" : "Text");
            StatusDetail.Text = string.IsNullOrEmpty(detail) ? "" : "   " + detail;
            StatusDot.Visibility = state == LauncherState.Ready || state == LauncherState.Playing ? Visibility.Visible : Visibility.Collapsed;
            bool busy = state == LauncherState.Starting || state == LauncherState.Stopping || state == LauncherState.Installing;
            Progress.IsIndeterminate = busy;
            Progress.Value = 0;
            Progress.Visibility = busy ? Visibility.Visible : Visibility.Hidden;
            switch (state)
            {
                case LauncherState.Missing:
                    PrimaryButton.Content = "Install";
                    PrimaryButton.IsEnabled = false;
                    break;
                case LauncherState.NotInstalled:
                    PrimaryButton.Content = m_installer.IsComplete ? "Repair" : m_installer.CompletedSteps.Count > 0 ? "Continue" : "Install";
                    PrimaryButton.IsEnabled = true;
                    break;
                case LauncherState.Installing:
                    PrimaryButton.Content = m_repairing ? "Repairing…" : m_updating ? "Updating…" : "Installing…";
                    PrimaryButton.IsEnabled = false;
                    break;
                case LauncherState.UpdateAvailable:
                    PrimaryButton.Content = "Update";
                    PrimaryButton.IsEnabled = true;
                    break;
                case LauncherState.Starting:
                    PrimaryButton.Content = "Starting…";
                    PrimaryButton.IsEnabled = false;
                    break;
                case LauncherState.Playing:
                    PrimaryButton.Content = "Playing";
                    PrimaryButton.IsEnabled = false;
                    break;
                case LauncherState.Stopping:
                    PrimaryButton.Content = "Closing…";
                    PrimaryButton.IsEnabled = false;
                    break;
                default:
                    PrimaryButton.Content = "Play";
                    PrimaryButton.IsEnabled = true;
                    break;
            }
        }

        void ShowProblem(string status, string detail)
        {
            StatusText.Text = status;
            StatusText.Foreground = (Brush)FindResource("Problem");
            StatusDetail.Text = "   " + detail;
            StatusDot.Visibility = Visibility.Collapsed;
            Progress.IsIndeterminate = false;
            Progress.Value = 0;
            Progress.Visibility = Visibility.Hidden;
        }

        async Task CheckForUpdatesAsync(bool userAsked)
        {
            if (m_updates.IsStandaloneCoop && UpdateCheck.LocalSource == null)
            {
                if (userAsked)
                    StatusDetail.Text = "   This co-op edition is updated with a complete co-op package.";
                return;
            }
            try
            {
                m_latest = await m_updates.FetchAsync();
                if (await RefreshLauncherFirstAsync(m_latest))
                    return;
                m_updates.PublishLatestVersion(m_latest);
                ShowNotes(m_latest.Notes);
                RefreshState();
                if (userAsked && m_state == LauncherState.Ready)
                    StatusDetail.Text = "   up to date";
            }
            catch (Exception e) when (e is System.Net.WebException || e is IOException || e is InvalidOperationException || e is ArgumentException || e is KeyNotFoundException || e is InvalidCastException)
            {
                if (m_latest == null)
                    ShowNotes(null);
                if (userAsked)
                    ShowProblem("Couldn't check for updates", UpdateProblem(e));
            }
        }

        async Task<bool> RefreshLauncherFirstAsync(Manifest manifest)
        {
            if (!IsInstalled() || (m_state != LauncherState.Ready && m_state != LauncherState.UpdateAvailable) || !m_installer.LauncherOutdated(manifest))
                return false;
            StatusText.Text = "Updating the launcher";
            StatusDetail.Text = "";
            await m_installer.RefreshLauncherAsync(manifest, CancellationToken.None);
            RestartLauncher();
            return true;
        }

        static string UpdateProblem(Exception e)
        {
            if (e is System.Net.WebException web && web.Response is System.Net.HttpWebResponse response)
            {
                if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
                    return "No release is published yet.";
                return $"GitHub answered with an error ({(int)response.StatusCode}). Try again in a moment.";
            }
            if (e is System.Net.WebException)
                return "Couldn't reach GitHub. Check your connection and try again.";
            return "The release information couldn't be read. Try again in a moment.";
        }

        void ShowNotes(List<ReleaseNote> notes)
        {
            if (notes == null || notes.Count == 0)
                notes = m_updates.LocalNotes();
            m_notes = notes.OrderByDescending(n => n.Version).ToList();
            m_notePage = 0;
            ShowNotePage();
        }

        void ShowNotePage()
        {
            NotesPanel.Children.Clear();
            NotesScroll.ScrollToTop();
            NotesPanel.Children.Add(new TextBlock
            {
                Text = "PATCH NOTES",
                FontSize = 11,
                FontWeight = FontWeights.Bold,
                Foreground = (Brush)FindResource("Accent"),
            });
            if (m_notes.Count == 0)
            {
                NotesPager.Visibility = Visibility.Collapsed;
                NotesPanel.Children.Add(Paragraph("Patch notes appear here once the launcher can reach GitHub.", (Brush)FindResource("Muted")));
                return;
            }
            ReleaseNote note = m_notes[m_notePage];
            NotesPanel.Children.Add(new TextBlock
            {
                Text = note.Version.PatchName,
                FontSize = 20,
                FontWeight = FontWeights.Bold,
                Foreground = (Brush)FindResource("Text"),
                Margin = new Thickness(0, 4, 0, 8),
            });
            foreach (string line in note.Text.Split('\n').Select(l => l.TrimEnd('\r')).Where(l => l.Trim().Length > 0))
                NotesPanel.Children.Add(NoteLine(line));
            ShowNotePager();
        }

        void ShowNotePager()
        {
            NotesPager.Visibility = m_notes.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
            OlderNotes.IsEnabled = m_notePage < m_notes.Count - 1;
            NewerNotes.IsEnabled = m_notePage > 0;
            NotePageText.Text = $"{m_notePage + 1} of {m_notes.Count}";
        }

        void OlderNotes_Click(object sender, RoutedEventArgs e)
        {
            if (m_notePage >= m_notes.Count - 1)
                return;
            m_notePage++;
            ShowNotePage();
        }

        void NewerNotes_Click(object sender, RoutedEventArgs e)
        {
            if (m_notePage <= 0)
                return;
            m_notePage--;
            ShowNotePage();
        }

        UIElement NoteLine(string line)
        {
            Brush colour = (Brush)FindResource("Text");
            string trimmed = line.TrimStart();
            if (trimmed.StartsWith("#### "))
                return NoteSubheading(trimmed.Substring(5).Trim());
            if (trimmed.StartsWith("### "))
                return NoteHeading(trimmed.Substring(4).Trim());
            if (!trimmed.StartsWith("- "))
                return NoteText(trimmed, colour);
            Grid row = new Grid { Margin = new Thickness(0, 0, 0, 6) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.Children.Add(new TextBlock { Text = "•", Foreground = colour, FontSize = 13 });
            TextBlock text = NoteText(trimmed.Substring(2), colour);
            text.Margin = new Thickness(0);
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            return row;
        }

        TextBlock NoteText(string text, Brush colour)
        {
            TextBlock block = Paragraph("", colour);
            bool afterOldValue = false;
            int at = 0;
            while (at < text.Length)
            {
                int strike = text.IndexOf("~~", at, StringComparison.Ordinal);
                int bold = text.IndexOf("**", at, StringComparison.Ordinal);
                int next = strike < 0 ? bold : bold < 0 ? strike : Math.Min(strike, bold);
                int close = next < 0 ? -1 : text.IndexOf(text.Substring(next, 2), next + 2, StringComparison.Ordinal);
                if (close < 0)
                {
                    block.Inlines.Add(new Run(text.Substring(at)));
                    break;
                }
                string between = text.Substring(at, next - at);
                if (between.Length > 0)
                    block.Inlines.Add(new Run(between));
                string inner = text.Substring(next + 2, close - next - 2);
                if (next == strike)
                {
                    block.Inlines.Add(new Run(inner) { Foreground = (Brush)FindResource("NoteOldValue") });
                    afterOldValue = true;
                }
                else
                {
                    bool isNewValue = afterOldValue && between.Trim().Length <= 2;
                    block.Inlines.Add(new Run(inner) { FontWeight = FontWeights.SemiBold, Foreground = isNewValue ? (Brush)FindResource("NoteNewValue") : colour });
                    afterOldValue = false;
                }
                at = close + 2;
            }
            return block;
        }

        TextBlock NoteHeading(string text)
        {
            return new TextBlock
            {
                Text = text.ToUpperInvariant(),
                FontSize = 14,
                FontWeight = FontWeights.Bold,
                Foreground = (Brush)FindResource("Accent"),
                Margin = new Thickness(0, 12, 0, 6),
            };
        }

        TextBlock NoteSubheading(string text)
        {
            return new TextBlock
            {
                Text = text.ToUpperInvariant(),
                FontSize = 11,
                FontWeight = FontWeights.Bold,
                Foreground = (Brush)FindResource("Text"),
                Margin = new Thickness(0, 6, 0, 4),
            };
        }

        static TextBlock Paragraph(string text, Brush colour)
        {
            return new TextBlock { Text = text, Foreground = colour, FontSize = 13, LineHeight = 19, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8) };
        }

        async void PrimaryButton_Click(object sender, RoutedEventArgs e)
        {
            if (m_state == LauncherState.UpdateAvailable)
            {
                await UpdateAsync();
                return;
            }
            if (m_state == LauncherState.Ready)
                await PlayAsync();
            else if (m_state == LauncherState.NotInstalled && m_installer.IsComplete)
                await RepairAsync(false);
            else if (m_state == LauncherState.NotInstalled)
                await InstallAsync();
        }

        async Task InstallAsync()
        {
            m_background?.Cancel();
            m_installCancel = new CancellationTokenSource();
            SetState(LauncherState.Installing, "Getting ready", "");
            ShowInstallCard(0);
            IProgress<InstallProgress> progress = new Progress<InstallProgress>(p =>
            {
                if (m_state != LauncherState.Installing)
                    return;
                ShowInstallCard(Array.IndexOf(Installer.Steps, p.Step));
                ShowStepProgress(p);
            });
            try
            {
                m_latest = await m_updates.FetchAsync();
                if (await m_installer.RefreshLauncherBeforeResumingAsync(m_latest, m_installCancel.Token))
                {
                    RestartLauncher();
                    return;
                }
                await m_installer.InstallAsync(m_latest, progress, m_installCancel.Token);
                if (m_latest.NavGroups.Count > 0)
                {
                    ShowInstallCard(Installer.Steps.Length);
                    await GetInstallPathsAsync(m_latest, m_installCancel.Token);
                }
                m_updates.PublishLatestVersion(m_latest);
                m_state = LauncherState.Ready;
                ShowNotes(m_latest.Notes);
                RefreshState();
                StartBackgroundBuild();
            }
            catch (OperationCanceledException)
            {
                await m_server.StopAsync();
            }
            catch (Exception e) when (!(e is OutOfMemoryException))
            {
                await m_server.StopAsync();
                m_state = LauncherState.NotInstalled;
                RefreshState();
                ShowProblem("The install stopped", e.Message);
            }
        }

        async Task UpdateAsync()
        {
            if (m_game.IsRunning)
            {
                ShowProblem("Close the game first", "the update replaces files the game has open");
                return;
            }
            Manifest manifest = m_latest;
            m_background?.Cancel();
            m_installCancel = new CancellationTokenSource();
            m_updating = true;
            string title = "Updating to " + manifest.Version.PatchName;
            SetState(LauncherState.Installing, "Getting ready", "");
            ShowStepsCard("UPDATE", title, "Your characters and unlocks are backed up first and stay as they are. You can close the launcher and come back; it carries on where it stopped.", Installer.UpdateSteps, 0);
            IProgress<InstallProgress> progress = new Progress<InstallProgress>(p =>
            {
                if (m_state != LauncherState.Installing)
                    return;
                ShowStepsCard("UPDATE", title, "Your characters and unlocks are backed up first and stay as they are. You can close the launcher and come back; it carries on where it stopped.", Installer.UpdateSteps, Array.IndexOf(Installer.UpdateSteps, p.Step));
                ShowStepProgress(p);
            });
            try
            {
                bool launcherChanged = await m_installer.UpdateAsync(manifest, progress, m_installCancel.Token);
                await GetInstallPathsAsync(manifest, m_installCancel.Token);
                m_updates.PublishLatestVersion(manifest);
                if (launcherChanged)
                {
                    RestartLauncher();
                    return;
                }
                m_updating = false;
                m_state = LauncherState.Ready;
                ShowNotes(manifest.Notes);
                RefreshState();
                StatusDetail.Text = $"   updated to {manifest.Version.PatchName}";
                StartBackgroundBuild();
            }
            catch (OperationCanceledException)
            {
                m_updating = false;
            }
            catch (Exception e) when (!(e is OutOfMemoryException))
            {
                m_updating = false;
                m_state = LauncherState.Ready;
                RefreshState();
                ShowProblem("The update stopped", e.Message);
            }
        }

        async Task RepairAsync(bool thorough)
        {
            if (m_game.IsRunning)
            {
                ShowProblem("Close the game first", "the repair replaces files the game has open");
                return;
            }
            m_background?.Cancel();
            m_installCancel = new CancellationTokenSource();
            m_repairing = true;
            string explanation = thorough ? FullRepairText : QuickRepairText;
            SetState(LauncherState.Installing, "Getting ready", "");
            ShowRepairCard(0, explanation);
            IProgress<InstallProgress> progress = new Progress<InstallProgress>(p =>
            {
                if (m_state != LauncherState.Installing)
                    return;
                ShowRepairCard(Array.IndexOf(Installer.RepairSteps, p.Step), explanation);
                ShowStepProgress(p);
            });
            try
            {
                await m_server.StopAsync();
                Manifest manifest = await LatestManifestAsync();
                await m_installer.RepairAsync(manifest, thorough, progress, m_installCancel.Token);
                await m_server.StopAsync();
                await GetInstallPathsAsync(manifest, m_installCancel.Token);
                m_updates.PublishLatestVersion(manifest);
                m_repairing = false;
                m_state = LauncherState.Ready;
                ShowNotes(manifest.Notes);
                RefreshState();
                if (m_state == LauncherState.Ready)
                    StatusDetail.Text = "   the game is repaired";
                StartBackgroundBuild();
            }
            catch (OperationCanceledException)
            {
                m_repairing = false;
                await m_server.StopAsync();
            }
            catch (Exception e) when (!(e is OutOfMemoryException))
            {
                m_repairing = false;
                await m_server.StopAsync();
                m_state = LauncherState.Ready;
                RefreshState();
                ShowProblem("The repair stopped", e.Message);
            }
        }

        async Task<Manifest> LatestManifestAsync()
        {
            try
            {
                return m_latest = await m_updates.FetchAsync();
            }
            catch (Exception e) when (m_latest != null && (e is System.Net.WebException || e is IOException))
            {
                return m_latest;
            }
        }

        void ShowRepairCard(int current, string explanation) =>
            ShowStepsCard("REPAIR", "Repairing Hordes of Azeroth", explanation, Installer.RepairSteps, current);

        void ShowStepProgress(InstallProgress p)
        {
            StatusText.Text = Installer.InProgress(p.Step);
            StatusDetail.Text = string.IsNullOrEmpty(p.Detail) ? "" : "   " + p.Detail;
            Progress.IsIndeterminate = p.Fraction < 0;
            if (p.Fraction >= 0)
                Progress.Value = p.Fraction;
        }

        void RestartLauncher()
        {
            string exe = Process.GetCurrentProcess().MainModule.FileName;
            string current = Path.Combine(Path.GetDirectoryName(exe), Installer.LauncherFileName);
            if (File.Exists(current))
                exe = current;
            string arguments = UpdateCheck.LocalSource != null ? "--source \"" + UpdateCheck.LocalSource + "\"" : "";
            m_quitting = true;
            m_tray.Visible = false;
            Process.Start(new ProcessStartInfo(exe, arguments) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(exe) });
            Application.Current.Shutdown();
        }

        void ShowInstallCard(int current)
        {
            NotesPanel.Children.Clear();
            NotesPager.Visibility = Visibility.Collapsed;
            NotesPanel.Children.Add(new TextBlock { Text = "FIRST INSTALL", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = (Brush)FindResource("Accent") });
            bool paths = current >= Installer.Steps.Length;
            NotesPanel.Children.Add(new TextBlock
            {
                Text = paths ? "Teaching monsters to find their way" : "Setting up Hordes of Azeroth",
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = (Brush)FindResource("Text"),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 4, 0, 8),
            });
            Brush text = (Brush)FindResource("Text");
            if (paths)
            {
                NotesPanel.Children.Add(Paragraph("Every zone gets a map of where creatures can walk, climb and fit. Monsters use it to chase you around trees, up ramps and through doorways instead of running into walls, and the horde uses it to spawn only where it can reach you, never inside a rock or on a rooftop.", text));
                if (m_latest != null && m_latest.NavGroups.All(g => g.Download != null))
                {
                    NotesPanel.Children.Add(Paragraph($"They come ready-made, a {m_latest.NavGroups.Sum(g => g.Download.Size) / 1048576} MB download for every zone.", text));
                }
                else
                {
                    NotesPanel.Children.Add(Paragraph("It's worked out from your own game files, one 533-yard square at a time. Westfall, The Barrens and Duskwood come first; the harder zones finish in the background while you play.", text));
                    NotesPanel.Children.Add(Paragraph("This is heavy work and only happens once. Your processor can sit at 100% and your fans may spin up until it's done. To use fewer cores, open the ••• menu next to Play and choose Monster path build speed.", text));
                }
            }
            else
            {
                NotesPanel.Children.Add(Paragraph("The launcher builds everything from your own World of Warcraft files. You can close it and come back; it carries on where it stopped.", text));
            }
            string[] checklist = Installer.Steps.Concat(new[] { "Monster paths" }).ToArray();
            for (int i = 0; i < checklist.Length; i++)
            {
                bool done = i < current;
                bool now = i == current;
                NotesPanel.Children.Add(new TextBlock
                {
                    Text = (done ? "✓  " : now ? "▸  " : "·  ") + checklist[i],
                    FontSize = 12.5,
                    FontWeight = now ? FontWeights.SemiBold : FontWeights.Normal,
                    Foreground = (Brush)FindResource(now ? "Text" : "Muted"),
                    Opacity = done || now ? 1 : 0.6,
                    Margin = new Thickness(0, i == 0 ? 6 : 2, 0, 2),
                });
            }
        }

        void ShowStepsCard(string kicker, string title, string explanation, string[] steps, int current)
        {
            NotesPanel.Children.Clear();
            NotesPager.Visibility = Visibility.Collapsed;
            NotesPanel.Children.Add(new TextBlock { Text = kicker, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = (Brush)FindResource("Accent") });
            NotesPanel.Children.Add(new TextBlock
            {
                Text = title,
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = (Brush)FindResource("Text"),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 4, 0, 8),
            });
            NotesPanel.Children.Add(Paragraph(explanation, (Brush)FindResource("Text")));
            for (int i = 0; i < steps.Length; i++)
            {
                bool done = i < current;
                bool now = i == current;
                NotesPanel.Children.Add(new TextBlock
                {
                    Text = (done ? "✓  " : now ? "▸  " : "·  ") + steps[i],
                    FontSize = 12.5,
                    FontWeight = now ? FontWeights.SemiBold : FontWeights.Normal,
                    Foreground = (Brush)FindResource(now ? "Text" : "Muted"),
                    Opacity = done || now ? 1 : 0.6,
                    Margin = new Thickness(0, i == 0 ? 6 : 2, 0, 2),
                });
            }
        }

        void AskBuildSpeedOnce()
        {
            if (!m_settings.BuildSpeedChosen)
                BuildSpeedWindow.Ask(this, m_settings);
        }

        async Task GetInstallPathsAsync(Manifest manifest, CancellationToken cancel)
        {
            List<NavGroup> downloads = manifest.NavGroups.Where(g => g.Download != null && !m_nav.IsGroupBuilt(g)).ToList();
            long total = downloads.Sum(g => g.Download.Size);
            long finished = 0;
            foreach (NavGroup group in downloads)
            {
                StatusText.Text = "Downloading monster paths";
                long before = finished;
                try
                {
                    await DownloadPathsAsync(group, new Progress<long>(bytes =>
                    {
                        if (m_state == LauncherState.Installing)
                            ShowPathDownloadProgress(before + bytes, total);
                    }), cancel);
                }
                catch (Exception e) when (IsDownloadProblem(e))
                {
                }
                finished += group.Download.Size;
            }
            NavGroup first = manifest.NavGroups.FirstOrDefault();
            if (first == null || m_nav.IsGroupBuilt(first))
                return;
            AskBuildSpeedOnce();
            StatusText.Text = first.Download != null
                ? "The download didn't work, so the launcher builds the monster paths for " + first.Name
                : "Building monster paths: " + first.Name;
            UseInstallBuildSpeed();
            await m_nav.BuildGroupAsync(first, new Progress<NavProgress>(n =>
            {
                if (m_state == LauncherState.Installing)
                    ShowInstallBuildProgress(n);
            }), cancel);
        }

        async Task DownloadPathsAsync(NavGroup group, IProgress<long> progress, CancellationToken cancel)
        {
            string zip = await m_installer.FetchAsync(group.Download.Url, group.Download.Sha256, progress.Report, cancel);
            await Task.Run(() => m_nav.InstallDownloaded(group, zip), cancel);
            File.Delete(zip);
        }

        static bool IsDownloadProblem(Exception e) => e is InvalidOperationException || e is InvalidDataException || e is IOException || e is UnauthorizedAccessException;

        void ShowPathDownloadProgress(long bytes, long total)
        {
            Progress.IsIndeterminate = false;
            Progress.Value = total > 0 ? (double)bytes / total : 0;
            StatusDetail.Text = $"   {bytes / 1048576.0:0.0} of {total / 1048576.0:0.0} MB";
        }

        void UseInstallBuildSpeed()
        {
            m_nav.Priority = ProcessPriorityClass.BelowNormal;
            m_nav.Workers = () => LauncherSettings.Workers(m_settings.InstallCores);
            m_nav.Paused = () => false;
        }

        void ShowInstallBuildProgress(NavProgress n)
        {
            Progress.IsIndeterminate = false;
            Progress.Value = n.Total > 0 ? (double)n.Done / n.Total : 0;
            StatusDetail.Text = $"   {n.Done} of {n.Total} areas on {CoresText(m_settings.InstallCores)}. High CPU use is expected and only happens once.";
        }

        static string CoresText(CoreShare share)
        {
            int cores = LauncherSettings.Workers(share);
            return cores == 1 ? "1 core" : cores + " cores";
        }

        void StartBackgroundBuild()
        {
            if (m_latest == null || !IsInstalled() || (m_background != null && !m_background.IsCancellationRequested))
                return;
            List<NavGroup> pending = m_latest.NavGroups.Skip(1).Where(g => !m_nav.IsGroupBuilt(g)).ToList();
            if (pending.Count == 0)
                return;
            if (IsVisible && pending.Any(g => g.Download == null))
                AskBuildSpeedOnce();
            m_background = new CancellationTokenSource();
            CancellationToken cancel = m_background.Token;
            m_nav.Priority = ProcessPriorityClass.BelowNormal;
            m_nav.Workers = () => LauncherSettings.Workers(m_settings.BackgroundCores);
            m_nav.Paused = () => !m_settings.BuildWhilePlaying && m_game.IsRunning;
            IProgress<NavProgress> progress = new Progress<NavProgress>(n =>
            {
                m_backgroundProgress = n;
                ShowBackgroundProgress();
            });
            Task.Run(async () =>
            {
                try
                {
                    foreach (NavGroup group in pending)
                        await GetBackgroundPathsAsync(group, progress, cancel);
                }
                catch (OperationCanceledException)
                {
                }
                catch (InvalidOperationException)
                {
                }
                Dispatcher.Invoke(() =>
                {
                    m_backgroundProgress = null;
                    ShowBackgroundProgress();
                });
            });
        }

        async Task GetBackgroundPathsAsync(NavGroup group, IProgress<NavProgress> progress, CancellationToken cancel)
        {
            if (group.Download != null)
            {
                int total = (int)Math.Max(1, group.Download.Size / 1048576);
                try
                {
                    await DownloadPathsAsync(group, new Progress<long>(bytes => progress.Report(new NavProgress
                    {
                        Group = group.Name,
                        Done = (int)Math.Min(total - 1, bytes / 1048576),
                        Total = total,
                        Downloading = true,
                    })), cancel);
                    return;
                }
                catch (Exception e) when (IsDownloadProblem(e))
                {
                }
            }
            await m_nav.BuildGroupAsync(group, progress, cancel);
        }

        void ShowBackgroundProgress()
        {
            if (m_state != LauncherState.Ready && m_state != LauncherState.Playing)
                return;
            NavProgress n = m_backgroundProgress;
            if (n == null || n.Done >= n.Total)
            {
                if (m_state == LauncherState.Ready)
                {
                    StatusDetail.Text = "";
                    Progress.Value = 0;
                    Progress.Visibility = Visibility.Hidden;
                }
                return;
            }
            StatusDetail.Text = n.Downloading
                ? $"   {n.Group}: downloading monster paths in the background, {n.Done} of {n.Total} MB"
                : $"   {n.Group}: building monster paths in the background, {n.Done} of {n.Total} areas on {CoresText(m_settings.BackgroundCores)}";
            Progress.IsIndeterminate = false;
            Progress.Value = (double)n.Done / n.Total;
            Progress.Visibility = Visibility.Visible;
        }

        async Task PlayAsync()
        {
            SetState(LauncherState.Starting, "Starting", "");
            Progress<string> progress = new Progress<string>(step => StatusDetail.Text = "   " + step);
            try
            {
                await RepairBeforePlayAsync();
                m_server.CoopEnabled = false;
                await StartServerAsync(progress);
                await m_server.EnsureAccountAsync("PLAYER", "player");
                m_game.Prepare(m_settings.Widescreen);
                await m_server.RemovePlayerGameMasterAsync();
                StatusDetail.Text = "   Starting the game";
                await m_game.StartAsync(CancellationToken.None);
            }
            catch (Exception e) when (!(e is OutOfMemoryException))
            {
                await m_server.StopAsync();
                m_state = LauncherState.Ready;
                RefreshState();
                ShowProblem("The game couldn't start", e.Message);
                return;
            }
            await WatchRunningGameAsync();
        }

        async Task RepairBeforePlayAsync()
        {
            if (m_latest == null || m_updates.IsStandaloneCoop)
                return;
            bool checking = true;
            bool repairing = false;
            IProgress<InstallProgress> progress = new Progress<InstallProgress>(p =>
            {
                if (!checking || m_state != LauncherState.Starting)
                    return;
                repairing |= p.Fixing;
                if (!repairing)
                {
                    StatusDetail.Text = "   " + Installer.InProgress(p.Step);
                    return;
                }
                ShowRepairCard(Array.IndexOf(Installer.RepairSteps, p.Step), QuickRepairText);
                ShowStepProgress(p);
            });
            bool repaired = await m_installer.RepairAsync(m_latest, false, progress, CancellationToken.None);
            checking = false;
            if (!repaired)
                return;
            ShowNotes(m_latest.Notes);
            SetState(LauncherState.Starting, "Starting", "");
        }

        async Task StartServerAsync(IProgress<string> progress)
        {
            try
            {
                await m_server.StartAsync(progress, CancellationToken.None);
            }
            catch (WorldDatabaseException) when (!m_folder.IsDevelopmentTree && !m_updates.IsStandaloneCoop)
            {
                StatusText.Text = "Reloading the world";
                StatusDetail.Text = "   the world database didn't match the server (about a minute)";
                ShowRepairCard(Installer.RepairSteps.Length - 1, QuickRepairText);
                await m_installer.ReloadWorldAsync(new Progress<InstallProgress>(_ => { }), CancellationToken.None);
                ShowNotes(m_latest?.Notes);
                SetState(LauncherState.Starting, "Starting", "");
                await m_server.StartAsync(progress, CancellationToken.None);
            }
        }

        async Task WatchRunningGameAsync()
        {
            SetState(LauncherState.Playing, m_coop != null ? "Playing together" : "Playing", m_coop != null ? "close the game to leave co-op" : "the game's server stops when you close the game");
            if (m_settings.KeepInTray)
                Hide();
            await m_game.WaitForAllToCloseAsync(CancellationToken.None);
            ShowFromTray();
            SetState(LauncherState.Stopping, "Closing", "saving and stopping the game's server");
            try
            {
                m_coop?.Dispose();
                if (m_coop == null || m_coop.IsHost)
                    await m_server.StopAsync();
            }
            finally
            {
                ResetCoop();
                m_state = LauncherState.Ready;
                RefreshState();
            }
        }

        async void HostCoop_Click(object sender, RoutedEventArgs e) => await StartCoopAsync(true);

        async void JoinCoop_Click(object sender, RoutedEventArgs e) => await StartCoopAsync(false);

        void ChooseJoinCoop_Click(object sender, RoutedEventArgs e)
        {
            HostCoopButton.Visibility = Visibility.Collapsed;
            ChooseJoinButton.Visibility = Visibility.Collapsed;
            CoopJoinForm.Visibility = Visibility.Visible;
            CoopHint.Text = "Paste the invitation copied by your friend, then join their game.";
            CoopInvitation.Focus();
        }

        void BackFromJoinCoop_Click(object sender, RoutedEventArgs e)
        {
            HostCoopButton.Visibility = Visibility.Visible;
            ChooseJoinButton.Visibility = Visibility.Visible;
            CoopJoinForm.Visibility = Visibility.Collapsed;
            CoopHint.Text = "Open a world for your friends, or join their invitation.";
        }

        async Task StartCoopAsync(bool host)
        {
            if (m_state != LauncherState.Ready || m_game.IsRunning)
                return;
            if (!host && string.IsNullOrWhiteSpace(CoopInvitation.Text))
            {
                CoopHint.Text = "Paste the invitation your friend copied from their game.";
                CoopInvitation.Focus();
                return;
            }
            string invitation = CoopInvitation.Text;
            m_coopCancel = new CancellationTokenSource();
            CancellationToken cancel = m_coopCancel.Token;
            m_coop = new CoopSession(m_folder, m_server);
            m_coop.StatusChanged += text => Dispatcher.BeginInvoke(new Action(() =>
            {
                if (m_coop == null)
                    return;
                CoopHint.Text = text;
                if (m_state == LauncherState.Playing)
                {
                    StatusDetail.Text = "   " + text;
                }
            }));
            SetState(LauncherState.Starting, host ? "Creating your game" : "Joining your friend", "");
            CoopChoices.Visibility = Visibility.Collapsed;
            CoopLobby.Visibility = Visibility.Visible;
            CoopCode.Visibility = Visibility.Collapsed;
            CopyCoopButton.Visibility = Visibility.Collapsed;
            CancelCoopButton.IsEnabled = true;
            CoopHint.Text = host ? "Preparing your camp…" : "Connecting to your friend's game…";
            CopyCoopButton.Content = "Copy invitation";
            try
            {
                if (host)
                {
                    m_server.CoopEnabled = true;
                    await m_server.StartAsync(new Progress<string>(text => CoopHint.Text = text), cancel);
                    string code = await m_coop.HostAsync(cancel);
                    cancel.ThrowIfCancellationRequested();
                    CoopCode.Text = code;
                    CoopCode.Visibility = Visibility.Visible;
                    CopyCoopButton.Visibility = Visibility.Visible;
                    CoopHint.Text = "Your game is open. Friends can join at any time using this invitation.";
                    StatusText.Text = "Starting your open game";
                    Progress.IsIndeterminate = false;
                    Progress.Visibility = Visibility.Hidden;

                }
                else
                    await m_coop.JoinAsync(invitation, cancel);
                cancel.ThrowIfCancellationRequested();
                CoopHint.Text = "Form your party in game. Mission invitations appear for everyone in your group.";
                m_game.Prepare(m_settings.Widescreen, m_coop.Account, m_coop.Password, true, m_coop.HeroProfile, m_coop.Invitation);
                await m_game.StartAsync(cancel);
                await WatchRunningGameAsync();
            }
            catch (Exception e) when (!(e is OutOfMemoryException))
            {
                m_coop?.Dispose();
                if (host)
                    await m_server.StopAsync();
                ResetCoop();
                m_state = LauncherState.Ready;
                RefreshState();
                if (!(e is OperationCanceledException))
                {
                    CoopHint.Text = e.Message;
                    ShowProblem("Co-op couldn't start", "You can try again below.");
                }
            }
        }

        void ResetCoop()
        {
            m_coop = null;
            m_coopCancel?.Dispose();
            m_coopCancel = null;
            m_server.CoopEnabled = false;
            CoopLobby.Visibility = Visibility.Collapsed;
            CoopChoices.Visibility = Visibility.Visible;
            BackFromJoinCoop_Click(null, null);
            CoopHint.Text = "Friends can join at any time. Co-op heroes are saved on the host's PC; rejoin the same host to continue.";
            CoopCode.Clear();
        }

        void CopyCoop_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Clipboard.SetText(CoopCode.Text);
                CopyCoopButton.Content = "Invitation copied!";
            }
            catch (System.Runtime.InteropServices.COMException)
            {
                CoopCode.SelectAll();
                CoopCode.Focus();
                CoopHint.Text = "Press Ctrl+C to copy your invitation.";
            }
        }

        void CancelCoop_Click(object sender, RoutedEventArgs e)
        {
            m_coopCancel?.Cancel();
            m_coop?.Dispose();
            CancelCoopButton.IsEnabled = false;
        }

        async void CheckForUpdates_Click(object sender, RoutedEventArgs e)
        {
            if (m_state == LauncherState.Ready || m_state == LauncherState.UpdateAvailable || m_state == LauncherState.Missing)
                StatusDetail.Text = "   checking…";
            await CheckForUpdatesAsync(true);
        }

        void OpenGameFolder_Click(object sender, RoutedEventArgs e) => OpenPath(m_folder.Root);

        void OpenLogs_Click(object sender, RoutedEventArgs e)
        {
            Directory.CreateDirectory(m_folder.ServerLogs);
            OpenPath(m_folder.ServerLogs);
        }

        void ReportBug_Click(object sender, RoutedEventArgs e)
        {
            if (SaveLogs())
                OpenUrl(NewIssueUrl);
        }

        void SaveLogs_Click(object sender, RoutedEventArgs e) => SaveLogs();

        bool SaveLogs()
        {
            try
            {
                string zip = LogBundle.Save(m_folder);
                Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + zip + "\"") { UseShellExecute = true });
                return true;
            }
            catch (Exception e) when (e is IOException || e is UnauthorizedAccessException)
            {
                ShowProblem("The logs couldn't be saved", e.Message);
                return false;
            }
        }

        void Discord_Click(object sender, RoutedEventArgs e) => OpenUrl(DiscordUrl);

        void MoreButton_Click(object sender, RoutedEventArgs e)
        {
            OptionsMenu.PlacementTarget = MoreButton;
            OptionsMenu.IsOpen = true;
        }

        async void OptionsMenu_Closed(object sender, RoutedEventArgs e)
        {
            await Task.Delay(MenuReopenGuard);
            MoreButton.IsHitTestVisible = true;
        }

        void OptionsMenu_Opened(object sender, RoutedEventArgs e)
        {
            MoreButton.IsHitTestVisible = false;
            ShowWindowMode();
            TrayItem.IsChecked = m_settings.KeepInTray;
            BuildItem.IsChecked = m_settings.BuildWhilePlaying;
            WidescreenItem.IsChecked = m_settings.Widescreen;
            WidescreenItem.ToolTip = "Widens the view to fit your screen's shape, from 16:9 to 21:9 and 32:9 ultrawide, so the world doesn't look zoomed in. Turn it off for the original 1.12 view.";
            RepairItem.Visibility = m_folder.IsDevelopmentTree ? Visibility.Collapsed : Visibility.Visible;
            RepairItem.IsEnabled = m_state == LauncherState.Ready || m_state == LauncherState.UpdateAvailable || (m_state == LauncherState.NotInstalled && m_installer.IsComplete);
        }

        async void RepairItem_Click(object sender, RoutedEventArgs e)
        {
            string question = "Repair checks every game file, downloads the ones that are missing or damaged and reloads the world. It takes a minute or two. Your characters and unlocks are backed up first and stay as they are.\n\nRepair the game now?";
            if (MessageBox.Show(this, question, "Hordes of Azeroth", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
                await RepairAsync(true);
        }

        void ShowWindowMode()
        {
            bool windowed = GameConfig.IsWindowed(m_folder);
            bool borderless = GameConfig.IsBorderless(m_folder);
            string resolution = GameConfig.Resolution(m_folder).Replace("x", "×");
            BorderlessItem.IsChecked = windowed && borderless;
            BorderlessItem.InputGestureText = resolution;
            BorderlessItem.ToolTip = "The game fills your screen without a title bar, like fullscreen, and Alt+Tab switches instantly.";
            WindowedItem.IsChecked = windowed && !borderless;
            WindowedItem.InputGestureText = resolution;
            FullscreenItem.IsChecked = !windowed;
        }

        void ChooseWindowMode(bool windowed, bool borderless)
        {
            GameConfig.SetWindowed(m_folder, windowed, borderless);
            ShowWindowMode();
        }

        void BorderlessItem_Click(object sender, RoutedEventArgs e) => ChooseWindowMode(true, true);

        void WindowedItem_Click(object sender, RoutedEventArgs e) => ChooseWindowMode(true, false);

        void FullscreenItem_Click(object sender, RoutedEventArgs e) => ChooseWindowMode(false, GameConfig.IsBorderless(m_folder));

        void WidescreenItem_Click(object sender, RoutedEventArgs e)
        {
            m_settings.Widescreen = WidescreenItem.IsChecked;
            m_settings.Save();
        }

        void BuildItem_Click(object sender, RoutedEventArgs e)
        {
            m_settings.BuildWhilePlaying = BuildItem.IsChecked;
            m_settings.Save();
        }

        void BuildSpeedItem_Click(object sender, RoutedEventArgs e) => BuildSpeedWindow.Ask(this, m_settings);

        void TrayItem_Click(object sender, RoutedEventArgs e)
        {
            m_settings.KeepInTray = TrayItem.IsChecked;
            m_settings.Save();
        }

        static void OpenPath(string path) => Process.Start(new ProcessStartInfo("explorer.exe", "\"" + path + "\"") { UseShellExecute = true });

        static void OpenUrl(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }
}
