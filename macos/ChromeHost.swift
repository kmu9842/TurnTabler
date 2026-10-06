import AppKit
import UniformTypeIdentifiers

enum HostError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
@main struct ChromeHost {
    static let origin = "chrome-extension://ebnjhkdpohpgeipkalbfklpfibjadnhd/"
    static let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TurnTablerChrome/settings.json")
    static func readExactly(_ count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let part = try FileHandle.standardInput.read(upToCount:count-result.count), !part.isEmpty else { throw HostError.invalid("요청이 불완전합니다.") }
            result.append(part)
        }
        return result
    }
    static func path() -> String {
        if let data = try? Data(contentsOf:config), let settings = try? JSONSerialization.jsonObject(with:data) as? [String:String], let path = settings["appPath"] { return path }
        return "/Applications/TurnTabler.app"
    }
    static func bundle(_ path: String) throws -> Bundle {
        guard path.hasPrefix("/"), path.count <= 4096, path.hasSuffix(".app"), let bundle = Bundle(path:path), bundle.bundleIdentifier == "com.turntabler.player", let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath:executable.path) else { throw HostError.invalid("TurnTabler.app 위치를 확인해 주세요.") }
        return bundle
    }
    static func settings() -> [String:Any] {
        let path = path(), app = try? bundle(path)
        return ["ok":true,"protocol":1,"appPath":path,"available":app != nil,"appVersion":app?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "","error":app == nil ? "TurnTabler.app 위치를 지정해 주세요." : ""]
    }
    static func save(_ value: String) throws {
        let path = value.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"\""))
        _ = try bundle(path)
        try FileManager.default.createDirectory(at:config.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:["appPath":path]).write(to:config,options:.atomic)
    }
    static func request(_ input: [String:Any]) throws -> [String:Any] {
        switch input["action"] as? String {
        case "ping", "getSettings": return settings()
        case "setPath": try save(input["appPath"] as? String ?? ""); return settings()
        case "choosePath":
            _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.activate(ignoringOtherApps:true)
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.message = "TurnTabler.app을 선택하세요."
            if panel.runModal() != .OK { var reply = settings(); reply["cancelled"] = true; return reply }
            try save(panel.url!.path); return settings()
        case "play":
            guard let text = input["url"] as? String, text.count <= 4096 else { throw AddressError.invalid }
            let url = try youtubeURL(text), app = try bundle(path())
            var handoff = URLComponents(); handoff.scheme = "turntabler"; handoff.host = "play"; handoff.queryItems = [URLQueryItem(name:"url",value:url.absoluteString)]
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            var completed = false, failure: Error?
            NSWorkspace.shared.open([handoff.url!],withApplicationAt:app.bundleURL,configuration:config) { _,error in failure = error; completed = true }
            let deadline = Date().addingTimeInterval(15)
            while !completed && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
            if let failure { throw failure }; if !completed { throw HostError.invalid("앱 실행 시간 초과") }
            return ["ok":true,"protocol":1,"url":url.absoluteString]
        default: throw HostError.invalid("지원하지 않는 요청입니다.")
        }
    }
    static func main() {
        if CommandLine.arguments.contains("--self-test") { do { try addressSelfTest(); print("PASS: macOS Chrome host URL validation"); exit(0) } catch { exit(1) } }
        var reply: [String:Any]
        do {
            guard CommandLine.arguments.dropFirst().first == origin else { throw HostError.invalid("허용되지 않은 확장 프로그램입니다.") }
            let header = try readExactly(4); let count = header.withUnsafeBytes { $0.loadUnaligned(as:UInt32.self).littleEndian }
            guard count > 0, count <= 16384 else { throw HostError.invalid("잘못된 메시지 크기입니다.") }
            guard let input = try JSONSerialization.jsonObject(with:readExactly(Int(count))) as? [String:Any] else { throw HostError.invalid("잘못된 메시지입니다.") }
            reply = try request(input)
        } catch { reply = ["ok":false,"protocol":1,"error":error.localizedDescription] }
        let data = try! JSONSerialization.data(withJSONObject:reply)
        var length = UInt32(data.count).littleEndian
        withUnsafeBytes(of:&length) { FileHandle.standardOutput.write(Data($0)) }; FileHandle.standardOutput.write(data)
    }
}
