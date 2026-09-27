import Foundation

public enum TransactionProgress: String, Sendable { case saving, applying, restoring, finishing }

public protocol EventLog { func read() throws -> String; func stop() }
extension LogCapture: EventLog {}
public protocol BridgeBackend {
    func devices() throws -> [Phone]
    func device(_ command: String, _ phone: Phone, _ args: [String]) throws -> [String: Any]
    func sync(_ phone: Phone, ids: [String], destinations: [String]) throws
    func capture(_ phone: Phone, file: URL) throws -> EventLog
}
public struct NativeBackend: BridgeBackend {
    public let paths: ToolPaths
    public init(paths: ToolPaths) { self.paths = paths }
    public func devices() throws -> [Phone] { try ToolRunner.devices(paths: paths) }
    public func device(_ command: String, _ phone: Phone, _ args: [String]) throws -> [String: Any] {
        let result = try ToolRunner.run(paths.url("hvalia-device"), [command, phone.id] + args, timeout: 90)
        guard let op = result["operation"] as? [String: Any] else { throw BridgeError.message("Нет ответа от iPhone.") }
        return op
    }
    public func sync(_ phone: Phone, ids: [String], destinations: [String]) throws {
        let args = [phone.id] + zip(ids, destinations).flatMap { [$0, $1] }
        let result = try ToolRunner.run(paths.url("hvalia-atc"), args, timeout: 110)
        guard (result["ok"] as? NSNumber)?.boolValue == true, (result["fileCompleteMessages"] as? NSNumber)?.intValue == ids.count else { throw BridgeError.message("Синхронизация не завершила отправку запросов. Повтор автоматически не выполняется.") }
    }
    public func capture(_ phone: Phone, file: URL) throws -> EventLog { try LogCapture(paths: paths, udid: phone.id, file: file, processName: "atc") }
}

public struct TransferPlan: Codable, Sendable {
    public let source: String
    public let link: String
    public let recovered: String
    public let ids: [String]
    public let destinations: [String]
    public init(export: Bool, leaf: String = Compatibility.leaf) {
        let token = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(20))
        source = "airlift-src-" + token; link = "airlift-link-" + token; recovered = "airlift-recovered-" + token
        ids = ["../../\(source)/p0/p1/p2/link", export ? "../../../Library/CountryBundles/Overlay/\(leaf)" : "../../\(source)/payload"]
        destinations = [link, export ? recovered : link + "/" + leaf]
    }
    public func moveConfirmed(in text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            line.contains("Airlock moved /var/mobile/Media/Airlock/Book/../../\(source)/payload to ")
        }
    }
}

/// Synchronous transaction, run on a worker queue. Never retry a mutation.
public final class Transaction {
    public let store: SessionStore
    private let backend: BridgeBackend
    private var allowCarrierChange = false
    private var auditFolder: URL?
    private let progress: (TransactionProgress) -> Void
    public init(store: SessionStore, backend: BridgeBackend, progress: @escaping (TransactionProgress) -> Void = { _ in }) {
        self.store = store; self.backend = backend; self.progress = progress
    }
    private func checked(_ command: String, _ phone: Phone, _ args: [String] = []) throws {
        let op = try backend.device(command, phone, args)
        if let auditFolder {
            try PrivateStorage.directory(auditFolder)
            let event: [String: Any] = ["command": command, "time": ISO8601DateFormatter().string(from: Date()), "result": op]
            try PrivateStorage.write(JSONSerialization.data(withJSONObject: event, options: [.prettyPrinted, .sortedKeys]), to: auditFolder.appendingPathComponent(UUID().uuidString + ".json"))
        }
        guard (op["ok"] as? NSNumber)?.boolValue == true else {
            let details = ["reason", "path", "extraPaths", "missingPaths", "failures", "afcError"].compactMap { key in op[key].map { "\(key): \($0)" } }.joined(separator: "; ")
            throw BridgeError.message("Шаг «\(command)» не подтверждён. Сессия сохранена; автоматического повтора нет." + (details.isEmpty ? "" : "\n" + details))
        }
    }
    private func verifyIdentity(_ phone: Phone, _ line: CarrierLine, restoring: Bool = false) throws {
        guard let fresh = try backend.devices().first(where: { $0.id == phone.id }), fresh.productType == phone.productType,
              fresh.hardwareModel == phone.hardwareModel, fresh.productVersion == phone.productVersion,
              fresh.buildVersion == phone.buildVersion, Compatibility.deviceCheck(fresh) == .eligible,
              restoring || (fresh.carriers.contains(line) && Compatibility.check(fresh, line: line) == .eligible) else {
            throw BridgeError.message("Устройство, SIM или версия iOS изменились. Запись заблокирована.")
        }
    }
    public func apply(phone: Phone, line: CarrierLine, restoring previous: SessionRecord? = nil) throws -> SessionRecord {
        allowCarrierChange = previous != nil
        let lock = try OperationLock(root: store.root); defer { withExtendedLifetime(lock) {} }
        guard !(try store.all()).contains(where: { $0.phase.isUnfinished }) else {
            throw BridgeError.message("Есть незавершённая сессия. Сначала откройте её резервную копию и инструкции восстановления.")
        }
        try verifyIdentity(phone, line, restoring: previous != nil)
        var desired: Data?
        if let previous {
            guard previous.phone.id == phone.id, previous.phone.productVersion == phone.productVersion,
                  previous.phone.buildVersion == phone.buildVersion, previous.phone.productType == phone.productType,
                  previous.phone.hardwareModel == phone.hardwareModel, Compatibility.validLeaf(previous.overlayLeaf ?? Compatibility.leaf, phone: phone) else { throw BridgeError.message("Эта копия принадлежит другому устройству или версии настроек.") }
            desired = try store.original(previous)
        }
        let leaf = try previous.map { $0.overlayLeaf ?? Compatibility.leaf } ?? Compatibility.candidateLeaf(phone, line: line)
        var session = SessionRecord(phone: phone, line: line); session.previousSessionID = previous?.id; session.overlayLeaf = leaf
        try store.save(session)
        let folder = store.directory(session.id)
        auditFolder = folder.appendingPathComponent("operations")
        do {
            let exportPlan = TransferPlan(export: true, leaf: leaf)
            let exportFolder = folder.appendingPathComponent("export")
            try transfer(plan: exportPlan, payload: Data("original-export".utf8), folder: exportFolder, session: &session, exporting: true)
            let original = try store.original(session)
            // If validation fails, put the exact bytes back, then surface the error.
            var validationError: Error?
            if desired == nil { do { desired = try OverlayPatch.apply(original) } catch { desired = original; validationError = error } }
            let payload = desired!
            try PrivateStorage.write(payload, to: folder.appendingPathComponent("replacement.plist"))
            session.patchedSHA256 = OverlayPatch.digest(payload); try store.save(session)
            try transfer(plan: TransferPlan(export: false, leaf: leaf), payload: payload, folder: folder.appendingPathComponent("install"), session: &session, exporting: false)
            session.phase = previous != nil || validationError != nil ? .restored : .restartNeeded
            session.message = validationError?.localizedDescription
            try store.save(session)
            return session
        } catch {
            session.interruptedPhase = session.phase; session.phase = .recoveryRequired; session.message = error.localizedDescription
            try? store.save(session)
            throw BridgeError.message("\(error.localizedDescription)\nСохранённая сессия: \(session.id.uuidString). Не запускайте другие активаторы и не удаляйте резервную копию.")
        }
    }
    /// Recover only states with a known empty target; never guess after an install began.
    public func recover(_ record: SessionRecord) throws -> SessionRecord {
        allowCarrierChange = true
        let lock = try OperationLock(root: store.root); defer { withExtendedLifetime(lock) {} }
        var session = try store.load(record.id)
        guard session.phase == .recoveryRequired || session.phase.isUnfinished else { throw BridgeError.message("Сессия уже завершена.") }
        try verifyIdentity(session.phone, session.line, restoring: true)
        guard Compatibility.validLeaf(session.overlayLeaf ?? Compatibility.leaf, phone: session.phone) else { throw BridgeError.message("В журнале указано некорректное имя профиля.") }
        let folder = store.directory(session.id)
        auditFolder = folder.appendingPathComponent("operations")
        let phase = session.interruptedPhase ?? session.phase
        if phase == .prepared {
            session.phase = .restored; session.message = "Запись на iPhone ещё не начиналась. Сессия закрыта."; try store.save(session); return session
        }
        guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent("install/plan.json").path), [.exportStarted, .originalSaved].contains(phase) else {
            throw BridgeError.message("Запись уже могла начаться. Автоматический откат остановлен: сначала нужно установить, есть ли файл на исходном месте. Откройте инструкцию восстановления; все копии сохранены.")
        }
        let exportFolder = folder.appendingPathComponent("export")
        let plan = try JSONDecoder().decode(TransferPlan.self, from: Data(contentsOf: exportFolder.appendingPathComponent("plan.json")))
        if session.originalSHA256 == nil {
            let recovered = folder.appendingPathComponent("recovered-after-interruption.plist")
            try checked("read-owned", session.phone, [plan.recovered, recovered.path])
            try store.saveOriginal(Data(contentsOf: recovered), session: &session)
        }
        let original = try store.original(session)
        try checked("full-restore", session.phone, [exportFolder.appendingPathComponent("books").path])
        try checked("cleanup-owned", session.phone, [plan.source, plan.link, plan.recovered])
        do {
            try transfer(plan: TransferPlan(export: false, leaf: session.overlayLeaf ?? Compatibility.leaf), payload: original, folder: folder.appendingPathComponent("install"), session: &session, exporting: false)
            session.phase = .restored; session.message = "Оригинал восстановлен после прерывания. Перезагрузите iPhone."; try store.save(session); return session
        } catch {
            session.interruptedPhase = session.phase; session.phase = .recoveryRequired; session.message = error.localizedDescription; try? store.save(session); throw error
        }
    }
    private func transfer(plan: TransferPlan, payload: Data, folder: URL, session: inout SessionRecord, exporting: Bool) throws {
        try verifyIdentity(session.phone, session.line, restoring: allowCarrierChange)
        try PrivateStorage.directory(folder)
        let books = folder.appendingPathComponent("books"); try PrivateStorage.directory(books)
        progress(exporting ? .saving : (session.previousSessionID == nil ? .applying : .restoring))
        try checked("snapshot-books", session.phone, [books.path])
        try checked("full-snapshot", session.phone, [books.path])
        try store.flushTree(books)
        try checked("full-verify", session.phone, [books.path])
        let archive = folder.appendingPathComponent("payload.zip"), manifest = folder.appendingPathComponent("Books.plist")
        try PrivateStorage.write(StreamingArchive.make(payload: payload), to: archive)
        try PrivateStorage.write(StreamingArchive.books(identifiers: plan.ids), to: manifest)
        try PrivateStorage.write(JSONEncoder().encode(plan), to: folder.appendingPathComponent("plan.json"))
        // Require two durable originals before the next ATC session can reconcile assets.
        if !exporting { _ = try store.original(session) }
        let capture = try backend.capture(session.phone, file: folder.appendingPathComponent("transfer.log"))
        defer { capture.stop() }
        var staged = false
        do {
            session.phase = exporting ? .exportStarted : .installStarted; try store.save(session)
            staged = true // even a failed stage may have written Books
            try checked("stage", session.phone, [plan.source, plan.link, plan.recovered, archive.path, manifest.path, books.path])
            try backend.sync(session.phone, ids: plan.ids, destinations: plan.destinations)
            if exporting {
                let recovered = folder.appendingPathComponent("recovered.plist")
                let deadline = Date().addingTimeInterval(15)
                while true {
                    let op = try backend.device("read-owned", session.phone, [plan.recovered, recovered.path])
                    if (op["ok"] as? NSNumber)?.boolValue == true { break }
                    guard (op["afcError"] as? NSNumber)?.intValue == 8, Date() < deadline else { throw BridgeError.message("Не удалось сохранить оригинал. Не запускайте следующую синхронизацию: оригинал может оставаться в Media.") }
                    Thread.sleep(forTimeInterval: 0.3)
                }
                try store.saveOriginal(Data(contentsOf: recovered), session: &session)
            } else {
                let deadline = Date().addingTimeInterval(10)
                while !plan.moveConfirmed(in: try capture.read()) {
                    guard Date() < deadline else { throw BridgeError.message("Запись не подтверждена журналом iPhone. Состояние файла требует проверки.") }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                try checked("payload-absent", session.phone, [plan.source])
                session.phase = .settingsWritten; try store.save(session)
            }
            if !exporting { progress(.finishing) }
            try checked("full-restore", session.phone, [books.path])
            try checked("cleanup-owned", session.phone, [plan.source, plan.link, plan.recovered])
        } catch {
            // Books recovery does not start another ATC session or touch the overlay.
            if staged { try? checked("full-restore", session.phone, [books.path]) }
            throw error
        }
    }
}
