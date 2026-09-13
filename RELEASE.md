# Omapager v1.1.1

A preferences and documentation cleanup following v1.1.0.

## Changes

- Website-icon fetching is now config-only. It stays automatic by default; set `fetchRemoteIcons: false` in the widget's `shell.json` entry to disable it. Local and validated cached icons still work when fetching is off.
- Replace rotating status phrases with the actual notification state. Tooltips, snooze controls and preferences now use direct labels.
- Simplify installation instructions into a choice of marketplace or Git, followed by a shared activation step. Until the new stable release is approved, marketplace installation uses Git HEAD.
- Shorten the README feature descriptions, lead with screen-sharing detection, and refresh the preferences and panel screenshots. The original demo names and icons are preserved.

## Updating

Run `omarchy restart shell` after updating. Existing configuration values are preserved. This patch does not change the network protections or optional Bubblewrap policy introduced in v1.1.0.

[Changes since v1.1.0](https://github.com/njpatel/omapager/compare/v1.1.0...v1.1.1)
