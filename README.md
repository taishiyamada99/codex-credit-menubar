# Codex Credit Menu Bar (macOS)

A macOS menu bar app that shows Codex credit usage limits from `codex app-server`.

## Implemented Features

- Menu bar resident app (`MenuBarExtra`)
- Default inline label: `7D xx%`
- Dropdown shows all detected limits (`5h`, `7d`, `Review`, `GPT Spark`, `Custom`)
- Source selection: Auto (Desktop-first), Codex App, Codex CLI, Custom path
- Refresh loop: every 5 minutes + manual refresh
- JSON-RPC connection to `codex app-server --listen stdio://`
- Rule-based limit classification with alias override rules
- Daily snapshot at 02:00 local time with 180-day retention
- History graph (Swift Charts) + CSV export
- Threshold notifications (20/10/5 default)
- Start at login toggle (`SMAppService`)
- UI language switching (English/Japanese/System)
- Diagnostics tab (connection and error logs)

## Project Layout

- `Sources/CodexCreditMenuBar/App` - app entry and view model
- `Sources/CodexCreditMenuBar/Views` - menu and settings UI
- `Sources/CodexCreditMenuBar/Services` - app-server client, source resolver, classification, notifications
- `Sources/CodexCreditMenuBar/Data` - SQLite persistence
- `Sources/CodexCreditMenuBar/Models` - domain models
- `Tests/CodexCreditMenuBarTests` - unit tests

## Build

```bash
swift build
swift test
```

## Notes

- Requires macOS 14+
- Requires an installed `codex` command (Codex App bundle or Codex CLI)
- Authentication is delegated to `codex app-server`
