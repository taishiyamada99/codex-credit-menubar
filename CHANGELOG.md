# Changelog

## v0.1.1

### Features

- Added raw-first dual retention storage:
  - short-term raw snapshots every 5 minutes for fixed 28 days
  - long-term raw daily snapshots at GMT 00:00
- Added configurable long-term retention options: `1 year`, `2 years`, `5 years`, `Unlimited`.
- Added manual refresh result feedback in General settings (success/failure with local date-time).
- Added redesigned settings structure with `General`, `Usage`, and `Diagnostics` tabs.
- Added usage-focused UI with line chart visualization and summary cards.
- Added app icon generation into packaging flow.

### Bug Fixes

- Fixed a multi-display menu bar visibility issue by moving to a standard title-based `MenuBarExtra` label.
- Fixed menu bar truncation pressure by compacting inline title rendering.
- Fixed refresh status visibility so users can immediately confirm the latest manual refresh outcome.

### Removed

- Removed notification settings and threshold notification code path.
- Removed alias rule management from UI and runtime classification path.
- Removed Privacy Mode from UI and runtime display logic.
- Removed `Max inline items` setting; menu bar inline display count is now fixed to 3.
- Removed obsolete custom menu label view used for menu bar title rendering.

## v0.1.0

### Features

- Added a macOS menu bar app to display Codex credit/rate-limit percentages.
- Added source selection with desktop-first auto mode and CLI fallback.
- Added configurable inline menu bar items and full dropdown bucket visibility.
- Added settings tabs for general/usage/diagnostics.
- Added daily 02:00 local snapshots with SQLite persistence and 180-day retention.
- Added history charting and CSV export.
- Added start-at-login support via `SMAppService`.
- Added English/Japanese/system language switching.

### Bug Fixes

- Fixed source resolution to avoid launching the Codex desktop main UI binary repeatedly.
- Fixed app-server parsing to correctly handle primary/secondary limit structures and alternative payload shapes.
- Fixed menu bar item selection so display changes are reflected immediately.
- Fixed fallback behavior so only actually available limit kinds are shown.
- Fixed settings-window presentation by using a dedicated settings window manager.
- Fixed refresh overlap by deduplicating concurrent refresh triggers.
- Fixed stream parsing to avoid dropping partial frames while reading app-server output.
- Reduced unnecessary background work by adaptive snapshot scheduling and diagnostics refresh scoping.
- Added diagnostics log pruning to prevent unbounded growth.
