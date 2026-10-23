using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace HordesOfAzeroth.Launcher
{
    sealed class WorldDatabaseException : InvalidOperationException
    {
        public WorldDatabaseException(string message) : base(message)
        {
        }
    }

    sealed class LocalServer
    {
        public const string RepairAdvice = "Choose Repair the game in the ••• menu next to Play.";
        static readonly string[] OutdatedWorldLines = { "database structure is not up to date", "Database `mangos` is missing the following migrations" };
        const string Host = "127.0.0.1";
        const int DatabasePort = 3306;
        const int LoginPort = 3724;
        const int WorldPort = 8085;
        static readonly string[] DatabaseLogin = { "-h", Host, "-P", DatabasePort.ToString(), "-u", "root", "-proot" };

        readonly GameFolder m_folder;
        Process m_world;
        Process m_login;
        Process m_database;
        public bool CoopEnabled { get; set; }

        public LocalServer(GameFolder folder)
        {
            m_folder = folder;
        }

        public bool StartedByUs => m_world != null || m_login != null || m_database != null;

        public async Task StartAsync(IProgress<string> progress, CancellationToken cancel)
        {
            ThrowIfPortTaken(DatabasePort, "its database");
            ThrowIfPortTaken(LoginPort, "its login server");
            ThrowIfPortTaken(WorldPort, "its world server");
            Directory.CreateDirectory(m_folder.ServerLogs);
            WriteServerConfig("mangosd");
            WriteServerConfig("realmd");

            if (!IsPortOpen(DatabasePort))
            {
                progress.Report("Starting the database");
                m_database = StartHidden(Path.Combine(m_folder.MariaDb, "bin", "mariadbd.exe"), m_folder.MariaDb,
                    $"\"--defaults-file={Path.Combine(m_folder.Config, "mariadb.ini")}\"",
                    $"\"--basedir={m_folder.MariaDb}\"",
                    $"\"--datadir={m_folder.MariaDbData}\"");
                await WaitForPortAsync(DatabasePort, m_database, TimeSpan.FromSeconds(60), "the database", cancel);
            }

            if (!IsPortOpen(LoginPort))
            {
                progress.Report("Starting the login server");
                m_login = StartHidden(Path.Combine(m_folder.ServerRun, "realmd.exe"), m_folder.ServerRun);
                await WaitForPortAsync(LoginPort, m_login, TimeSpan.FromSeconds(30), "the login server", cancel);
            }

            if (!IsPortOpen(WorldPort))
            {
                progress.Report("Loading the world");
                DateTime started = DateTime.UtcNow;
                m_world = StartHidden(Path.Combine(m_folder.ServerRun, "mangosd.exe"), m_folder.ServerRun, redirectInput: true);
                try
                {
                    await WaitForPortAsync(WorldPort, m_world, TimeSpan.FromMinutes(5), "the world server", cancel);
                }
                catch (InvalidOperationException) when (m_world.HasExited && WorldLogsMention(OutdatedWorldLines, started))
                {
                    throw new WorldDatabaseException("The world database doesn't match the server. " + RepairAdvice);
                }
            }
        }

        bool WorldLogsMention(string[] texts, DateTime sinceUtc)
        {
            foreach (string name in new[] { "Server.log", "DBErrors.log" })
            {
                string log = Path.Combine(m_folder.ServerLogs, name);
                if (!File.Exists(log) || File.GetLastWriteTimeUtc(log) < sinceUtc.AddSeconds(-2))
                    continue;
                using (FileStream stream = new FileStream(log, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (StreamReader reader = new StreamReader(stream))
                {
                    string written = reader.ReadToEnd();
                    if (texts.Any(t => written.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0))
                        return true;
                }
            }
            return false;
        }

        public async Task StopAsync()
        {
            if (m_world != null && !m_world.HasExited)
            {
                try
                {
                    m_world.StandardInput.WriteLine("server shutdown 0");
                    m_world.StandardInput.Flush();
                }
                catch (IOException)
                {
                }
                await WaitForExitAsync(m_world, TimeSpan.FromSeconds(30));
            }
            if (m_login != null && !m_login.HasExited)
                KillQuietly(m_login);
            if (m_database != null && !m_database.HasExited)
            {
                string admin = Path.Combine(m_folder.MariaDb, "bin", "mariadb-admin.exe");
                Process shutdown = StartHidden(admin, m_folder.MariaDb, DatabaseLogin.Concat(new[] { "shutdown" }).ToArray());
                await WaitForExitAsync(shutdown, TimeSpan.FromSeconds(30));
                await WaitForExitAsync(m_database, TimeSpan.FromSeconds(30));
            }
            m_world = m_login = m_database = null;
            await StopLeftoversAsync();
        }

        async Task StopLeftoversAsync()
        {
            foreach (Process world in OwnProcesses("mangosd"))
                KillQuietly(world);
            foreach (Process login in OwnProcesses("realmd"))
                KillQuietly(login);
            if (OwnProcesses("mariadbd").Any())
            {
                string admin = Path.Combine(m_folder.MariaDb, "bin", "mariadb-admin.exe");
                if (File.Exists(admin))
                {
                    Process shutdown = StartHidden(admin, m_folder.MariaDb, DatabaseLogin.Concat(new[] { "shutdown" }).ToArray());
                    await WaitForExitAsync(shutdown, TimeSpan.FromSeconds(30));
                }
                foreach (Process database in OwnProcesses("mariadbd"))
                    await WaitForExitAsync(database, TimeSpan.FromSeconds(30));
            }
        }

        IEnumerable<Process> OwnProcesses(string name)
        {
            string root = Path.GetFullPath(m_folder.Root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            foreach (Process process in Process.GetProcessesByName(name))
            {
                string path = null;
                try
                {
                    path = process.MainModule.FileName;
                }
                catch (System.ComponentModel.Win32Exception)
                {
                }
                catch (InvalidOperationException)
                {
                }
                if (path != null && path.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                    yield return process;
            }
        }

        void ThrowIfPortTaken(int port, string use)
        {
            foreach (PortOwners.Owner owner in PortOwners.Listening(port))
                if (!owner.IsInside(m_folder.Root))
                    throw new InvalidOperationException(
                        $"Port {port} is in use by {owner.Describe()}. Hordes of Azeroth needs it for {use}. Close that program (or stop its service) and try again.");
        }

        public bool DatabaseExists => Directory.Exists(Path.Combine(m_folder.MariaDbData, "mysql"));

        public async Task CreateDatabaseFilesAsync()
        {
            if (Directory.Exists(m_folder.MariaDbData))
                Directory.Delete(m_folder.MariaDbData, true);
            Directory.CreateDirectory(m_folder.MariaDbData);
            try
            {
                await RunToEndAsync(Path.Combine(m_folder.MariaDb, "bin", "mariadb-install-db.exe"), m_folder.MariaDb,
                    $"\"--datadir={m_folder.MariaDbData}\"", "--password=root");
            }
            catch (InvalidOperationException failure)
            {
                string serverLog = DatabaseErrorLogLine();
                try
                {
                    Directory.Delete(m_folder.MariaDbData, true);
                }
                catch (IOException)
                {
                }
                catch (UnauthorizedAccessException)
                {
                }
                throw serverLog == null ? failure : new InvalidOperationException($"{failure.Message} Database log: {serverLog}", failure);
            }
        }

        string DatabaseErrorLogLine()
        {
            if (!Directory.Exists(m_folder.MariaDbData))
                return null;
            foreach (string log in Directory.GetFiles(m_folder.MariaDbData, "*.err"))
            {
                string line = File.ReadAllLines(log).Select(l => l.Trim()).LastOrDefault(l => l.IndexOf("ERROR", StringComparison.OrdinalIgnoreCase) >= 0);
                if (line != null)
                    return line;
            }
            return null;
        }

        public async Task StartDatabaseOnlyAsync(CancellationToken cancel)
        {
            ThrowIfPortTaken(DatabasePort, "its database");
            if (IsPortOpen(DatabasePort))
                return;
            m_database = StartHidden(Path.Combine(m_folder.MariaDb, "bin", "mariadbd.exe"), m_folder.MariaDb,
                $"\"--defaults-file={Path.Combine(m_folder.Config, "mariadb.ini")}\"",
                $"\"--basedir={m_folder.MariaDb}\"",
                $"\"--datadir={m_folder.MariaDbData}\"");
            await WaitForPortAsync(DatabasePort, m_database, TimeSpan.FromSeconds(60), "the database", cancel);
        }

        public Task RunSqlFileAsync(string database, string file)
        {
            string source = "source " + file.Replace('\\', '/');
            List<string> arguments = DatabaseLogin.ToList();
            if (database != null)
                arguments.Add(database);
            arguments.Add("-e");
            arguments.Add("\"" + source + "\"");
            return RunToEndAsync(Path.Combine(m_folder.MariaDb, "bin", "mariadb.exe"), m_folder.MariaDb, arguments.ToArray());
        }

        public async Task RemovePlayerGameMasterAsync()
        {
            if (m_folder.IsDevelopmentTree)
                return;
            await QueryAsync("realmd", "DELETE FROM account_access WHERE id IN (SELECT id FROM account WHERE username = 'PLAYER')");
        }

        public async Task EnsureAccountAsync(string account, string password)
        {
            if (!Regex.IsMatch(account, @"\A(?:PLAYER|COOP[0-9A-F]{12})\z") || !Regex.IsMatch(password, @"\A[A-Z0-9]{1,16}\z", RegexOptions.IgnoreCase))
                throw new InvalidDataException("Invalid co-op profile.");
            string exists = await QueryAsync("realmd", $"SELECT COUNT(*) FROM account WHERE username = '{account}'");
            if (exists.Trim() == "0")
                await RunConsoleAsync($"account create {account} {password}");
            await RunConsoleAsync($"account set password {account} {password} {password}");
            if (CoopEnabled || account != "PLAYER" || !m_folder.IsDevelopmentTree)
                await QueryAsync("realmd", $"DELETE FROM account_access WHERE id IN (SELECT id FROM account WHERE username = '{account}')");
            if ((await QueryAsync("realmd", $"SELECT COUNT(*) FROM account WHERE username = '{account}'")).Trim() != "1")
                throw new InvalidOperationException("Your co-op profile couldn't be prepared. Please try hosting again.");
        }

        public async Task<string> QueryAsync(string database, string sql)
        {
            List<string> arguments = DatabaseLogin.ToList();
            arguments.AddRange(new[] { "-N", "-B", database, "-e", "\"" + sql.Replace("\"", "\\\"") + "\"" });
            return await RunToEndAsync(Path.Combine(m_folder.MariaDb, "bin", "mariadb.exe"), m_folder.MariaDb, arguments.ToArray());
        }

        public async Task<object> ReadHeroProfileAsync(string account)
        {
            if (!Regex.IsMatch(account, @"\ACOOP[0-9A-F]{12}\z"))
                throw new InvalidDataException("Invalid co-op profile.");
            string goldText = await QueryAsync("characters", $"SELECT COALESCE(b.gold, 0) FROM realmd.account a LEFT JOIN bonk_account b ON b.account = a.id WHERE a.username = '{account}'");
            uint.TryParse(goldText.Trim(), out uint gold);
            string rows = await QueryAsync("characters", $"SELECT c.name, c.played_time_total, COALESCE(s.runs, 0), COALESCE(s.best_stage, 0), COALESCE(s.best_time_sec, 0), COALESCE(s.kills, 0), COALESCE(s.gold_earned, 0) FROM realmd.account a JOIN characters c ON c.account = a.id LEFT JOIN bonk_character_stats s ON s.guid = c.guid WHERE a.username = '{account}' ORDER BY c.guid LIMIT 10");
            var heroes = new List<Dictionary<string, object>>();
            foreach (string row in rows.Split('\n'))
            {
                string[] cells = row.TrimEnd('\r').Split('\t');
                if (cells.Length != 7)
                    continue;
                var hero = new Dictionary<string, object> { ["name"] = cells[0] };
                string[] keys = { "played", "runs", "bestStage", "bestTime", "kills", "goldEarned" };
                for (int i = 0; i < keys.Length; i++)
                {
                    uint.TryParse(cells[i + 1], out uint number);
                    hero[keys[i]] = number;
                }
                heroes.Add(hero);
            }
            return new { gold, heroes };
        }

        public Task BackUpAsync(string file, params string[] databases)
        {
            List<string> arguments = DatabaseLogin.ToList();
            arguments.AddRange(new[] { "--single-transaction", $"\"--result-file={file}\"", "--databases" });
            arguments.AddRange(databases);
            return RunToEndAsync(Path.Combine(m_folder.MariaDb, "bin", "mariadb-dump.exe"), m_folder.MariaDb, arguments.ToArray());
        }

        public async Task RunConsoleAsync(string command)
        {
            if (m_world == null || m_world.HasExited)
                throw new InvalidOperationException("The world server isn't running.");
            m_world.StandardInput.WriteLine(command);
            m_world.StandardInput.Flush();
            await Task.Delay(1500);
        }

        static async Task<string> RunToEndAsync(string exe, string workingDirectory, params string[] arguments)
        {
            ProcessStartInfo info = new ProcessStartInfo(exe, string.Join(" ", arguments))
            {
                WorkingDirectory = workingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            using (Process process = Process.Start(info))
            {
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                while (!process.HasExited)
                    await Task.Delay(100);
                string text = await output;
                string problem = await error;
                if (process.ExitCode != 0)
                    throw new InvalidOperationException($"{Path.GetFileName(exe)} failed (exit code 0x{process.ExitCode:X}): {Details(problem, text)}");
                return text;
            }
        }

        static string Details(string error, string output)
        {
            string line = Lines(error).FirstOrDefault(l => l.StartsWith("ERROR", StringComparison.OrdinalIgnoreCase))
                ?? Lines(error).FirstOrDefault(l => !l.StartsWith("WARNING") && !l.StartsWith("---"))
                ?? Lines(output).LastOrDefault();
            return line ?? "no details";
        }

        static IEnumerable<string> Lines(string text)
        {
            return (text ?? "").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0);
        }

        void WriteServerConfig(string name)
        {
            string dist = Path.Combine(m_folder.ServerRun, name + ".conf.dist");
            string overrides = Path.Combine(m_folder.Config, name + ".overrides.conf");
            string target = Path.Combine(m_folder.ServerRun, name + ".conf");
            if (!File.Exists(dist) || !File.Exists(overrides))
                return;

            List<string> lines = File.ReadAllLines(dist).ToList();
            Regex setting = new Regex(@"^\s*([\w.]+)\s*=");
            foreach (string line in File.ReadAllLines(overrides))
            {
                Match match = setting.Match(line);
                if (!match.Success)
                    continue;
                Regex key = new Regex(@"^\s*" + Regex.Escape(match.Groups[1].Value) + @"\s*=");
                int index = lines.FindIndex(l => key.IsMatch(l));
                if (index < 0)
                    throw new InvalidDataException($"{overrides} sets {match.Groups[1].Value}, which {dist} does not define.");
                lines[index] = line.Trim();
            }
            if (name == "mangosd")
            {
                SetConfigLine(lines, "Bonk.Coop", CoopEnabled ? "1" : "0");
                if (CoopEnabled)
                {
                    SetConfigLine(lines, "AllowTwoSide.Interaction.Group", "1");
                    SetConfigLine(lines, "AllowTwoSide.Interaction.Chat", "1");
                    SetConfigLine(lines, "MapUpdate.Instanced.UpdateThreads", "0");
                    SetConfigLine(lines, "MapUpdate.ObjectsUpdate.MaxThreads", "1");
                    SetConfigLine(lines, "MapUpdate.VisibilityUpdate.MaxThreads", "1");
                    SetConfigLine(lines, "PlayerLimit", "0");
                }
            }
            File.WriteAllLines(target, lines);
        }

        static void SetConfigLine(List<string> lines, string key, string value)
        {
            Regex match = new Regex(@"^\s*" + Regex.Escape(key) + @"\s*=");
            lines.RemoveAll(line => match.IsMatch(line));
            lines.Add(key + " = " + value);
        }

        static Process StartHidden(string exe, string workingDirectory, params string[] arguments)
        {
            return StartHidden(exe, workingDirectory, false, arguments);
        }

        static Process StartHidden(string exe, string workingDirectory, bool redirectInput, params string[] arguments)
        {
            if (!File.Exists(exe))
                throw new FileNotFoundException($"{Path.GetFileName(exe)} is missing. {RepairAdvice}", exe);
            ProcessStartInfo info = new ProcessStartInfo(exe, string.Join(" ", arguments))
            {
                WorkingDirectory = workingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = redirectInput,
                RedirectStandardOutput = redirectInput,
                RedirectStandardError = redirectInput,
            };
            Process process = Process.Start(info);
            if (redirectInput)
            {
                process.OutputDataReceived += (s, e) => { };
                process.ErrorDataReceived += (s, e) => { };
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            return process;
        }

        static bool IsPortOpen(int port)
        {
            using (TcpClient client = new TcpClient())
            {
                try
                {
                    return client.ConnectAsync(Host, port).Wait(500) && client.Connected;
                }
                catch (AggregateException)
                {
                    return false;
                }
            }
        }

        async Task WaitForPortAsync(int port, Process process, TimeSpan timeout, string what, CancellationToken cancel)
        {
            Stopwatch clock = Stopwatch.StartNew();
            while (!IsPortOpen(port))
            {
                cancel.ThrowIfCancellationRequested();
                if (process.HasExited)
                    throw new InvalidOperationException($"{CapitalFirst(what)} stopped with code {process.ExitCode}. See {Path.Combine(m_folder.ServerLogs, "Server.log")}.");
                if (clock.Elapsed > timeout)
                    throw new TimeoutException($"{CapitalFirst(what)} did not start within {timeout.TotalSeconds:0} seconds.");
                await Task.Delay(500, cancel);
            }
        }

        static async Task WaitForExitAsync(Process process, TimeSpan timeout)
        {
            Stopwatch clock = Stopwatch.StartNew();
            while (!process.HasExited && clock.Elapsed < timeout)
                await Task.Delay(250);
            if (!process.HasExited)
                KillQuietly(process);
        }

        static void KillQuietly(Process process)
        {
            try
            {
                process.Kill();
                process.WaitForExit(5000);
            }
            catch (InvalidOperationException)
            {
            }
            catch (System.ComponentModel.Win32Exception)
            {
            }
        }

        static string CapitalFirst(string text) => char.ToUpperInvariant(text[0]) + text.Substring(1);
    }
}
