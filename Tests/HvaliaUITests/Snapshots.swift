import SwiftUI
import HvaliaCore

/// Synthetic view renders, deliberately independent of phone helpers and user sessions.
@MainActor enum WaveSnapshots {
    static func render() async throws {
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".private/wave-qa")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let steps = ["home", "connect", "trust", "review", "prepare", "working", "restart", "settings", "network", "result", "backups", "recovery"]
        let scenarios = ["no-device", "multiple-devices", "locked", "multiple-lines", "no-backups", "invalid-backup", "many-backups", "saving", "applying", "restoring", "finishing", "restart-waiting", "missing-options", "checking", "confirmed", "unconfirmed", "skipped", "diagnosis", "diagnosis-result", "restored", "wrong-device", "damaged-store"]
        var count = 0
        for language in Localization.supportedLanguages {
            for dark in [false, true] {
                do {
                    let cases = steps.map { ($0, ["--demo-step", $0]) } + scenarios.map { ($0, ["--demo-scenario", $0]) } + [("restore-prepare", ["--demo-mode", "restore", "--demo-step", "prepare"]), ("long-error", ["--demo-step", "prepare", "--demo-error"])]
                    for (name, arguments) in cases {
                        let m = AppModel()
                        await m.refresh()
                        m.demoConfigured = false
                        m.configureDemoIfNeeded(arguments: ["--demo", "--demo-language", language] + arguments)
                        let size = NSSize(width: 720, height: 480)
                        let root = WizardShell().environmentObject(m)
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .environment(\.locale, Locale(identifier: language))
                            .transaction { $0.disablesAnimations = true; $0.animation = nil }
                            .frame(width: size.width, height: size.height)
                        let host = NSHostingView(rootView: root)
                        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                        window.contentView = host
                        host.frame = NSRect(origin: .zero, size: size)
                        window.orderFront(nil)
                        host.layoutSubtreeIfNeeded()
                        try await Task.sleep(for: .milliseconds(60))
                        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
                        let filename = "\(name)-\(language)-\(dark ? "dark" : "light")-fixed.png"
                        try png.write(to: folder.appendingPathComponent(filename))
                        window.orderOut(nil)
                        window.close()
                        count += 1
                    }
                }
            }
        }
        print("Rendered \(count) synthetic views to \(folder.path)")
    }
}
