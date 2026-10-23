using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

static class VerifyCoop
{
    static async Task Run(string[] args)
    {
        Assembly assembly = Assembly.LoadFrom(Path.GetFullPath(args[0]));
        Func<string, Type> type = name => assembly.GetType("HordesOfAzeroth.Launcher." + name, true);
        Func<string, object[], object> create = (name, values) => Activator.CreateInstance(type(name), BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, values, null);
        Func<object, string, object[], object> invoke = (target, method, values) => target.GetType().GetMethod(method).Invoke(target, values);
        object folder = create("GameFolder", new object[] { Path.GetFullPath(args[1]) });
        object server = create("LocalServer", new[] { folder });
        server.GetType().GetProperty("CoopEnabled").SetValue(server, true);
        string[] accounts = { "COOPFFFFFFFFFFF1", "COOPFFFFFFFFFFF2", "COOPFFFFFFFFFFF3" };
        bool fixturesCreated = false;
        try
        {
            Console.WriteLine("Starting the real game server for three simulated clients");
            await (Task)invoke(server, "StartAsync", new object[] { new Progress<string>(Console.WriteLine), CancellationToken.None });
            string config = File.ReadAllText(Path.Combine(args[1], "server", "run", "mangosd.conf"));
            foreach (string key in new[] { "Bonk.Coop", "PlayerLimit", "MapUpdate.Instanced.UpdateThreads", "AllowTwoSide.Interaction.Group" })
                if (Regex.Matches(config, @"(?m)^\s*" + Regex.Escape(key) + @"\s*=").Count != 1)
                    throw new InvalidDataException("Duplicate config: " + key);
            Console.WriteLine("PASS one effective value per co-op server setting");
            var fixtures = new object[accounts.Length];
            for (int i = 0; i < accounts.Length; i++)
            {
                var exists = (Task<string>)invoke(server, "QueryAsync", new object[] { "realmd", "SELECT COUNT(*) FROM account WHERE username = '" + accounts[i] + "'" });
                if ((await exists).Trim() != "0")
                    throw new InvalidOperationException("A test account already exists. Refusing to alter it.");
            }
            fixturesCreated = true;
            for (int i = 0; i < accounts.Length; i++)
            {
                await (Task)invoke(server, "EnsureAccountAsync", new object[] { accounts[i], "COOPTESTPASS1234" });
                await (Task)invoke(server, "ReadHeroProfileAsync", new object[] { accounts[i] });
                if (args.Length > 4 && args[4] == "--extended")
                    await (Task)invoke(server, "RunConsoleAsync", new object[] { "account set gmlevel " + accounts[i] + " 6" });
                fixtures[i] = new { account = accounts[i], password = "COOPTESTPASS1234", name = new[] { "Coopalpha", "Coopbeta", "Coopgamma" }[i], race = i == 1 ? 2 : 1, heroClass = i == 1 ? 1 : 8, extended = args.Length > 4 && args[4] == "--extended" };
            }
            using (Process process = Process.Start(new ProcessStartInfo(args[2], "\"" + Path.GetFullPath(args[3]) + "\"") { UseShellExecute = false, RedirectStandardInput = true, CreateNoWindow = true }))
            {
                process.StandardInput.WriteLine(new JavaScriptSerializer().Serialize(fixtures));
                process.StandardInput.Close();
                await Task.Run(() => process.WaitForExit());
                if (process.ExitCode != 0) throw new InvalidOperationException("The game simulation failed.");
            }
        }
        finally
        {
            if (fixturesCreated)
                foreach (string account in accounts)
                {
                    string id = (await (Task<string>)invoke(server, "QueryAsync", new object[] { "realmd", "SELECT id FROM account WHERE username='" + account + "'" })).Trim();
                    await (Task)invoke(server, "RunConsoleAsync", new object[] { "account delete " + account });
                    uint accountId;
                    if (uint.TryParse(id, out accountId))
                    {
                        await (Task<string>)invoke(server, "QueryAsync", new object[] { "realmd", "DELETE FROM account_access WHERE id=" + accountId });
                        foreach (string table in new[] { "bonk_account", "bonk_account_mastery", "bonk_account_mastery_node", "bonk_account_quest", "bonk_account_starter", "bonk_account_talent", "bonk_account_tier", "bonk_account_upgrade" })
                            await (Task<string>)invoke(server, "QueryAsync", new object[] { "characters", "DELETE FROM " + table + " WHERE account=" + accountId });
                    }
                }
            await (Task)invoke(server, "StopAsync", new object[0]);
        }
    }

    static int Main(string[] args)
    {
        try { Run(args).GetAwaiter().GetResult(); return 0; }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
