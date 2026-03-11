import Darwin
import Foundation

@Observable
class ProcessMonitor {
    var processes: [ClaudeProcess] = []
    var overallState: ProcessState = .done

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 0.5
    private let claudeProjectsDir: String

    init() {
        claudeProjectsDir = NSHomeDirectory() + "/.claude/projects"
        refresh()
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let claudePids = discoverClaudeProcesses()
        let allKnownPids = Set(processes.map(\.pid))
        let activePids = Set(claudePids.map(\.pid))

        // Mark disappeared processes as done
        for process in processes where activePids.contains(process.pid) == false && process.state != .done && process.state != .error {
            process.state = .done
            process.stateChangeTime = .now
        }

        // Add newly discovered processes (skip if we already track this PID)
        for info in claudePids where !allKnownPids.contains(info.pid) {
            let process = ClaudeProcess(pid: info.pid, startTime: info.startTime)
            process.workingDirectory = info.cwd
            processes.insert(process, at: 0)
        }

        // Update metrics and state for active processes
        for process in processes where activePids.contains(process.pid) {
            updateMetrics(for: process)
            updateStateFromSession(process)
        }

        // Remove done processes older than 5 minutes
        let cutoff = Date.now.addingTimeInterval(-300)
        processes.removeAll { $0.state == .done && $0.stateChangeTime < cutoff }

        updateOverallState()
    }

    // MARK: - State Detection

    /// Determines state from the JSONL session log:
    /// - Last entry is role=user → Running (Claude is thinking/streaming)
    /// - Last entry is assistant + stop_reason=tool_use + file stale → Blocked
    /// - Last entry is assistant + stop_reason=tool_use + file fresh → Running (tool executing)
    /// - Last entry is assistant + stop_reason=end_turn → Done
    private func updateStateFromSession(_ process: ClaudeProcess) {
        guard let cwd = process.workingDirectory,
              let sessionState = readSessionState(for: cwd) else {
            process.state = .done
            return
        }

        switch sessionState {
        case .userTurn:
            // Last entry is a user message — Claude must be working on a response
            process.state = .running

        case .assistantStreaming:
            // Partial assistant message (stop_reason=None) — still streaming
            process.state = .running

        case .toolUse(let fileAge):
            if fileAge < 15 {
                // Tool is being executed right now
                process.state = .running
            } else {
                // File is stale — waiting for user approval
                process.state = .blocked
            }

        case .endTurn:
            process.state = .done

        case .other:
            process.state = .done
        }
    }

    private enum SessionState {
        case userTurn           // Last entry is role=user
        case assistantStreaming  // Last assistant message has stop_reason=None (still streaming)
        case toolUse(fileAge: TimeInterval) // stop_reason=tool_use, with file staleness
        case endTurn            // stop_reason=end_turn
        case other              // progress, system, file-history-snapshot, etc.
    }

    private func readSessionState(for cwd: String) -> SessionState? {
        let dirName = cwd.replacingOccurrences(of: "/", with: "-")
        let projectDir = claudeProjectsDir + "/" + dirName

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: projectDir) else {
            return nil
        }

        // Find the most recently modified .jsonl file
        var newest: (path: String, date: Date)?
        for file in contents where file.hasSuffix(".jsonl") {
            let path = projectDir + "/" + file
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mod = attrs[.modificationDate] as? Date else {
                continue
            }
            if newest == nil || mod > newest!.date {
                newest = (path, mod)
            }
        }

        guard let best = newest else { return nil }
        let fileAge = Date.now.timeIntervalSince(best.date)

        // Read last few lines and find the last meaningful entry
        guard let fileHandle = FileHandle(forReadingAtPath: best.path) else {
            return nil
        }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        let readSize = min(fileSize, 16384)
        fileHandle.seek(toFileOffset: fileSize - readSize)
        let data = fileHandle.readData(ofLength: Int(readSize))

        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Walk backwards through lines to find last message entry
        // (skip progress, system, file-history-snapshot entries)
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines.reversed() {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let entryType = json["type"] as? String ?? ""

            // Skip non-message entries
            if entryType == "progress" || entryType == "system" || entryType == "file-history-snapshot" {
                continue
            }

            guard let message = json["message"] as? [String: Any] else {
                continue
            }

            let role = message["role"] as? String ?? ""

            if role == "user" {
                return .userTurn
            }

            if role == "assistant" {
                let stopReason = message["stop_reason"]
                if stopReason is NSNull || stopReason == nil {
                    // stop_reason is null/None — still streaming
                    return .assistantStreaming
                }
                let stop = stopReason as? String ?? ""
                if stop == "tool_use" {
                    return .toolUse(fileAge: fileAge)
                }
                if stop == "end_turn" {
                    return .endTurn
                }
                return .other
            }

            // Unknown message type, skip
            continue
        }

        return nil
    }

    private func updateOverallState() {
        if processes.contains(where: { $0.state == .error }) {
            overallState = .error
        } else if processes.contains(where: { $0.state == .running }) {
            overallState = .running
        } else if processes.contains(where: { $0.state == .blocked }) {
            overallState = .blocked
        } else {
            overallState = .done
        }
    }

    // MARK: - Process Discovery

    private struct DiscoveredProcess {
        let pid: pid_t
        let startTime: Date
        let cwd: String?
    }

    private func discoverClaudeProcesses() -> [DiscoveredProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size: Int = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
            return []
        }

        let count = (size / MemoryLayout<kinfo_proc>.stride) * 2
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        size = count * MemoryLayout<kinfo_proc>.stride

        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else {
            return []
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        return procs.prefix(actualCount).compactMap { proc in
            let pid = proc.kp_proc.p_pid
            guard isClaudeProcess(pid: pid) else { return nil }

            let tv = proc.kp_proc.p_starttime
            let startTime = Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
            let cwd = getProcessCwd(pid: pid)

            return DiscoveredProcess(pid: pid, startTime: startTime, cwd: cwd)
        }
    }

    private func isClaudeProcess(pid: pid_t) -> Bool {
        let maxPathSize = Int(4 * MAXPATHLEN)
        var pathBuffer = [CChar](repeating: 0, count: maxPathSize)
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(maxPathSize))
        if pathLen > 0 {
            let path = String(cString: pathBuffer)
            if path.contains("/claude/versions/") || path.hasSuffix("/claude") {
                return true
            }
        }

        var argsMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var argsSize: Int = 0
        guard sysctl(&argsMib, 3, nil, &argsSize, nil, 0) == 0, argsSize > 0 else {
            return false
        }

        var argsBuffer = [CChar](repeating: 0, count: argsSize)
        guard sysctl(&argsMib, 3, &argsBuffer, &argsSize, nil, 0) == 0 else {
            return false
        }

        if argsSize > MemoryLayout<Int32>.size {
            let execPath = argsBuffer.withUnsafeBufferPointer { buf in
                let start = buf.baseAddress!.advanced(by: MemoryLayout<Int32>.size)
                return String(cString: start)
            }
            if execPath.contains("/claude/versions/") || execPath.hasSuffix("/claude") {
                return true
            }
        }

        return false
    }

    private func getProcessCwd(pid: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, size)
        guard result == size else { return nil }

        let path = withUnsafePointer(to: pathInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cstr in
                String(cString: cstr)
            }
        }
        return path.isEmpty ? nil : path
    }

    // MARK: - Metrics

    private func updateMetrics(for process: ClaudeProcess) {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(process.pid, PROC_PIDTASKINFO, 0, &taskInfo, size)

        guard result == size else { return }

        let currentCPUTime = taskInfo.pti_total_user + taskInfo.pti_total_system
        let now = Date.now
        let wallDelta = now.timeIntervalSince(process.previousSampleTime)

        if wallDelta > 0 && process.previousCPUTime > 0 {
            let cpuDelta = Double(currentCPUTime - process.previousCPUTime)
            let cpuPercent = (cpuDelta / 1_000_000_000) / wallDelta * 100
            process.recordCPU(cpuPercent)
        }

        process.previousCPUTime = currentCPUTime
        process.previousSampleTime = now
    }
}
