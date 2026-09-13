# Omapager v1.0.0

The first tagged release of Omapager, a notification daemon for Omarchy with grouped notification decks, actionable cards and per-source quiet controls.

## Notifications that fit the desktop

- Group notifications by source and expand a deck to read its messages without losing the individual cards.
- Use Omarchy's native colours, typography, buttons, borders and theme-controlled corners. Notification text can be scaled from 75–200% without resizing the bar or panel text.
- Act on detected verification codes, links and phone numbers, use sender-provided actions, and reply inline to supported KDE Connect notifications.
- Keep recent notifications in the panel after their popups disappear. Recent starts collapsed and resets on shell restart; verification codes are redacted.
- Snooze individual sources or everything for a chosen duration, or enable Do Not Disturb. Critical notifications and the configurable verification-code exception retain their existing behaviour.

## Display and sharing controls

- Choose the active display, a specific output or all displays. A fresh deck follows focus in active-display mode; an already-visible deck stays put.
- Retain a selected output across disconnection, with a connected-display fallback while it is unavailable.
- Detect Hyprland portal sharing sessions and offer a timed snooze. Detection never mutes notifications automatically: you choose 30 minutes, 1 hour, 4 hours or Not now.
- Keep preferences focused on display selection, countdown animation and sharing suggestions. Edge spacing is config-only, defaults to 12 logical pixels, and supports 0–64. The visual countdown is off by default; notifications still expire normally.

## Safer defaults and fixes

- Require Bubblewrap for storage, icon and KDE Connect helpers, with no automatic unsandboxed fallback.
- Leave remote website-icon fetching and implicit sender default actions off by default. Remote icon connections use validated public addresses, including redirects, and downloaded images are checked before use.
- Bound notification admission and stored content. Disk history defaults to 24 hours and 100 entries; detected verification-code notifications are redacted before persistence. Copied codes clear after 60 seconds by default if the clipboard still contains the same code.
- Preserve ordinary numbered build messages, escaped text and restored action offers. Fix notification replacement/lifetime handling and hidden-display card measurement.
- Restore Escape when switching to preferences, prevent pointer hover from arming state-changing keyboard shortcuts, and keep the card's context menu available on the compact close button.
- Repair the local reply demo using a dedicated short-lived session. Demo replies stay in a private local result file and are never sent to a phone.

## Upgrading and requirements

This release replaces the earlier untagged `0.1.0` manifest version; configuration remains on the same `njpatel.omapager` bar-widget entry in `~/.config/omarchy/shell.json`.

- Use Omarchy with Quickshell 0.3.x, Hyprland, Python 3 and Bubblewrap. Pillow is required for optional remote website icons. `wl-clipboard` is recommended; KDE Connect and its phone app are needed for real phone notifications and replies.
- Keep the built-in `omarchy.notifications` service disabled while Omapager is enabled so only one daemon owns the notification bus name.
- Review the safer defaults when upgrading from older untagged builds, especially history retention, remote icons and card-click actions. Existing stored notifications are processed under the current validation and redaction policy.
- After updating the plugin, run `omarchy restart shell` to recreate its notification surfaces.

The `v1.0.0` tag and GitHub source archives identify this release. Marketplace submission or verification is a separate step and is not implied by this release.

## Known limits

Sharing detection recognises the Hyprland portal's stream metadata, not every capture application. It is a convenience, not a privacy guarantee. Dismissing a sharing offer is in-memory, so restarting the shell during a share can offer again. Code recognition is heuristic; real-phone reply support depends on the notification exposing a uniquely matching KDE Connect reply channel.

## Contributors

- @theaxlklo (Axel Calo): notification, storage, network, action and helper hardening, with regression coverage and integration work in #4.
- @salemsayed (Salem Sayed Abdel Gawad): notification font scaling in #5.
- @njpatel: Omapager, display routing, sharing offers, Recent, native UI integration, follow-up fixes and demo/documentation work.
