import SwiftUI
import HvaliaCore

@MainActor final class AppModel: ObservableObject {
    @Published var phones: [Phone] = []
    @Published var connections: [DeviceConnection] = []
    @Published var sessions: [SessionRecord] = []
    @Published var flow = WizardState() { didSet { persistFlow() } }
    @Published var busy = false
    @Published var refreshing = false
    @Published var connectionIssue: String?
    @Published var mutating = false
    @Published var status = ""
    @Published var transactionProgress: TransactionProgress?
    @Published var error: String?
    @Published var evidence: RadioEvidence?
    @Published var singleLine = false
    @Published var switchesSeen = false
    @Published var missingSwitches = false
    @Published var diagnosisOnly = false
    @Published var storeHealthy = true
    @Published var language = Localization.systemLanguage {
        didSet { if !demo { UserDefaults.standard.set(language, forKey: "language") } }
    }
    let demo = CommandLine.arguments.contains("--demo")
    var demoConfigured = false
    var demoBackupInvalid = false
    let paths = ToolPaths.bundled
    let store: SessionStore?
    var phone: Phone? { phones.first { $0.id == flow.phoneID } }
    var line: CarrierLine? { phone?.carriers.first { $0.id == flow.lineID } }
    var unfinished: SessionRecord? { sessions.first { $0.phase.isUnfinished } }
    var support: Support? { guard let phone else { return nil }; if flow.mode != .activate { return Compatibility.deviceCheck(phone) }; guard let line else { return .diagnosisOnly(t("Белорусская SIM не найдена.", "No Belarus SIM was found.")) }; return Compatibility.check(phone, line: line) }
    var backups: [SessionRecord] { guard let phone else { return [] }; return sessions.filter { BackupEligibility.matches($0, phone: phone) }.sorted { $0.created < $1.created } }
    var recommendedID: UUID? { guard let phone else { return nil }; return BackupEligibility.firstOriginal(sessions, phone: phone) }
    var selectedBackup: SessionRecord? { backups.first { $0.id == flow.backupID } }
    var canWrite: Bool { !demo && !busy && !refreshing && support == .eligible && unfinished == nil && storeHealthy && store != nil && (flow.mode != .restore || selectedBackup != nil) }
    var connectedState: ConnectionState? { connections.first { $0.id == flow.phoneID }?.state }
    var radioReminder: String { t("Верните Wi-Fi и вторую SIM, если отключали их. Для повседневного использования можно выбрать «5G автоматически».", "Turn Wi-Fi and your second SIM back on if you disabled them. You can use 5G Auto for everyday use.") }
    func t(_ ru: String, _ en: String) -> String { Localization.text(ru, en, language: language) }
    init(storeFactory: () throws -> SessionStore = { try SessionStore() }) {
        if demo { store = nil; return }
        if let saved = UserDefaults.standard.string(forKey: "language"), Localization.supportedLanguages.contains(saved) { language = saved }
        do { store = try storeFactory() } catch { store = nil; storeHealthy = false; self.error = error.localizedDescription }
        resetNavigationForLaunch()
    }
    func resetNavigationForLaunch() {
        guard !busy, !mutating else { return }
        if store != nil { error = nil; reloadSessions() }
        // wizard.json remains compatible with older versions, but is never a launch route.
        flow = WizardState()
        transactionProgress = nil; status = ""; evidence = nil
        singleLine = false; switchesSeen = false; missingSwitches = false; diagnosisOnly = false
        if !storeHealthy {
            flow.mode = .recover; flow.step = .recovery
        } else if let pending = unfinished {
            flow.mode = .recover; flow.step = .recovery
            flow.phoneID = pending.phone.id; flow.lineID = pending.line.id
        }
    }
    private func persistFlow() {
        guard !demo, storeHealthy, let store else { return }
        do { try PrivateStorage.write(JSONEncoder().encode(flow), to: store.root.appendingPathComponent("wizard.json")) }
        catch { self.error = error.localizedDescription; storeHealthy = false }
    }
    func reloadSessions() {
        guard !demo else { return }
        do { sessions = try store?.all() ?? []; storeHealthy = store != nil }
        catch { storeHealthy = false; self.error = error.localizedDescription }
    }
    func start(_ mode: FlowMode) {
        guard !busy, !mutating else { return }
        reloadSessions()
        guard storeHealthy else { flow.step = .recovery; return }
        transactionProgress = nil; error = nil; status = ""; evidence = nil; singleLine = false; switchesSeen = false; missingSwitches = false; diagnosisOnly = false
        if let pending = unfinished {
            flow.mode = .recover; flow.step = .recovery; flow.phoneID = pending.phone.id; flow.lineID = pending.line.id
        } else {
            flow = WizardState(); flow.mode = mode; flow.step = .connect
            if phones.count == 1 { selectPhone(phones[0].id) }
        }
    }
    func selectPhone(_ id: String) { flow.phoneID = id; selectLine(); advanceConnection() }
    func selectLine() { flow.lineID = phone?.carriers.first(where: \.isBelarus)?.id ?? ""; evidence = nil; singleLine = false }
    func advanceConnection() {
        flow.observeConnection(readyIDs: phones.map(\.id), attachedIDs: connections.map(\.id))
        if flow.step == .backups && flow.backupID == nil { flow.backupID = recommendedID ?? backups.first?.id }
    }
    func refresh() async {
        if demo && demoConfigured { return }
        guard !busy, !refreshing else { return }; refreshing = true; defer { refreshing = false }
        if demo {
            phones = [Phone(id: "demo", name: "iPhone", productType: "iPhone15,4", productVersion: "27.0", buildVersion: "24A437", hardwareModel: "D37AP", carriers: [CarrierLine(slot: "kOne", mcc: "257", mnc: "02", bundleID: "com.apple.MTS_by", bundleVersion: "72.0"), CarrierLine(slot: "kTwo", mcc: "257", mnc: "04", bundleID: "demo.life", bundleVersion: "72.0")])]
        } else {
            let paths = paths
            do {
                let snapshot = try await Task.detached { try ToolRunner.connectionSnapshot(paths: paths) }.value
                phones = snapshot.devices; connections = snapshot.connections; connectionIssue = nil
            } catch {
                phones = []; connections = []
                connectionIssue = t("Ожидаем связи с iPhone. Разблокируйте экран и проверьте кабель.", "Waiting for your iPhone. Unlock its screen and check the cable.")
                return
            }
        }
        if flow.phoneID.isEmpty {
            if phones.count == 1 { flow.phoneID = phones[0].id; selectLine() }
            else if connections.count == 1 { flow.phoneID = connections[0].id }
        }
        if line == nil && phone != nil { selectLine() }
        if demo { configureDemoIfNeeded(); return }
        advanceConnection()
    }
    func monitor() async {
        await refresh()
        if demo { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            if [.home, .connect, .trust, .restart, .recovery].contains(flow.step) { await refresh() }
        }
    }
    func nextFromBackups() {
        if demo {
            if demoBackupInvalid { error = t("Целостность копии не подтверждена. Выберите другую копию.", "Backup integrity could not be verified. Choose another backup.") }
            else { flow.step = .prepare }
            return
        }
        guard let backup = selectedBackup, let store else { return }
        do { _ = try store.original(backup); error = nil; flow.step = .prepare }
        catch { self.error = error.localizedDescription }
    }
    func back() {
        guard !busy else { return }; error = nil; status = ""
        switch flow.step {
        case .connect, .trust, .review, .backups, .about: flow.step = .home
        case .prepare: flow.step = flow.mode == .activate ? .review : .backups
        case .network: flow.step = standaloneDiagnosis ? .home : .settings
        case .settings: flow.step = .restart
        case .result: flow.step = .home
        default: break
        }
    }
    func progress(_ progress: TransactionProgress) {
        transactionProgress = progress
        switch progress {
        case .saving: status = t("Сохраняем настройки…", "Saving settings…")
        case .applying: status = t("Включаем 5G…", "Enabling 5G…")
        case .restoring: status = t("Возвращаем исходные настройки…", "Restoring original settings…")
        case .finishing: status = t("Завершаем…", "Finishing…")
        }
    }
    func execute() {
        guard canWrite, let phone, let store else { return }
        let backup = flow.mode == .restore ? selectedBackup : nil
        guard let targetLine = flow.mode == .activate ? line : backup?.line else { return }
        transactionProgress = .saving
        busy = true; mutating = true; error = nil; flow.operationStartedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)); flow.step = .working; status = t("Сохраняем настройки…", "Saving settings…")
        let paths = paths
        Task {
            do {
                let result = try await Task.detached {
                    try Transaction(store: store, backend: NativeBackend(paths: paths), progress: { event in Task { @MainActor in self.progress(event) } }).apply(phone: phone, line: targetLine, restoring: backup)
                }.value
                flow.operationID = result.id; flow.step = .restart; flow.sawDisconnect = false; flow.restartConfirmed = false
                if result.phase == .restored { flow.mode = .restore }
                if let message = result.message { self.error = message }
                status = ""
            } catch { self.error = error.localizedDescription; flow.step = .recovery; flow.mode = .recover; status = "" }
            busy = false; mutating = false; reloadSessions()
        }
    }
    func confirmRestart() {
        flow.restartConfirmed = true
        // Acknowledgement is independent of transient USB polling. Advance on a fresh snapshot.
        if !refreshing { Task { await refresh() } }
    }
    func skipNetwork() { guard !busy else { return }; flow.checkedNetwork = false; flow.confirmedNR = false; flow.step = .result }
    func startDiagnosis() {
        guard !busy, storeHealthy, line?.isBelarus == true, unfinished == nil else { return }
        diagnosisOnly = true; singleLine = false; evidence = nil; error = nil; status = ""
        flow.mode = .activate; flow.operationID = nil; flow.checkedNetwork = false; flow.confirmedNR = false; flow.step = .network
    }
    func diagnose() {
        guard !demo, !busy, let phone, let line, let store, singleLine, line.isBelarus else { return }
        busy = true; error = nil; evidence = nil; status = t("Пользуйтесь мобильным интернетом на iPhone. Проверка займёт 60 секунд…", "Use mobile data on your iPhone. The check takes 60 seconds…")
        let paths = paths
        Task {
            do {
                let result = try await Task.detached {
                    let folder = store.root.deletingLastPathComponent().appendingPathComponent("diagnostics/\(UUID().uuidString)")
                    try PrivateStorage.directory(folder)
                    let capture = try LogCapture(paths: paths, udid: phone.id, file: folder.appendingPathComponent("radio.log"), processName: "CommCenter")
                    defer { capture.stop() }
                    for _ in 0..<60 { try await Task.sleep(for: .seconds(1)); _ = try capture.read() }
                    return RadioEvidence.parse(try capture.read(), plmn: line.mcc + "-" + line.mnc, unambiguousDataLine: true)
                }.value
                evidence = result; flow.checkedNetwork = true; flow.confirmedNR = result.confirmed; flow.step = .result; status = ""
            } catch { self.error = error.localizedDescription; status = "" }
            busy = false
        }
    }
    func recover() {
        guard !demo, !busy, !refreshing, let store, let session = unfinished, phone?.id == session.phone.id else { return }
        transactionProgress = nil
        busy = true; mutating = true; error = nil; let paths = paths; status = t("Проверяем возможность восстановления…", "Checking recovery state…")
        Task {
            do {
                let result = try await Task.detached { try Transaction(store: store, backend: NativeBackend(paths: paths), progress: { event in Task { @MainActor in self.progress(event) } }).recover(session) }.value
                flow.operationID = result.id; flow.mode = .restore; flow.step = .restart; flow.restartConfirmed = false; flow.sawDisconnect = false; status = ""
            } catch { self.error = error.localizedDescription; status = "" }
            busy = false; mutating = false; reloadSessions()
        }
    }
    var resultDescription: String {
        if flow.confirmedNR { return t("Модем подтвердил активное соединение во время проверки.", "The modem confirmed an active connection during the check.") }
        let prefix = settingsApplied ? t("Настройки применены. ", "Settings applied. ") : ""
        return prefix + (flow.checkedNetwork ? t("Проверьте покрытие и услугу 5G. Недостаток сообщений модема не доказывает отсутствие 5G.", "Check coverage and 5G provisioning. Missing modem messages do not prove 5G is unavailable.") : t("Проверка сети пропущена.", "Network check skipped."))
    }
    func openFinder() { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) } }
    func openBackups() { if let store { NSWorkspace.shared.open(store.root) } }
    func openRecovery() { if let url = Bundle.main.url(forResource: "RECOVERY", withExtension: "md") { NSWorkspace.shared.open(url) } }
}
