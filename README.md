## Claude Code Status Bar

A native macOS menu bar app that monitors Claude Code CLI processes in real-time.

### Features

- **Per-instance status icons** in the menu bar separated by pipes (e.g. `🏃 | ✋`)
- **Three distinct states:**
  - 🏃 **Running** — Claude is actively working (streaming, executing tools)
  - ✋ **Blocked** — Claude needs your approval for a command
  - ✅ **Done** — Claude finished, waiting for your next message
- **JSONL-based state detection** — reads Claude's session logs for accurate state, no CPU guessing
- **Project name display** — shows the working directory name for each instance
- **Auto-cleanup** — finished processes removed after 5 minutes
- **500ms polling** — near-instant status updates
- **Zero dependencies** — pure Swift/SwiftUI, < 10MB memory

### Requirements

- macOS 14.0+
- Xcode 16+
- XcodeGen (`brew install xcodegen`)

### Build

```bash
xcodegen generate
open ClaudeCodeMonitor.xcodeproj
# Build and run from Xcode
```
