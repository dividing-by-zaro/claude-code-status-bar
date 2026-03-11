import Foundation

@Observable
class ClaudeProcess: Identifiable {
    let id = UUID()
    let pid: pid_t
    let startTime: Date

    var state: ProcessState = .running
    var cpuUsage: Double = 0.0
    var workingDirectory: String?

    // For CPU delta calculation
    var previousCPUTime: UInt64 = 0
    var previousSampleTime: Date = .now

    // State tracking
    var previousState: ProcessState? = nil
    var stateChangeTime: Date = .now
    var lastSoundTime: Date = .distantPast
    var cpuHistory: [Double] = []

    init(pid: pid_t, startTime: Date) {
        self.pid = pid
        self.startTime = startTime
    }

    /// Short project name from working directory
    var projectName: String {
        guard let cwd = workingDirectory else { return "PID \(pid)" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Rolling average CPU from recent samples
    var averageCPU: Double {
        guard !cpuHistory.isEmpty else { return 0 }
        return cpuHistory.reduce(0, +) / Double(cpuHistory.count)
    }

    func recordCPU(_ cpu: Double) {
        cpuHistory.append(cpu)
        if cpuHistory.count > 3 {
            cpuHistory.removeFirst()
        }
        cpuUsage = cpu
    }
}
