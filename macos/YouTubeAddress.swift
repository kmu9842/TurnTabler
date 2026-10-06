import Foundation

enum AddressError: Error, LocalizedError {
    case invalid
    var errorDescription: String? { "올바른 YouTube 영상 또는 재생목록 주소를 입력해 주세요." }
}

func youtubeURL(_ input: String) throws -> URL {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://" + text }
    guard let inputURL = URLComponents(string: text), ["http", "https"].contains(inputURL.scheme ?? ""),
          inputURL.user == nil, inputURL.password == nil,
          let host = inputURL.host?.lowercased(),
          ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be"].contains(host) else { throw AddressError.invalid }
    var query: [String: String] = [:]
    for item in inputURL.queryItems ?? [] where query[item.name] == nil { query[item.name] = item.value ?? "" }
    let parts = inputURL.path.split(separator: "/").map(String.init)
    var video = query["v"]
    if host.hasSuffix("youtu.be") { video = parts.first }
    else if parts.count > 1 && ["shorts", "live", "embed"].contains(parts[0]) { video = parts[1] }
    let list = query["list"]
    func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    if let video, !matches(video, "^[A-Za-z0-9_-]{11}$") { throw AddressError.invalid }
    if let list, !matches(list, "^[A-Za-z0-9_-]{10,150}$") { throw AddressError.invalid }
    guard video != nil || list != nil else { throw AddressError.invalid }
    var result = URLComponents(string: "https://www.youtube.com/" + (video == nil ? "playlist" : "watch"))!
    var items: [URLQueryItem] = []
    if let video { items.append(URLQueryItem(name: "v", value: video)) }
    if let list { items.append(URLQueryItem(name: "list", value: list)) }
    if let raw = query["index"], let index = Int(raw), index > 0 { items.append(URLQueryItem(name: "index", value: String(index))) }
    if let time = query["t"] ?? query["start"], !time.isEmpty, matches(time, "^(?:[0-9]+|(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?)$") { items.append(URLQueryItem(name: "t", value: time)) }
    result.queryItems = items
    return result.url!
}

func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])
    return String(data: data, encoding: .utf8)!.dropFirst().dropLast().description
}

func addressSelfTest() throws {
    let valid = try youtubeURL("https://youtu.be/2qfoSxRRCJc?list=RD2qfoSxRRCJc&index=2&t=1m2s")
    precondition(valid.absoluteString.contains("list=RD2qfoSxRRCJc"))
    precondition(valid.absoluteString.contains("index=2"))
    precondition(valid.absoluteString.contains("t=1m2s"))
    for value in ["https://youtube.com.evil.org/watch?v=2qfoSxRRCJc", "file:///etc/passwd", "https://user@youtube.com/watch?v=2qfoSxRRCJc", "https://youtube.com/@channel", "https://youtube.com/watch?v=x"] {
        do { _ = try youtubeURL(value); preconditionFailure("Invalid URL accepted") } catch { }
    }
    _ = try youtubeURL("https://youtube.com/playlist?list=PL1234567890")
}
