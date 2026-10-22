using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace HordesOfAzeroth.Launcher
{
    sealed class CoopSession : IDisposable
    {
        readonly GameFolder m_folder;
        readonly LocalServer m_server;
        readonly JavaScriptSerializer m_json = new JavaScriptSerializer { MaxJsonLength = 16384 };
        readonly TaskCompletionSource<string> m_hosted = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        readonly TaskCompletionSource<bool> m_ready = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        Process m_process;
        bool m_disposed;
        bool m_joined;

        public bool IsHost { get; private set; }
        public string Account { get; private set; } = "PLAYER";
        public string Password { get; private set; }
        public string HeroProfile { get; private set; }
        public event Action<string> StatusChanged;

        public CoopSession(GameFolder folder, LocalServer server)
        {
            m_folder = folder;
            m_server = server;
        }

        public async Task<string> HostAsync(CancellationToken cancel)
        {
            IsHost = true;
            Password = RandomHex(8);
            await m_server.EnsureAccountAsync(Account, Password);
            Start("host", "");
            return await WithDeadline(m_hosted.Task, cancel);
        }

        public async Task JoinAsync(string code, CancellationToken cancel)
        {
            IsHost = false;
            Start("join", code.Trim());
            await WithDeadline(m_ready.Task, cancel);
        }

        public Task WaitForGuestAsync(CancellationToken cancel) => WaitForGuestCoreAsync(cancel);

        async Task WaitForGuestCoreAsync(CancellationToken cancel)
        {
            using (cancel.Register(() => m_ready.TrySetCanceled()))
                await m_ready.Task;
        }

        static async Task<T> WithDeadline<T>(Task<T> task, CancellationToken cancel)
        {
            Task delay = Task.Delay(TimeSpan.FromSeconds(70), cancel);
            if (await Task.WhenAny(task, delay) != task)
            {
                cancel.ThrowIfCancellationRequested();
                throw new TimeoutException("We couldn't reach your friend. Check your connection and try again with a new invitation.");
            }
            return await task;
        }

        void Start(string mode, string code)
        {
            string exe = Path.Combine(m_folder.Root, "tools", "hoa-coop.exe");
            if (!File.Exists(exe))
                throw new FileNotFoundException("The co-op component is missing. Install the complete co-op version of the game.");
            m_process = new Process
            {
                StartInfo = new ProcessStartInfo(exe)
                {
                    WorkingDirectory = m_folder.Root,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8,
                },
                EnableRaisingEvents = true,
            };
            m_process.Start();
            m_process.StandardError.ReadToEndAsync();
            m_process.StandardInput.WriteLine(m_json.Serialize(new
            {
                mode,
                code,
                version = CompatibilityVersion(),
                identity = IsHost ? RandomHex(32) : LoadIdentity(),
            }));
            m_process.StandardInput.Flush();
            ReadEventsAsync();
        }

        string CompatibilityVersion()
        {
            string build = Path.Combine(m_folder.LauncherData, "coop-build.txt");
            return File.Exists(build) ? File.ReadAllText(build).Trim() : (m_folder.InstalledVersion?.Full ?? "development") + "/coop-1";
        }

        async void ReadEventsAsync()
        {
            try
            {
                string line;
                while (!m_disposed && (line = await m_process.StandardOutput.ReadLineAsync()) != null)
                {
                    if (line.Length > 16384)
                        throw new InvalidDataException("The co-op component sent an invalid response.");
                    var message = m_json.Deserialize<Dictionary<string, object>>(line);
                    string kind = Value(message, "event");
                    switch (kind)
                    {
                        case "hosting":
                            m_hosted.TrySetResult(Value(message, "code"));
                            break;
                        case "guest":
                            if (!IsHost)
                                throw new InvalidDataException("Unexpected co-op response.");
                            StatusChanged?.Invoke("Your friend is joining…");
                            string account = Value(message, "account");
                            await m_server.EnsureAccountAsync(account, Value(message, "password"));
                            object profile = await m_server.ReadHeroProfileAsync(account);
                            if (!m_disposed)
                            {
                                m_process.StandardInput.WriteLine(m_json.Serialize(new { command = "admit", profile }));
                                m_process.StandardInput.Flush();
                            }
                            break;
                        case "ready":
                            Account = Value(message, "account");
                            Password = Value(message, "password");
                            HeroProfile = ProfileLua(message);
                            m_ready.TrySetResult(true);
                            m_joined = true;
                            break;
                        case "connected":
                            m_ready.TrySetResult(true);
                            m_joined = true;
                            break;
                        case "left":
                            if (m_joined)
                                StatusChanged?.Invoke("Your friend has left the game.");
                            break;
                        case "error":
                            Fail(Problem(Value(message, "code")));
                            break;
                    }
                }
                if (!m_disposed)
                    Fail("The connection to your friend has ended.");
            }
            catch (Exception e) when (!(e is OutOfMemoryException))
            {
                if (!m_disposed)
                    Fail(e.Message);
            }
        }

        static string Value(Dictionary<string, object> message, string key) => message.TryGetValue(key, out object value) ? value as string ?? "" : "";

        static string ProfileLua(Dictionary<string, object> message)
        {
            if (!message.TryGetValue("profile", out object value) || !(value is Dictionary<string, object> profile))
                return "BONK_STATS = nil;";
            var lua = new StringBuilder("BONK_STATS = { gold = ");
            lua.Append(Number(profile, "gold")).Append(", heroes = {");
            if (profile.TryGetValue("heroes", out object list) && list is System.Collections.IEnumerable heroes && !(list is string))
                foreach (object hero in heroes)
                {
                    var fields = hero as Dictionary<string, object>;
                    if (fields == null)
                        continue;
                    string name = Value(fields, "name");
                    if (name.Length < 2 || name.Length > 12 || !System.Text.RegularExpressions.Regex.IsMatch(name, @"\A[\p{L}']+\z"))
                        continue;
                    lua.Append("[\"").Append(name).Append("\"] = {");
                    foreach (string key in new[] { "played", "runs", "bestStage", "bestTime", "kills", "goldEarned" })
                        lua.Append(key).Append(" = ").Append(Number(fields, key)).Append(',');
                    lua.Append("},");
                }
            return lua.Append("} };").ToString();
        }

        static uint Number(Dictionary<string, object> fields, string key)
        {
            return fields.TryGetValue(key, out object value) && uint.TryParse(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture), out uint number) ? number : 0;
        }

        static string Problem(string code)
        {
            switch (code)
            {
                case "invalid-code": return "This invitation is incomplete or incorrect. Ask your friend to copy it again.";
                case "version-mismatch": return "You have different versions of the game. Update both copies and create a new invitation.";
                case "host-not-ready": return "Your friend's game isn't ready yet. Try again in a moment.";
                case "local-port-in-use": return "Another copy of the game is running. Close it before joining your friend.";
                case "room-full": return "This game already has two players. Ask your friend to create a new invitation when a place is available.";
                default: return "We couldn't connect to your friend. Check that their invitation is still open and that you are both connected to the Internet.";
            }
        }

        void Fail(string text)
        {
            if (m_disposed)
                return;
            var problem = new InvalidOperationException(text);
            m_hosted.TrySetException(problem);
            m_ready.TrySetException(problem);
            StatusChanged?.Invoke(text);
        }

        string LoadIdentity()
        {
            string directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HordesOfAzeroth");
            string file = Path.Combine(directory, "coop-identity.dat");
            Directory.CreateDirectory(directory);
            if (File.Exists(file))
            {
                try
                {
                    byte[] identity = ProtectedData.Unprotect(File.ReadAllBytes(file), null, DataProtectionScope.CurrentUser);
                    if (identity.Length == 32)
                        return BitConverter.ToString(identity).Replace("-", "");
                }
                catch (CryptographicException)
                {
                    throw new InvalidOperationException("Your co-op profile couldn't be opened on this Windows account.");
                }
            }
            byte[] bytes = new byte[32];
            using (var random = RandomNumberGenerator.Create())
                random.GetBytes(bytes);
            File.WriteAllBytes(file, ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser));
            return BitConverter.ToString(bytes).Replace("-", "");
        }

        static string RandomHex(int count)
        {
            byte[] bytes = new byte[count];
            using (var random = RandomNumberGenerator.Create())
                random.GetBytes(bytes);
            return BitConverter.ToString(bytes).Replace("-", "");
        }

        public void Dispose()
        {
            if (m_disposed)
                return;
            m_disposed = true;
            m_hosted.TrySetCanceled();
            m_ready.TrySetCanceled();
            if (m_process == null)
                return;
            try
            {
                if (!m_process.HasExited)
                {
                    m_process.StandardInput.WriteLine("{\"command\":\"stop\"}");
                    m_process.StandardInput.Close();
                    if (!m_process.WaitForExit(3000))
                        m_process.Kill();
                }
            }
            catch (InvalidOperationException) { }
            catch (IOException) { }
            finally { m_process.Dispose(); }
        }
    }
}
