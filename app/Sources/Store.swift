import AppKit
import Foundation

/// Talks to the bundled `claude-switch` script: the single source of truth for all switching logic.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var status: Status?
    @Published private(set) var loadError: String?
    @Published private(set) var operation: Operation?
    @Published var lastFailure: String?

    struct Operation: Equatable {
        var title: String
        var target: String?
        var line: String
        var cancellable: Bool
    }

    private var timer: Timer?
    private var process: Process?
    private var refreshing = false

    let scriptPath: String = Bundle.main.path(forResource: "claude-switch", ofType: nil)
        ?? (NSHomeDirectory() + "/.local/bin/claude-switch")

    lazy var pythonPath: String? = Store.findPython()

    var isBusy: Bool { operation != nil || status?.busy == true }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Reading state

    func refresh() {
        guard !refreshing else { return }
        guard let python = pythonPath else {
            loadError = "Python 3 is required. Install the Command Line Tools: xcode-select --install"
            return
        }
        refreshing = true
        let script = scriptPath
        Task.detached {
            let result = Store.runCapturing(python, [script, "status", "--json"])
            await MainActor.run {
                self.refreshing = false
                guard result.code == 0, let data = result.out.data(using: .utf8) else {
                    self.loadError = result.err.isEmpty ? "claude-switch status failed" : result.err
                    return
                }
                do {
                    let s = try JSONDecoder().decode(Status.self, from: data)
                    if s != self.status { self.status = s }
                    self.loadError = nil
                } catch {
                    self.loadError = "Could not read state: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Actions

    func switchTo(_ name: String) {
        perform(["use", name, "--force"], title: "Switching to \(name)", target: name)
    }

    func addAccount(_ name: String) {
        perform(["add", name, "--force"], title: "Adding \(name)", target: name, cancellable: true)
    }

    func syncWorkspace() {
        perform(["sync", "--force"], title: "Moving chats", target: status?.currentProfile)
    }

    func saveCurrent(as name: String) { perform(["save", name], title: "Saving \(name)", target: name) }

    func rename(_ old: String, to new: String) { perform(["rename", old, new], title: "Renaming", target: new) }

    func remove(_ name: String) { perform(["remove", name], title: "Removing \(name)", target: name) }

    func cancel() { process?.terminate() }

    private func perform(_ args: [String], title: String, target: String?, cancellable: Bool = false) {
        guard operation == nil, let python = pythonPath else { return }
        lastFailure = nil
        operation = Operation(title: title, target: target, line: "Starting…", cancellable: cancellable)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [scriptPath] + args
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_SWITCH_WORKER"] = "1"
        env["CLAUDE_SWITCH_NO_NOTIFY"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let lastError = ErrorBox()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = String(decoding: h.availableData, as: UTF8.self)
            let lines = chunk.split(separator: "\n").map { line -> String in
                // drop the "[12:00:00] " timestamp
                var s = String(line)
                if s.hasPrefix("["), let end = s.firstIndex(of: "]") { s = String(s[s.index(after: end)...]).trimmingCharacters(in: .whitespaces) }
                return s
            }.filter { !$0.isEmpty }
            guard let last = lines.last else { return }
            if let err = lines.last(where: { $0.hasPrefix("ERROR:") }) { lastError.set(String(err.dropFirst(6)).trimmingCharacters(in: .whitespaces)) }
            Task { @MainActor in self?.operation?.line = last }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = proc.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.operation = nil
                self.process = nil
                if code != 0 { self.lastFailure = lastError.get() ?? "Something went wrong (exit \(code)). See ~/.claude-switch/switch.log" }
                self.refresh()
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            operation = nil
            lastFailure = error.localizedDescription
        }
    }

    // MARK: Helpers

    final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?
        func set(_ v: String) { lock.lock(); value = v; lock.unlock() }
        func get() -> String? { lock.lock(); defer { lock.unlock() }; return value }
    }

    nonisolated static func runCapturing(_ exe: String, _ args: [String]) -> (code: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    static func findPython() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/usr/local/bin/python3",
        ]
        if let p = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return p }
        // /usr/bin/python3 is only a stub until the Command Line Tools (or Xcode) are installed
        let developerToolsPresent = fm.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3")
            || fm.fileExists(atPath: "/Applications/Xcode.app")
        return developerToolsPresent ? "/usr/bin/python3" : nil
    }

    static var claudeIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").isEmpty
    }

    static func openClaude() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    static func reveal(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
