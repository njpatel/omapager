# Validation record

Local checks completed during this implementation (2026-09-06/07), plus a second
pass (2026-09-09) after rebasing onto current upstream and fixing PR #4's six
review findings. Fixtures are synthetic; no real notification history, OTP,
private key or phone message was used.

## 2026-09-09 — post-rebase, PR #4 findings fixed

Run from a fresh `python3 -m venv .venv` with `pillow==12.3.0` installed (the
version `security/requirements.txt` pins) so the raster test is not skipped,
and a locally-built `osv-scanner` (Go was not preinstalled in this environment;
built via `go install .../osv-scanner@408fcd6f8707999a29e7ba45e15809764cf24f67`).
Qt6 declarative tooling (`qmllint`, `qmltestrunner`) is not installed in this
environment and was not exercised in this pass — see "Still required" below.

| Check | Result |
| --- | --- |
| Rebase onto `upstream/main` at `06f5117d4cca5730470100f3b7949933adccd839` | Clean; conflicts resolved semantically, see UPSTREAM_HANDOFF.md |
| `node tests/baseline.cjs` | Pass |
| `node tests/security.cjs` | Pass; includes the six named PR #4 finding regressions and the `focusWindow`/capacity extraction tests run against the actual production Service.qml source |
| `python3 -m unittest discover -s tests -v` (with Pillow) | **27 tests pass, none skipped** — includes `tests/test_icon_network.py`, upstream's real-TLS/real-HTTP transport suite, adapted to the consolidated transport |
| `python3 -B -m unittest discover -s tests -p 'test_icon_network.py' -v` | 6 tests pass |
| `python3 tests/http_server.py` | Pass (required a fixture update: `resolve_public_host` → `resolve_public_answers`, an artifact of the transport consolidation, caught by this run) |
| `python3 security/check_invariants.py` | Pass |
| `rg` sweeps for `Qt.openUrlExternally`, `os.system`, `shell=True`, `sh -c`/`bash -c`, `urllib.request.urlopen`/`OPENER.open` | `Qt.openUrlExternally` only in `Security.js` plus tooling/docs references; no other matches anywhere |
| Semgrep 1.176.1 custom rules | 4 rules, 16 targets, zero findings |
| OSV 2.3.8 | No issues found (67 locked packages in `security/requirements.txt`) |
| `git diff --check` (whitespace) on `upstream/main...HEAD` | Pass |

Not re-run in this pass (validated earlier in this branch's history, see the
2026-09-06/07 record below, and not affected by the rebase or the six fixes):
Bubblewrap HOME/network/write tests, `bin/omapager-run-helper status`.

## 2026-09-09 (later same day) — Omarchy host: qmllint, QtTest, Bubblewrap, live session

Run directly on an Arch/Omarchy host with Quickshell, Hyprland, Bubblewrap and
`wl-clipboard` present, closing every gap the previous pass on this same day
listed under "Still required" except KDE Connect (no device or daemon on this
host). Commands and exit codes below; the live-session results were produced
by driving the daemon's own IPC on the real desktop, then reverted.

| Check | Result |
| --- | --- |
| `/usr/lib/qt6/bin/qmllint Service.qml Toast.qml Widget.qml DeedButton.qml` | Exit 0. 455 warnings, 0 errors — all in the documented unresolved Omarchy/Quickshell import/unqualified-access categories; none are runtime errors |
| `QT_QPA_PLATFORM=offscreen ... qmltestrunner -input tests/tst_security.qml` | 4 passed, 0 failed (`initTestCase`, `test_markup_and_storage`, `test_urls`, `cleanupTestCase`) |
| `python3 tests/sandbox.py` | Pass — real Bubblewrap namespaces: HOME contents denied, repo parent directory denied, network denied, scoped writes to `STATE`/`STATE/icons` succeed, OTP redacted on the synthetic store `put` |
| `bin/omapager-run-helper status` | `{"bubblewrapAvailable": true, "sandboxOperational": true, "required": true, "unsandboxedFallback": false}` |
| `bin/omapager-run-helper capabilities` | Exit 0 (`wl-copy`/`wl-paste` both present) |
| `python3 tests/http_server.py` | Pass |
| `bin/omapager-demo --list` | Pass (7 scenes, 25 notifications total) |

### Live Omarchy session

Installed via the real `omarchy plugin` CLI — `omarchy plugin validate` first
rejected the plugin folder (`bin/omapager-run-icon` etc. were committed
symlinks to `omapager-run-helper` at the time; Omarchy's validator disallows
symlinks inside a plugin folder). That validator is not invoked by `plugin
add`/`enable` for an already-present local folder, so install proceeded here,
but this blocked the documented `omarchy plugin add <git-url>` path for
anyone installing this plugin from git rather than a manual symlink — see
"Helper launchers are regular files, not symlinks" below for the fix and its
own validation pass. `shell.json` was backed up and its SHA-256 recorded first;
`omarchy plugin disable omarchy.notifications` / `enable njpatel.omapager
center` brought the plugin up, and disable/enable in reverse plus `plugin
remove njpatel.omapager` afterward restored it — `diff` against the backup
and a repeat SHA-256 both confirmed `shell.json` came back byte-identical.
Synthetic data only (`notify-send`, no real accounts/messages); the test-only
state directory was removed afterward. Single `quickshell` instance
throughout, confirmed by `pgrep -xc quickshell` after every restart; no
QML runtime error or warning attributable to Omapager appeared in
`journalctl --user` at any point (the two warnings present are pre-existing,
from the unrelated `OmaDisplay` and `axelkalo.agents` plugins).

| Area | Result |
| --- | --- |
| Load / restart | Loads with no Omapager QML error or warning; one `quickshell` process across three restarts |
| Appear/disappear, stacking, expand/collapse | `probe`/`expand` IPC confirmed: 1→4 toasts, `expanded` true/false toggled correctly |
| DND | `dnd` IPC on/off; a notification sent while on did not increment `count`; normal notifications resumed after `dnd` off |
| Per-source snooze | Snoozing `app:notify-send` held a same-source notification (`count` stayed 0) but not a distinctly-named source (`notify-send -a OtherSrc`, `count` → 1); `unsnooze` restored delivery |
| Restore across restart | A notification with a link and a phone number persisted, survived `omarchy-restart-shell`, and both `offer link`/`offer phone` still returned `performed` afterward |
| OTP redaction | `Your verification code is 415926` persisted as `body:"[redacted]"`; recursive `grep -rl` for the digits across the whole state directory found nothing |
| Link policy | `https://example.com/` → `offer link` = `performed` (opened). `https://paypal.com@evil.example/`, `http://0x7f.0x0.0x0.0x1/`, `file:///etc/passwd`, `javascript:alert(1)`, `http://127.0.0.1/admin` → all `none` (never reached the opener) |
| Capacity | 130 concurrent synthetic notifications across 5 sources admitted exactly 100 (`count`); a further notification while at capacity did not raise it; one `quickshell` process throughout, no crash |
| Clipboard | Plain-code copy via `offer code` landed on `wl-paste`; copied with `--sensitive` (confirmed by code path, `hasWlCopy: true`); untouched, it was cleared after the configured 60s `clipboardTimeout`; when the user overwrote the clipboard first, the 60s timeout left the user's text untouched |
| Default-action policy | `probe` showed `allowDefaultActionOnCardClick: false` at every check, including mid-flood and after restore |
| Local/named icons | `notify-send -i utilities-terminal` and `notify-send -i archlinux-logo` both delivered and survived a restart with no crash; **not visually confirmed** — no screenshot was taken (icon rendering is checked by the automated `test_review_p2_*` suite, not this pass) |

Not exercised in this pass, and explicitly left untested rather than faked:

- **KDE Connect**: no device paired and no `kdeconnectd`/`kdeconnect-cli` installed on this host. Reply, stale-target, ambiguous-target and failed-target behavior against a real phone remain untested; current coverage is the mocked-bus argv/logic tests only.
- **Remote-icon opt-in fetch**, an explicit sender action button's D-Bus `ActionInvoked` round trip, and pointer-driven card click / hover — no safe input injection was available, and toggling `fetchRemoteIcons` needs a config change not attempted this pass.
- **Failure-injection**: Bubblewrap missing, the icon/store helpers failing, or `wl-clipboard` absent were not reproduced live (would mean uninstalling working tooling from this machine); the fail-closed behavior for each is exercised in `tests/security.cjs`/`test_security.py` instead, not on this host.

## 2026-09-09 (third pass) — helper launchers are regular files, not symlinks

The live-session pass above found that `omarchy plugin validate` rejects a
plugin folder containing symlinks, and that `bin/omapager-run-icon`,
`bin/omapager-run-store` and `bin/omapager-run-kdeconnect` were committed as
symlinks to `bin/omapager-run-helper` (an argv0-dispatch trick: the helper
reads `Path(sys.argv[0]).name` to pick `icon`/`store`/`kdeconnect`). That
validator isn't invoked by `plugin add`/`enable` on an already-local folder,
which is how the previous pass installed it, but it blocks the documented
`omarchy plugin add <git-url>` distribution path for anyone else.

Fixed by replacing the three symlinks with regular executable Python files
that `os.execv()` into `omapager-run-helper <kind> ...`, passing argv through
unchanged — `bin/omapager-run-helper` (the sandbox/Bubblewrap implementation)
is untouched and still the only place that logic lives; the launchers already
matched an existing, previously-untested `kind == "helper"` dispatch branch
in `omapager-run-helper` designed for exactly this call shape.

| Check | Result |
| --- | --- |
| `git ls-files -s bin/omapager-run-{icon,store,kdeconnect,helper}` | All four now `100755` (`omapager-run-helper` was already a regular file; the other three changed from `120000` symlink mode) |
| `find . -type l -not -path './.git/*'` | Only under `.venv/` (this machine's own gitignored, untracked dev venv — not part of the plugin tree) |
| `node tests/baseline.cjs` / `security.cjs` | Pass |
| `python3 -m unittest discover -s tests -v` | 27 pass, none skipped |
| `python3 security/check_invariants.py` | Pass — now also asserts, via `git ls-files -s`, that no tracked path in the repository (the plugin folder a git-based install ships) is a symlink; verified this actually fails by reintroducing a symlink in a scratch tree and re-running the check before committing the fix |
| `python3 tests/sandbox.py` | Pass |
| `bin/omapager-run-helper status` | `{"bubblewrapAvailable": true, "sandboxOperational": true, "required": true, "unsandboxedFallback": false}` |
| `bin/omapager-run-icon --help` / `bin/omapager-run-store restore` / `bin/omapager-run-store quiet` / `bin/omapager-run-kdeconnect list` | Each launcher exercised end-to-end through the real Bubblewrap sandbox with a safe, read-only verb; all returned the same output the pre-fix symlinks did |
| `omarchy plugin validate <fresh checkout of this commit's tree>` | **Exit 0.** (Running it against the live working directory in place first failed — on `.venv/lib64`, this machine's own untracked venv, not this fix; a clean export of the exact tree passes) |
| `omarchy plugin add <local clone of this branch>` | See below |

Not touched, per scope: `bin/omapager_http.py public_hostname()`'s documented
hex-host follow-up, KDE Connect logic, and no new hardening features were
added — this is a packaging/compatibility fix only.

## 2026-09-06/07 — original hardening pass

| Check | Result |
| --- | --- |
| Frozen baseline and predecessor ancestry | Exact baseline commit; ancestor verified |
| `node tests/baseline.cjs` | Pass |
| `node tests/security.cjs` | Pass; hostile URLs/markup, bounds, OTPs, corpus and 1,000 deterministic generated cases |
| Python unittest suite with locked Pillow environment | 16 tests pass, none skipped |
| QtTest policy suite, Qt 6.11.2 | 4 passes including init/cleanup; 2 policy test functions |
| `python3 tests/http_server.py` | Pass against real synthetic loopback HTTP responses |
| `python3 tests/sandbox.py` | Pass outside nested agent sandbox: HOME/network denied, scoped writes work, OTP redacted |
| `bin/omapager-run-helper status` | Bubblewrap available and operational on host, fallback false |
| Static repository invariants | Pass |
| Semgrep 1.176.1 custom rules | 4 rules, 16 targets, zero findings; not a whole-program proof |
| OSV 2.3.8 | 67 locked development/test packages, no known issues returned by database |
| qmllint on four production QML files | Exit 0; unresolved Omarchy/Quickshell import/type warnings remain |
| `git diff --check` | Pass |
| Synthetic demo scene listing | Pass; listing only, no live scene injection |

The initial older Semgrep toolchain had a pkg_resources incompatibility and OSV
advisories in click/protobuf/setuptools. It was replaced, the environment synced,
and the complete lock re-audited. No vulnerability suppression was added.
OSV binary SHA-256 checked against its official release asset digest:
`bc98e15319ed0d515e3f9235287ba53cdc5535d576d24fd573978ecfe9ab92dc`.

## Reproduction

```bash
node tests/baseline.cjs
node tests/security.cjs
python3 -m unittest discover -s tests -v
python3 security/check_invariants.py
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_CONTROLS_STYLE=Basic \
  /usr/lib/qt6/bin/qmltestrunner -input tests/tst_security.qml
/usr/lib/qt6/bin/qmllint Service.qml Toast.qml Widget.qml DeedButton.qml
python3 tests/http_server.py
python3 tests/sandbox.py
# Upstream's real-TLS/real-HTTP transport integration suite alone:
python3 -B -m unittest discover -s tests -p 'test_icon_network.py' -v
```

The system Python suite explicitly skips the raster test if Pillow is absent.
For all 27 tests, use Python 3.12 and the hash-locked development environment:

```bash
python3.12 -m venv /tmp/omapager-tests
/tmp/omapager-tests/bin/pip install --require-hashes -r security/requirements.txt
/tmp/omapager-tests/bin/python -m unittest discover -s tests -v
SEMGREP_ENABLE_VERSION_CHECK=0 /tmp/omapager-tests/bin/semgrep scan \
  --config security/semgrep --error --metrics=off .
osv-scanner scan source -r .
```

HTTP test needs a temporary loopback socket. Sandbox test needs functioning
unprivileged user namespaces and Bubblewrap; nested container restrictions can
prevent it. Neither test edits the live desktop. The raster test exercises the
same decoder function in a temporary environment; Pillow is not installed into
the desktop's system Python by this patch.

## Still required before a release

- **Consenting real KDE Connect phone**: target identity, reply, failed/stale
  reply, cancellation and dismissal. No device or `kdeconnectd` was available
  on the host used for the 2026-09-09 live-session pass above. Current
  automated coverage mocks the bus and validates argv/logic only.
- ~~Plugin-folder symlinks~~ — **resolved**: the hardened helper aliases were
  converted from Git symlinks to regular executable launchers because current
  Omarchy validation rejects symlinks inside plugins. `omarchy plugin
  validate` now passes on the exact branch head; see "helper launchers are
  regular files, not symlinks" above.
- Remote-icon opt-in fetch, an explicit sender action button's D-Bus
  `ActionInvoked` round trip, pointer-driven card click/hover, and visual
  confirmation of icon rendering (no screenshot was taken) — not exercised in
  the live-session pass above; see that section for what was.
- Failure-injection (Bubblewrap missing, icon/store helper failure,
  `wl-clipboard` absent) — not reproduced on live hardware; covered instead by
  `tests/security.cjs`/`test_security.py`'s fail-closed unit coverage.
- Repository owner: fork/publication decision, private vulnerability reporting,
  secret scanning/push protection, required reviews and release signing identity.
- Optional independent audit, Scorecard CLI and GitHub Actions/zizmor review.

Hosted CI (Tests, CodeQL, Security scanners) is confirmed green on the current
head via `gh api repos/theaxlklo/omapager/commits/<head>/check-runs` — see the
PR description for the run links.

## Hosted draft checks

The first Ubuntu 24.04 hosted run passed JS, Python, HTTP and actual Qt policy
tests. Full-plugin qmllint then failed on unavailable Omarchy/Quickshell imports
(Qt's older linter treats those warnings as a failure). CI now uses qmlformat as
a non-mutating production syntax parser, while keeping actual Qt policy tests.
Full qmllint/type integration remains required on an Omarchy host. No blanket
continue-on-error or suppression of malformed QML was added.
