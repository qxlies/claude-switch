import AppKit
import ServiceManagement
import SwiftUI

enum MainRoute { case overview, add, settings }

final class MainNav: ObservableObject {
    enum Selection: Hashable { case profile(String), settings }
    @Published var selection: Selection?
    @Published var showAdd = false
}

struct MainView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: MainNav

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 248)
                .padding(10)
            Group {
                switch nav.selection {
                case .settings: SettingsPane()
                case .profile(let name):
                    if let p = store.status?.profiles.first(where: { $0.name == name }) {
                        ProfileDetail(profile: p)
                    } else { EmptyDetail() }
                case nil: EmptyDetail()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 580)
        .background(WindowBackdrop().ignoresSafeArea())
        .overlay(alignment: .bottom) { OperationToast().padding(.bottom, 18) }
        .sheet(isPresented: $nav.showAdd) { AddAccountSheet() }
        .onAppear(perform: selectDefault)
        .onChange(of: store.status) { _ in selectDefault() }
    }

    private func selectDefault() {
        guard let s = store.status else { return }
        if case .profile(let n) = nav.selection, s.profiles.contains(where: { $0.name == n }) { return }
        if nav.selection == .settings { return }
        if let first = s.active ?? s.profiles.first { nav.selection = .profile(first.name) }
    }
}

// MARK: - Sidebar (floating glass, macOS 26 style)

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: MainNav

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Claude Switch").font(.system(size: 14, weight: .semibold))
                    Text("Shared local workspace").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 34)   // room for the traffic lights
            .padding(.bottom, 12)

            Text("ACCOUNTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 10)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.status?.profiles ?? []) { p in
                        SidebarRow(selected: nav.selection == .profile(p.name)) {
                            Avatar(name: p.name, size: 26, active: p.active)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 13, weight: .medium))
                                Text(p.stateLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.operation?.target == p.name { ProgressView().controlSize(.mini) }
                        } action: { nav.selection = .profile(p.name) }
                    }
                }
            }

            Spacer(minLength: 0)

            SidebarRow(selected: false) {
                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.claude).frame(width: 26)
                Text("Add Account").font(.system(size: 13, weight: .medium))
                Spacer()
            } action: { nav.showAdd = true }
            .disabled(store.isBusy)

            SidebarRow(selected: nav.selection == .settings) {
                Image(systemName: "gearshape.fill").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 26)
                Text("Settings").font(.system(size: 13, weight: .medium))
                Spacer()
            } action: { nav.selection = .settings }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(24)
    }
}

struct SidebarRow<Content: View>: View {
    var selected: Bool
    @ViewBuilder var content: Content
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Palette.claude.opacity(0.22) : .primary.opacity(hover ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Detail

struct ProfileDetail: View {
    @EnvironmentObject var store: Store
    var profile: Profile
    @State private var renaming = false
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if store.status?.mismatch == true && profile.active { mismatchBanner }
                usageSection
                workspaceSection
            }
            .padding(.horizontal, 30)
            .padding(.top, 44)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $renaming) { RenameSheet(old: profile.name) }
        .alert("Remove “\(profile.name)”?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { store.remove(profile.name) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the saved sign-in is deleted. Your chats are not touched. You can add the account again later.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Avatar(name: profile.name, size: 72, active: profile.active)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name).font(.system(size: 30, weight: .bold))
                HStack(spacing: 6) {
                    Chip(text: profile.stateLabel,
                         color: profile.active ? Color(red: 0.2, green: 0.7, blue: 0.4) : (profile.hasSavedSignIn ? Palette.claude : .orange),
                         systemImage: profile.active ? "checkmark" : (profile.hasSavedSignIn ? "key.fill" : "exclamationmark"))
                    if profile.holdsWorkspace { Chip(text: "Holds workspace", color: .blue, systemImage: "tray.full.fill") }
                }
                Text("Account \(Fmt.shortID(profile.accountUuid)) · Org \(Fmt.shortID(profile.orgUuid))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Spacer()
            if profile.active {
                Button { Store.openClaude() } label: { Label("Open Claude", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(GlassButtonStyle())
            } else {
                Button { store.switchTo(profile.name) } label: {
                    Label("Switch to \(profile.name)", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .disabled(store.isBusy)
            }
            moreMenu
        }
    }

    /// Secondary actions live in a "…" menu, the way macOS apps keep the content area clean.
    private var moreMenu: some View {
        GlassIconButton(systemName: "ellipsis", size: 34, help: "More") {
            PopupMenu.show([
                .init(title: "Rename…", symbol: "pencil") { renaming = true },
                .separator,
                .init(title: "Show Backups in Finder", symbol: "clock.arrow.circlepath") { Store.reveal("~/.claude-switch/backups") },
                .init(title: "Show Log in Finder", symbol: "doc.text") { Store.reveal("~/.claude-switch/switch.log") },
                .separator,
                .init(title: "Remove Account…", symbol: "trash", enabled: !profile.active && !store.isBusy) { confirmRemove = true },
            ])
        }
    }

    private var mismatchBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill").font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your chats are under another account").font(.system(size: 13, weight: .semibold))
                Text("You signed in without Claude Switch. Move the shared workspace here.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Move chats here") { store.syncWorkspace() }.buttonStyle(GlassButtonStyle(prominent: true, tint: .orange))
        }
        .padding(16)
        .card()
    }

    private var usageSection: some View {
        let u = profile.usage
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Usage limits", trailing: u?.updated.map { "Updated \(Fmt.relative($0))" } ?? "No data yet")
            HStack(spacing: 14) {
                gauge(title: "Current session", subtitle: u?.fiveHourIsStale == true ? "Window has likely reset" : "5-hour limit",
                      value: u?.fiveHour, stale: u?.fiveHourIsStale ?? true)
                gauge(title: "Weekly", subtitle: "7-day limit", value: u?.weekly, stale: false)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly trend").font(.system(size: 13, weight: .semibold))
                    Text("Last \(u?.history.count ?? 0) readings").font(.system(size: 11)).foregroundStyle(.secondary)
                    let points = (u?.history ?? []).compactMap { $0.weekly }
                    if points.count > 1 {
                        Sparkline(points: points, color: Palette.usage(u?.weekly)).frame(maxHeight: .infinity)
                    } else {
                        Text("The trend appears after a few readings.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card()
            }
            .frame(height: 170)
            Text("Readings come from Claude Desktop itself and refresh while you use that account.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private func gauge(title: String, subtitle: String, value: Double?, stale: Bool) -> some View {
        VStack(spacing: 10) {
            UsageRing(value: value, lineWidth: 11, stale: stale).frame(width: 96, height: 96)
            VStack(spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 170)
        .frame(maxHeight: .infinity)
        .card()
    }

    private var workspaceSection: some View {
        let ws = store.status?.workspace
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Shared workspace", trailing: "Same for every account")
            HStack(spacing: 14) {
                Stat(icon: "bubble.left.and.bubble.right.fill", color: Palette.claude, value: "\(ws?.chats ?? 0)", label: "Code chats")
                Stat(icon: "square.stack.3d.up.fill", color: .purple, value: "\(ws?.cowork ?? 0)", label: "Cowork sessions")
                Stat(icon: "clock.fill", color: .blue, value: Fmt.relative(ms: ws?.lastActivity), label: "Last activity")
                Stat(icon: "sparkles", color: .pink, value: Fmt.compact(store.status?.tokensToday), label: "Tokens today")
            }
        }
    }

}

struct SectionTitle: View {
    var title: String
    var trailing: String?
    init(_ title: String, trailing: String? = nil) { self.title = title; self.trailing = trailing }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

struct Stat: View {
    var icon: String
    var color: Color
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct EmptyDetail: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: MainNav

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(store.loadError ?? "No accounts yet").font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center)
            if store.loadError == nil {
                Text("Save the account you're signed in to, then add more.").foregroundStyle(.secondary)
                if store.status?.currentAccount != nil {
                    Button("Save current account") { nav.showAdd = true }.buttonStyle(GlassButtonStyle(prominent: true))
                }
            }
        }
        .padding(40)
    }
}

// MARK: - Settings

struct SettingsPane: View {
    @EnvironmentObject var store: Store
    @AppStorage("showUsageInMenuBar") private var showUsage = true
    @AppStorage("showInDock") private var showInDock = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cliMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings").font(.system(size: 30, weight: .bold))
                group("General") {
                    toggleRow("Launch at login", "Keep Claude Switch in the menu bar after restarting your Mac.", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { on in
                            do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                            catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                        }
                    Divider().opacity(0.4)
                    toggleRow("Show weekly usage in the menu bar", "Displays the active account's weekly limit next to the icon.", isOn: $showUsage)
                    Divider().opacity(0.4)
                    toggleRow("Keep icon in the Dock", "Otherwise the Dock icon appears only while this window is open.", isOn: $showInDock)
                        .onChange(of: showInDock) { _ in AppDelegate.shared?.updateActivationPolicy() }
                }
                group("Command line") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("claude-switch command").font(.system(size: 13, weight: .medium))
                            Text(cliMessage ?? "Installs the CLI to ~/.local/bin for use in Terminal.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Install") { installCLI() }.buttonStyle(GlassButtonStyle())
                    }
                }
                group("About") {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Claude Switch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Unofficial. Not affiliated with Anthropic.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/qxlies/claude-switch")!) }
                            .buttonStyle(GlassButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 44)
            .padding(.bottom, 40)
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .card()
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(Palette.claude)
    }

    private func installCLI() {
        let bin = NSHomeDirectory() + "/.local/bin"
        let dest = bin + "/claude-switch"
        do {
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(atPath: dest)
            try FileManager.default.copyItem(atPath: store.scriptPath, toPath: dest)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
            cliMessage = "Installed to \(dest)"
        } catch {
            cliMessage = error.localizedDescription
        }
    }
}

// MARK: - Sheets & toast

struct AddAccountSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var unsavedCurrent: Bool { store.status?.currentAccount != nil && store.status?.currentProfile == nil }
    private var valid: Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) }
            && !(store.status?.profiles.contains { $0.name == name } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Avatar(name: name.isEmpty ? "+" : name, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unsavedCurrent ? "Save current account" : "Add an account").font(.system(size: 18, weight: .bold))
                    Text(unsavedCurrent ? "Give the account you're signed in to a name." : "Claude will reopen on the sign-in screen.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            TextField("Profile name, e.g. work", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit(go)
            if !unsavedCurrent {
                VStack(alignment: .leading, spacing: 6) {
                    step("1", "Claude quits and opens on the sign-in screen.")
                    step("2", "Sign in with claude.ai (not Gateway).")
                    step("3", "Your chats move to the new account automatically.")
                }
                .font(.system(size: 12))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(GlassButtonStyle())
                Button(unsavedCurrent ? "Save" : "Continue", action: go)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(!valid)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(n).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Palette.claude))
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func go() {
        guard valid else { return }
        unsavedCurrent ? store.saveCurrent(as: name) : store.addAccount(name)
        dismiss()
    }
}

struct RenameSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var old: String
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename “\(old)”").font(.system(size: 18, weight: .bold))
            TextField("New name", text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(GlassButtonStyle())
                Button("Rename") { store.rename(old, to: name); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(name.isEmpty || name == old || !name.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) })
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { name = old }
    }
}

struct OperationToast: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if let op = store.operation {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(op.title).font(.system(size: 13, weight: .semibold))
                        Text(op.line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if op.cancellable {
                        Button("Cancel") { store.cancel() }.buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: 460)
                .glass(24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let failure = store.lastFailure {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(failure).font(.system(size: 12)).lineLimit(2)
                    Button { store.lastFailure = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: 520)
                .glass(24, tint: Color.red.opacity(0.2))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.operation)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.lastFailure)
    }
}


/// A native context menu shown at the pointer, so the trigger can be any custom (glass) button.
enum PopupMenu {
    struct Item {
        var title = ""
        var symbol: String?
        var enabled = true
        var isSeparator = false
        var action: () -> Void = {}

        init(title: String, symbol: String?, enabled: Bool = true, action: @escaping () -> Void) {
            self.title = title; self.symbol = symbol; self.enabled = enabled; self.action = action
        }
        private init() { isSeparator = true }
        static let separator = Item()
    }

    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }

    @MainActor static func show(_ items: [Item]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var targets: [Target] = []
        for item in items {
            if item.isSeparator { menu.addItem(.separator()); continue }
            let target = Target(item.action)
            targets.append(target)
            let mi = NSMenuItem(title: item.title, action: #selector(Target.fire), keyEquivalent: "")
            mi.target = target
            mi.isEnabled = item.enabled
            if let s = item.symbol { mi.image = NSImage(systemSymbolName: s, accessibilityDescription: nil) }
            menu.addItem(mi)
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.title == "Claude Switch" }),
              let view = window.contentView else { return }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
        withExtendedLifetime(targets) {}
    }
}
