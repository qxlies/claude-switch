import Foundation
import SwiftUI

/// Mirrors `claude-switch status --json`.
struct Status: Decodable, Equatable {
    var version: String
    var currentAccount: String?
    var currentProfile: String?
    var workspace: Workspace?
    var mismatch: Bool
    var busy: Bool
    var appMode: String?
    var tokensToday: Int?
    var profiles: [Profile]

    var active: Profile? { profiles.first { $0.active } }
}

struct Workspace: Decodable, Equatable {
    var acct: String
    var org: String
    var chats: Int
    var cowork: Int
    var lastActivity: Double?
}

struct Profile: Decodable, Identifiable, Hashable {
    var name: String
    var accountUuid: String
    var orgUuid: String
    var addedAt: String?
    var active: Bool
    var hasSavedSignIn: Bool
    var holdsWorkspace: Bool
    var usage: Usage?

    var id: String { name }

    var stateLabel: String {
        if active { return "Signed in" }
        return hasSavedSignIn ? "Ready to switch" : "Needs sign-in"
    }
}

struct Usage: Decodable, Hashable {
    var fiveHour: Double?
    var weekly: Double?
    var at: Double?
    var history: [UsagePoint]

    var updated: Date? { at.map { Date(timeIntervalSince1970: $0 / 1000) } }

    /// The 5-hour window has certainly rolled over if the sample is older than that.
    var fiveHourIsStale: Bool {
        guard let updated else { return true }
        return Date().timeIntervalSince(updated) > 5 * 3600
    }
}

struct UsagePoint: Decodable, Hashable {
    var t: Double
    var fiveHour: Double?
    var weekly: Double?
}

// MARK: - Formatting

enum Fmt {
    static func relative(_ date: Date?) -> String {
        guard let date else { return "never" }
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func relative(ms: Double?) -> String {
        relative(ms.map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    static func compact(_ n: Int?) -> String {
        guard let n else { return "0" }
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    static func shortID(_ s: String) -> String { String(s.prefix(8)) }
}

// MARK: - Colors

enum Palette {
    static let claude = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757
    static let claudeDeep = Color(red: 0.757, green: 0.333, blue: 0.188)

    static func usage(_ pct: Double?) -> Color {
        guard let pct else { return .secondary }
        switch pct {
        case ..<60: return Color(red: 0.20, green: 0.78, blue: 0.45)
        case ..<85: return Color(red: 1.00, green: 0.62, blue: 0.20)
        default: return Color(red: 1.00, green: 0.30, blue: 0.30)
        }
    }

    /// Stable, pleasant hue per profile name.
    static func avatar(_ name: String) -> (Color, Color) {
        var h: UInt64 = 1469598103934665603
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let hue = Double(h % 360) / 360
        return (Color(hue: hue, saturation: 0.55, brightness: 0.98),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.78))
    }
}
