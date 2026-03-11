import SwiftUI

struct ProcessRowView: View {
    let process: ClaudeProcess

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(process.state.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(process.state.statusBarIcon) \(process.projectName)")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Text(process.state.label)
                        .font(.caption)
                        .foregroundStyle(process.state.color)
                }

                HStack {
                    Text("CPU \(process.cpuUsage, specifier: "%.1f")%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if process.state == .blocked {
                        Text("Needs approval")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var relativeTime: String {
        let interval = Date.now.timeIntervalSince(process.startTime)
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}
