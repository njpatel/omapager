# Working on omapager

> Not called `AGENTS.md`, and not at the repository root, on purpose. Omarchy
> installs a plugin's whole tree into `~/.config/omarchy/plugins/`, so a root
> agent-instruction file would become ambient context for any coding agent the
> *installing user* happens to run — instructions they never chose to load.
> Marketplace review raised it; this is the fix. If you keep a `CLAUDE.md`
> symlink to this file locally, leave it untracked.

A notification daemon for Omarchy (Quickshell/QML + Hyprland). It replaces
`omarchy.notifications`, so that plugin must be in `disabledPlugins` or the two
fight over the `org.freedesktop.Notifications` bus name.

## How we review contributions

We review the idea first: does it fit the project, and does it solve a useful problem?

If it does, we prefer helping it land over sending you through repeated rounds of small adjustments. We’ll offer directly applicable suggestions where useful. For remaining maintainer preferences, we may prepare and verify a follow-up fix, merge your contribution, then land our adjustments immediately afterwards. Your contribution keeps its GitHub authorship and credit; our follow-up changes are ours.

Further review rounds are appropriate when the idea fits but the implementation still has substantial correctness, security or design problems. We may also offer to finish the agreed changes on your PR branch, with your consent and without rewriting your commits.

We won’t knowingly merge a broken or unsafe intermediate version. Required checks and release or verification gates still apply. If a contribution doesn’t fit the project, we’ll explain that and close it rather than leave it waiting indefinitely.

## Layout

| | |
| --- | --- |
| `Service.qml` | the daemon: owns the bus, the model, snooze/silence state, routing, the surface |
| `Toast.qml` | one card, in every state it has |
| `Widget.qml` | the bar indicator and its panel; **also where settings live** |
| `DeedButton.qml` | one action on a card |
| `Layout.js` | pure: rows in, placements out. No compositor needed to reason about it |
| `Detect.js` `Markup.js` `Store.js` | pure: what a body is offering, what is safe to render, what to keep |
| `bin/omapager-*` | Python helpers: store, icon resolution, KDE Connect bridge, demo |

Settings only reach a **bar widget**, never a service — so `Widget.applySettings()`
reads `shell.json` and pushes values onto the daemon. That is the only path.

## Running and testing

```bash
qmllint Service.qml            # CHECK THE EXIT CODE. Its stderr is easy to lose
                               # in a pipeline and a syntax error looks like silence
omarchy-restart-shell          # reload
omarchy-shell omapager probe   # what the daemon believes, as JSON
bin/omapager-demo --list       # scenes; --scene routing prints its predictions first
```

**Hot reload does not recreate `Variants` windows.** Edit `Toast.qml`, the
surface, or `Widget.qml` and you must restart the shell — otherwise you are
looking at the old surface and will chase a bug that is not there. Touching any
file in this directory also triggers a reload, which briefly makes IPC answer
"target not found"; that is not a crash.

**Never run `omarchy-refresh-shell`** — it resets `shell.json` to defaults.

Restart with `omarchy-restart-shell`, and let it finish. Killing and relaunching
by hand races: a second instance starting while the first is still coming up
dies on the socket, and Quickshell writes a crash report and refuses to retry
("crashed within 10 seconds of launching"). Count instances with `pgrep -xc
quickshell` — `pgrep -f` matches the shell command you are running it from and
will tell you there are two when there are none.

Almost everything is drivable without a pointer, which is how it gets tested:
`expand`, `offer`, `act`, `reply`, `snooze`, `snoozeAll`, `codes`,
`omapager.panel expand`, `omapager.panel line`. Add a verb rather than reaching
for a screenshot.

Reading the panel by eye is the expensive case: an open panel owns the
keyboard, so a person at the machine types into it. `omapager.panel line`
reports the line under the title and which phrase set it is drawing from, which
is most of what you would have opened it to see.

Screenshots are a last resort: the panel dismisses on **any** click, so a user
at the keyboard will close it under you, and a wide crop catches their desktop.
Crop to the card and check a corner pixel is the card's own colour.

## Things that cost a day to learn

**Qt/QML**

- `function f(): void` is rejected by this Qt's QML grammar. Use `: string`.
- `Qt.formatTime(d, Locale.ShortFormat)` takes its second argument as a *format
  string*, makes nothing of the enum and falls back to a full clock with
  seconds. Use `d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)`.
- A `ListModel` fixes its roles from the first row and silently drops keys that
  row lacked. Every row goes through `Store.normalise`. No nested arrays in
  roles either — that is why `codes` is a space-joined string.
- Live `Notification` objects must never go in the model: the server destroys
  them and the next read is a dangling pointer inside `QQmlListModel::data`,
  which takes the shell down. They live in the `refs` map.
- `Text.linkColor` is ignored for `RichText`; the colour has to be in the
  markup (`Markup.colourLinks`). And `lineCount` counts *paragraphs*, so
  overflow is measured from `contentHeight`.
- `MultiEffect` re-renders its whole blurred source on every repaint of the
  item it is attached to. Shadows go on a childless plate, never on a card with
  a countdown ticking in it.
- Iterate a **snapshot of keys** when closing many cards. `closeToast` marks a
  row leaving and removes it 200ms later, so `while (count > 0)` never makes
  progress and spins the main thread at 100% with no error and no log.
- **Nothing a card's `visible` reads may come from the layout.** Toggling
  `visible` changes what the card contributes, the layout is measured back into
  `heights`, and `heights` is where the scene gets opacity from — a closed
  circle. `visible: opacity > 0.01` cost ~120 binding-loop warnings per scene
  and the re-evaluation behind them; deriving it from `place.hidden` only moved
  the loop, because `place` is layout output too. It is now bound to nothing,
  and `enabled` refuses the pointer instead. A fully transparent subtree is
  skipped by the scene graph, so nothing is drawn either way.
- An **id is file-scoped, not a property**. `toasts` is the `ListModel`'s id;
  `service.toasts` is `undefined` and throws a TypeError per evaluation. Inside
  the delegate, write `toasts.count`.
- Bindings here **span lines**. `expanded:` is two lines, and a patch anchored
  on the first line inserted itself into the middle of it: `expanded` silently
  lost its second half and the orphaned `&&` was grafted onto the new property
  below. Anchor on something that includes the whole binding, and read the
  journal afterwards — both of those sat there as warnings for a morning.

**Omarchy**

- `KeyboardPanel` dismisses by calling `close()` on its `owner`, and otherwise
  writes its own `open` property — which breaks your binding and leaves the
  panel stuck shut. A bar widget acting as its own panel must expose
  `open()` / `close()` / `toggle()`.
- An open panel holds the keyboard **exclusively**, so anything typed at
  another window lands on it. Keyboard shortcuts there may navigate; they must
  never change state. (A stray `s` used to silence the desktop.)
- `PanelHero` anchors its labels to the right edge of whatever its icon loader
  turns out to be, so an icon that changes glyph must sit in a fixed-size Item
  or the title jumps.
- Panels are `Style.space(380)` wide unless they have a calendar in them.
- Status glyphs are `Style.font.caption` in a `Style.bar.statusSlot`; bar
  *widgets* are bigger. Compare against the other indicators, not the widgets
  next to them.
- Never edit `/usr/share/omarchy/` — package-owned, overwritten on update.
  Reading it is the best documentation there is.

**Hyprland**

- Dispatch arguments are evaluated as **Lua** here: `hyprctl dispatch
  focuswindow ...` fails. Focus with
  `hl.dsp.focus({window = hl.get_window("address:0x...")})`.
- Focus by **address**, not class: two windows can share a class (two browser
  profiles both called `chrome-work`) and only one is showing the thing that
  notified you.
- Use `Hyprland.toplevels`, not `Hyprland.clients`.
- A window title is the **active tab**. Matching a site against browser titles
  finds it only while it is the tab in front; there is no way to see the rest.

**This desktop's senders**

- KDE Connect is a multiplexer: everything from the phone arrives as one app,
  with the app it really came from in the summary and `Sender: message` in the
  body. Group and snooze on that summary, or "snooze this" means "snooze the
  phone". It also sends raw pixels as an `image://qsimage/...` handle that dies
  with the shell, so an icon is resolved alongside it and kept in reserve.
- Chrome announces every web app as "Google Chrome" and glues an anchor to its
  own origin onto the front of the body. That anchor is the only thing telling
  its sites apart, which is what `Markup.liftSource` is for.

## IPC targets

| | |
| --- | --- |
| `omapager` | the daemon |
| `omapager.panel` | the panel |
| `notifications` | **Omarchy's own**, answered here so the five stock `SUPER + ,` keybindings keep working when the built-in service is disabled. Names and return values are the built-in service's, not ours — do not rename them |

## State

`~/.local/state/omarchy/omapager/` — `live/` (what is on screen, for restoring
across a restart), `history/` (one file per notification), `icons/` (resolved
per source), `quiet.json` (snoozes + silencing). It is state, not cache: it
survives `rm -rf ~/.cache`.

Every history entry is the text of a message somebody sent, so it is trimmed by
**age as well as count** — 7 days or 200 entries, whichever bites first, on
every close. Icons are pruned at 60 days by `tidy`, which the daemon runs at
startup. Nothing is written to the journal: no `console.log` anywhere, and the
Python helpers speak on stdout, which is the IPC channel.

## Security boundaries in this branch

Read SECURITY.md and docs/SECURITY_ARCHITECTURE.md before editing capability
paths. Security.js is the only URL-opening broker. Never add direct desktop
opens elsewhere, raw helper launches, command shells, or automatic URL/action
side effects. Notification labels are plain text; only sanitized body markup is
RichText. Store.sanitiseForPersistence and the Python store independently redact
code-bearing notifications. Do not remove either boundary.

The panel's Recent stack is session-only, not another persistence path.
`Service.rememberRecent()` keeps at most 20 bounded text snapshots after
notification admission, excluding arrivals during global quiet or a source
snooze. It uses `Store.sanitiseForPersistence()` so verification codes do not
outlive their toast here either. Never retain Notification objects, images or
actions in this stack. A source digest supports snooze matching without keeping
its unredacted label. Replacements update by the existing live key; expiry and
dismissal leave the snapshot readable. `recentForPanel()` filters currently
snoozed sources before the widget's 1–20 card limit; global quiet hides the whole
Recent block. Snooze revisions refresh that filter on snooze, wake and expiry.
Shell restart clears the stack.

`node tests/security.cjs` covers recent ordering/eviction, expiry, replacement,
redaction and snooze filtering through the production notification lifecycle.
For visual proof, use a private omalab bus: send short-lived notifications from
two sources, snooze one and verify only the other remains in Recent. Snooze
everything and verify the whole Recent block disappears. Wake the sources and
verify held arrivals did not enter Recent while earlier entries become eligible.

- **`bin/omapager-icon` fetches, through `bin/omapager_http.py`.** This is the
  single network-security implementation for icon fetching; there is no second,
  competing HTTP client. `parse_url()` requires `http(s)`, a public-looking
  hostname, no userinfo and the scheme's default port only, and rejects control
  characters and percent-encoded control bytes that could confuse the request
  line or inject headers. `resolve_public_host()` resolves once and rejects the
  whole DNS answer if any address is non-global, reserved, multicast, or an
  IPv6-mapped IPv4 address (a documented `ipaddress.is_global` gap upstream's
  own transport does not check). `PinnedHTTPConnection.connect()` then connects
  directly to that checked sockaddr — never re-resolving — while still using
  the URL hostname for the HTTP `Host` header, TLS SNI, and normal certificate
  hostname verification. `fetch()` re-validates every redirect target the same
  way, caps hops at `MAX_REDIRECTS`, and rejects control characters in the
  `Location` header. `fetch_once()` enforces a byte limit (`Content-Length`
  pre-check plus an incremental read that never exceeds it), a response
  deadline, and `identity`-only `Content-Encoding`. `http.client` is used
  directly rather than `urllib.request`, so there is no opener to route through
  an environment proxy in the first place. Without these checks a site you
  allowed notifications from could read `file:///etc/passwd`, aim a GET at
  `127.0.0.1`, or hold the connection open past a reasonable budget.
  `host_names()` gates the first hop the same way: a source is a plain dotted
  hostname or it is nothing, so no ports, userinfo or paths.
- **`Markup.js` renders.** Everything is escaped, then a fixed tag list is put
  back — no `img`, so a body cannot pull a remote image. An anchor survives only
  if `linkable()` vouches for its scheme; `Toast.onLinkActivated` asks again
  before `Qt.openUrlExternally`. The label is the sender's too, so a `file://`
  href is free to read like an ordinary web link.

Adding anything that fetches, opens, or writes a path from notification text
means extending one of these, not working around it.

Use the `bin/omapager-run-*` wrappers: Bubblewrap is required, with no
unsandboxed fallback. Remote icons are off by default, use the pinned
transport above, and require sandboxed Pillow raster decoding. Tests use
synthetic data only. Run `node tests/baseline.cjs`, `node tests/security.cjs`,
Python unittest discovery, Qt policy tests and `security/check_invariants.py`
after changes. See `docs/VALIDATION.md` for exact commands and integration
limits.

The transport regression uses synthetic DNS and a test-owned loopback server
for real HTTP, redirects and TLS; it never contacts an external or existing
local service. It needs Python 3 and `openssl` (test certificate generation):

```sh
python3 -B -m unittest discover -s tests -p test_icon_network.py -v
```

## Conventions

Comments say **why**, and especially why not the obvious thing — most of them
are a bug that took a while to find. Keep them when you move code; delete them
when they stop being true. Runtime dependencies: Quickshell, Hyprland, Python 3 and Bubblewrap.
Pillow is optional for local icons and required for opted-in remote icons.
Additional dependencies require an explicit security/compatibility review.

`wl-clipboard` is **not** an Omarchy dependency and may simply be absent, so
nothing may assume `wl-copy`. The copy buttons probe once at startup
(`service.hasWlCopy`, reported by `probe`) and fall back to Qt's own clipboard,
which loses `--sensitive` and nothing else — Omarchy's clipboard history is
`wl-paste --watch`, so it cannot be running either. A button that says "Copied"
and copied nothing is the outcome to rule out. KDE Connect is different: it is
the bridge that puts phone notifications on the bus at all, so without it that
half of the feature set has no input, not a degraded one.

## Font layout regression check

Run `tests/font-layout.sh` on an Omarchy installation. It renders the actual
Toast and DeedButton components offscreen without starting a notification
daemon. Three explicit typography profiles (12px monospace, 14px monospace and
12px proportional) each run 77 cases, including:

- Every 5% font-scale step from 75–200%, with both action alignments.
- Opening More, checking labels and buttons against every clipping ancestor,
  and activating Reply or a wrapped action.
- Long labels, unbroken strings, RTL text and literal markup; changing font
  size and replacing actions while the list is open.
- A short title that should remain on one line, and a wrapping fixture that
  is extended until its measured text exceeds the available width.

The long-label cases reach the expanded list, not just the More-only row.
Set `OMARCHY_SHELL_DIR` if the shell is installed somewhere other than
`/usr/share/omarchy/shell`.
