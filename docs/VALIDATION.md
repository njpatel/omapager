# Validation record

Local checks completed during this implementation (2026-09-06/07). Fixtures are
synthetic; no real notification history, OTP, private key or phone message was used.

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
```

The system Python suite explicitly skips the raster test if Pillow is absent.
For all 16 tests, use Python 3.12 and the hash-locked development environment:

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

- Disposable Omarchy session: render production deck, restore, DND, snooze,
  settings propagation, default-action buttons, clipboard expiry, failures and
  hot reload. qmllint with missing dynamic imports does not prove visual behavior.
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
