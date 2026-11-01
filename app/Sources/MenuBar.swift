import AppKit
import Combine
import SwiftUI

/// The menu bar item and its floating glass panel (styled like Control Center).
@MainActor
final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: GlassPanel?
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private let store = Store.shared
    var openMainWindow: (MainRoute) -> Void = { _ in }

    static let width: CGFloat = 340

    override init() {
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.imagePosition = .imageLeading
        }
        updateButton()
        store.$status.combineLatest(store.$operation)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        UserDefaults.standard.publisher(for: \.showUsageInMenuBar)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = item.button else { return }
        let symbol = store.operation != nil ? "arrow.triangle.2.circlepath" : "person.2.crop.square.stack.fill"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Claude Switch")
        img?.isTemplate = true
        button.image = img?.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        var title = ""
        if UserDefaults.standard.showUsageInMenuBar, let weekly = store.status?.active?.usage?.weekly {
            title = " \(Int(weekly))%"
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        ])
    }

    @objc func toggle() {
        if let panel, panel.isVisible { hide() } else { show() }
    }

    func show() {
        store.refresh()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel, height: panel.frame.height)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            if e.keyCode == 53 { self?.hide(); return nil }
            return e
        }
        monitors = [global as Any, local as Any].compactMap { $0 }
        item.button?.highlight(true)
    }

    func hide() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        item.button?.highlight(false)
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> GlassPanel {
        let panel = GlassPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        let root = MenuPanelView(
            onHeight: { [weak self, weak panel] h in
                guard let self, let panel else { return }
                self.position(panel, height: h)
            },
            openMain: { [weak self] route in
                self?.hide()
                self?.openMainWindow(route)
            },
            close: { [weak self] in self?.hide() }
        ).environmentObject(store)
        let host = NSHostingView(rootView: root)
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// Keep the panel's top edge just under the menu bar item.
    private func position(_ panel: NSPanel, height: CGFloat) {
        guard let button = item.button, let bw = button.window else { return }
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var x = b.midX - Self.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - Self.width - 8)
        let top = b.minY - 6
        panel.setFrame(NSRect(x: x, y: top - height, width: Self.width, height: height), display: true)
    }
}

final class GlassPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Panel content

struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct MenuPanelView: View {
    @EnvironmentObject var store: Store
    var onHeight: (CGFloat) -> Void
    var openMain: (MainRoute) -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let status = store.status {
                header(status)
                if let op = store.operation {
                    progressTile(op)
                } else if let failure = store.lastFailure {
                    failureTile(failure)
                }
                if status.mismatch && store.operation == nil { mismatchTile(status) }
                usageTile(status)
                accountsTile(status)
                footer
            } else {
                loadingTile
            }
        }
        .padding(10)
        .frame(width: MenuBarController.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { Color.clear.preference(key: PanelHeightKey.self, value: $0.size.height) })
        .onPreferenceChange(PanelHeightKey.self) { h in if h > 0 { onHeight(h) } }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.status)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.operation)
    }

    // Header: who is signed in now
    private func header(_ s: Status) -> some View {
        HStack(spacing: 12) {
            Avatar(name: s.currentProfile ?? "?", size: 42, active: s.currentProfile != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.currentProfile ?? (s.currentAccount == nil ? "Signed out" : "Unsaved account"))
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle(s)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            GlassIconButton(systemName: "macwindow", size: 32, help: "Open Claude Switch") { openMain(.overview) }
        }
        .padding(12)
        .glass(26)
    }

    private func subtitle(_ s: Status) -> String {
        guard let ws = s.workspace else { return "No workspace yet" }
        return "\(ws.chats) chats · Claude \(Store.claudeIsRunning ? "open" : "closed")"
    }

    private func usageTile(_ s: Status) -> some View {
        let u = s.active?.usage
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Usage limits", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(u?.updated.map { Fmt.relative($0) } ?? "no data yet")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            UsageBar(label: "Current session · 5h", value: u?.fiveHour, stale: u?.fiveHourIsStale ?? true)
            UsageBar(label: "Weekly", value: u?.weekly)
        }
        .padding(14)
        .glass(26)
    }

    private func accountsTile(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Accounts").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 6).padding(.bottom, 2)
            ForEach(s.profiles) { p in
                AccountRow(profile: p, busyTarget: store.operation?.target, disabled: store.isBusy) {
                    store.switchTo(p.name)
                }
            }
            if s.profiles.isEmpty {
                Text("No saved accounts yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(6)
            }
        }
        .padding(10)
        .glass(26)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { openMain(.add) } label: {
                Label("Add account", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(store.isBusy)
            GlassIconButton(systemName: "gearshape", size: 34, help: "Settings") { openMain(.settings) }
            GlassIconButton(systemName: "power", size: 34, help: "Quit Claude Switch") { NSApp.terminate(nil) }
        }
    }

    private func progressTile(_ op: Store.Operation) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(op.title).font(.system(size: 13, weight: .semibold))
                Text(op.line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if op.cancellable {
                Button("Cancel") { store.cancel() }.buttonStyle(GlassButtonStyle())
            }
        }
        .padding(14)
        .glass(26, tint: Palette.claude.opacity(0.35))
    }

    private func failureTile(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { store.lastFailure = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(14)
        .glass(26, tint: Color.red.opacity(0.25))
    }

    private func mismatchTile(_ s: Status) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chats are under another account").font(.system(size: 12, weight: .semibold))
                Text("Move them to the account you're signed in to.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Move") { store.syncWorkspace() }.buttonStyle(GlassButtonStyle(prominent: true, tint: .orange))
        }
        .padding(14)
        .glass(26, tint: Color.orange.opacity(0.25))
    }

    private var loadingTile: some View {
        VStack(spacing: 8) {
            if let err = store.loadError {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                Text(err).font(.system(size: 12)).multilineTextAlignment(.center)
            } else {
                ProgressView().controlSize(.small)
                Text("Loading…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glass(26)
    }
}

struct AccountRow: View {
    var profile: Profile
    var busyTarget: String?
    var disabled: Bool
    var onSwitch: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: profile.name, size: 30, active: profile.active)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if busyTarget == profile.name {
                ProgressView().controlSize(.small)
            } else if profile.active {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.45))
            } else if hover && !disabled {
                Text("Switch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.claude))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(hover && !profile.active ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { if !profile.active && !disabled { onSwitch() } }
    }

    private var detail: String {
        if let u = profile.usage, let w = u.weekly {
            let five = u.fiveHourIsStale ? "—" : "\(Int(u.fiveHour ?? 0))%"
            return "5h \(five) · week \(Int(w))%"
        }
        return profile.stateLabel
    }
}

extension UserDefaults {
    @objc dynamic var showUsageInMenuBar: Bool {
        get { object(forKey: "showUsageInMenuBar") as? Bool ?? true }
        set { set(newValue, forKey: "showUsageInMenuBar") }
    }

    @objc dynamic var showInDock: Bool {
        get { bool(forKey: "showInDock") }
        set { set(newValue, forKey: "showInDock") }
    }
}
