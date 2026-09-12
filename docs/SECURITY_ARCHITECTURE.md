# Hardened architecture

No rewrite or daemon/UI split is introduced. The existing QML deck and Omarchy
integration remain the application. Changes follow the implementation plan's
incremental phases 0–8, followed by adversarial tests. Phase 9 is deferred pending
integration stability, as the plan requires.

1. `Store.snapshot` bounds bus fields before parsing. `Security.js` defines limits.
2. `Markup` escapes content and restores a small formatting/anchor allowlist.
   Summary and fallback text use PlainText. Restored rich text is regenerated.
3. Every URL sink enters `Security.openExternalUrl`. It validates again immediately
   before the sole `Qt.openUrlExternally` call. Detection is not authorization.
4. `Store.sanitiseForPersistence` separates live and persisted rows. Detected-code
   rows become generic placeholders; sender metadata, raw/derived body and links
   cannot carry alternate encodings into files. Python independently sanitises
   raw callers and old files. Images/reply handles/rich markup are not persisted.
   Its independent detector uses bounded summary/raw-body/body content, not
   generated metadata, with the same product/year exclusions and 24-before /
   72-after keyword windows as the JS detector. Recognition remains heuristic.
5. QML launches `omapager-run-*` wrappers. Bubblewrap is required; no automatic
   unsandboxed fallback exists. The probe distinguishes availability from an
   operational namespace test. It does not claim every helper operation succeeded.
6. Remote icons are opt-in. `omapager_http.py` resolves once per hop, validates
   every address (including against an IPv6-mapped-IPv4 bypass) and connects
   to a numeric sockaddr, falling back across every validated address for that
   hop but never re-resolving and never letting a TLS failure be masked by a
   fallback attempt. TLS validates the original hostname. The original host
   supplies SNI and Host; there is no urllib opener to route through an
   environment proxy in the first place. This is the sole HTTP implementation
   `bin/omapager-icon` uses — upstream (06f511) independently reached the same
   resolve-once/validate-all/connect-direct design inline in that file; this
   module is kept as the one transport rather than carrying both. A remote
   cache hit is re-validated against the same raster/format policy a fresh
   fetch uses before being trusted, so a cache entry from before that policy
   existed (a cached SVG, most notably) cannot bypass it merely by predating it.
7. Explicit actions use argv. Generic card clicks do not invoke the sender's
   default action unless configured; that action is available as an explicit
   "Open in app" button. Replies require unique exact app/body matching, valid
   discovered KDE paths, and a second match immediately before send.
   The helper preserves the explicitly selected local session-bus socket; it
   does not substitute the host session when running inside a private session.

## Deliberate URL compatibility restrictions

QML's JS engine does not expose the browser WHATWG URL constructor. Rather than
simulate all browser parsing, accept a restricted grammar: HTTP(S), dotted ASCII
hostnames (Punycode allowed), valid decimal ports, no userinfo, backslashes,
controls, nested percent escapes or raw quotation/angle brackets. IP literals,
single-label hosts and raw Unicode hosts fail closed. A hostname's last label
is rejected as numeric-looking in every form a real WHATWG parser would accept
as "ends in a number" — plain decimal and 0x-prefixed hex, including bare `0x`
(which the browser treats as zero) — so an alternate IPv4 spelling cannot pass this
grammar as an ordinary hostname and later canonicalize to a private/loopback
address. Mailto accepts one address, no query headers/attachments/percent
escapes. External browser links may use valid nonstandard ports; automatic
icon requests allow only HTTP:80/HTTPS:443.

## Limits and defaults

App 256; summary 2,048; body/raw body 32,768 characters; URL 4,096; source 253;
actions 16 with 256-character labels/IDs; codes 8; phone 64; JSON entry 65,536
bytes; live notifications 100 (`maxLiveNotifications`, counting every one
currently visible, held while the deck is occupied, or mid-flight in a
deferred insertion — not just what is on screen at the instant of the check);
pending icon/reply lookups 100; store queue 256. Oversized
serialized entries fail closed rather than writing partial JSON. Queue overflow
may drop persistence work; this bounds resource use, not reliable delivery under
notification floods. The sender's underlying bus allocation is outside this cap.

Replacements reuse the admitted key in all live states. Quickshell updates an
existing notification QObject through property-change signals; those signals
are coalesced before resnapshotting. Reservation identity guards deferred
callbacks after cancellation, and startup restore/history replay share the cap.
Stored IDs cannot replace a new session's live sender merely by matching its ID.

History: 100 entries and 24 hours by default. `historyHours`: 0, 1, 24, 168.
Remote icons: off (`fetchRemoteIcons`). Default card action: off
(`allowDefaultActionOnCardClick`). Clipboard timeout: 60 seconds, choices 30/60/90.
Widget.applySettings is the only settings path to the service, as upstream expects.

HTTP caps: HTML 512 KiB, manifest 256 KiB, icon 1 MiB, three redirects, five-second
socket timeout, bounded body deadline plus 45-second helper wall timeout. DNS is
bounded by the helper timeout. No compressed responses. Remote PNG/JPEG/WebP/ICO
must decode in Pillow, dimensions <=2048 per side, normalized PNG <=128 per side.
Without Pillow remote bytes never reach Qt; local theme resolution still works.

## Future separation

An independent daemon could own D-Bus, policy and state and send only structured
notification-ID actions to Quickshell. That is a larger compatibility project,
not a prerequisite for these changes. Evaluate Python versus Rust based on
maintainability and IPC boundaries after the current integration is validated;
a language rewrite alone does not fix trust-boundary mistakes.
