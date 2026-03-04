# Changelog

## v0.1.0

### Features

- Added a macOS menu bar app to display Codex credit/rate-limit percentages.
- Added source selection with desktop-first auto mode and CLI fallback.
- Added configurable inline menu bar items and full dropdown bucket visibility.
- Added settings tabs for general/display/history/notifications/language/diagnostics.
- Added daily 02:00 local snapshots with SQLite persistence and 180-day retention.
- Added history charting and CSV export.
- Added low-remaining notifications with threshold configuration.
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

