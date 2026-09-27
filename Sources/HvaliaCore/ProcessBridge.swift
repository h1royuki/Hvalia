import Foundation
import Darwin

public struct ToolPaths: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static var bundled: ToolPaths { ToolPaths(directory: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")) }
    public func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
}

public enum JSONOutput {
    /// Helpers can emit framework messages before a final one-line JSON result.
    public static func parse(_ data: Data) throws -> [String: Any] {
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] { return object }
        }
        throw BridgeError.message("Компонент связи не вернул результат. Переподключите разблокированный iPhone.")
    }
}

public enum ToolRunner {
    public static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 35) throws -> [String: Any] {
        // Regular files avoid stdout/stderr pipe deadlocks. Never invoke a shell.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Hvalia-\(UUID().uuidString)")
        try PrivateStorage.directory(temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("stdout"), err = temp.appendingPathComponent("stderr")
        try PrivateStorage.write(Data(), to: out); try PrivateStorage.write(Data(), to: err)
        let stdout = try FileHandle(forWritingTo: out), stderr = try FileHandle(forWritingTo: err)
        defer { try? stdout.close(); try? stderr.close() }
        let p = Process(); p.executableURL = executable; p.arguments = arguments
        p.standardOutput = stdout; p.standardError = stderr
        try p.run()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning {
            p.terminate(); Thread.sleep(forTimeInterval: 0.2)
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }; p.waitUntilExit()
            throw BridgeError.message("Время ожидания истекло. Если запись уже началась, автоматический повтор запрещён. Откройте сохранённую сессию.")
        }
        return try JSONOutput.parse(Data(contentsOf: out))
    }
    public static func connectionSnapshot(paths: ToolPaths) throws -> ConnectionSnapshot {
        let result = try run(paths.url("hvalia-device"), ["list"])
        guard (result["ok"] as? NSNumber)?.boolValue == true else { throw BridgeError.message("Не удалось проверить подключение iPhone.") }
        return try JSONDecoder().decode(ConnectionSnapshot.self, from: JSONSerialization.data(withJSONObject: result))
    }
    public static func devices(paths: ToolPaths) throws -> [Phone] {
        let result = try run(paths.url("hvalia-device"), ["list"])
        guard (result["ok"] as? NSNumber)?.boolValue == true, let rows = result["devices"] else { throw BridgeError.message("Не удалось найти iPhone. Разблокируйте его и подтвердите доверие к Mac.") }
        return try JSONDecoder().decode([Phone].self, from: JSONSerialization.data(withJSONObject: rows))
    }
}

public final class LogCapture {
    private let process = Process()
    private let handle: FileHandle
    public let file: URL
    public init(paths: ToolPaths, udid: String, file: URL, processName: String) throws {
        self.file = file
        try PrivateStorage.write(Data(), to: file)
        handle = try FileHandle(forWritingTo: file)
        process.executableURL = paths.url("hvalia-device")
        process.arguments = ["syslog", udid, processName]
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(15)
        while true {
            let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            if text.contains("HVALIA_LOG_READY") { break }
            guard process.isRunning && Date() < deadline else { process.terminate(); throw BridgeError.message("Поток диагностики недоступен. Разблокируйте iPhone и проверьте доверие.") }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    public func read() throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attrs[.size] as? NSNumber)?.intValue ?? 0 < 32 * 1024 * 1024 else { throw BridgeError.message("Достигнут предел размера журнала.") }
        return String(decoding: try Data(contentsOf: file), as: UTF8.self)
    }
    public func stop() {
        if process.isRunning { process.interrupt(); Thread.sleep(forTimeInterval: 0.2) }
        if process.isRunning { process.terminate(); Thread.sleep(forTimeInterval: 0.2) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit(); try? handle.close()
    }
    deinit { if process.isRunning { process.terminate() }; try? handle.close() }
}
