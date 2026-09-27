import SwiftUI
import HvaliaCore

#if !HVALIA_UI_CHECKS
@main struct HvaliaApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private var demoScheme: ColorScheme? {
        guard CommandLine.arguments.contains("--demo") else { return nil }
        if CommandLine.arguments.contains("--demo-light") { return .light }
        if CommandLine.arguments.contains("--demo-dark") { return .dark }
        return nil
    }
    var body: some Scene {
        WindowGroup("Hvalia") {
            WizardShell().environmentObject(model)
                .frame(width: 720, height: 480)
                .preferredColorScheme(demoScheme)
                .environment(\.locale, Locale(identifier: model.language))
                .onAppear {
                    delegate.model = model
                    DispatchQueue.main.async { for window in NSApp.windows where window.title == "Hvalia" { delegate.configure(window) } }
                }
                .onChange(of: model.isHome) {
                    for window in NSApp.windows where window.title == "Hvalia" { delegate.configure(window) }
                }
                .task { await model.monitor() }
        }
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(model.t("О Hvalia", "About Hvalia")) {
                    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Hvalia", .applicationVersion: "1.0.0 Preview", .credits: NSAttributedString(string: model.t("Включение 5G на iPhone в Беларуси\nМТС · life\n\nhttps://github.com/h1royuki/Hvalia", "Enable 5G on iPhone in Belarus\nMTS · life\n\nhttps://github.com/h1royuki/Hvalia"))])
                }
            }
        }
    }
}
#endif

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == "Hvalia" { configure(window) }
    }
    func configure(_ window: NSWindow) {
        window.delegate = self
        window.titleVisibility = model?.isHome == true ? .hidden : .visible
        if let toolbar = window.toolbar {
            let spaces = toolbar.items.indices.filter { toolbar.items[$0].itemIdentifier == .flexibleSpace }
            if spaces != [0] {
                for index in spaces.reversed() { toolbar.removeItem(at: index) }
                toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 0)
            }
        }
        let fixedSize = NSSize(width: 720, height: 520)
        window.styleMask.remove(.resizable)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.minSize = fixedSize
        window.maxSize = fixedSize
        // Apply to normal launches too, overriding any previously saved resizable frame.
        if window.frame.size != fixedSize {
            window.setFrame(NSRect(origin: window.frame.origin, size: fixedSize), display: true)
        }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "Hvalia" else { return }
        configure(window)
    }
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "Hvalia" else { return }
        model?.resetNavigationForLaunch()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model?.busy == true ? .terminateCancel : .terminateNow }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.busy != true }
}

enum Layout {
    static let inset: CGFloat = 20
    static let section: CGFloat = 16
    static let related: CGFloat = 8
}
struct Instructions: View {
    let rows: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(item.offset + 1)").font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary).frame(width: 18)
                    Text(item.element).fixedSize(horizontal: false, vertical: true)
                }.accessibilityElement(children: .combine)
            }
        }
    }
}
