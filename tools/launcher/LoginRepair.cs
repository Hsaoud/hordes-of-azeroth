using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;

namespace HordesOfAzeroth.Launcher
{
    static class LoginRepair
    {
        public static void Apply(GameFolder folder)
        {
            Assembly assembly = typeof(LoginRepair).Assembly;
            foreach (string name in new[] { "GlueXML.toc", "BonkGlue.lua", "BonkGlue.xml", "BonkGluePad.lua", "BonkGluePad.xml" })
                Restore(assembly, "LoginRepair." + name, Path.Combine(folder.GlueXml, name));
            Restore(assembly, "LoginRepair.client-patches.json", Path.Combine(folder.Config, "client-patches.json"));
            ClientPatcher.Apply(folder);
            Restore(assembly, "LoginRepair.HordesOfAzerothClientFix.dll", Path.Combine(folder.Root, "HordesOfAzerothClientFix.dll"));
            string dlls = Path.Combine(folder.Root, "dlls.txt");
            string[] lines = File.Exists(dlls) ? File.ReadAllLines(dlls) : new string[0];
            if (!lines.Any(line => string.Equals(line.Trim(), "HordesOfAzerothClientFix.dll", StringComparison.OrdinalIgnoreCase)))
                File.WriteAllLines(dlls, lines.Concat(new[] { "HordesOfAzerothClientFix.dll" }), new UTF8Encoding(false));
            if (!File.Exists(Path.Combine(folder.Root, "VanillaFixes.exe")))
                throw new FileNotFoundException("The game loader is missing. Extract the complete co-op game before playing.");
        }

        static void Restore(Assembly assembly, string resource, string path)
        {
            using (Stream source = assembly.GetManifestResourceStream(resource))
            {
                if (source == null)
                    throw new InvalidDataException("The launcher is incomplete. Install the complete co-op game.");
                using (var buffer = new MemoryStream())
                {
                    source.CopyTo(buffer);
                    byte[] expected = buffer.ToArray();
                    if (File.Exists(path) && File.ReadAllBytes(path).SequenceEqual(expected))
                        return;
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    File.WriteAllBytes(path, expected);
                }
            }
        }
    }
}
