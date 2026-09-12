> **Unreleased hardening branch:** based on upstream commit
> `29548e5761f1b9f419afe988d77f67e3dd3e81cb`. See
> [upstream handoff](docs/UPSTREAM_HANDOFF.md) for the implementation and review
> notes. Bubblewrap is required for helpers; remote icons and implicit sender
> default actions are off by default. History defaults to 24 hours/100 entries,
> and detected-code notifications are stored as redacted placeholders.
> This branch is a draft review proposal and has not passed live integration testing.
> The original feature documentation below describes the upstream UX; the
> [security architecture](docs/SECURITY_ARCHITECTURE.md) overrides conflicting
> security/default-behavior statements. Use reviewed commits for installation,
> and complete disposable-session integration checks before enabling this branch.

<img src="assets/title.png" width="1266" alt="Omapager">

<!--
 ▄█████▄    ▄███████████▄   ▄███████   ▄███████▄  ▄███████    ▄█████▄   ▄████████  ▄███████▄
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███        ███   ███  ███   ███
███   ███  ███   ███   ███  ███▄▄▄███  ███▄▄▄███  ███▄▄▄███  ███ ▄▄▄▄▄  ███▄▄▄     ███▄▄▄██▀
███   ███  ███   ███   ███  ███▀▀▀███  ███▀▀▀▀▀▀  ███▀▀▀███  ███ ▀▀███  ███▀▀▀     ███▀▀▀██▄
███   ███  ███   ███   ███  ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀   ███   █▀    ▀█        ███   █▀    ▀█████▀    ▀███████   ███   █▀
-->

A notification daemon for [Omarchy](https://omarchy.org). It replaces the
built-in notification service with a stacking deck that groups by source,
reads what a notification is actually offering you, and lets you act on it
without leaving the card.

<img src="assets/deck.gif" width="440" alt="Notifications landing and stacking in the corner of the screen">

## What it does

**Stacks and groups.** Notifications from the same source collect into one
deck. Hovering expands it. Nothing is hidden behind a "3 more" summary —
every notification is a real card you can act on.

A body is held to two lines while you are scanning a deck, and opens to its
full length — up to eight lines — once the deck is expanded, or on hover when
it is the only card on screen. Phone messages are why: a sentence and a half
arriving as a sentence and an ellipsis is the commonest way to lose the point
of a message.

**Reads the contents.** A verification code, a link or a phone number in the
body becomes a labelled button: `Copy code`, `Open link`, `Copy number`. A mark
on the headline tells you a card is
carrying something before you hover, because the useful part of a message is
usually past the ellipsis.

<img src="assets/actions.png" width="369" alt="A card showing a Copy code button">

A message carrying two codes gets a button each, labelled with the digits,
because "Copy code" twice is a coin toss. Detection is deliberately
conservative: `412 passed, 0 failed` is not a code, and neither is
`Claude Code build 1841`.

**Shows the sender's own actions.** The freedesktop spec has carried actions
all along; most desktops draw none of them. Reply, Mark as read, whatever the
app offered, appear as buttons on hover.

**Replies to your phone.** Phone notifications reach the desktop through KDE
Connect, and the ones carrying a reply channel grow a text field on the card.
The answer goes back to the conversation, and the notification is dismissed on
the phone too. Nothing new lands and nothing expires while you are typing, so
the field cannot move out from under you mid-sentence.

<img src="assets/reply.png" width="369" alt="Typing a reply into a notification">

**Sends you back where it came from.** Clicking a card focuses the window that
source is already showing in — a Slack notification lands in the Chrome you
already have Slack open in, rather than a new tab — and opens something new
only when there is nothing to go back to. It can only see the tab a browser is
actually showing, so a site sitting in a background tab opens fresh.

**Quietens one source at a time.** Right-click a card and pick how long. It is
the *source* that goes quiet, not the app that relayed it: snoozing a Slack
notification that arrived through Chrome silences `app.slack.com` and nothing
else, and snoozing a noisy shopping app on your phone leaves WhatsApp alone.
Snoozed notifications are still recorded — they go to history without ever
being on screen.

The panel does the same for everything at once. Both offer the lengths in
`snoozeDurations`, which are yours to change.

**Lets the code through anyway.** A snooze or a silence holds everything back
except a notification carrying a verification code. You asked for that code
thirty seconds ago and it expires in five minutes — and being locked out of a
login because you had quietened Slack is exactly the failure that makes people
stop snoozing anything. The key beside the panel's snooze button closes the
hole for the times you want nothing at all. Copying a code dismisses its
notification; there is nothing left in it afterwards.

**Shows you what quiet cost.** Silence is only tolerable if you can see what it
kept from you. While anything is being held back, the panel lists the sources
that caught something and opens each one to show what it caught, newest first —
capped at both ends, so a fortnight of silence doesn't turn a panel into a log
file.

**Keeps the notification you just missed.** The panel's Recent stack shows the
newest notifications even while notifications are enabled, after their toasts
expire or are dismissed. Right-click the bar indicator to read them; hover the
centre of the bar to reveal it when nothing is held back. Cards show the source,
arrival time, title and a two-line text preview, with no actions or replay.
Recent starts collapsed, showing only its count. Click the heading or chevron to
reveal the cards; closing and reopening the panel collapses it again. New
notifications update the count without opening the list.

`recentCount` chooses how many cards to show: **1–20, default 5**. The latest 20
text snapshots stay in memory for this shell session only, and replacing a live
notification updates its entry rather than duplicating it. Restarting the shell
clears Recent; it does not load or alter the existing disk history. Verification
notifications use the same redacted placeholder as history, not the code.

Recent is hidden while everything is snoozed or silenced. Snoozed sources are
excluded before applying the card limit, so other sources can still fill it.
Notifications received during a snooze or silence belong only in Held Back;
they do not populate Recent when quiet ends. A source's earlier recent entries
are hidden while it is snoozed and become eligible again when it wakes.

<img src="assets/quiet.png" width="404" alt="The bar indicator and the panel behind it">

**Resolves real icons.** Your own icon themes win; web notifications fall back
to the site's own icon, in dark and light variants to suit the theme.

## Install

```bash
git clone https://github.com/njpatel/omapager.git \
  ~/.config/omarchy/plugins/njpatel.omapager
```

Then in `~/.config/omarchy/shell.json`, turn off the built-in service, add the
plugin, and put the indicator in the bar beside the other status glyphs, since
it behaves like one:

```json
{
  "disabledPlugins": ["omarchy.notifications"],
  "plugins": [{ "id": "njpatel.omapager" }],
  "bar": { "layout": { "center": ["omarchy.indicators", "njpatel.omapager", "omarchy.clock"] } }
}
```

`omarchy-restart-shell` to pick it up. (Not `omarchy-refresh-shell` — that
resets `shell.json` to defaults.)

### Removing it

```bash
omarchy plugin remove njpatel.omapager
```

Then undo the three lines above: take `omarchy.notifications` back out of
`disabledPlugins` so the built-in service can claim the bus again, and drop
`njpatel.omapager` from the bar layout. `omarchy-restart-shell` to apply.

State is left behind on purpose, in case you are only reinstalling —
`rm -rf ~/.local/state/omarchy/omapager` clears the history and the resolved
icons for good.

## Settings

Open the notification panel and click the cog for preferences. In the native
**Show notifications on** dropdown, **Active display** places a fresh deck on
Hyprland's focused monitor. A visible deck stays put when focus moves.
**Only DP-1**, for example, pins notifications to that output; disconnected selections are
retained, with a connected-display fallback until the output returns.
**All displays** shows the same deck everywhere. Dismissal and snoozing remain shared.

The dropdown, switch, header and separator reuse Omarchy's UI components. Font,
spacing, borders and switch rounding follow the theme. Use arrows or `j`/`k` in
the dropdown, Enter to choose and Escape to close the menu.

The preferences and configuration use the same bar-widget entry; changes made
in the view persist across shell restarts. No separate settings file is created.

| key | default | what it does |
| --- | --- | --- |
| `stacking` | `source` | `source` gives each sender its own deck; `all` puts everything in one |
| `displayMode` | `active` | `active` follows focus for each fresh deck; `specific` uses `displayName`; `all` mirrors notifications |
| `displayName` | empty | output name for `specific`, such as `DP-1`; retained while disconnected |
| `offerSnoozeWhenSharing` | `true` | offer a timed snooze when a Hyprland portal sharing session is detected; never mute automatically |
| `fontScale` | `100` | notification font size as a percentage of the theme (75–200); scales card text, actions and inline replies, leaving the bar and panel unchanged |
| `actionsAlign` | `right` | which end of a card its buttons sit at |
| `hideSettingsAction` | `true` | drop the browser's "Settings" button, which is on every web notification and is never the one you wanted |
| `snoozeDurations` | `30, 60, 240, tomorrow` | what the snooze menus offer — minutes, or `tomorrow` |
| `wakeHour` | `8` | the hour "until tomorrow" wakes a source at |
| `smartRaise` | `true` | match a site against browser window titles, so a click lands in the window already showing it |
| `alwaysShow` | `false` | keep the bar slot even when nothing is held back, so the centre of the bar never shifts |
| `codesBypassQuiet` | `true` | let a notification carrying a verification code through a snooze or a silence |
| `timeFormat` | `system` | `system` follows `LC_TIME`; `24h` and `12h` pin it |
| `sourceLimit` | `8` | how many quietened sources the panel lists |
| `heldPerSource` | `10` | how many held notifications it shows per source |
| `recentCount` | `5` | recent notifications shown in the panel (1–20), including when notifications are enabled; resets on shell restart |

Notification text at 100% and 150% of the theme size:

| 100% (default) | 150% |
| --- | --- |
| ![Sample notification at 100%](assets/font-scale-100.png) | ![Sample notification at 150%](assets/font-scale-150.png) |

Long titles wrap, and actions that do not fit move behind **More**. At 200%:

| Action row | More expanded |
| --- | --- |
| ![Actions at 200%](assets/font-scale-200.png) | ![All actions at 200%](assets/font-scale-200-more.png) |

Long action labels wrap inside the expanded list, with the button growing to
fit the full text:

![Wrapped action label at 200%](assets/font-scale-200-long.png)

Every history entry is the text of a message somebody sent you, so it is
trimmed by age as well as count: **7 days or 200 entries**, whichever comes
first. Resolved icons are dropped after 60 days unused, and nothing is ever
written to the system log.

Settings live on the bar widget's entry in `shell.json`, all in one place
next to `id`:

```json
{ "id": "njpatel.omapager", "snoozeDurations": ["60", "480"], "wakeHour": 9 }
```

### Sharing offers

When the Hyprland screen-sharing portal creates a screen, window or area stream,
the bar shows a sharing indicator. Click it to choose **30 minutes**, **1 hour**,
**4 hours**, or **Not now**. No notification toast or panel opens automatically,
and notifications continue until you choose a snooze. The ordinary snooze rules
still apply, including critical alerts and the configured verification-code exception.

An offer is handled once until all detected streams end. Additional simultaneous
streams do not repeat it. If DND or a global snooze is already active, no offer is
shown for that sharing period. A chosen snooze keeps its timer regardless of when
sharing ends: it can outlast a short share or expire during a long one.

Detection reads current PipeWire video-node metadata, including streams already
present at shell startup. It recognises the Hyprland portal's `xdph-streaming-`
media names, not arbitrary video sources or compositor capture events. Direct
VNC captures, screenshots and applications that bypass that portal do not trigger
it; portal-based recording can. This is a convenience, not a privacy guarantee.
Only 64 video-source nodes are tracked. Dismissal is in memory, so restarting the
shell during a share can offer again. Disable the offer in settings or set
`offerSnoozeWhenSharing` to `false` in the same widget config entry.

## The bar

omapager takes a slot in the bar while notifications are held back or a sharing
offer is waiting. Hovering the centre of the bar reveals it otherwise, the way
Omarchy reveals its own inactive indicators — that is the way back into silence
when nothing is showing.

| | |
| --- | --- |
| crossed-out bell, in the theme's urgent colour | silenced |
| bell with a `z` in it, in amber | snoozed — everything, or a source |
| monitor-share icon, in amber | sharing detected; click for a snooze offer, without toggling DND |
| crossed-out bell, dimmed | nothing held back |

Same crossed-out bell as Omarchy's own indicator, so a silenced desktop looks
the same whichever service is running. Amber rather than red for a snooze,
because a snooze ends by itself.

**Left-click** silences and unsilences. **Right-click** opens the panel: the
switch, a button beside it that snoozes everything for a while, the Recent
stack, and what is being kept from you — when each source comes back, how much
it has caught, and the messages themselves when you open one.

## Keybindings

Omarchy's five stock bindings on the comma key keep working unchanged.
omapager answers the same IPC target the built-in service did, so there is
nothing to rebind and nothing to configure:

| | |
| --- | --- |
| `SUPER` `,` | dismiss the newest notification |
| `SUPER` `SHIFT` `,` | dismiss all of them |
| `SUPER` `CTRL` `,` | toggle silencing |
| `SUPER` `ALT` `,` | invoke the newest one, as clicking it would |
| `SUPER` `SHIFT` `ALT` `,` | put the last few back on screen |

### Worth adding

Three things the stock bindings have no key for. All three are free on a stock
install — check yours with `omarchy menu keybindings --print`, and `hl.unbind`
first if you have moved things around.

In `~/.config/hypr/bindings.lua`:

```lua
-- Copy a code without touching the mouse. The notification takes itself away.
o.bind("SUPER + ALT + C", "Copy code from newest notification",
       "omarchy-shell omapager offer code")

-- Next to SUPER + CTRL + comma, which silences. Quiet for an hour, rather
-- than quiet until you remember you turned it off.
o.bind("SUPER + CTRL + ALT + comma", "Snooze all notifications for an hour",
       "omarchy-shell omapager snoozeAll 60")

-- What is snoozed, what it has held, and the way back. Worth a key: the bar
-- icon is not there at all when nothing is being held back.
o.bind("SUPER + CTRL + SHIFT + comma", "Notification options",
       "omarchy-shell omapager.panel toggle")
```

## Driving it from a script

```
omarchy-shell omapager count            how many are on screen
omarchy-shell omapager clear            dismiss them
omarchy-shell omapager dnd              toggle Do Not Disturb
omarchy-shell omapager expand           open the deck, as hovering would
omarchy-shell omapager offer code       take the front card's offer (code|link|phone)
omarchy-shell omapager act reply        invoke one of the sender's actions
omarchy-shell omapager reply "text"     answer the front card ("" opens the field)
omarchy-shell omapager snooze 60        quieten the front card's source, in minutes
omarchy-shell omapager snoozeAll 60     quieten everything for 60 minutes, or wake it
omarchy-shell omapager codes off        stop letting verification codes through
omarchy-shell omapager unsnooze ""      wake everything ("" for all, or a source key)
omarchy-shell omapager snoozes          what is snoozed, and until when
omarchy-shell omapager stack source     switch stacking mode
omarchy-shell omapager align right      switch which end the buttons sit at
omarchy-shell omapager probe            what the daemon believes, as JSON

omarchy-shell omapager.panel toggle     the panel
omarchy-shell omapager.panel expand x   open a source's held list, as clicking it would
omarchy-shell omapager.panel openSettings  display and sharing-offer settings
```

## Seeing it work

```bash
bin/omapager-demo                       # the everyday scenes
bin/omapager-demo --scene interactive   # codes, links, and the sender's buttons
bin/omapager-demo --scene routing       # where a click sends you, per source
bin/omapager-demo --scene reply         # inline reply, against a stand-in phone
bin/omapager-demo --replay 40           # your own notifications, re-sent
bin/omapager-demo --list
```

`--scene routing` reads your open windows and prints what each card *should*
do before it sends anything, so you can check it against what happens.
`--scene reply` writes a fixture the daemon treats as a repliable notification
and logs the reply to a file rather than sending it to a person.

## Requirements

Omarchy (Quickshell 0.3.x, Hyprland), and Python 3 for the helpers in `bin/`.

Two more things are worth having, and they are not the same kind of thing.

**`wl-clipboard` — recommended.** Not an Omarchy dependency, so check before you
assume it: `command -v wl-copy`. The copy buttons work either way, but with it a
copied verification code is marked sensitive and Omarchy's clipboard history
skips it. Either way the code is cleared again 90 seconds later, unless you have
copied something else since — that stays.

**KDE Connect — the whole phone half.** Without it there are no phone
notifications at all: it is the bridge that puts them on the bus in the first
place, so the reply field, `Mark as read` and the grouping by the app a message
really came from all go with it.

```bash
sudo pacman -S wl-clipboard kdeconnect   # kdeconnect also needs the phone app
```

## Contributing

See [how we review contributions](docs/DEVELOPING.md#how-we-review-contributions)
and the [development guide](docs/DEVELOPING.md) for working on omapager.

## Licence

Apache-2.0.
