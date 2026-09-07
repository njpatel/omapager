# Omapager hardening: upstream implementation handoff

## Purpose and scope

This patch preserves Omapager's QML/Quickshell notification deck while tightening
its URL, storage, network, process and action boundaries. It implements the
incremental hardening route described in the supplied **Omapager Hardened Fork
Implementation Plan**, with tests and explicit compatibility choices.

Baseline: `29548e5761f1b9f419afe988d77f67e3dd3e81cb`.
The predecessor security fix `e0fa1128dcb317641a47a98dd3fb365e67025ae1` was confirmed
as an ancestor. Work is on local branch `hardening/main`, with local tag
`security-baseline-2026-09-06` and the original repository recorded as `upstream`.
The review fork is https://github.com/theaxlklo/omapager. No release or
active-desktop installation was created. This branch is being submitted as a
draft upstream pull request, with integration checks still pending.

This is an unreleased proposal for maintainer review, not a claim that the
application is fully secure. Source changes and automated tests are ready for
review; desktop/phone integration and hosted security checks remain release gates.

## What changed, why, and how

| Area | Previous behavior / risk | Implementation route | Compatibility effect |
| --- | --- | --- | --- |
| External navigation | Several call sites could open detected or stored links without the markup path's checks | Added `Security.js`; body anchors, detected offers and card fallback all use its sole URL opener | Restricted URL forms described below |
| Deceptive URLs | A detected HTTP prefix did not establish a safe destination | Reject userinfo, controls, backslashes, nested escapes and invalid authority; canonicalize ASCII host and ports | Raw Unicode/IP/single-label hosts rejected; Punycode accepted |
| Notification bounds | Sender fields could propagate through regexes/UI/storage without explicit common caps | Bound ingress and restored rows; limit actions, codes, cards, queues, JSON and downloads | Over-limit content truncates or fails closed |
| Qt markup | Body sanitizer existed, but other text and restored derived fields needed review | Keep tiny formatting allowlist; validate anchors; force ordinary text to PlainText; rebuild restored rich body | Sender images through arbitrary local/remote URLs no longer render |
| OTP privacy | Raw notification rows, including code/raw-body fields, could reach live/history files | Separate `Store.sanitiseForPersistence`; Python independently sanitizes raw/legacy entries | Code-bearing persisted cards become generic redacted placeholders |
| History | Seven days / 200 entries; files inherited normal defaults | Default 24 hours / 100; settings for off/1h/24h/7d; 0700 directories, 0600 atomic files, no-follow reads, symlink refusal | Shorter history; invalid/oversized legacy entries and old .part files discarded |
| Remote icons | Enabled by default; a DNS check was followed by a separate urllib resolution | Opt-in `fetchRemoteIcons`; direct numeric-sockaddr connection after validating all DNS results; per-hop checks | No initial website contact unless enabled |
| Remote images | Download extension could determine rendering path, including SVG | Sandbox decode PNG/JPEG/WebP/ICO, cap dimensions at 2048, output PNG <=128 | Remote SVG rejected; remote decoding requires Pillow |
| Icon identity/path | App-name guesses and parent-domain fallback could contact unrelated origins; hints entered glob patterns | Remove guessed/parent-site fetches; validate names and restrict resolved paths | Some sources use local/generic icons instead |
| Helpers | Ambient HOME and network capabilities | Required Bubblewrap wrappers with per-helper mounts/namespaces and resource limits | Missing/blocked Bubblewrap disables helpers, never silently bypasses isolation |
| Default actions | Generic card click could invoke sender default action first | Strict default off; explicit "Open in app" action button; compatibility setting available | Some applications need that explicit action button |
| KDE replies | Fuzzy/app-only first match could select the wrong message | Unique exact normalized app/body match; validate discovered path; re-match at send; explicit argv terminator | Ambiguous or stale targets fail closed; card closes only on success |
| Clipboard | Existing sensitive argv behavior and conditional expiry | Preserve `--sensitive --`; bound values and check code belongs to selected row; configurable 60-second default | 30/60/90-second choices; existing Qt fallback remains |
| Command safety | Static shell capability probe and window-class Lua fallback | Shell-free executable probe; compositor hex address is the only focus dispatch argument; busctl `--` separates options/data | No class-based fallback when a compositor address is missing |
| Diagnostics | Probe/offer IPC could return notification text, labels, URLs or a copied code | Probe returns counts/policy/status; offer returns a generic result | Existing debug/demo tools expecting old probe fields need adjustment |
| CI/supply chain | No permanent gates for these invariants | Synthetic tests, custom static/Semgrep rules, CodeQL config, OSV, SHA-pinned Actions, hash-locked test tools | Hosting owner must enable repository features and execute workflows |

## Implementation route used

1. Read the supplied plan and repository-specific `AGENTS.md`; checked the exact
   baseline and predecessor commit without following a moving branch.
2. Recorded baseline behavior with synthetic fixtures, including the issue #2
   userinfo payload, code detection, web-source lifting and history normalization.
3. Traced notification-derived fields to URL, Qt text/image, disk, HTTP, process,
   clipboard, D-Bus and Hyprland sinks. Centralized policy before changing defaults.
4. Added URL/markup/input controls and separate persistence sanitisation. Chose
   whole-notification placeholders for detected codes because replacing just the
   visible digits would leave encoded/raw/URL/metadata representations behind.
5. Replaced the HTTP client, restricted icons, and routed production helper calls
   through fail-closed namespace launchers. Kept the desktop UI architecture.
6. Tightened default action routing, reply matching and clipboard handling; removed
   the class-to-Lua and shell-probe paths found during the sink review.
7. Exercised pure JS under Node and actual Qt, Python boundaries, a real local HTTP
   fixture, raster decode, and real Bubblewrap namespaces using synthetic HOME.
8. Added CI and audited its own dependencies. An older scanner toolchain failed
   compatibility/security checks; upgraded to Semgrep 1.176.1, regenerated hashes
   and reran OSV successfully instead of suppressing the findings.
9. Reviewed remaining capabilities and wrote the threat model, architecture,
   validation, sandbox and release/upstream checklists. Did not switch the user's
   notification service or send anything to the repository author.

## Suggested upstream review order

These are separable review areas, not a request to accept every strict default:

1. Central URL broker and issue #2/bypass tests.
2. Input/markup bounds and local path safety.
3. Sensitive persistence and private atomic file handling.
4. Pinned-address HTTP client, redirect/size/raster tests.
5. Action/clipboard/reply hardening and focus dispatch restriction.
6. Optional/default privacy choices and their settings UI wording.
7. Helper isolation packaging and failure UX.
8. CI, supply-chain policy and maintained release process.

The URL broker, bounded parsers, pinned network transport, path checks, explicit
argv and regression tests are strong candidates for general upstream adoption.
Whole-message code redaction, raw-Unicode/IP-link rejection, strict default card
clicks, mandatory Bubblewrap and removal of domain guesses are product/packaging
choices that deserve explicit maintainer discussion.

## New settings

Settings remain on the bar-widget entry; `Widget.applySettings()` passes them to
the service, respecting the existing plugin architecture.

| Setting | Hardened default | Supported values |
| --- | --- | --- |
| `fetchRemoteIcons` | `false` | boolean |
| `allowDefaultActionOnCardClick` | `false` | boolean |
| `historyHours` | `24` | 0, 1, 24, 168 |
| `clipboardTimeout` | `60` | 30, 60, 90 seconds |

History off controls archived history; non-code live notifications can still be
persisted while on screen for restart recovery. It is not a no-disk mode.
Pillow remains optional, but remote icon bytes are rejected without it. No desktop
package installation is performed by this source patch. Bubblewrap is a new
required helper dependency, overriding the baseline no-new-runtime-dependencies
convention in accordance with the supplied plan.

## Security findings addressed

Severity here describes potential impact, not a CVSS score or confirmed exploit
against a real application. All reproductions use synthetic values.

| Priority | Location / path | Evidence and fix |
| --- | --- | --- |
| High | Service detected-link / card fallback URL sinks | Direct opener calls bypassed the markup gate; only Security.js now opens URLs |
| High | Icon DNS validate-then-open | Validation and connection resolved independently; pinned sockaddr + TLS hostname tests prove no second DNS lookup |
| High | Store row serialization | Synthetic OTP appeared in fields sent to disk; tests inspect actual live/history files after redaction |
| High | Focus class fallback | A window-class string entered a Lua expression; removed fallback and accept only hexadecimal addresses |
| Medium | KDE fuzzy matching | Duplicate/empty/app-only candidates could pick a first match; exact unique matching and send-time revalidation |
| Medium | Icon name glob/path construction | Sender names could contain separators/glob characters; name and resolved-root checks plus sandbox |
| Medium | File permission/symlink handling | Predictable .part writes and ambient umask; secure temp + atomic replace, private modes, static symlink refusal |
| Medium | Automatic icons and generic card default | Arrival contacted sites and card clicks invoked sender actions; safer defaults with explicit settings/actions |
| Defense in depth | UI parsing, process capabilities, diagnostics | Plain text, bounds, namespace/resource restrictions and redacted diagnostic response |

## Validation and limitations

Completed: baseline/JS corpus/generated tests, **16 Python tests**, actual Qt policy
suite (**4 passes including setup/cleanup**), real loopback HTTP fixture, real
Bubblewrap HOME/network/write tests, static gates, **Semgrep: zero findings**,
**OSV: no known issues in 67 locked packages**, and whitespace checks.
`qmllint` exits 0 but emits unresolved dynamic Omarchy/Quickshell imports and type
warnings. This is syntax/static evidence, not successful production UI execution.
See [VALIDATION.md](VALIDATION.md) for exact commands and scope.

Still needed: disposable live Omarchy rendering/interaction tests, a consenting
real KDE Connect phone, hosted CI/CodeQL run, repository reporting/secret-scanning
settings, maintainer review and release provenance/signing. No release exists yet. The plan's long-term daemon/UI split is deliberately deferred
until the incremental work is stable; it was not silently treated as implemented.

Residual risks: unsandboxed Quickshell and Qt notification ingress/image-provider
code; forged source/PID claims; existing same-user IPC action access; unfiltered
KDE session-bus access; same-user directory races; clipboard compare/clear race;
heuristic code recognition; other secrets in ordinary messages; old backups;
and opted-in website tracking. This patch does not authenticate sender identity,
securely erase past copies or prevent all phishing. It is defense in depth, not a
substitute for the desktop's trust model or an independent security audit.

## Files to start with

- `Security.js`, `Markup.js`, `Detect.js`, `Store.js`
- `Service.qml`, `Toast.qml`, `Widget.qml`, `manifest.json`
- `bin/omapager_http.py`, `bin/omapager_files.py`, `bin/omapager-run-helper`
- `bin/omapager-store`, `bin/omapager-icon`, `bin/omapager-kdeconnect`
- `tests/`, `security/`, `.github/workflows/`
- `SECURITY.md`, `docs/THREAT_MODEL.md`, `docs/SECURITY_ARCHITECTURE.md`,
  `docs/SANDBOX.md`, `docs/VALIDATION.md`, `docs/UPSTREAM_MERGE_CHECKLIST.md`

Tooling references used while configuring CI: [CodeQL Action](https://github.com/github/codeql-action),
[Semgrep CI documentation](https://semgrep.dev/docs/semgrep-ci/sample-ci-configs),
[OSV GitHub integration](https://google.github.io/osv-scanner/github-action/).
Action release tags were resolved from the official repositories to full commits;
scanner packages are version- and hash-locked. No mutable Action refs are used.
