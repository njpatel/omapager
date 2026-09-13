# Omapager v1.1.0

Changes from **9–13 September**, for people already using Omapager. The new v1.1.0 defaults are first; the remaining highlights also include work shipped in v1.0.0 during this five-day window.

## New in v1.1.0

- **Website icons are automatic again.** Missing icons are fetched by default, with a **Fetch website icons** switch in preferences. Switching it off stops new requests and cancels the current lookup; local and validated cached icons still work. An explicit saved `fetchRemoteIcons: false` is respected.
- **Bubblewrap is no longer a hard dependency.** Helpers use it when operational and otherwise run directly as your user. Set `requireSandbox: true` in the widget's `shell.json` entry to require isolation instead. That policy is applied before startup helpers run, and a failed helper is never replayed outside its sandbox.
- **Automatic fetching keeps strict boundaries.** HTTPS-only requests, public-address checks, DNS pinning, redirect validation, bounded downloads and verified raster decoding apply in both execution modes. Added coverage for downgrade attempts, malformed icon metadata, slow responses, cached icons with fetching disabled, and helper cancellation.
- **Security trade-offs are documented.** The README now explains what icon requests disclose, what the optional sandbox does and does not protect, and how to turn fetching off or require sandboxing. The demo's helper calls follow the same configured policies.

## Also landed in the last five days

- Notification cards and panels now use Omarchy's native controls, theme borders and typography. The close button is a compact bordered control; settings sits to the left of the enable switch. The README has refreshed screenshots, the original named/icon-rich demos and a default-theme ASCII header.
- Added active-display, specific-output and all-display routing, plus explicit timed snooze offers when Hyprland portal sharing is detected. Sharing detection does not mute notifications automatically.
- Added the collapsed **Recent** stack and notification font scaling. Edge spacing is config-only, defaults to 12 logical pixels, and the visual countdown is optional and off by default.
- Fixed escaped preview text, hidden-display card measurement, notification replacements, ordinary numbered messages being over-redacted, and restored offers. Preferences now handles Escape correctly, and merely hovering a source cannot arm the unsnooze shortcut.
- Repaired the local inline-reply demo. Replies go to its private result file, never to a real phone.

## Updating

Restart with `omarchy restart shell` after updating. Pillow is needed for remote icon decoding; Bubblewrap is optional unless you enable `requireSandbox`. If your saved configuration explicitly disables remote icons, use the new preferences switch to enable them.

Website requests expose your IP and request time to the source site and its icon hosts. Direct helper mode is not sandboxed. See the README's **Security** section for protections and limitations; this release does not imply marketplace verification.

Thanks to @theaxlklo for the hardening and integration fixes, and @salemsayed for notification font scaling.

[Changes since v1.0.0](https://github.com/njpatel/omapager/compare/v1.0.0...v1.1.0)
