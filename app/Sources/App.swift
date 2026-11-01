import AppKit
import SwiftUI

@main
struct ClaudeSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Everything lives in the menu bar item and an AppKit-managed main window.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    private var menuBar: MenuBarController!
    private var window: NSWindow?
    private let nav = MainNav()

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        Store.shared.start()
        menuBar = MenuBarController()
        menuBar.openMainWindow = { [weak self] route in self?.showMain(route) }
        updateActivationPolicy()
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showMain(.overview)
        }
        // `open -a "Claude Switch" --args -showPanelOnLaunch YES` opens the menu bar panel right away
        if UserDefaults.standard.bool(forKey: "showPanelOnLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.menuBar.show() }
        }
        // Development aid: the panel content in an ordinary window, for screenshots
        if UserDefaults.standard.bool(forKey: "panelPreviewWindow") { showPanelPreview() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMain(.overview)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showMain(_ route: MainRoute) {
        if window == nil { window = makeWindow() }
        switch route {
        case .add: nav.showAdd = true
        case .settings: nav.selection = .settings
        case .overview: if nav.selection == .settings { nav.selection = nil }
        }
        updateActivationPolicy(forceRegular: true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.title = "Claude Switch"
        w.backgroundColor = .clear
        w.delegate = self
        w.contentView = NSHostingView(rootView: MainView().environmentObject(Store.shared).environmentObject(nav))
        w.setFrameAutosaveName("ClaudeSwitchMain")
        if !w.setFrameUsingName("ClaudeSwitchMain") { w.center() }
        return w
    }

    private var previewWindow: NSWindow?

    private func showPanelPreview() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: MenuBarController.width + 40, height: 620),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isOpaque = false
        w.backgroundColor = .clear
        w.title = "Panel Preview"
        let root = MenuPanelView(onHeight: { [weak w] h in
            guard let w else { return }
            var f = w.frame
            f.origin.y += f.height - (h + 60)
            f.size.height = h + 60
            w.setFrame(f, display: true)
        }, openMain: { _ in }, close: {}).environmentObject(Store.shared).padding(.top, 30).padding(.horizontal, 20)
            .background(  // a wallpaper-like backdrop so the glass has something to refract in screenshots
                ZStack {
                    LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.40), Color(red: 0.45, green: 0.25, blue: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(Color(red: 1, green: 0.8, blue: 0.5).opacity(0.7)).frame(width: 260).blur(radius: 60).offset(x: -90, y: -160)
                    Circle().fill(Color(red: 0.3, green: 0.5, blue: 0.95).opacity(0.6)).frame(width: 300).blur(radius: 70).offset(x: 120, y: 180)
                }
                .ignoresSafeArea()
            )
        w.contentView = NSHostingView(rootView: root)
        w.center()
        w.makeKeyAndOrderFront(nil)
        previewWindow = w
        updateActivationPolicy(forceRegular: true)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { self.updateActivationPolicy() }
    }

    /// Dock icon only while the window is open, unless the user keeps it there.
    func updateActivationPolicy(forceRegular: Bool = false) {
        let windowOpen = forceRegular || (window?.isVisible ?? false)
        let policy: NSApplication.ActivationPolicy = (windowOpen || UserDefaults.standard.showInDock) ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
}
