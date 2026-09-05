# Working on omapager

A notification daemon for Omarchy (Quickshell/QML + Hyprland). It replaces
`omarchy.notifications`, so that plugin must be in `disabledPlugins` or the two
fight over the `org.freedesktop.Notifications` bus name.

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
`omapager.panel expand`. Add a verb rather than reaching for a screenshot.

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

## Conventions

Comments say **why**, and especially why not the obvious thing — most of them
are a bug that took a while to find. Keep them when you move code; delete them
when they stop being true. No new runtime dependencies: Quickshell, Hyprland,
Python 3.

`wl-clipboard` is **not** an Omarchy dependency and may simply be absent, so
nothing may assume `wl-copy`. The copy buttons probe once at startup
(`service.hasWlCopy`, reported by `probe`) and fall back to Qt's own clipboard,
which loses `--sensitive` and nothing else — Omarchy's clipboard history is
`wl-paste --watch`, so it cannot be running either. A button that says "Copied"
and copied nothing is the outcome to rule out. KDE Connect is different: it is
the bridge that puts phone notifications on the bus at all, so without it that
half of the feature set has no input, not a degraded one.
