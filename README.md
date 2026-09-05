# omapager

A notification daemon for [Omarchy](https://omarchy.org). It replaces the
built-in notification service with a stacking deck that groups by source,
reads what a notification is actually offering you, and lets you act on it
without leaving the card.

![Notifications stacking in the corner of the screen](assets/deck.png)

## What it does

**Stacks and groups.** Notifications from the same source collect into one
deck. Hovering expands it. Nothing is hidden behind a "3 more" summary —
every notification is a real card you can act on.

**Reads the contents.** A verification code, a link, a phone number or a file
path in the body becomes a labelled button: `Copy code`, `Open link`,
`Copy number`, `Open file`. A mark on the headline tells you a card is
carrying something before you hover, because the useful part of a message is
usually past the ellipsis.

![A card showing a Copy code button](assets/actions.png)

Detection is deliberately conservative — a rule that fires wrongly is worse
than one that doesn't fire. A code needs a keyword (*code*, *OTP*,
*verification*, *passcode*, *2FA*) **near** a plausible shape, so
`412 passed, 0 failed` stays silent, and so does `Claude Code build 1841`,
where the word is half a product name.

**Shows the sender's own actions.** The freedesktop spec has carried actions
all along; most desktops draw none of them. Reply, Mark as read, whatever the
app offered, appear as buttons on hover.

**Replies to your phone.** KDE Connect keeps a reply channel for the
notifications that have one. When it does, the card grows a text field and the
answer goes back to the conversation on the device. Escape puts the buttons
back; while you are typing, nothing new lands on the deck and nothing already
on it expires, so the field cannot move out from under you mid-sentence.

![Typing a reply into a notification](assets/reply.png)

**Sends you back where it came from.** Clicking a card runs the sender's
default action; failing that it focuses the window that source is already
showing in, and only opens something new if there's nothing to go back to.
Omarchy's web apps carry their host in their Hyprland class, so those match
outright; a site open as a tab in an ordinary browser doesn't, so the brand is
matched against browser window titles instead — a Slack notification lands in
the Chrome that's already showing Slack rather than in a new tab.

**Quietens one source at a time.** Right-click a card for half an hour, an
hour, or until tomorrow morning. It is the *source* that goes quiet, not the
app that relayed it — so snoozing a Slack notification that arrived through
Chrome silences `app.slack.com`, not every website you have open. Snoozed
notifications are still recorded; they go to history without ever being on
screen.

![The bar indicator and the panel behind it](assets/quiet.png)

**Resolves real icons.** Local icon themes first, so your own overrides win,
then the site's own icon for web notifications, with dark and light variants.
A one-colour glyph is redrawn in the theme's text colour so it doesn't
disappear into a dark card.

## Install

```bash
git clone https://github.com/njpatel/omapager.git \
  ~/.config/omarchy/plugins/njpatel.omapager
```

Then in `~/.config/omarchy/shell.json`, turn off the built-in service, add the
plugin, and put the indicator in the bar — beside the other status glyphs in
the centre is where it belongs, since it behaves like one:

```json
{
  "disabledPlugins": ["omarchy.notifications"],
  "plugins": [{ "id": "njpatel.omapager" }],
  "bar": { "layout": { "center": ["omarchy.indicators", "njpatel.omapager", "omarchy.clock"] } }
}
```

`omarchy-restart-shell` to pick it up. (Not `omarchy-refresh-shell` — that
resets `shell.json` to defaults.)

## Settings

| key | default | what it does |
| --- | --- | --- |
| `stacking` | `source` | `source` gives each sender its own deck; `all` puts everything in one |
| `actionsAlign` | `right` | which end of a card its buttons sit at |
| `hideSettingsAction` | `true` | drop the browser's "Settings" button, which is on every web notification and is never the one you wanted |

## The bar

omapager takes a slot in the bar only while it is keeping something from you:
a crossed-out bell when the desktop is silenced, a `zᶻᶻ` when a source is
snoozed, and nothing at all the rest of the time. Hovering the centre of the
bar reveals it the way it reveals Omarchy's own inactive indicators — that's
the way back into silence when nothing is showing.

Left-click opens a panel listing what is snoozed, with the time each one comes
back, a button to give it another half hour and one to wake it now. It also
carries the silence switch. Right-click on the glyph silences without opening
anything.

## Driving it from a script

```
omarchy-shell omapager count            how many are on screen
omarchy-shell omapager clear            dismiss them
omarchy-shell omapager dnd              toggle Do Not Disturb
omarchy-shell omapager expand           open the deck, as hovering would
omarchy-shell omapager offer code       take the front card's offer (code|link|phone|path)
omarchy-shell omapager act reply        invoke one of the sender's actions
omarchy-shell omapager reply "text"     answer the front card ("" opens the field)
omarchy-shell omapager swipe            throw the front card away
omarchy-shell omapager snooze 60        quieten the front card's source, in minutes
omarchy-shell omapager unsnooze ""      wake everything ("" for all, or a source key)
omarchy-shell omapager snoozes          what is snoozed, and until when
omarchy-shell omapager stack source     switch stacking mode
omarchy-shell omapager align right      switch which end the buttons sit at
omarchy-shell omapager probe            what the daemon believes, as JSON

omarchy-shell omapager.panel toggle     the snooze panel
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

Two things are optional, and each one only disables what it powers:

| | for |
| --- | --- |
| `wl-clipboard` | the `Copy code` and `Copy number` buttons. Codes are copied with `wl-copy --sensitive`, so Omarchy's clipboard history skips them, and they are cleared again after 90 seconds if nothing else has been copied since. Without it those buttons do nothing. |
| KDE Connect | replying to a phone notification from the card. Without it, cards from your phone still arrive; they just have no reply field. |

## Licence

Apache-2.0.
