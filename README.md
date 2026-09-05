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
answer goes back to the conversation on the device.

![Typing a reply into a notification](assets/reply.png)

**Sends you back where it came from.** Clicking a card runs the sender's
default action; failing that it focuses the window that source is already
showing in, and only opens something new if there's nothing to go back to.
Omarchy's web apps carry their host in their Hyprland class, so those match
outright; a site open as a tab in an ordinary browser doesn't, so the brand is
matched against browser window titles instead — a Slack notification lands in
the Chrome that's already showing Slack rather than in a new tab.

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
plugin, and put the bell somewhere in the bar:

```json
{
  "disabledPlugins": ["omarchy.notifications"],
  "plugins": [{ "id": "njpatel.omapager" }],
  "bar": { "layout": { "right": ["njpatel.omapager", "omarchy.tray"] } }
}
```

`omarchy-restart-shell` to pick it up. (Not `omarchy-refresh-shell` — that
resets `shell.json` to defaults.)

## Settings

| key | default | what it does |
| --- | --- | --- |
| `stacking` | `source` | `source` gives each sender its own deck; `all` puts everything in one |
| `actionsAlign` | `right` | which end of a card its buttons sit at |

## The bell

Left-click dismisses what's on screen, right-click is Do Not Disturb. It shows
a hollow bell when nothing is waiting and a filled one with a count when
something is.

## Driving it from a script

```
omarchy-shell omapager count            how many are on screen
omarchy-shell omapager clear            dismiss them
omarchy-shell omapager dnd              toggle Do Not Disturb
omarchy-shell omapager expand           open the deck, as hovering would
omarchy-shell omapager offer code       take the front card's offer (code|link|phone|path)
omarchy-shell omapager act reply        invoke one of the sender's actions
omarchy-shell omapager reply "text"     answer the front card; no text opens the field
omarchy-shell omapager swipe            throw the front card away
omarchy-shell omapager stack source     switch stacking mode
omarchy-shell omapager align right      switch which end the buttons sit at
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

## Why there is no notification centre

There was one — a slide-in tray with everything you hadn't dealt with — and it
was deleted on purpose.

Android and macOS can have a notification centre because the *app* owns the
notification: read the message in Slack and the entry disappears, because
Slack tells the system it was handled. Freedesktop has `CloseNotification` for
exactly this and almost nobody calls it. Chrome doesn't close a web
notification when you read the tab, `notify-send` can't, and a script that
fired one has already exited. So "outstanding" could only ever mean *omapager
hasn't seen you click it*, which stops matching reality within minutes, and
the list fills with things you dealt with hours ago. A list you have to prune
by hand is worse than no list.

What the daemon can know honestly is what is on screen right now. That's the
deck. History is still kept — 300 entries, for `--replay` and for restoring
notifications across a shell restart — but as a log, not an inbox.

## Requirements

Omarchy (Quickshell 0.3.x, Hyprland). Optional: `wl-copy` for the copy
buttons, KDE Connect for phone replies.

## Licence

Apache-2.0.
