# codex-credit-menubar

A lightweight macOS menu bar app that shows Codex credit/rate-limit remaining percentages using the official `codex app-server`.

## Highlights

- Menu bar resident app (`MenuBarExtra`) with default inline display: `7Dxx%`
- Inline menu bar display is fixed to 3 items maximum
- Minimal dropdown menu with quick actions (`Refresh now`, `Settings`, `Language`, `Quit`)
- Data source modes:
  - `Auto (Desktop-first)`
  - `Codex App`
  - `Codex CLI`
  - `Custom Path`
- Automatic refresh every 5 minutes + manual refresh
- App-server notifications (`account/rateLimits/updated`, `account/updated`) trigger immediate refresh
- Manual refresh result message with local timestamp in Settings
- Raw dual-retention persistence (SQLite):
  - Short-term: every 5 minutes, fixed 28 days
  - Long-term: daily at GMT 00:00, retention selectable (`1y`, `2y`, `5y`, `unlimited`)
- Usage graph (7/30/90/180 days) + CSV export
- Start at login toggle (`SMAppService`)
- UI language switching (`system`, `en`, `ja`)
- Settings tabs: `General`, `Usage`, `Diagnostics`
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

## Data Retention Model

- Storage backend: local SQLite (`Application Support/CodexCreditMenuBar/app.sqlite`)
- Short-term table stores raw bucket-level rows every 5 minutes for 28 days
- Long-term table stores raw bucket-level rows once per GMT day
- Long-term retention is configurable from Settings: 1 year / 2 years / 5 years / unlimited

## Project Layout

- `Sources/CodexCreditMenuBar/App`: app entry, view model, settings window manager
- `Sources/CodexCreditMenuBar/Views`: menu and settings UI
- `Sources/CodexCreditMenuBar/Services`: app-server client, source resolver, classification
- `Sources/CodexCreditMenuBar/Data`: SQLite persistence layer
- `Sources/CodexCreditMenuBar/Models`: domain/state models
- `Tests/CodexCreditMenuBarTests`: unit tests

## Privacy

- This app does not manage API keys directly.
- Authentication is delegated to `codex app-server`.
- Stored data is limited to usage percentages, settings, diagnostics, and history metadata.
