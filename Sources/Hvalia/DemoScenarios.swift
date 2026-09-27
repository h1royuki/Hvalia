import SwiftUI
import HvaliaCore

extension AppModel {
    private func demoConnection(id: String, state: ConnectionState) -> DeviceConnection {
        // Exercise the same Codable boundary as a helper snapshot using invented identifiers.
        let data = try! JSONSerialization.data(withJSONObject: ["id": id, "state": state.rawValue])
        return try! JSONDecoder().decode(DeviceConnection.self, from: data)
    }
    func configureDemoIfNeeded(arguments args: [String] = CommandLine.arguments) {
        guard demo, !demoConfigured, let phone, let line else { return }
        demoConfigured = true
        func argument(_ name: String) -> String? { guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }; return args[i + 1] }
        if let locale = argument("--demo-language"), Localization.supportedLanguages.contains(locale) { language = locale }
        var first = SessionRecord(phone: phone, line: line)
        first.id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        first.created = Date(timeIntervalSince1970: 1_790_000_000); first.phase = .restartNeeded; first.originalSHA256 = "demo-only"
        var second = SessionRecord(phone: phone, line: line)
        second.id = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        second.created = first.created.addingTimeInterval(3600); second.phase = .restored; second.originalSHA256 = "demo-only"; second.previousSessionID = first.id
        sessions = [second, first]
        connections = [demoConnection(id: phone.id, state: .ready)]
        if argument("--demo-mode") == "restore" { flow.mode = .restore; flow.backupID = first.id }
        if let step = argument("--demo-step"), let value = FlowStep(rawValue: step) { flow.step = value }
        if flow.step == .backups { flow.mode = .restore; flow.backupID = first.id }
        if [.restart, .settings, .network, .result].contains(flow.step) { flow.operationID = first.id }
        if flow.step == .working { busy = true; progress(.saving) }
        if flow.step == .result { flow.checkedNetwork = true; if flow.mode == .restore { flow.operationID = second.id } }
        if flow.step == .recovery { first.phase = .recoveryRequired; sessions = [first]; flow.mode = .recover }
        switch argument("--demo-scenario") ?? "" {
        case "no-device": flow.step = .connect; phones = []; connections = []
        case "multiple-devices":
            flow.step = .connect; flow.phoneID = ""; flow.lineID = ""
            phones.append(Phone(id: "demo-other", name: "Second iPhone", productType: phone.productType, productVersion: phone.productVersion, buildVersion: phone.buildVersion, hardwareModel: phone.hardwareModel, carriers: phone.carriers))
        case "locked", "trust":
            flow.step = .trust; phones = []
            connections = [demoConnection(id: phone.id, state: argument("--demo-scenario") == "locked" ? .locked : .needsTrust)]
        case "multiple-lines": flow.step = .review
        case "no-backups": flow.mode = .restore; flow.step = .backups; sessions = []
        case "invalid-backup": flow.mode = .restore; flow.step = .backups; flow.backupID = first.id; demoBackupInvalid = true; error = t("Целостность копии не подтверждена. Выберите другую копию.", "Backup integrity could not be verified. Choose another backup.")
        case "many-backups":
            flow.mode = .restore; flow.step = .backups; flow.backupID = first.id
            for i in 1...12 { var copy = second; copy.id = UUID(); copy.created = first.created.addingTimeInterval(Double(i) * 86400); sessions.append(copy) }
        case "saving", "applying", "restoring", "finishing":
            flow.step = .working; busy = true
            if argument("--demo-scenario") == "restoring" { flow.mode = .restore }
            progress(TransactionProgress(rawValue: argument("--demo-scenario")!) ?? .saving)
        case "restart-waiting": flow.step = .restart; flow.restartConfirmed = true; phones = []; connections = []
        case "missing-options": flow.step = .settings; flow.operationID = first.id; missingSwitches = true
        case "checking": flow.step = .network; flow.operationID = first.id; busy = true; singleLine = true; status = t("Собираем данные модема…", "Collecting modem data…")
        case "confirmed", "unconfirmed", "skipped":
            flow.step = .result; flow.operationID = first.id; switchesSeen = true
            flow.checkedNetwork = argument("--demo-scenario") != "skipped"
            flow.confirmedNR = argument("--demo-scenario") == "confirmed"
            if flow.confirmedNR { var e = RadioEvidence(); e.plmn = true; e.modemNR = true; e.activeNR = true; e.endcInterface = true; evidence = e }
        case "diagnosis": flow.step = .network; flow.operationID = nil; diagnosisOnly = true
        case "diagnosis-result": flow.step = .result; flow.operationID = nil; diagnosisOnly = true; flow.checkedNetwork = true
        case "restored": flow.mode = .restore; flow.step = .result; flow.operationID = second.id
        case "wrong-device":
            first.phase = .recoveryRequired; sessions = [first]; flow.mode = .recover; flow.step = .recovery; flow.phoneID = "original-not-present"
        case "damaged-store":
            storeHealthy = false; flow.mode = .recover; flow.step = .recovery
            error = t("Сохранённые данные повреждены. Сохраните копии и откройте инструкцию восстановления.", "Saved data is damaged. Preserve backups and open the recovery guide.")
        default: break
        }
        if args.contains("--demo-error") {
            error = t("Соединение с iPhone прервано. Подключите тот же телефон, чтобы проверить состояние операции.\nДемонстрационный журнал: устройство отключено во время сохранения. Автоматический повтор записи остановлен.", "The iPhone connection was interrupted. Reconnect the same phone to check the operation.\nDemo log: disconnected during backup. Automatic write retry stopped.")
        }
    }
}
