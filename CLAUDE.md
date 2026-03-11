## Architecture

Native macOS menu bar app using Swift/SwiftUI, targeting macOS 14.0+. Uses XcodeGen (`project.yml`) for project generation.

- `LSUIElement = true` — menu bar only, no Dock icon
- `MenuBarExtra` with `.window` style for a rich SwiftUI popover
- `@Observable` for reactive state management
- Zero third-party dependencies

## Process Detection

Claude Code CLI installs as a symlink (`~/.local/bin/claude` → `~/.local/share/claude/versions/X.Y.Z`). The kernel reports `p_comm` as the resolved filename (e.g. `2.1.72`), NOT `claude`. Detection uses:

1. `sysctl(KERN_PROC, KERN_PROC_UID)` to list user processes (buffer oversized 2x to avoid race condition)
2. `proc_pidpath()` to get full executable path, matching `/claude/versions/` or suffix `/claude`
3. Fallback: `KERN_PROCARGS2` to check argv

## State Detection

State is determined by reading Claude's JSONL session logs in `~/.claude/projects/`. The process CWD (via `proc_pidinfo(PROC_PIDVNODEPATHINFO)`) maps to the project directory name (slashes replaced with dashes).

The last meaningful entry in the most recent `.jsonl` file determines state:
- `role=user` → **Running** (Claude is thinking/streaming)
- `role=assistant, stop_reason=None` → **Running** (still streaming)
- `role=assistant, stop_reason=tool_use` + file < 15s old → **Running** (tool executing)
- `role=assistant, stop_reason=tool_use` + file > 15s old → **Blocked** (needs user approval)
- `role=assistant, stop_reason=end_turn` → **Done** (waiting for next message)

Non-message entries (`progress`, `system`, `file-history-snapshot`) are skipped when scanning backwards.

## Key Files

- `ClaudeCodeMonitor/Services/ProcessMonitor.swift` — Core engine: process discovery, JSONL state reading, metrics
- `ClaudeCodeMonitor/Models/ProcessState.swift` — Three states: running/done/blocked + icons/colors
- `ClaudeCodeMonitor/Models/ClaudeProcess.swift` — Per-process data model
- `ClaudeCodeMonitor/App/ClaudeCodeMonitorApp.swift` — Menu bar label showing per-instance status icons
- `project.yml` — XcodeGen config (never edit Info.plist directly)

## Build

```bash
xcodegen generate  # after changing project.yml or adding/removing files
```
Then build and run from Xcode.
