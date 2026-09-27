import Foundation
import Darwin

public final class SessionStore: @unchecked Sendable {
    public let root: URL
    public init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NRBridge/sessions")
        try PrivateStorage.directory(self.root)
    }
    public func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }
    public func save(_ session: SessionRecord) throws {
        let folder = directory(session.id); try PrivateStorage.directory(folder)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try PrivateStorage.write(encoder.encode(session), to: folder.appendingPathComponent("session.json"))
    }
    public func load(_ id: UUID) throws -> SessionRecord {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionRecord.self, from: Data(contentsOf: directory(id).appendingPathComponent("session.json")))
    }
    public func all() throws -> [SessionRecord] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            // A damaged journal must block further writes, never silently disappear.
            return try load(id)
        }.sorted { $0.created > $1.created }
    }
    public func saveOriginal(_ data: Data, session: inout SessionRecord) throws {
        let folder = directory(session.id), hash = OverlayPatch.digest(data)
        for file in ["original.plist", "original-second-copy.plist"] {
            let url = folder.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw BridgeError.message("Оригинальная копия уже существует; перезапись запрещена.") }
            try PrivateStorage.write(data, to: url)
            guard OverlayPatch.digest(try Data(contentsOf: url)) == hash else { throw BridgeError.message("Контрольная сумма резервной копии не совпала.") }
        }
        session.originalSHA256 = hash; session.phase = .originalSaved; try save(session)
    }
    public func original(_ session: SessionRecord) throws -> Data {
        guard let hash = session.originalSHA256 else { throw BridgeError.message("В сессии нет проверенного оригинала.") }
        let a = try Data(contentsOf: directory(session.id).appendingPathComponent("original.plist"))
        let b = try Data(contentsOf: directory(session.id).appendingPathComponent("original-second-copy.plist"))
        guard OverlayPatch.digest(a) == hash, a == b else { throw BridgeError.message("Резервная копия повреждена. Запись заблокирована.") }
        return a
    }
    public func flushTree(_ folder: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        for file in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let data = try Data(contentsOf: file); try PrivateStorage.write(data, to: file)
            guard data == (try Data(contentsOf: file)) else { throw BridgeError.message("Ошибка сохранения резервной копии.") }
        }
    }
}

/// One process across all windows/instances can own the USB mutation at a time.
public final class OperationLock {
    private let fd: Int32
    public init(root: URL) throws {
        fd = open(root.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw BridgeError.message("Не удалось создать блокировку операции.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw BridgeError.message("Другая операция Hvalia уже выполняется.") }
    }
    deinit { flock(fd, LOCK_UN); close(fd) }
}
