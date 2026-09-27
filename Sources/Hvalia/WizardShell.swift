import SwiftUI
import HvaliaCore

struct WizardShell: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            if m.routeIndex != nil {
                WaveStepper()
                Divider()
            }
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Layout.section) {
                            if !m.isHome {
                                HStack {
                                    Text(m.stageName)
                                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    Spacer()
                                    if m.demo { Label(m.t("Демо · запись отключена", "Demo · writing disabled"), systemImage: "eye").font(.caption2).foregroundStyle(.secondary) }
                                }
                                WaveHeading()
                                    .id(m.flow.step)
                                    .transition(.opacity)
                            }
                            WizardContent()
                            if let issue = m.connectionIssue { Label(issue, systemImage: "cable.connector").font(.callout).foregroundStyle(.secondary) }
                            if !m.storeHealthy && m.flow.step != .recovery {
                                WaveNotice(text: m.t("Не удалось проверить сохранённые данные. Новая операция недоступна.", "Saved data could not be verified. A new operation is unavailable."), blocking: true)
                                Button(m.t("Инструкция восстановления", "Recovery guide")) { m.openRecovery() }
                            }
                            if let error = m.error { errorView(error).id("error") }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(m.isHome ? 32 : Layout.inset).id("top")
                    }.scrollBounceBehavior(.basedOnSize)
                        .onChange(of: m.flow.step) { proxy.scrollTo("top", anchor: .top) }
                        .onChange(of: m.error) { if m.error != nil { proxy.scrollTo("error", anchor: .bottom) } }
                }
                if !m.status.isEmpty {
                    HStack(spacing: 10) {
                        if m.busy || m.flow.step == .working { ProgressView().controlSize(.small) }
                        Text(m.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, Layout.inset).padding(.vertical, 8).accessibilityElement(children: .combine)
                }
                if m.flow.step == .prepare {
                    WaveNotice(text: m.t("Оригинал сначала перемещается на iPhone, затем сохраняется. Не отключайте кабель: прерывание может потребовать восстановления.", "The original is moved on the iPhone before it is saved. Keep the cable connected: an interruption may require recovery."))
                        .padding(.horizontal, Layout.inset).padding(.bottom, 8)
                }
                WizardActionBar()
            }
        }
        .animation(reduceMotion || m.flow.step == .recovery ? nil : .easeInOut(duration: 0.2), value: m.flow.step)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) { previewLabel }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) { settingsMenu }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) { previewLabel }
                ToolbarItem(placement: .primaryAction) { settingsMenu }
            }
        }
    }
    private var previewLabel: some View {
        Text("Preview").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
    }
    private var settingsMenu: some View {
        Menu {
            Picker(m.t("Язык", "Language"), selection: $m.language) { Text("Русский").tag("ru"); Text("Беларуская").tag("be"); Text("English").tag("en") }
            Divider()
            Button(m.t("Проверить подключение к 5G", "Check 5G connection"), systemImage: "antenna.radiowaves.left.and.right") { m.startDiagnosis() }.disabled(m.busy || m.line?.isBelarus != true || m.unfinished != nil || !m.storeHealthy)
            Button(m.t("Открыть папку резервных копий", "Open backup folder"), systemImage: "folder") { m.openBackups() }.disabled(m.mutating || m.demo)
            Button(m.t("Инструкция восстановления", "Recovery guide"), systemImage: "questionmark.circle") { m.openRecovery() }
            Link(m.t("Проект на GitHub", "Project on GitHub"), destination: URL(string: "https://github.com/h1royuki/Hvalia")!)
            Divider()
            Text("1.0.0 Preview")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(m.t("Настройки и справка", "Settings and help"))
        .accessibilityLabel(m.t("Настройки и справка", "Settings and help"))
    }
    func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Layout.related) {
            WaveNotice(text: error.components(separatedBy: "\n").first ?? error, blocking: m.flow.step == .recovery || !m.storeHealthy)
            if error.contains("\n") { DisclosureGroup(m.t("Технические подробности", "Technical details")) { Text(error).font(.caption).textSelection(.enabled) } }
        }
    }
}

struct WizardActionBar: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 12) {
            WaveActionContainer {
                HStack(spacing: 12) {
                    if m.isHome {
                        Button { m.start(.activate) } label: {
                            Text(m.t("Включить 5G", "Enable 5G"))
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 6)
                        }
                            .waveButton(prominent: true).tint(.blue).controlSize(.large)
                            .keyboardShortcut(.defaultAction).disabled(m.busy || !m.storeHealthy)
                        Button { m.start(.restore) } label: {
                            Text(m.t("Восстановить", "Restore"))
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 6)
                        }
                            .waveButton().controlSize(.large)
                            .help(m.t("Вернуть исходные настройки", "Restore original settings"))
                            .disabled(m.busy || !m.storeHealthy)
                        Spacer(minLength: 0)
                    } else {
                        if m.canGoBack {
                            Button { m.back() } label: { Label(m.t("Назад", "Back"), systemImage: "chevron.left") }
                                .waveButton().keyboardShortcut(.cancelAction).disabled(m.busy)
                        }
                        Spacer(minLength: 8)
                        if let title = m.primaryTitle {
                            Button(title) { m.performPrimary() }.waveButton(prominent: true).tint(.blue)
                                .keyboardShortcut(.defaultAction).disabled(!m.primaryEnabled)
                        }
                    }
                }.controlSize(.regular)
            }
        }
        .padding(.horizontal, m.isHome ? 32 : Layout.inset)
        .padding(.top, m.isHome ? 16 : 12)
        .padding(.bottom, m.isHome ? 28 : 12)
        .background { if reduceTransparency || m.isHome { Color(nsColor: .windowBackgroundColor) } else { Rectangle().fill(.bar) } }
    }
}

extension AppModel {
    var flowTitle: String { standaloneDiagnosis ? t("Проверка сети", "Network check") : flow.mode == .activate ? t("Включение 5G", "Enable 5G") : t("Восстановление", "Restore settings") }
    var stepLabel: String { guard let index = routeIndex else { return stageName }; return t("Шаг", "Step") + " \(index) " + t("из", "of") + " \(routeCount)" }
    var canGoBack: Bool { ![.home, .working, .restart, .recovery].contains(flow.step) }
    var primaryTitle: String? {
        switch flow.step {
        case .connect: return t("Проверить подключение", "Check connection")
        case .trust: return t("Открыть Finder", "Open Finder")
        case .review: return t("Продолжить", "Continue")
        case .backups: return backups.isEmpty ? nil : t("Проверить копию", "Check backup")
        case .prepare: return flow.mode == .activate ? t("Сохранить и включить", "Back up and enable") : t("Восстановить настройки", "Restore settings")
        case .restart: return flow.restartConfirmed ? t("Ожидаем iPhone…", "Waiting for iPhone…") : t("Я перезагрузил iPhone", "I restarted my iPhone")
        case .settings: return t("Продолжить к проверке", "Continue to check")
        case .network: return t("Проверить · 60 секунд", "Check · 60 seconds")
        case .result: return t("Готово", "Done")
        case .recovery: return !storeHealthy ? nil : (unfinished == nil ? t("К началу", "Go to start") : t("Проверить и восстановить", "Check and recover"))
        default: return nil
        }
    }
    var primaryEnabled: Bool {
        guard !busy else { return false }
        switch flow.step {
        case .connect: return !refreshing
        case .review: return support == .eligible && storeHealthy && unfinished == nil
        case .backups: return selectedBackup != nil
        case .prepare: return canWrite
        case .restart: return !flow.restartConfirmed
        case .settings: return switchesSeen || missingSwitches
        case .network: return !demo && singleLine && line?.isBelarus == true
        case .recovery: return storeHealthy && (unfinished == nil || canRecover)
        default: return true
        }
    }
    func performPrimary() {
        guard primaryEnabled else { return }
        switch flow.step {
        case .connect: Task { await refresh() }
        case .trust: openFinder()
        case .review: flow.step = .prepare
        case .backups: nextFromBackups()
        case .prepare: execute()
        case .restart: confirmRestart()
        case .settings: flow.step = .network
        case .network: diagnose()
        case .result: flow.step = .home
        case .recovery: if unfinished == nil { flow.step = .home } else { recover() }
        default: break
        }
    }
}
