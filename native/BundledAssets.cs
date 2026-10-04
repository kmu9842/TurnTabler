using System;
using System.IO;

namespace TurnTabler;

internal static class BundledAssets
{
    internal static Stream Open(string name) => typeof(BundledAssets).Assembly.GetManifestResourceStream("TurnTabler.Assets." + name)
        ?? throw new InvalidOperationException("Bundled asset is missing: " + name);

    internal static string ReadText(string name)
    {
        using var stream = Open(name);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
