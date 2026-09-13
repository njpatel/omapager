# Security changelog

## Unreleased — preview markup, 2026-09-12

- Flatten only allowlisted markup in plain-text previews, preserving escaped
  literals without interpreting them as rich text.
- Keep the independent JS redaction scan separate from display previews. Strip
  tag-shaped content before code detection so long literal attributes cannot
  move legacy or raw-only codes outside the keyword window. Regression checks
  cover both entry shapes; a private Omarchy lab verified a redacted Recent card.

## Unreleased — maintainer follow-up, 2026-09-11

Follow-up to PR #4 at `8f3a16cef4d4f05860b7fe7b4808c0eba189797a`:

- Align independent Python code recognition with the bounded content view,
  product/year exclusions, split-code shapes and context windows used by JS.
  Ordinary numbered build messages survive writes and legacy migration; recognised
  split OTPs do not remain in raw or legacy history.
- Keep one reservation through held, deferred and visible notification states.
  Replace pending snapshots, cancel stale callbacks, and cap startup/history replay.
  Only a live sender can claim a replacement ID from the current server session.
- Observe Quickshell's in-place notification property changes, coalescing them
  before resnapshotting. Close each native notification once, not twice.
- Reject a bare terminal `0x` as an alternate numeric-host spelling.
- Bind the explicitly selected local session-bus socket in the KDE sandbox;
  unsupported addresses fail closed rather than selecting the host session.
- Try the next validated address when socket creation fails, without another
  DNS lookup or falling through a TLS validation failure.

Focused regressions and a private Omarchy lab exercised held replacements at
capacity, cancellation, replay limits, ordinary-message persistence and restored
offer rendering. No real phone, external URL or clipboard action was used.

## Unreleased — hardening/main, 2026-09-09

Rebased onto current upstream `njpatel/omapager:main` at `06f5117d4cca5730470100f3b7949933adccd839`
(previous local base: `29548e5761f1b9f419afe988d77f67e3dd3e81cb`), and fixed every
finding from PR #4's review. See UPSTREAM_HANDOFF.md's "Rebase onto current
upstream" and "PR #4 review findings" sections for the full account; summary:

- Upstream 06f511 introduced checked-address HTTP connections in
  `bin/omapager-icon`, independently reaching the same design this branch's
  `bin/omapager_http.py` already had. The rebase keeps this branch's module as
  the single transport (it is a strict superset: same resolve-once/validate-all/
  connect-direct guarantees, plus an IPv6-mapped-IPv4 bypass check upstream's
  version lacks, byte/redirect limits with a read deadline, identity-only
  Content-Encoding, and URL syntax hardening) rather than carrying two
  competing HTTP clients, and adds upstream's per-address connect fallback.
- **P1** — the Python persistence detector treated a bare verification keyword
  ("code", "verification", "pin", ...) as sufficient to redact a notification,
  so "Visual Studio Code: Build completed successfully" was rewritten to
  `[redacted]` — including destructively, on a plain restore of already-stored
  benign state. Now requires a distinct, nearby, digit-bearing token.
- **P2** — a remote icon cache entry written before raster validation existed
  (most dangerously a cached SVG) was trusted on every later run purely
  because its path resolved inside the cache directory. Now validated against
  the same format policy a fresh fetch uses, and invalidated on failure.
- **P2** — the notification admission cap counted `toasts.count` only, so
  notifications held while the pointer was over the deck, or mid-flight in a
  deferred insertion, did not count against it; 150 could be admitted before
  any of them were visible. Replaced with a single reservation set covering
  every live state.
- **P2** — the hostname policy rejected a numeric last label only in decimal
  form, so a 0x-prefixed hex label ("0x7f.0x0.0x0.0x1") — which a WHATWG URL
  parser canonicalises to a private/loopback address — read as an ordinary
  hostname.
- **P2** — the image-hint handler validated the raw handle against the
  qsimage-only shape before the `image://icon/<name>` extraction ran, so
  every named-icon hint (what `notify-send -i` and KDE Connect actually send)
  was silently dropped.
- **P2** — a restored notification never recomputed its link/meeting/phone
  offers, which the persistence allowlist deliberately excludes from what is
  written to disk, so those offers never came back after a restart. Restore
  now re-runs the current detectors against the persisted text and
  re-validates through today's URL policy, rather than trusting a legacy
  entry's own copy of those fields.

## Unreleased — hardening/main, 2026-09-06

Baseline: 29548e5761f1b9f419afe988d77f67e3dd3e81cb; predecessor fix verified.

- Centralized URL authorization for body links, detected offers and card clicks.
- Bounded notification fields, collections, parsing and persistent entries.
- Regenerated stored markup and denied sender-controlled file/network images.
- Redacted detected OTP notifications before persistence; reduced retention and
  added private atomic writes, symlink refusal and legacy-state sanitisation.
- Made remote icons opt-in; pinned connections to public DNS answers; validated
  every redirect and raster decode; removed guessed brand/parent-domain requests.
- Required fail-closed Bubblewrap wrappers for storage, icon and KDE helpers.
- Disabled implicit sender default actions; bounded explicit actions and clipboard.
- Replaced fuzzy reply guesses with unique exact matches, rechecked before send.
- Removed the shell capability probe and window-class-to-Lua fallback.
- Removed notification text/URLs/actions from diagnostic probe and OTP IPC return.
- Added synthetic tests, actual Qt policy tests, isolation tests, static gates,
  pinned CI actions and hash-locked development scanner dependencies.

See UPSTREAM_HANDOFF.md for rationale, compatibility effects, validation evidence
and the distinction between implemented changes and deferred release/integration work.
