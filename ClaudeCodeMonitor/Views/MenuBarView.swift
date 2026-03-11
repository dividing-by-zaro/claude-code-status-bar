import SwiftUI

struct MenuBarView: View {
    let monitor: ProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Claude Code Monitor")
                    .font(.headline)
                Spacer()
                Button(action: { monitor.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if monitor.processes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Claude processes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(monitor.processes) { process in
                    ProcessRowView(process: process)
                    Divider()
                }
            }

            // Footer
            HStack {
                Text("\(activeCount) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    private var activeCount: Int {
        monitor.processes.filter { $0.state == .running || $0.state == .blocked }.count
    }
}
