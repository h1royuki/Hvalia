import SwiftUI
import HvaliaCore

@main struct UIModelChecks {
    @MainActor static func main() async throws {
        precondition(CommandLine.arguments.contains("--demo"), "Checks must run in demo mode")
        var storeOpened = false
        let m = AppModel(storeFactory: { storeOpened = true; throw BridgeError.message("No store may be opened") })
        precondition(!storeOpened && m.store == nil, "Demo must never initialize real session storage")
        let languageBeforeDemo = UserDefaults.standard.string(forKey: "language")
        m.language = "en"
        precondition(UserDefaults.standard.string(forKey: "language") == languageBeforeDemo, "Demo must not modify language preferences")
        await m.refresh()
        precondition(m.phone != nil && m.sessions.count == 2)
        m.demoConfigured = false
        m.configureDemoIfNeeded(arguments: ["--demo", "--demo-language", "be"])
        precondition(m.language == "be" && UserDefaults.standard.string(forKey: "language") == languageBeforeDemo)
        precondition(!m.canWrite)
        let originalStep = m.flow.step
        m.execute(); m.recover(); m.diagnose()
        precondition(!m.busy && m.flow.step == originalStep, "Demo must never invoke device operations")
        m.flow.step = .prepare
        precondition(!m.primaryEnabled, "Demo write CTA must stay disabled")
        m.progress(.saving); precondition(m.transactionProgress == .saving)
        m.progress(.restoring); precondition(m.transactionProgress == .restoring)
        m.startDiagnosis()
        precondition(m.standaloneDiagnosis && m.routeIndex == nil && !m.settingsApplied)
        m.skipNetwork()
        precondition(!m.flow.confirmedNR && !m.flow.checkedNetwork && !m.settingsApplied)
        m.diagnosisOnly = false // Equivalent to reloading old Codable wizard data.
        precondition(m.standaloneDiagnosis, "Standalone diagnosis must remain truthful without transient flag")
        let backup = m.sessions.first { $0.phase == .restartNeeded }!
        m.flow.operationID = backup.id; m.flow.step = .result
        precondition(m.settingsApplied && !m.flow.confirmedNR, "Applied settings do not prove NR")
        m.sessions = []; precondition(!m.settingsRestored, "Missing journal must not claim restoration")
        precondition(!m.settingsApplied, "An ID alone must not claim successful settings")
        m.sessions = [backup]; m.flow.mode = .restore; m.flow.step = .backups; m.flow.backupID = backup.id
        let p = backup.phone
        m.phones = [Phone(id: p.id, name: p.name, productType: p.productType, productVersion: p.productVersion, buildVersion: p.buildVersion, hardwareModel: p.hardwareModel, carriers: [])]
        precondition(m.support == .eligible && m.selectedBackup != nil, "SIM removal must not invalidate restoration")
        m.demoBackupInvalid = true; m.nextFromBackups()
        precondition(m.flow.step == .backups && m.error != nil, "A failed backup check must not reach prepare")
        var pending = backup; pending.phase = .recoveryRequired; m.sessions = [pending]
        m.flow.step = .recovery; m.flow.phoneID = "wrong-demo-phone"
        precondition(!m.primaryEnabled && !m.canRecover)
        m.storeHealthy = false; m.start(.activate)
        precondition(m.flow.step == .recovery && !m.canWrite && m.primaryTitle == nil)
        m.storeHealthy = true; m.sessions = [backup]
        for oldStep in [FlowStep.prepare, .working, .restart, .settings, .network, .result, .backups] {
            m.flow.step = oldStep; m.flow.mode = .restore; m.flow.phoneID = "stale-phone"
            m.flow.operationID = backup.id; m.flow.confirmedNR = true; m.switchesSeen = true
            m.resetNavigationForLaunch()
            precondition(m.flow.step == .home && m.flow.mode == .activate)
            precondition(m.flow.phoneID.isEmpty && m.flow.operationID == nil && !m.flow.confirmedNR && !m.switchesSeen)
        }
        m.sessions = [pending]; m.resetNavigationForLaunch()
        precondition(m.flow.step == .recovery && m.flow.mode == .recover && m.flow.phoneID == pending.phone.id)
        m.sessions = []; m.storeHealthy = false; m.resetNavigationForLaunch()
        precondition(m.flow.step == .recovery && !m.primaryEnabled)
        m.storeHealthy = true; m.sessions = []; m.busy = true
        let delegate = AppDelegate(); delegate.model = m
        precondition(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        delegate.configure(window)
        precondition(window.frame.size == NSSize(width: 720, height: 520))
        precondition(window.minSize == window.maxSize && !window.styleMask.contains(.resizable))
        precondition(window.collectionBehavior.contains(.fullScreenNone))
        precondition(window.standardWindowButton(.zoomButton)?.isHidden == true)
        precondition(!delegate.windowShouldZoom(window, toFrame: .zero))
        precondition(!delegate.windowShouldClose(window) && delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        let step = m.flow.step; m.start(.activate); m.back(); m.skipNetwork()
        precondition(m.flow.step == step, "Busy operations must block navigation")
        m.busy = false; m.flow.step = .settings; window.title = "Hvalia"
        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        precondition(m.flow.step == .home, "Closing the main window must discard ordinary navigation")
        print("PASS: demo isolation, mutation guards, typed progress, evidence separation, backup gate, recovery, fixed window, clean launch and busy navigation")
        if CommandLine.arguments.contains("--render") { try await WaveSnapshots.render() }
    }
}
