using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace TurnTabler;

internal static class YouTubeAddress
{
    internal static Uri Parse(string input)
    {
        input = input.Trim();
        if (!input.Contains("://")) input = "https://" + input;
        if (!Uri.TryCreate(input, UriKind.Absolute, out var uri) || (uri.Scheme != "https" && uri.Scheme != "http") || uri.UserInfo.Length != 0)
            throw new ArgumentException("올바른 유튜브 주소를 입력해 주세요.");
        string[] hosts = { "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be" };
        if (!hosts.Contains(uri.Host.ToLowerInvariant())) throw new ArgumentException("유튜브 링크를 입력해 주세요.");
        var query = uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2)).GroupBy(pair => Uri.UnescapeDataString(pair[0]))
            .ToDictionary(group => group.Key, group => Uri.UnescapeDataString(group.First().Length > 1 ? group.First()[1] : ""));
        var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        string? video = query.GetValueOrDefault("v");
        if (uri.Host.EndsWith("youtu.be", StringComparison.OrdinalIgnoreCase)) video = segments.FirstOrDefault();
        else if (segments.Length > 1 && new[] { "shorts", "live", "embed" }.Contains(segments[0])) video = segments[1];
        string? list = query.GetValueOrDefault("list");
        if (video != null && !Regex.IsMatch(video, "^[a-zA-Z0-9_-]{11}$")) throw new ArgumentException("영상 주소를 확인해 주세요.");
        if (list != null && !Regex.IsMatch(list, "^[a-zA-Z0-9_-]{10,150}$")) throw new ArgumentException("재생목록 주소를 확인해 주세요.");
        if (video == null && list == null) throw new ArgumentException("영상 또는 재생목록 주소를 입력해 주세요.");
        var values = new List<string>();
        if (video != null) values.Add("v=" + video);
        if (list != null) values.Add("list=" + list);
        if (int.TryParse(query.GetValueOrDefault("index"), out var index) && index > 0) values.Add("index=" + index);
        var time = query.GetValueOrDefault("t") ?? query.GetValueOrDefault("start");
        if (time != null && Regex.IsMatch(time, "^(?:[0-9]+|(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?)$") && time.Length > 0) values.Add("t=" + time);
        return new Uri("https://www.youtube.com/" + (video == null ? "playlist" : "watch") + "?" + string.Join("&", values));
    }

    internal static bool IsYouTubePage(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme == "https" && uri.Host == "www.youtube.com";
}
