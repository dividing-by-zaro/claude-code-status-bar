import SwiftUI

@main
struct ClaudeCodeMonitorApp: App {
    @State private var monitor = ProcessMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            if monitor.processes.isEmpty {
                Image(systemName: "terminal")
            } else {
                Text(monitor.processes.map(\.state.statusBarIcon).joined(separator: " | "))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
