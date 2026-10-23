using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;

namespace HordesOfAzeroth.Launcher
{
    static class LogBundle
    {
        const long MaxBytesPerFile = 2 * 1024 * 1024;
        const int NewestCrashes = 3;
        static readonly string[] SkippedLogs = { "Chat.log", "WoWChatLog.txt", "coop-invitation.txt" };

        public static string Save(GameFolder folder)
        {
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            string zip = Path.Combine(desktop, $"Hordes of Azeroth logs {DateTime.Now:yyyy-MM-dd HH.mm}.zip");
            if (File.Exists(zip))
                File.Delete(zip);
            using (ZipArchive archive = ZipFile.Open(zip, ZipArchiveMode.Create))
            {
                AddText(archive, "about.txt", About(folder));
                foreach (string file in Logs(folder.ServerLogs, "*.log"))
                    AddTail(archive, "server/" + Path.GetFileName(file), file);
                foreach (string file in Logs(Path.Combine(folder.Root, "Logs"), "*.*"))
                    AddTail(archive, "client/" + Path.GetFileName(file), file);
                foreach (string file in Logs(Path.Combine(folder.Root, "Logs", "wow_turbo"), "*.log").OrderByDescending(File.GetLastWriteTimeUtc).Take(1))
                    AddTail(archive, "client/wow_turbo/" + Path.GetFileName(file), file);
                foreach (string file in NewestCrashFiles(folder))
                    AddTail(archive, "crashes/" + Path.GetFileName(file), file);
                foreach (string file in Logs(folder.LauncherData, "*.txt"))
                    AddTail(archive, "launcher/" + Path.GetFileName(file), file);
                AddTail(archive, "launcher/Config.wtf", folder.ConfigWtf);
            }
            return zip;
        }

        static IEnumerable<string> Logs(string directory, string pattern)
        {
            if (!Directory.Exists(directory))
                return Enumerable.Empty<string>();
            return Directory.GetFiles(directory, pattern)
                .Where(file => !SkippedLogs.Contains(Path.GetFileName(file), StringComparer.OrdinalIgnoreCase))
                .Where(file => new FileInfo(file).Length > 0);
        }

        static IEnumerable<string> NewestCrashFiles(GameFolder folder)
        {
            string errors = Path.Combine(folder.Root, "Errors");
            if (!Directory.Exists(errors))
                return Enumerable.Empty<string>();
            List<string> reports = Directory.GetFiles(errors, "*.txt")
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .Take(NewestCrashes)
                .ToList();
            string newestDump = Path.ChangeExtension(reports.FirstOrDefault() ?? "", ".dmp");
            if (File.Exists(newestDump))
                reports.Add(newestDump);
            return reports;
        }

        static string About(GameFolder folder)
        {
            StringBuilder text = new StringBuilder();
            text.AppendLine($"Launcher: {typeof(LogBundle).Assembly.GetName().Version}");
            text.AppendLine($"Installed: {folder.InstalledVersion?.ToString() ?? "unknown"}");
            text.AppendLine($"Windows: {Environment.OSVersion.VersionString}, {(Environment.Is64BitOperatingSystem ? "64" : "32")}-bit");
            text.AppendLine($"Processors: {Environment.ProcessorCount}");
            text.AppendLine($"wow_turbo: {TurboMod.Describe(folder)}");
            text.AppendLine($"Game folder: {HideUserName(folder.Root)}");
            text.AppendLine($"Saved: {DateTime.Now:yyyy-MM-dd HH:mm:ss zzz}");
            return text.ToString();
        }

        static string HideUserName(string path)
        {
            string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return profile.Length > 0 && path.StartsWith(profile, StringComparison.OrdinalIgnoreCase)
                ? "%USERPROFILE%" + path.Substring(profile.Length)
                : path;
        }

        static void AddText(ZipArchive archive, string name, string text)
        {
            using (StreamWriter writer = new StreamWriter(archive.CreateEntry(name).Open(), new UTF8Encoding(false)))
                writer.Write(text);
        }

        static void AddTail(ZipArchive archive, string name, string file)
        {
            if (!File.Exists(file))
                return;
            try
            {
                using (FileStream source = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (Stream target = archive.CreateEntry(name).Open())
                {
                    if (source.Length > MaxBytesPerFile)
                        source.Seek(-MaxBytesPerFile, SeekOrigin.End);
                    source.CopyTo(target);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }
}
