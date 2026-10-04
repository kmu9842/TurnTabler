using System;
using System.IO;
using System.Security.Cryptography;

namespace TurnTabler;

internal static class SelfTests
{
    internal static int Run()
    {
        try
        {
            using (var artwork = BundledAssets.Open("Record.png"))
                if (Convert.ToHexString(SHA256.HashData(artwork)) != "B3D705FCD86CFDE1DA84D3B131B28A36696BDDD40C354B2C77843D76D65F58AB") throw new Exception("Original record image changed.");
            if (!BundledAssets.ReadText("YouTubeBridge.js").Contains("window.turntablerNative")) throw new Exception("Bundled playback bridge missing.");
            const string requested = "https://www.youtube.com/watch?v=2qfoSxRRCJc&list=RD2qfoSxRRCJc&index=1";
            if (YouTubeAddress.Parse(requested).AbsoluteUri != requested) throw new Exception("Mix must preserve both the selected video and RD playlist.");
            foreach (var link in new[] { "youtu.be/2qfoSxRRCJc", "youtube.com/shorts/2qfoSxRRCJc", "youtube.com/live/2qfoSxRRCJc", "youtube.com/embed/2qfoSxRRCJc" })
                if (YouTubeAddress.Parse(link).AbsoluteUri != "https://www.youtube.com/watch?v=2qfoSxRRCJc") throw new Exception("Watch address conversion failed: " + link);
            if (!YouTubeAddress.Parse("youtu.be/2qfoSxRRCJc?t=1m23s").Query.EndsWith("t=1m23s")) throw new Exception("Timestamp lost.");
            if (YouTubeAddress.Parse("youtube.com/playlist?list=PL1234567890").AbsolutePath != "/playlist") throw new Exception("Playlist lost.");
            foreach (var link in new[] { "https://youtube.com.evil.org/watch?v=2qfoSxRRCJc", "file:///etc/passwd", "https://user@youtube.com/watch?v=2qfoSxRRCJc", "youtube.com/watch?v=bad", "youtube.com/playlist?list=bad", "youtube.com/" })
            {
                bool rejected = false;
                try { YouTubeAddress.Parse(link); } catch (ArgumentException) { rejected = true; }
                if (!rejected) throw new Exception("Invalid address accepted: " + link);
            }
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-result.txt"), "PASS: embedded original artwork SHA256, embedded playback bridge, requested Mix URL, watch/short/live/embed normalization, timestamps, playlist, invalid host/input rejection.");
            return 0;
        }
        catch (Exception error) { File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-result.txt"), error.ToString()); return 1; }
    }
}
