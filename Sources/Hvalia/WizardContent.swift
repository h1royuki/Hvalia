import SwiftUI
import HvaliaCore

struct WizardContent: View {
    @EnvironmentObject var m: AppModel
    @ViewBuilder var body: some View {
        switch m.flow.step {
        case .home: home
        case .connect, .trust: connection
        case .review: review
        case .backups: backups
        case .prepare: prepare
        case .working:
            deviceSummary
            WaveOperationStages()
        case .restart: restart
        case .settings: settings
        case .network: network
        case .result: result
        case .recovery: recovery
        case .about: home
        }
    }
    var home: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            if m.demo {
                HStack {
                    Spacer()
                    Label(m.t("Демо · запись отключена", "Demo · writing disabled"), systemImage: "eye")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            WaveWelcome()
            Divider()
            HStack(spacing: 16) {
                Image(systemName: "iphone").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    if let phone = m.phone ?? m.phones.first {
                        Text(phone.displayModel).font(.headline)
                        Label(m.t("Подключён", "Connected"), systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Text(m.t("Подключите iPhone", "Connect your iPhone")).font(.headline)
                        Text(m.t("Кабелем к Mac, затем разблокируйте экран", "Use a cable to connect to your Mac, then unlock the screen"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 4).accessibilityElement(children: .combine)
            DisclosureGroup(m.t("Совместимость и условия", "Compatibility and requirements")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.t("Нужны iPhone с поддержкой 5G, подходящий тариф и покрытие. Работа метода на всех моделях и версиях iOS не гарантируется.", "A 5G-capable iPhone, an eligible plan and coverage are required. The method is not guaranteed to work on every model and iOS version."))
                    Text(m.t("Приложение меняет настройки телефона, но не подключает услугу 5G и не увеличивает покрытие.", "The app changes phone settings; it does not provision 5G service or extend coverage."))
                }.font(.callout).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
    }
    var deviceSummary: some View {
        VStack(alignment: .leading, spacing: Layout.related) {
            if let phone = m.phone ?? (m.flow.step == .home ? m.phones.first : nil) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "iphone").accessibilityHidden(true)
                    Text(phone.displayModel).fontWeight(.medium)
                    if let line = m.line { Text("· " + line.operatorName).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    Label(m.t("Подключён", "Connected"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }.accessibilityElement(children: .combine)
                DisclosureGroup(m.t("Подробности", "Details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iOS \(phone.productVersion) · \(phone.buildVersion) · \(phone.hardwareModel)")
                        if let line = m.line {
                            Text("\(line.mcc)/\(line.mnc) · \(line.bundleID) \(line.bundleVersion)")
                            if let leaf = try? Compatibility.candidateLeaf(phone, line: line) { Text(m.t("Предполагаемый файл: ", "Expected file: ") + leaf).textSelection(.enabled) }
                        }
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            } else {
                Label(m.t("iPhone не подключён", "No iPhone connected"), systemImage: "cable.connector").fontWeight(.medium)
                Text(m.t("Подключите его кабелем и разблокируйте экран.", "Connect it with a cable and unlock the screen.")).foregroundStyle(.secondary)
            }
        }
    }
    var connection: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            if m.flow.step == .trust {
                if m.connectedState == .locked {
                    Text(m.t("Введите код-пароль на самом iPhone.", "Enter the passcode on your iPhone."))
                } else {
                Instructions(rows: [m.t("Откройте Finder и выберите iPhone слева.", "Open Finder and select your iPhone in the sidebar."), m.t("Нажмите «Доверять», если появилась такая кнопка.", "Click Trust if prompted."), m.t("На iPhone нажмите «Доверять» и введите код-пароль телефона.", "Tap Trust on your iPhone and enter its passcode.")])
                }
            } else {
                if m.flow.mode != .activate { Text(m.t("Подключите тот же iPhone, для которого сохранена копия.", "Connect the same iPhone the backup belongs to.")).foregroundStyle(.secondary) }
                if m.phones.count > 1 {
                    ForEach(m.phones) { phone in Button { m.selectPhone(phone.id) } label: { Label(phone.name + " · " + phone.displayModel, systemImage: "iphone").frame(maxWidth: .infinity, alignment: .leading) }.waveButton() }
                }
                if m.connections.count > 1 && m.phones.isEmpty { Text(m.t("Оставьте подключённым только нужный iPhone.", "Leave only the intended iPhone connected.")) }
                Button(m.t("Подключён, но не появился", "Connected but not showing")) { m.flow.step = .trust }
                Text(m.t("Попробуйте другой порт или кабель. Проверьте, виден ли телефон в Finder.", "Try another port or cable. Check whether the phone appears in Finder.")).foregroundStyle(.secondary)
            }
            if m.refreshing { Text(m.t("Проверяем подключение…", "Checking connection…")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    var review: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            deviceSummary
            if let phone = m.phone, phone.carriers.filter(\.isBelarus).count > 1 {
                Picker(m.t("Линия", "Line"), selection: $m.flow.lineID) { ForEach(phone.carriers.filter(\.isBelarus)) { line in Text(m.lineTitle(line)).tag(line.id) } }.pickerStyle(.menu)
            }
            if case .diagnosisOnly(let reason) = m.support {
                Label(reason, systemImage: "exclamationmark.circle").fixedSize(horizontal: false, vertical: true)
                if m.line?.isBelarus == true { Button(m.t("Перейти к проверке сети", "Go to network check")) { m.startDiagnosis() } }
            } else {
                Text(m.t("Подготовим профиль по данным телефона. Изменения применяются только после сохранения и проверки оригинала.", "The profile is prepared from your phone's details. Changes are applied only after saving and validating the original.")).foregroundStyle(.secondary)
            }
            if m.line?.mnc == "04" { Text(m.t("Подключение к life:) ещё не проверено на сети.", "Network access with life:) has not yet been verified.")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    var backups: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            if m.backups.isEmpty {
                Label(m.t("Подходящей копии нет", "No compatible backup"), systemImage: "externaldrive.badge.questionmark").fontWeight(.medium)
                Text(m.t("Для восстановления нужна копия, сохранённая Hvalia или NRBridge. Подключите тот же телефон.", "Restoration requires a backup saved by Hvalia or NRBridge. Connect the same phone.")).foregroundStyle(.secondary)
            } else {
                List(selection: $m.flow.backupID) {
                    ForEach(m.backups) { backup in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(backup.created.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: m.language)))).fontWeight(.medium)
                                Spacer()
                                if backup.id == m.recommendedID { Label(m.t("Оригинал", "Original"), systemImage: "checkmark.seal").font(.caption) }
                            }
                            Text(backup.id == m.recommendedID ? m.t("До первой активации · рекомендуется", "Before first activation · recommended") : m.t("Снимок настроек", "Settings snapshot")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(backup.id)
                    }
                }.listStyle(.inset).frame(height: min(CGFloat(m.backups.count) * 62 + 8, 192))
                Text(m.t("Перед восстановлением проверим целостность копии.", "The backup's integrity is checked before restoration.")).foregroundStyle(.secondary)
            }
        }
    }
    var prepare: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            deviceSummary
            if let backup = m.selectedBackup, m.flow.mode == .restore { Text(m.t("Копия от ", "Backup from ") + backup.created.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: m.language)))) }
            Text(m.flow.mode == .activate ? m.t("Экспериментальный метод. Изменения общего профиля Беларуси могут повлиять на обе линии.", "Experimental method. Changes to the shared Belarus profile may affect both lines.") : m.t("Сохраним текущее состояние и вернём точные байты выбранной копии.", "We will save the current state and restore the exact selected backup."))
            DisclosureGroup(m.t("О методе", "About this method")) {
                Text(m.t("Экспериментальный метод. Имя файла определяется по модели и версии настроек оператора; его наличие не гарантируется. Сохраняются две проверенные копии на этом Mac; они не защищают от потери диска. Не запускайте синхронизацию Finder во время операции. Работа метода на всех моделях и версиях iOS не гарантируется.", "Experimental method. The filename is inferred from the board and carrier settings version; its existence is not guaranteed. Two verified copies are saved on this Mac; they do not protect against disk loss. Do not start Finder sync during the operation. The method is not guaranteed to work on every model or iOS build.")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    var restart: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            Instructions(rows: [m.t("Удерживайте боковую кнопку и любую кнопку громкости.", "Hold the side button and either volume button."), m.t("Передвиньте ползунок «Выключить».", "Drag the power-off slider."), m.t("После выключения удерживайте боковую кнопку до логотипа Apple.", "Once off, hold the side button until the Apple logo appears."), m.t("Разблокируйте iPhone и оставьте подключённым к Mac.", "Unlock your iPhone and leave it connected to your Mac.")])
            Text(m.phone == nil || m.flow.restartConfirmed ? m.t("Ожидаем тот же iPhone…", "Waiting for the same iPhone…") : m.t("iPhone доступен. Подтвердите перезагрузку кнопкой внизу.", "Your iPhone is available. Confirm the restart below.")).foregroundStyle(.secondary)
        }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            Instructions(rows: [m.t("Откройте Настройки → Сотовая связь.", "Open Settings → Cellular."), m.t("Выберите линию ", "Select your ") + (m.line?.operatorName ?? "") + m.t(" → Голос и данные.", " line → Voice & Data."), m.t("Выберите «5G вкл.».", "Select 5G On.")])
            Toggle(m.t("Вижу «5G вкл.» и «5G автоматически»", "I can see 5G On and 5G Auto"), isOn: $m.switchesSeen).onChange(of: m.switchesSeen) { if m.switchesSeen { m.missingSwitches = false } }
            HStack { Button(m.t("Пунктов 5G нет", "5G options are missing")) { m.missingSwitches = true; m.switchesSeen = false }; Button(m.t("Проверить позже", "Check later")) { m.skipNetwork() } }
            if m.missingSwitches {
                Text(m.t("Не повторяйте запись. Можно проверить сеть кнопкой внизу или восстановить оригинал.", "Do not repeat the write. Check the network below or restore the original.")).foregroundStyle(.secondary)
                Button(m.t("Восстановить настройки", "Restore settings")) { m.start(.restore) }
            }
        }
    }
    var network: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            Instructions(rows: [m.t("Выключите Wi-Fi в Настройках.", "Turn off Wi-Fi in Settings."), m.t("Временно отключите вторую SIM, если она есть.", "Temporarily disable your second SIM, if present."), m.t("Выберите нужную белорусскую линию для мобильного интернета.", "Select the intended Belarus line for mobile data."), m.t("Во время проверки открывайте веб-страницы на iPhone.", "Browse websites on your iPhone during the check.")])
            Toggle(m.t("Готово: Wi-Fi и вторая SIM выключены, линия выбрана", "Ready: Wi-Fi and second SIM off, correct line selected"), isOn: $m.singleLine).disabled(m.busy)
            Button(m.t("Проверить позже", "Check later")) { m.skipNetwork() }.disabled(m.busy)
        }
    }
    var result: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            if m.flow.mode != .activate {
                WaveFact(title: m.t("Восстановление", "Restoration"), value: m.settingsRestored ? m.t("Завершено", "Completed") : m.t("Не подтверждено", "Not confirmed"), confirmed: m.settingsRestored)
            } else {
                VStack(spacing: 10) {
                    if !m.standaloneDiagnosis {
                        WaveFact(title: m.t("Настройки", "Settings"), value: m.settingsApplied ? m.t("Применены", "Applied") : m.t("Нет подтверждения", "Not confirmed"), confirmed: m.settingsApplied)
                        WaveFact(title: m.t("Пункты 5G", "5G options"), value: m.switchesSeen ? m.t("Подтверждены вами", "Confirmed by you") : m.t("Не подтверждены", "Not confirmed"), confirmed: m.switchesSeen)
                    }
                    WaveFact(title: m.t("Соединение 5G", "5G connection"), value: m.flow.confirmedNR ? m.t("Подтверждено модемом", "Confirmed by modem") : (m.flow.checkedNetwork ? m.t("Не подтверждено", "Not confirmed") : m.t("Проверка пропущена", "Check skipped")), confirmed: m.flow.confirmedNR)
                }
                Button(m.t("Повторить проверку сети", "Check network again")) { m.flow.step = .network; m.singleLine = false }
                if let e = m.evidence { DisclosureGroup(m.t("Данные модема", "Modem evidence")) { Text(verbatim: "PLMN: \(e.plmn)\nNR NSA: \(e.modemNR)\nActive NR: \(e.activeNR)\nEN-DC: \(e.endcInterface)").font(.caption.monospaced()).textSelection(.enabled) } }
            }
            Text(m.flow.mode == .activate ? m.radioReminder : m.t("Верните Wi-Fi и вторую SIM, если отключали их.", "Turn Wi-Fi and your second SIM back on if you disabled them.")).font(.callout).foregroundStyle(.secondary)
        }
    }
    var recovery: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            if m.unfinished != nil && m.phone?.id != m.unfinished?.phone.id {
                Label(m.t("Нужен исходный iPhone. Проверьте подключение и разблокируйте его.", "The original iPhone is required. Check the connection and unlock it."), systemImage: "iphone.slash").foregroundStyle(.secondary)
            }
            Text(m.t("Если состояние файла неоднозначно, приложение остановится и сохранит журнал для разбора.", "If the file's state is ambiguous, the app stops and retains its journal for investigation.")).foregroundStyle(.secondary)
            Button(m.t("Инструкция восстановления", "Recovery instructions")) { m.openRecovery() }
            Button(m.t("Открыть Finder", "Open Finder")) { m.openFinder() }
        }
    }
}
