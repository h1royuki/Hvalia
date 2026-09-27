import SwiftUI
import HvaliaCore

struct WavePresentation {
    let title: String
    let subtitle: String
}

extension AppModel {
    var stepSymbol: String { symbol(for: flow.step) }
    private func symbol(for step: FlowStep) -> String {
        switch step {
        case .home, .about: "water.waves"
        case .connect: "cable.connector"
        case .trust: "lock.iphone"
        case .review: "simcard"
        case .backups: "externaldrive"
        case .prepare: flow.mode == .activate ? "externaldrive" : "arrow.uturn.backward.circle"
        case .working: "gearshape.2"
        case .restart: "power"
        case .settings: "slider.horizontal.3"
        case .network: "antenna.radiowaves.left.and.right"
        case .result:
            if flow.mode != .activate { settingsRestored ? "checkmark.circle" : "questionmark.circle" }
            else { flow.confirmedNR ? "checkmark.circle" : "antenna.radiowaves.left.and.right" }
        case .recovery: "lifepreserver"
        }
    }
    func lineTitle(_ line: CarrierLine) -> String {
        let index = (phone?.carriers.firstIndex { $0.id == line.id } ?? 0) + 1
        return line.operatorName + " · " + t("Линия", "Line") + " " + String(index)
    }
    var standaloneDiagnosis: Bool {
        diagnosisOnly || (flow.mode == .activate && [.network, .result].contains(flow.step) && flow.operationID == nil)
    }
    var isHome: Bool { [.home, .about].contains(flow.step) }
    var routeCount: Int { flow.mode == .activate ? 8 : 6 }
    var routeTitles: [String] {
        let connection = [t("Подключение", "Connection"), t("Доступ", "Access")]
        if flow.mode == .activate {
            return connection + [t("Телефон и линия", "iPhone and line"), t("Подготовка", "Preparation"), t("Применение", "Apply settings"), t("Перезагрузка", "Restart"), t("Настройки iPhone", "iPhone settings"), t("Проверка сети", "Network check")]
        }
        return connection + [t("Выбор копии", "Choose backup"), t("Восстановление", "Restore settings"), t("Перезагрузка", "Restart"), t("Результат", "Result")]
    }
    func routeSymbol(at index: Int) -> String {
        if index + 1 == routeIndex { return stepSymbol }
        let steps: [FlowStep] = flow.mode == .activate
            ? [.connect, .trust, .review, .prepare, .working, .restart, .settings, .network]
            : [.connect, .trust, .backups, .prepare, .restart, .result]
        let step = steps[index]
        return step == .result ? "flag" : symbol(for: step)
    }
    var routeIndex: Int? {
        guard !isHome, flow.step != .recovery, !standaloneDiagnosis else { return nil }
        let activation: [FlowStep: Int] = [.connect: 1, .trust: 2, .review: 3, .prepare: 4, .working: 5, .restart: 6, .settings: 7, .network: 8, .result: 8]
        let restore: [FlowStep: Int] = [.connect: 1, .trust: 2, .backups: 3, .prepare: 4, .working: 4, .restart: 5, .result: 6]
        return (flow.mode == .activate ? activation : restore)[flow.step]
    }
    var stageName: String {
        if standaloneDiagnosis { return t("Проверка сети", "Network check") }
        switch flow.step {
        case .home, .about: return "Preview"
        case .connect: return t("Подключение", "Connection")
        case .trust: return t("Доступ", "Access")
        case .review: return t("Телефон и линия", "iPhone and line")
        case .backups: return t("Выбор копии", "Choose a backup")
        case .prepare: return t("Подготовка", "Preparation")
        case .working: return t("Применение", "Applying settings")
        case .restart: return t("Перезагрузка", "Restart")
        case .settings: return t("Настройки iPhone", "iPhone settings")
        case .network: return t("Проверка сети", "Network check")
        case .result: return t("Результат", "Result")
        case .recovery: return t("Восстановление", "Recovery")
        }
    }
    var presentation: WavePresentation {
        switch flow.step {
        case .home, .about:
            return .init(title: "Hvalia", subtitle: t("Включение 5G на iPhone в Беларуси", "Enable 5G on iPhone in Belarus"))
        case .connect:
            return .init(title: t("Подключите iPhone", "Connect your iPhone"), subtitle: t("Используйте кабель с передачей данных и разблокируйте экран.", "Use a data cable and unlock the screen."))
        case .trust:
            return .init(title: connectedState == .locked ? t("Разблокируйте iPhone", "Unlock your iPhone") : t("Разрешите доступ к iPhone", "Allow access to your iPhone"), subtitle: t("После предоставления доступа продолжим автоматически.", "We will continue automatically when access is available."))
        case .review:
            return .init(title: t("Проверьте телефон и линию", "Check your iPhone and line"), subtitle: t("На выбранной линии будем проверять соединение с 5G.", "We will check the 5G connection on the selected line."))
        case .backups:
            return .init(title: t("Выберите исходные настройки", "Choose original settings"), subtitle: t("Копии для этого iPhone и текущей версии iOS.", "Backups for this iPhone and its current iOS version."))
        case .prepare:
            return flow.mode == .activate
                ? .init(title: t("Сначала сохраним оригинал", "First, save the original"), subtitle: t("Создадим две проверенные копии на Mac перед изменением настроек.", "We will save and verify two copies on this Mac before changing settings."))
                : .init(title: t("Вернём исходные настройки", "Restore original settings"), subtitle: t("Сохраним текущее состояние и вернём точные байты выбранной копии.", "We will save the current state and restore the exact selected backup."))
        case .working:
            return .init(title: t("Не отключайте iPhone", "Keep your iPhone connected"), subtitle: t("Не запускайте синхронизацию Finder и другие программы для телефона.", "Do not start Finder sync or other phone utilities."))
        case .restart:
            return .init(title: t("Перезагрузите iPhone", "Restart your iPhone"), subtitle: t("Выключите и снова включите телефон обычным способом.", "Turn your iPhone off and back on normally."))
        case .settings:
            return .init(title: t("Выберите 5G на iPhone", "Select 5G on your iPhone"), subtitle: t("Откройте настройки выбранной линии.", "Open the settings for the selected line."))
        case .network:
            return .init(title: t("Проверим соединение", "Check the connection"), subtitle: busy ? t("Открывайте веб-страницы на iPhone, пока собираются данные модема.", "Browse websites on your iPhone while modem data is collected.") : t("Проверка занимает 60 секунд и использует данные модема.", "The check takes 60 seconds and uses modem data."))
        case .result:
            if flow.mode != .activate {
                if !settingsRestored { return .init(title: t("Восстановление не подтверждено", "Restoration not confirmed"), subtitle: t("Проверьте сохранённые данные и инструкцию восстановления.", "Check saved data and the recovery guide.")) }
                return .init(title: t("Исходные настройки восстановлены", "Original settings restored"), subtitle: t("Проверьте звонки и мобильный интернет. Пункты 5G могут остаться, если они были в оригинале.", "Check calls and mobile data. 5G options may remain if they were in the original."))
            }
            let title = flow.confirmedNR ? t("Подключение к 5G подтверждено", "5G connection confirmed") : (flow.checkedNetwork ? t("Соединение с 5G не подтверждено", "5G connection not confirmed") : t("Проверку сети можно выполнить позже", "You can check the network later"))
            return .init(title: title, subtitle: resultDescription)
        case .recovery:
            return .init(title: storeHealthy ? t("Завершим восстановление", "Complete recovery") : t("Проверьте сохранённые данные", "Check saved data"), subtitle: t("Подключите тот же iPhone. Не запускайте синхронизацию и не удаляйте копии.", "Connect the same iPhone. Do not start sync or delete backups."))
        }
    }
    var canRecover: Bool { !demo && !busy && !refreshing && storeHealthy && unfinished != nil && phone?.id == unfinished?.phone.id }
    var settingsRestored: Bool {
        guard let id = flow.operationID else { return false }
        return sessions.contains { $0.id == id && $0.phase == .restored }
    }
    var settingsApplied: Bool {
        guard !standaloneDiagnosis, let id = flow.operationID else { return false }
        return sessions.contains { $0.id == id && [.restartNeeded, .nrConfirmed].contains($0.phase) }
    }
}
