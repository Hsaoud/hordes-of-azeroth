using System;
using System.Collections;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;

sealed class PreparationProgress<T> : IProgress<T>
{
    DateTime last;
    string step;

    public void Report(T value)
    {
        var type = typeof(T);
        string name = (type.GetField("Step") ?? type.GetField("Group"))?.GetValue(value) as string ?? "Preparing";
        if (step == name && DateTime.UtcNow - last < TimeSpan.FromSeconds(10))
            return;
        last = DateTime.UtcNow;
        step = name;
        Console.WriteLine(name + " " + (type.GetField("Detail")?.GetValue(value) ?? ""));
    }
}

static class PrepareGame
{
    static Assembly assembly;
    static Type Type(string name) { return assembly.GetType("HordesOfAzeroth.Launcher." + name, true); }
    static object New(string name, params object[] args) { return Activator.CreateInstance(Type(name), BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, args, null); }
    static object Field(object value, string name) { return value.GetType().GetField(name).GetValue(value); }
    static object Invoke(object value, string name, params object[] args) { return value.GetType().GetMethod(name).Invoke(value, args); }
    static object Progress(string name) { return Activator.CreateInstance(typeof(PreparationProgress<>).MakeGenericType(Type(name))); }

    static async Task Run(string[] args)
    {
        assembly = Assembly.LoadFrom(Path.GetFullPath(args[0]));
        object folder = New("GameFolder", Path.GetFullPath(args[1]));
        if (!(bool)Type("Installer").GetMethod("IsStockClient").Invoke(null, new[] { folder }))
            throw new InvalidOperationException("The client is not the supported enUS 1.12.1 build.");
        object server = New("LocalServer", folder);
        object updates = New("UpdateCheck", folder);
        object installer = New("Installer", folder, server);
        try
        {
            var fetch = (Task)Invoke(updates, "FetchAsync");
            await fetch;
            object manifest = fetch.GetType().GetProperty("Result").GetValue(fetch);
            bool complete = (bool)installer.GetType().GetProperty("IsComplete").GetValue(installer);
            await (Task)Invoke(installer, complete ? "UpdateAsync" : "InstallAsync", manifest, Progress("InstallProgress"), CancellationToken.None);
            object nav = New("NavBuilder", folder);
            foreach (object group in (IEnumerable)Field(manifest, "NavGroups"))
            {
                if ((bool)Invoke(nav, "IsGroupBuilt", group))
                    continue;
                object download = Field(group, "Download");
                if (download == null)
                {
                    await (Task)Invoke(nav, "BuildGroupAsync", group, Progress("NavProgress"), CancellationToken.None);
                    continue;
                }
                Console.WriteLine("Downloading monster paths: " + Field(group, "Name"));
                var task = (Task)Invoke(installer, "FetchAsync", Field(download, "Url"), Field(download, "Sha256"), new Action<long>(_ => { }), CancellationToken.None);
                await task;
                string zip = (string)task.GetType().GetProperty("Result").GetValue(task);
                Invoke(nav, "InstallDownloaded", group, zip);
            }
            Console.WriteLine("INSTALLATION COMPLETE");
        }
        finally { await (Task)Invoke(server, "StopAsync"); }
    }

    static int Main(string[] args)
    {
        try { Run(args).GetAwaiter().GetResult(); return 0; }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
