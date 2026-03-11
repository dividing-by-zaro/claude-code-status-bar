import SwiftUI

enum ProcessState: String {
    case running    // Actively working (any CPU > 0.1%)
    case done       // Finished, waiting for user's next message
    case blocked    // Needs user approval for a tool/command
    case error      // Process disappeared unexpectedly

    var label: String {
        switch self {
        case .running: "Running"
        case .done: "Done"
        case .blocked: "Blocked"
        case .error: "Error"
        }
    }

    var color: Color {
        switch self {
        case .running: .green
        case .done: .secondary
        case .blocked: .orange
        case .error: .red
        }
    }

    var systemImage: String {
        switch self {
        case .running: "bolt.fill"
        case .done: "checkmark.circle.fill"
        case .blocked: "hand.raised.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    /// Unicode character shown in the menu bar for each instance
    var statusBarIcon: String {
        switch self {
        case .running: "\u{1F3C3}" // 🏃
        case .done: "\u{2705}"     // ✅
        case .blocked: "\u{270B}"  // ✋ raised hand (needs approval)
        case .error: "\u{26A0}"    // ⚠️
        }
    }
}
