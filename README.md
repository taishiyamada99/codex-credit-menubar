# codex-credit-menubar

A lightweight macOS menu bar app that shows Codex credit/rate-limit remaining percentages using the official `codex app-server`.

## Highlights

- Menu bar resident app (`MenuBarExtra`) with default inline display: `7D xx%`
- Dropdown menu with all available buckets from app-server
- Data source modes:
  - `Auto (Desktop-first)`
  - `Codex App`
  - `Codex CLI`
  - `Custom Path`
- Automatic refresh every 5 minutes + manual refresh
- App-server notifications (`account/rateLimits/updated`, `account/updated`) trigger immediate refresh
- Daily local snapshot at 02:00 with 180-day retention (SQLite)
- History graph (7/30/90/180 days) + CSV export
- Threshold notifications (default: 20/10/5%) with duplicate suppression
- Start at login toggle (`SMAppService`)
- UI language switching (`system`, `en`, `ja`)
- Diagnostics tab for connection/source/error visibility

## Requirements

- macOS 14+
- Swift 5.10+
- Installed `codex` command (Codex desktop app bundle or Codex CLI)
- Authenticated Codex session (handled by app-server)

## Build and Test

```bash
swift build
swift test
```

## Package `.app`

```bash
./scripts/package_app.sh
```

Output:

- `output/CodexCreditMenuBar.app`

## Runtime Update Timing

The app updates data at these points:

- Immediately after successful startup connection
- Every 5 minutes by default
- Immediately when app-server emits account/rate-limit update notifications
- When `Refresh now` is pressed
- On reconnect attempts after failures with exponential backoff

## Project Layout

- `Sources/CodexCreditMenuBar/App`: app entry, view model, settings window manager
- `Sources/CodexCreditMenuBar/Views`: menu and settings UI
- `Sources/CodexCreditMenuBar/Services`: app-server client, source resolver, classification, notifications
- `Sources/CodexCreditMenuBar/Data`: SQLite persistence layer
- `Sources/CodexCreditMenuBar/Models`: domain/state models
- `Tests/CodexCreditMenuBarTests`: unit tests

## Privacy

- This app does not manage API keys directly.
- Authentication is delegated to `codex app-server`.
- Stored data is limited to usage percentages, settings, diagnostics, and history metadata.

