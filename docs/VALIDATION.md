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

- Re-run `qmllint`/`qmltestrunner` (Qt6 declarative tooling) and the Bubblewrap
  sandbox tests: this environment does not have that tooling installed, so the
  2026-09-09 pass validated the JS/Python/network layers but not these. Nothing
  in the six PR #4 fixes touched the sandbox wrappers; the QtTest policy suite
  covers `Security.js`/`Markup.js`/`Store.js`, and finding 4's fix (Security.js)
  is the one most worth re-confirming there.
- Disposable Omarchy session: render production deck, restore, DND, snooze,
  named/local icons, remote-icon opt-in, clipboard copy, OTP copy+expiry,
  default-action strict behavior, browser/source navigation, notification
  flood behavior, restart/failure behavior, settings propagation,
  default-action buttons, clipboard expiry, failures and hot reload. qmllint
  with missing dynamic imports does not prove visual behavior, and none of
  this was exercised in this pass.
- Consenting real KDE Connect phone: target identity, reply, failed/stale reply,
  cancellation and dismissal. Current tests mock the bus and validate argv/logic.
- CI run on the actual maintained GitHub repository. CodeQL is configured for
  JavaScript/Python/Actions but was not run locally. It does not model QML natively;
  the custom broker/static checks and actual Qt policy tests cover that gap only
  partially. No hosted runner execution is claimed here.
- Repository owner: fork/publication decision, private vulnerability reporting,
  secret scanning/push protection, required reviews and release signing identity.
- Optional independent audit, Scorecard CLI and GitHub Actions/zizmor review.

## Hosted draft checks

The first Ubuntu 24.04 hosted run passed JS, Python, HTTP and actual Qt policy
tests. Full-plugin qmllint then failed on unavailable Omarchy/Quickshell imports
(Qt's older linter treats those warnings as a failure). CI now uses qmlformat as
a non-mutating production syntax parser, while keeping actual Qt policy tests.
Full qmllint/type integration remains required on an Omarchy host. No blanket
continue-on-error or suppression of malformed QML was added.
