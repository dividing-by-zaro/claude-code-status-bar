# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
xcodegen generate   # Regenerate .xcodeproj after changing project.yml or adding/removing Swift files
```

Then build and run from Xcode. Do not use `xcodebuild` — the user builds manually in Xcode. Never edit `Info.plist` directly; all plist properties are defined in `project.yml` under `targets.ClaudeCodeMonitor.info.properties`.

## Architecture

Native macOS menu bar app (Swift/SwiftUI, macOS 14.0+). Zero third-party dependencies.

- `LSUIElement = true` — menu bar only, no Dock icon
- `MenuBarExtra` with `.window` style for a rich SwiftUI popover
- `@Observable` for reactive state management
- 500ms polling interval

**`ProcessMonitor`** is the core engine — it discovers Claude processes, reads JSONL session state, collects CPU metrics, and publishes an observable `[ClaudeProcess]` array that drives the UI.

## Process Detection

Claude Code CLI installs as a symlink (`~/.local/bin/claude` → `~/.local/share/claude/versions/X.Y.Z`). The kernel reports `p_comm` as the resolved filename (e.g. `2.1.72`), NOT `claude`. Detection uses:

1. `sysctl(KERN_PROC, KERN_PROC_UID)` to list user processes (buffer oversized 2x to avoid race condition between size query and data fetch)
2. `proc_pidpath()` to get full executable path, matching `/claude/versions/` or suffix `/claude`
3. Fallback: `KERN_PROCARGS2` to check argv

## State Detection

Three states: **Running** (🏃), **Blocked** (✋ needs user approval), **Done** (✅).

State is determined by reading Claude's JSONL session logs in `~/.claude/projects/`. The process CWD (via `proc_pidinfo(PROC_PIDVNODEPATHINFO)`) maps to the project directory name (path slashes replaced with dashes).

The last meaningful entry (skipping `progress`, `system`, `file-history-snapshot`) in the most recent `.jsonl` file determines state, combined with file modification time (staleness):

- `role=user` + file < 30s old → **Running** (Claude is thinking/streaming)
- `role=assistant, stop_reason=null` + file < 30s old → **Running** (still streaming)
- `role=assistant, stop_reason=tool_use` + file < 15s old → **Running** (tool executing)
- `role=assistant, stop_reason=tool_use` + file > 15s old → **Blocked** (needs user approval)
- `role=assistant, stop_reason=end_turn` → **Done**
- Any stale entry (> 30s) with `role=user` or `stop_reason=null` → **Done** (stale partial message from finished session)

File staleness is critical: `stop_reason=null` can be a leftover partial message, not active streaming. The 30s threshold accounts for long streaming responses where the JSONL isn't written until the message completes.

### Subagent Detection

Before walking backwards through JSONL entries, the monitor checks if the very last line is an `agent_progress` progress entry (file < 60s old). This catches subagent activity (Explore, Plan, etc.) that would otherwise be skipped by the "skip progress entries" logic, preventing false "Done" states during long-running subagent work.

## Sound Notifications

State transitions trigger macOS system sounds via `NSSound`:
- **Running → Blocked**: Morse (soft ping — needs attention)
- **Running → Done**: Glass (chime — task complete)

Safeguards:
- `previousState` starts as `nil` — first state observation is silent (no sounds on app startup)
- 3-second cooldown per process prevents rapid-fire sounds from state flicker
- `isPlaying` check prevents overlapping playback
