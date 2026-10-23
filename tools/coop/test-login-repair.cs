using System;
using System.IO;
using System.Linq;
using System.Reflection;

static class TestLoginRepair
{
    static int Main(string[] args)
    {
        try
        {
            string root = Path.GetFullPath(args[1]);
            string target = Path.Combine(root, "release", "login-repair-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(target);
            File.Copy(Path.Combine(args[2], "WoW.exe"), Path.Combine(target, "WoW.exe"));
            File.Copy(Path.Combine(args[2], "VanillaFixes.exe"), Path.Combine(target, "VanillaFixes.exe"));
            string glue = Path.Combine(target, "Interface", "GlueXML");
            Directory.CreateDirectory(glue);
            File.WriteAllText(Path.Combine(glue, "BonkAccount.lua"), "preserve account");
            File.WriteAllText(Path.Combine(glue, "BonkStats.lua"), "preserve heroes");
            File.WriteAllText(Path.Combine(glue, "BonkGlue.lua"), "damaged interface");
            File.WriteAllText(Path.Combine(target, "dlls.txt"), "ClassicAPI.dll\r\n");
            Assembly assembly = Assembly.LoadFrom(Path.GetFullPath(args[0]));
            Type folderType = assembly.GetType("HordesOfAzeroth.Launcher.GameFolder", true);
            object folder = Activator.CreateInstance(folderType, BindingFlags.Instance | BindingFlags.NonPublic, null, new object[] { target }, null);
            MethodInfo repair = assembly.GetType("HordesOfAzeroth.Launcher.LoginRepair", true).GetMethod("Apply");
            repair.Invoke(null, new[] { folder });
            string executable = Path.Combine(target, "HordesOfAzeroth.exe");
            byte[] expected = File.ReadAllBytes(executable);
            using (FileStream stream = File.OpenWrite(executable))
            {
                stream.Position = 0x11FB7D;
                stream.WriteByte(0x74);
            }
            repair.Invoke(null, new[] { folder });
            if (!expected.SequenceEqual(File.ReadAllBytes(executable))) throw new Exception("Client patch repair failed");
            foreach (string name in new[] { "GlueXML.toc", "BonkGlue.lua", "BonkGlue.xml", "BonkGluePad.lua", "BonkGluePad.xml" })
                if (!File.ReadAllBytes(Path.Combine(glue, name)).SequenceEqual(File.ReadAllBytes(Path.Combine(root, "Interface", "GlueXML", name)))) throw new Exception("Interface repair failed: " + name);
            if (!File.ReadAllBytes(Path.Combine(target, "HordesOfAzerothClientFix.dll")).SequenceEqual(File.ReadAllBytes(Path.Combine(root, "tools", "clientfix", "build", "Release", "HordesOfAzerothClientFix.dll")))) throw new Exception("Native recovery repair failed");
            if (File.ReadAllText(Path.Combine(glue, "BonkStats.lua")) != "preserve heroes" || File.ReadAllText(Path.Combine(glue, "BonkAccount.lua")) != "preserve account") throw new Exception("Player data modified");
            string[] dlls = File.ReadAllLines(Path.Combine(target, "dlls.txt"));
            if (dlls.Count(line => line == "HordesOfAzerothClientFix.dll") != 1 || !dlls.Contains("ClassicAPI.dll")) throw new Exception("DLL registration failed");
            DateTime lastWrite = File.GetLastWriteTimeUtc(executable);
            repair.Invoke(null, new[] { folder });
            if (File.GetLastWriteTimeUtc(executable) != lastWrite) throw new Exception("Unchanged executable rewritten");
            Console.WriteLine("PASS missing/damaged UI, missing/altered executable, native recovery, DLL registration, idempotence and preserved player data");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
