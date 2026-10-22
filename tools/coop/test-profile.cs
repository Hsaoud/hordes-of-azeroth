using System;
using System.Collections.Generic;
using System.Reflection;
using System.Web.Script.Serialization;

static class TestProfile
{
    static void Main(string[] args)
    {
        var assembly = Assembly.LoadFrom(args[0]);
        var method = assembly.GetType("HordesOfAzeroth.Launcher.CoopSession").GetMethod("ProfileLua", BindingFlags.Static | BindingFlags.NonPublic);
        var serializer = new JavaScriptSerializer();
        var profile = serializer.Deserialize<Dictionary<string, object>>("{\"profile\":{\"gold\":42,\"heroes\":[{\"name\":\"Testhero\",\"runs\":3,\"kills\":19}]}}");
        string lua = (string)method.Invoke(null, new object[] { profile });
        if (!lua.Contains("Testhero") || !lua.Contains("runs = 3") || !lua.Contains("gold = 42"))
            throw new InvalidOperationException("The guest hero profile was not restored.");
        profile = serializer.Deserialize<Dictionary<string, object>>("{\"profile\":{\"heroes\":[{\"name\":\"bad\\\"name\",\"runs\":\"invalid\"}]}}");
        lua = (string)method.Invoke(null, new object[] { profile });
        if (lua.Contains("bad") || lua.Contains("invalid"))
            throw new InvalidOperationException("Untrusted profile fields reached the Lua output.");
        Console.WriteLine("PASS guest hero records restored; names and numeric fields validated");
    }
}
