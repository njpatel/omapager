// Omapager - notifications for Omarchy.
//
// This file IS the notification daemon: Quickshell's NotificationServer owns
// org.freedesktop.Notifications, so omarchy.notifications must be listed in
// shell.json's disabledPlugins or the two fight over the bus name.
//
// Stage 1 is deliberately plain: take the bus, hold the notifications, draw one
// card each, expire them, and lose nothing across a restart. The deck, the
// grouping build on the state kept here.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.Commons

import "Store.js" as Store
import "Layout.js" as Layout

Item {
  id: service

  // Injected by omarchy-shell's service loader.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string storeBin: Qt.resolvedUrl("bin/omapager-store").toString().replace(/^file:\/\//, "")
  readonly property string iconBin: Qt.resolvedUrl("bin/omapager-icon").toString().replace(/^file:\/\//, "")

  // Ask the site for its icon when nothing local matches. On by default: a
  // notification wearing the wrong logo is the thing people notice first. It
  // does mean a request to that host the first time it notifies you, which is
  // why it can be turned off.
  property bool fetchIcons: true

  // Which variant of a site's icon to ask for. Derived from the theme's own
  // notification background rather than a setting: if the card is light, the
  // icon meant for light backgrounds is the one that will read on it.
  readonly property bool lightTheme: {
    var c = Color.notifications.background
    return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.5
  }

  // ------------------------------------------------------------- settings
  // Read from the plugin's shell.json entry once the settings plumbing lands;
  // until then these are the defaults the plan calls for.
  // source by default: a deck per sender, each expanding on its own. One pile
  // for everything is the simpler model but it stops telling you anything the
  // moment two apps are talking at once.
  property string stacking: "source"     // all | source

  // Which end of a card its buttons sit at. Settings plumbing has not landed
  // for plugins yet, so this is a property with an IPC verb, the same as
  // stacking above.
  property string actionsAlign: "right"  // right | left

  // Chrome puts a "Settings" action on every web notification, which opens
  // its site-permissions page. It is the same button on every card, it is
  // never the thing you wanted, and it crowds out the ones that are - so it
  // is dropped by default and can be put back.
  property bool hideSettingsAction: true

  // A verification code is the one thing quiet cannot afford to swallow: you
  // asked for it thirty seconds ago, it expires in five minutes, and no amount
  // of "I'll look later" applies. Codes are only ever detected from a keyword
  // sitting next to a plausible shape, so this is a narrow hole rather than an
  // exception anything can walk through - and it can be closed.
  property bool codesBypassQuiet: true
  function setCodesBypassQuiet(value) {
    if (!!value === codesBypassQuiet) return
    codesBypassQuiet = !!value
    saveQuiet()
  }

  property bool doNotDisturb: false
  property double silencedSince: 0
  function setDoNotDisturb(value) {
    var on = !!value
    if (on === doNotDisturb) return
    if (on) silencedSince = Date.now() / 1000
    doNotDisturb = on
    saveQuiet()
  }
  readonly property int gap: Style.space(6)

  // ------------------------------------------------------------- bar room
  //
  // The deck hangs from the top right corner, so it has to keep clear of the
  // bar on exactly two of the four edges it could be on - and of neither if
  // it is hidden. This used to assume a bar across the top and nothing else:
  // a bar down the right ran straight through the cards, a bar at the bottom
  // pushed them a bar's height down from a top edge with nothing on it, and a
  // hidden bar still had room left for it.
  readonly property var barRef: shell && shell.bar ? shell.bar : null
  readonly property string barPosition: barRef ? String(barRef.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int barThickness: {
    if (!barRef || barRef.barHidden) return 0
    var size = Number(barRef.barSize || 0)
    if (size > 0) return size
    return barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  }
  // Down from the top edge, and in from the right one.
  readonly property int barClearance: (barPosition === "top" ? barThickness : 0) + Style.gapsOut
  readonly property int edgeClearance: (barPosition === "right" ? barThickness : 0) + Style.space(14)

  readonly property int lowDuration: 5000
  readonly property int normalDuration: 8000
  readonly property int maxDuration: 30000

  function durationFor(urgency, requested) {
    if (urgency === NotificationUrgency.Critical) return 0        // never expires
    var base = urgency === NotificationUrgency.Low ? lowDuration : normalDuration
    if (requested > 0) return Math.min(requested, maxDuration)
    return base
  }

  // ------------------------------------------------------------- snooze
  //
  // Silencing one source instead of the whole desktop. The key is the row's
  // group key, so it is per site for anything arriving through a browser
  // ("web:app.slack.com") and per app for everything else - which is what
  // "snooze Slack" has to mean on a desktop where Slack is a tab in Chrome.
  //
  // A snoozed notification is still recorded: it goes to history the way a
  // silenced one does, so "what did I miss" survives the decision to not be
  // interrupted by it.
  property var snoozes: ({})        // groupKey -> { until: epoch seconds, label }

  // How long "snooze" is allowed to mean. Minutes, or the literal "tomorrow",
  // which is the one choice that is not a duration at all - it is a time, and
  // what time depends on when you start work. Both come from the widget's
  // settings; these are the defaults.
  property var snoozeChoices: ["30", "60", "240", "tomorrow"]
  property int wakeHour: 8

  // "40 minutes", "An hour", "4 hours" - and a short form for somewhere that
  // only has room for a chip.
  function durationWords(minutes) {
    if (minutes < 60) return minutes + " minutes"
    var hours = minutes / 60
    if (hours === 1) return "an hour"
    return (Math.round(hours * 10) / 10) + " hours"
  }

  function shortWords(minutes) {
    return minutes < 60 ? (minutes + "m") : ((Math.round(minutes / 6) / 10) + "h").replace(".0h", "h")
  }

  // One choice, worked out against the clock as it is now: "tomorrow" is a
  // different number of seconds at every hour of the day.
  function snoozeOption(choice) {
    var value = String(choice || "")
    if (value === "tomorrow") {
      var wake = new Date()
      wake.setDate(wake.getDate() + 1)
      wake.setHours(Math.max(0, Math.min(23, wakeHour)), 0, 0, 0)
      return { short: "Tomorrow", menuLabel: "Snooze until tomorrow",
               seconds: Math.max(600, Math.round((wake.getTime() - Date.now()) / 1000)) }
    }
    var minutes = Number(value)
    if (!(minutes > 0)) return null
    return { short: shortWords(minutes), menuLabel: "Snooze for " + durationWords(minutes),
             seconds: Math.round(minutes * 60) }
  }

  readonly property var snoozeOptions: {
    var out = []
    for (var i = 0; i < snoozeChoices.length; i++) {
      var option = snoozeOption(snoozeChoices[i])
      if (option) out.push(option)
    }
    return out
  }
  // snoozes is a plain map, so nothing re-evaluates when it changes; this is
  // what the bar indicator and the panel are bound through.
  property int snoozeRevision: 0

  // Snoozing everything is the same mechanism under a key no source can have.
  // It persists, prunes and restores with the rest, and the panel only has to
  // know to leave it out of the source list.
  readonly property string globalKey: "*"
  readonly property double globalSnoozeUntil: { snoozeRevision; return snoozedUntil(globalKey) }

  function snoozedUntil(groupKey) {
    var entry = snoozes[String(groupKey || "")]
    var until = entry ? Number(entry.until || 0) : 0
    return until > Date.now() / 1000 ? until : 0
  }

  // Soonest to wake first, which is the order the panel lists them in.
  function liveSnoozes() {
    snoozeRevision
    var now = Date.now() / 1000, out = []
    for (var key in snoozes) {
      if (key === globalKey) continue
      var entry = snoozes[key]
      if (!entry || Number(entry.until || 0) <= now) continue
      out.push({ key: key, label: String(entry.label || key), until: Number(entry.until) })
    }
    out.sort(function(a, b) { return a.until - b.until })
    return out
  }

  readonly property int snoozeCount: { snoozeRevision; return liveSnoozes().length }

  // Including the global one, which liveSnoozes() deliberately leaves out -
  // the source list has no row for it. Anything that has to keep running while
  // something is asleep has to watch this rather than the count, or a snooze
  // of everything is a snooze nothing is ticking for.
  readonly property bool anySnooze: { snoozeRevision; return snoozeCount > 0 || globalSnoozeUntil > 0 }

  // `fromNow` re-snoozes rather than extends. Picking "4 hours" from the panel
  // means the source comes back in four hours - not four hours after whatever
  // was already left on it, which would make the number on the button a lie.
  function snoozeSource(groupKey, label, seconds, fromNow) {
    var key = String(groupKey || "")
    if (!key || !(seconds > 0)) return 0
    var from = fromNow ? Date.now() / 1000
                       : Math.max(Date.now() / 1000, snoozedUntil(key))
    var next = {}
    for (var k in snoozes) next[k] = snoozes[k]
    // `since` is when this quiet period began. Without it the panel would
    // list everything the source has ever had held back, including what it
    // held during a snooze you ended last week.
    var since = (next[key] && snoozedUntil(key)) ? Number(next[key].since || 0)
                                                 : Date.now() / 1000
    next[key] = { until: from + seconds, label: String(label || key), since: since }
    snoozes = next
    snoozeRevision += 1
    saveQuiet()
    // Anything from that source already on screen goes now: leaving it there
    // is the opposite of what was just asked for.
    var keys = []
    for (var i = 0; i < toasts.count; i++) {
      var row = toasts.get(i)
      if (String(row.groupKey || "") === key) keys.push(row.key)
    }
    for (var j = 0; j < keys.length; j++) closeToast(keys[j], "snoozed")
    return next[key].until
  }

  function unsnooze(groupKey) {
    var next = {}
    for (var k in snoozes) if (k !== String(groupKey)) next[k] = snoozes[k]
    snoozes = next
    snoozeRevision += 1
    saveQuiet()
  }

  function unsnoozeAll() {
    snoozes = ({})
    snoozeRevision += 1
    saveQuiet()
  }

  // Silencing outlives a shell restart, the way the built-in service's does.
  // It has to: nothing on screen says the desktop is quiet, so a silence that
  // quietly lifts itself when the shell reloads is a silence you cannot rely
  // on - and one that stays on when you thought it had gone is worse.
  function saveQuiet() {
    Store.write(storeProc, storeBin, "quiet-save",
                { snoozes: snoozes, dnd: doNotDisturb, silencedSince: silencedSince,
                  codesBypassQuiet: codesBypassQuiet })
  }

  // ------------------------------------------------------- what was held
  //
  // A notification that never reached the screen is the one you most want to
  // be able to look at: "quiet" is only tolerable if you can see what it cost.
  // Read on demand rather than kept up to date - the panel is the only thing
  // that asks, and it asks when it opens.
  property var heldRows: []
  property int heldRevision: 0
  property int heldLimit: 80          // read from the store; the panel shows far fewer

  function refreshHeld() { if (!heldProc.running) heldProc.running = true }

  Process {
    id: heldProc
    running: false
    command: [service.storeBin, "held", String(service.heldLimit)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.heldRows = Store.parseList(text)
        service.heldRevision += 1
      }
    }
  }

  // When the quiet that is holding this source began. Everything older than
  // that was held by some earlier decision and is not what you are asking
  // about now.
  function quietSince(groupKey) {
    var entry = snoozes[String(groupKey || "")]
    var mine = entry && snoozedUntil(groupKey) ? Number(entry.since || 0) : 0
    var global = globalSnoozeUntil ? Number((snoozes[globalKey] || {}).since || 0) : 0
    var silence = doNotDisturb ? silencedSince : 0
    // The earliest of the reasons currently in force: if the desktop has been
    // silent for an hour and this source was snoozed ten minutes ago, the hour
    // is the honest window.
    var starts = [mine, global, silence].filter(function(t) { return t > 0 })
    return starts.length ? Math.min.apply(null, starts) : 0
  }

  function heldFor(groupKey, limit) {
    heldRevision
    var since = quietSince(groupKey)
    var out = []
    for (var i = 0; i < heldRows.length && out.length < limit; i++) {
      var row = heldRows[i]
      if (String(row.groupKey || "") !== String(groupKey)) continue
      if (since && Number(row.ts || 0) < since) continue
      out.push(row)
    }
    return out
  }

  // Every source being kept quiet right now, with what it has held. Sources
  // that are snoozed by name come first and keep their own wake time; after
  // them come the ones that are only quiet because everything is, and they
  // are here because they actually held something.
  function quietSources(limit) {
    snoozeRevision; heldRevision
    var rows = [], seen = {}
    var snoozed = liveSnoozes()
    var i, key
    for (i = 0; i < snoozed.length && rows.length < limit; i++) {
      seen[snoozed[i].key] = true
      rows.push({ key: snoozed[i].key, label: snoozed[i].label, until: snoozed[i].until,
                  held: heldFor(snoozed[i].key, heldPerSource) })
    }
    if (!doNotDisturb && !globalSnoozeUntil) return rows
    for (i = 0; i < heldRows.length && rows.length < limit; i++) {
      key = String(heldRows[i].groupKey || "")
      if (!key || seen[key]) continue
      var held = heldFor(key, heldPerSource)
      if (!held.length) continue
      seen[key] = true
      rows.push({ key: key, label: String(heldRows[i].source || heldRows[i].app || key),
                  until: 0, held: held })
    }
    return rows
  }

  // Caps, so a fortnight of silence does not turn the panel into a log file.
  property int sourceLimit: 8
  property int heldPerSource: 10

  // Wakes the bindings so a snooze that has run out stops being counted, and
  // drops it from the map so the file does not collect the past. Only runs
  // while something is actually snoozed.
  Timer {
    interval: 20000
    repeat: true
    running: service.anySnooze
    onTriggered: {
      var now = Date.now() / 1000, next = {}, dropped = false
      for (var k in service.snoozes) {
        if (Number(service.snoozes[k].until || 0) > now) next[k] = service.snoozes[k]
        else dropped = true
      }
      if (dropped) { service.snoozes = next; service.saveQuiet() }
      service.snoozeRevision += 1
    }
  }

  // ------------------------------------------------------------- state
  //
  // The live Notification objects stay in a plain JS map, never in the model.
  // A QObject in a ListModel role becomes a dangling C++ pointer the moment
  // the server destroys it, and the next read of that role takes the shell
  // down inside QQmlListModel::data. A map only holds a wrapper, so a stale
  // entry throws where we can catch it.
  property var refs: ({})
  property int keySeed: 0

  ListModel { id: toasts }

  // ------------------------------------------------------------- icons
  //
  // Resolved once per source and remembered, so a chatty Slack does not spawn
  // a lookup per message. The answer is written back onto every row that
  // shares the source, and persisted, so history and restarts keep it.
  property var iconCache: ({})
  property var iconQueue: []
  property string iconWanted: ""

  function wantIcon(row) {
    if (String(row.image || "")) return                 // the sender sent one
    var key = String(row.groupKey || row.source || row.app || "")
    if (!key) return
    if (iconCache[key] !== undefined) {
      // Write it onto the row in hand as well as onto the model. This is
      // called before the row is inserted, so applyIcon - which walks the
      // model - cannot see it: the first notification from a source got its
      // icon (resolved after the insert, asynchronously) and every later one
      // from the same source fell back to a letter, because by then the answer
      // was cached and arrived too early.
      if (iconCache[key]) {
        row.stored_image = iconCache[key]
        applyIcon(key, iconCache[key])
      }
      return
    }
    for (var i = 0; i < iconQueue.length; i++) if (iconQueue[i].key === key) return
    iconQueue.push({ key: key, app: String(row.app || ""),
                     appIcon: String(row.appIcon || ""),
                     source: String(row.source || "") })
    pumpIcons()
  }

  function pumpIcons() {
    if (iconProc.running || iconQueue.length === 0) return
    var job = iconQueue.shift()
    iconWanted = job.key
    var args = [iconBin, "--key", job.key, "--app", job.app,
                "--app-icon", job.appIcon, "--source", job.source,
                "--scheme", service.lightTheme ? "light" : "dark"]
    if (fetchIcons) args.push("--fetch")
    iconProc.command = args
    iconProc.running = true
  }

  function applyIcon(key, path) {
    for (var i = 0; i < toasts.count; i++) {
      var row = toasts.get(i)
      if (String(row.groupKey || row.source || row.app || "") !== key) continue
      if (row.stored_image === path) continue
      toasts.setProperty(i, "stored_image", path)
      var copy = {}
      for (var k in row) copy[k] = row[k]
      copy.stored_image = path
      Store.write(storeProc, storeBin, "put", copy)
    }

  }

  Process {
    id: iconProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        service.iconCache[service.iconWanted] = path
        if (path) service.applyIcon(service.iconWanted, path)
        service.iconWanted = ""
        Qt.callLater(service.pumpIcons)
      }
    }
  }

  // A single clock the cards' relative times hang off. Per-card timers would
  // be a dozen wakeups a minute to move the word "now" to "1m".
  property double nowTick: Date.now()
  Timer { interval: 20000; repeat: true; running: toasts.count > 0
          onTriggered: service.nowTick = Date.now() }

  // A copy of what is on screen, for anything that wants to read it: handing
  // the ListModel across would let the reader outlive rows it still holds.
  readonly property int toastCount: toasts.count
  function liveRows() {
    var out = []
    for (var i = 0; i < toasts.count; i++) {
      var r = toasts.get(i)
      var copy = {}
      for (var k in r) copy[k] = r[k]
      out.push(copy)
    }
    return out
  }

  // ------------------------------------------------------------- the deck
  //
  // Expansion is pointer containment, not a click, and it survives a short
  // trip outside: crossing a gap between two cards should not slam the deck
  // shut in your face.
  property bool pointerIn: false
  property bool expanded: false
  property string openDeck: ""
  property string hoverKey: ""     // the card under the pointer, when open
  property real hoverX: -1         // where it is, in the deck's coordinates
  property real hoverY: -1

  // ------------------------------------------------------------- swipe
  //
  // Pushing a card to the right throws it away. Collapsed, the deck travels
  // together and goes together - the stack is one object until you open it.
  property real swipeX: 0
  property string swipeKey: ""
  property bool swipeWholeDeck: false
  // A drag in progress freezes the deck: nothing collapses, nothing expires,
  // nothing new lands. Dragging a card to the right takes the pointer out of
  // the hover region, which used to collapse the deck mid-gesture and re-lay
  // out every card underneath the one being dragged - the fight you could
  // feel.
  property bool dragging: false

  function swipeMoved(key, dx) {
    if (!dragging) { dragging = true; swipeWholeDeck = !expanded }
    swipeKey = key
    swipeX = dx
  }

  function swipeEnded(key, away) {
    dragging = false
    if (!away) {
      settleBack.start()          // not far enough: it comes back
      return
    }
    var keys = []
    if (swipeWholeDeck) {
      for (var i = 0; i < toasts.count; i++) keys.push(toasts.get(i).key)
    } else {
      keys.push(key)
    }
    swipeX = 0
    swipeKey = ""
    swipeWholeDeck = false
    for (var k = 0; k < keys.length; k++) closeToast(keys[k], "dismissed")
  }

  // Carries the test throw past the threshold a moment later, so the movement
  // is visible rather than instantaneous.
  Timer {
    id: swipeDemo
    property string key: ""
    interval: 180
    onTriggered: {
      service.swipeMoved(key, service.swipeX + Style.space(200))
      service.swipeEnded(key, true)
    }
  }

  NumberAnimation {
    id: settleBack
    target: service; property: "swipeX"; to: 0
    duration: 260; easing.type: Easing.OutCubic
    onFinished: { service.swipeKey = ""; service.swipeWholeDeck = false }
  }
  property var heights: ({})          // key -> measured card height
  property int layoutRevision: 0

  Timer {
    id: collapseGrace
    interval: 120
    onTriggered: {
      if (service.dragging) return
      service.expanded = false; service.openDeck = ""
      service.releaseHeld()
    }
  }

  // Notifications that arrived while the deck was held. A card appearing
  // under the pointer moves everything below it by one place, which is
  // maddening when you are part-way through reading - or dragging - the card
  // it lands on.
  property var held: []

  // Held only while the pointer is genuinely on the deck, or mid-drag. Keying
  // this off `expanded` alone was wrong: the deck can be expanded with no
  // pointer anywhere near it - the IPC verb does exactly that - and then
  // nothing ever "leaves", so arrivals queue up invisibly until the 30-second
  // safety valve fires. A notification held because of a pointer that is not
  // there is just a lost notification.
  // ...and while an answer is being typed. A card arriving above the one you
  // are replying to moves the field out from under the cursor mid-sentence.
  function holding() { return (pointerIn && expanded) || dragging || replyingKey !== "" }

  function releaseHeld() {
    if (!held.length) return
    var queue = held
    held = []
    for (var i = 0; i < queue.length; i++) service.showRow(queue[i])
  }

  // Nothing waits forever: a pointer parked over the deck should not silence
  // the machine.
  Timer {
    id: heldTooLong
    interval: 30000
    running: service.held.length > 0
    onTriggered: service.releaseHeld()
  }

  function pointerEntered(deckKey) {
    collapseGrace.stop()
    expanded = true
    if (deckKey !== undefined) openDeck = deckKey
  }
  function pointerLeft() {
    if (dragging) return          // the pointer leaves during every throw
    collapseGrace.restart()
  }

  // Every card is measured and laid out at its own height, collapsed or not.
  // There was a second map here holding each card's height "at rest" so that
  // collapsed cards could share the tallest one - it went with the shared
  // height itself, which padded one-line cards out to match two-line ones and
  // made the whole deck resize whenever a card grew for its buttons.
  function noteHeight(key, h) {
    if (Math.abs((heights[key] || 0) - h) < 0.5) return
    heights[key] = h
    layoutRevision += 1
  }

  readonly property var layout: {
    layoutRevision                      // recompute when a card is measured
    var rows = []
    for (var i = 0; i < toasts.count; i++) rows.push(toasts.get(i))
    return Layout.compute(rows, {
      stacking: stacking,
      expanded: expanded,
      openDeck: stacking === "source" ? openDeck : undefined,
      gap: gap,
      deckGap: Style.space(11),
      heightOf: function(key) { return service.heights[key] || Style.space(58) }
    })
  }

  Connections {
    target: toasts
    function onCountChanged() { service.layoutRevision += 1 }
  }

  // Our own identity for a notification. The sender's id is reused (that is
  // what replaces_id is for), so it identifies a slot, not an event.
  function nextKey() {
    keySeed += 1
    return "n" + Date.now().toString(36) + keySeed.toString(36)
  }

  function rowIndexFor(key) {
    for (var i = 0; i < toasts.count; i++)
      if (toasts.get(i).key === key) return i
    return -1
  }

  // id 0 means "this is a new notification", not "replace the one with id 0".
  // Matching on it made every notify-send take over whichever restored row
  // happened to have no id.
  function rowIndexForOriginal(id) {
    if (!id) return -1
    for (var i = 0; i < toasts.count; i++)
      if (toasts.get(i).originalId === id) return i
    return -1
  }

  // ------------------------------------------------------------- arrival
  function handleNotification(notification) {
    // Without this the object is destroyed as soon as this handler returns,
    // taking the actions and the image with it.
    notification.tracked = true

    // replaces_id: the sender is updating something already on screen.
    var replacing = rowIndexForOriginal(notification.id)
    var key = replacing >= 0 ? toasts.get(replacing).key : nextKey()

    var row = Store.snapshot(notification, key, NotificationUrgency)
    row.duration = durationFor(notification.urgency, row.expireTimeout)

    var previous = refs[key]
    refs[key] = notification
    // refs is a plain map, so nothing watching it re-evaluates on its own. The
    // card's action buttons are bound through this counter, or they would be
    // read once - before the sender was recorded - and stay empty forever.
    refsRevision += 1
    notification.closed.connect(function() {
      if (service.refs[key] === notification) delete service.refs[key]
    })
    if (previous && previous !== notification) {
      try { previous.tracked = false } catch (e) {}
    }

    // Silenced or snoozed still means recorded: "what did I miss" is the whole
    // point of a store. It goes straight to history without being on screen.
    // Critical is never muted - that is what critical means.
    var muted = doNotDisturb ? "silenced"
              : (globalSnoozeUntil || snoozedUntil(row.groupKey)) ? "snoozed" : ""
    if (muted && codesBypassQuiet && String(row.code || "")) muted = ""
    if (muted && notification.urgency !== NotificationUrgency.Critical) {
      Store.write(storeProc, storeBin, "put", row)
      Store.write(storeProc, storeBin, "close", null, [key, muted])
      release(key)
      return
    }

    Store.write(storeProc, storeBin, "put", row)
    wantIcon(row)
    lookForReply(row)

    // An update to something already on screen goes through either way: it
    // changes a card in place rather than moving anything. Only a genuinely
    // new card waits, and only while the deck is being held.
    if (service.holding() && service.rowIndexFor(key) < 0) {
      var queue = service.held.slice()
      queue.push(row)
      service.held = queue
      return
    }

    service.showRow(row)
  }

  // Qt.callLater: mutating the model while a Repeater is mid-incubation
  // crashes in QV4::Object::insertMember.
  function showRow(row) {
    var key = String(row.key || "")
    Qt.callLater(function() {
      var at = service.rowIndexFor(key)
      if (at >= 0) {
        Store.applyTo(toasts, at, row)      // an update, in place
      } else {
        toasts.insert(0, row)
      }
    })
  }

  // Let go of the sender's object. Untracking tells it the notification
  // closed, which is when Chromium deletes the avatar it handed us.
  function release(key) {
    var ref = refs[key]
    if (!ref) return
    try { ref.tracked = false } catch (e) {}
    delete refs[key]
  }

  // ------------------------------------------------------------- departure
  // Removing the row immediately would mean no exit to animate, so the card
  // is asked to play its exit and the row goes when it has finished.
  property var leaving: ({})

  function closeToast(key, reason) {
    var at = rowIndexFor(key)
    if (at < 0 || leaving[key]) return
    leaving[key] = true
    exitTimer.pending.push({ key: key, reason: reason, at: Date.now() })
    exitTimer.start()
    cardExit(key, reason !== "expired")
    return
  }

  Timer {
    id: exitTimer
    property var pending: []
    interval: 210
    repeat: true
    running: pending.length > 0
    onTriggered: {
      var now = Date.now()
      var keep = []
      for (var i = 0; i < pending.length; i++) {
        if (now - pending[i].at >= 200) service.finishClose(pending[i].key, pending[i].reason)
        else keep.push(pending[i])
      }
      pending = keep
      if (pending.length === 0) stop()
    }
  }

  signal cardExit(string key, bool byHand)

  function finishClose(key, reason) {
    if (replyingKey === key) replyingKey = ""
    delete leaving[key]
    var at = rowIndexFor(key)
    if (at < 0) return
    var ref = refs[key]
    if (ref) {
      // Tell the sender which way it went: expired and dismissed are
      // different events on the bus, and some apps act on the difference.
      try {
        if (reason === "expired" && typeof ref.expire === "function") ref.expire()
        else ref.dismiss()
      } catch (e) {}
    }
    release(key)
    toasts.remove(at)
    delete heights[key]
    Store.write(storeProc, storeBin, "close", null, [key, reason])
  }

  function clearAll(reason) {
    // Over a snapshot of the keys, never over the model's count: closeToast
    // does not remove the row, it marks it leaving and lets the exit timer
    // take it 200ms later. `while (toasts.count > 0)` therefore never made
    // progress - the second pass at the same key returned early on `leaving`,
    // the count stayed put, and the loop spun the main thread at 100% with no
    // error and no log. Every wedge traced back to here, because the demo
    // script clears before it starts.
    var keys = []
    for (var i = 0; i < toasts.count; i++) keys.push(toasts.get(i).key)
    for (var k = 0; k < keys.length; k++) closeToast(keys[k], reason || "cleared")
  }

  // What the sender said can be done with this notification. Not a guess - the
  // app put these on the wire itself, and until now the daemon accepted them
  // (actionsSupported: true), invoked "default" on a click, and drew none of
  // the rest. A restored row has no live sender, so it has none of these.
  property int refsRevision: 0

  function actionsOf(key, revision) {
    var out = []
    var ref = refs[key]
    if (!ref || !ref.actions) return out
    for (var i = 0; i < ref.actions.length; i++) {
      var a = ref.actions[i]
      var identifier = String(a.identifier || "")
      if (identifier === "default" || !identifier) continue
      var label = String(a.text || identifier)
      if (hideSettingsAction && (/^settings$/i.test(label) || /^settings$/i.test(identifier)))
        continue
      out.push({ id: identifier, text: label })
    }
    return out
  }

  function invokeAction(key, identifier) {
    var ref = refs[key]
    if (ref && ref.actions) {
      for (var i = 0; i < ref.actions.length; i++) {
        if (String(ref.actions[i].identifier) === identifier) {
          try { ref.actions[i].invoke() } catch (e) {}
          break
        }
      }
    }
    closeToast(key, "activated")
  }

  // ------------------------------------------------------- source routing
  //
  // Which open window is already showing the thing that notified you.
  // Senders come in two shapes and need two different answers:
  //
  //   web.whatsapp.com   an Omarchy web app, which writes its host straight
  //                      into its class: "chrome-web.whatsapp.com__-Default"
  //   app.slack.com      a tab in an ordinary browser, whose class says only
  //                      which browser it is ("chrome-work"). Nothing about
  //                      Slack appears anywhere but the window title.
  //
  // So: the class first, because it is exact, and the title second, cautiously.

  // Whole words only: "slack" must not match "slackline", and a brand that
  // happens to be a substring of a longer word is not a sighting of it.
  function wordIn(text, word) {
    var at = text.indexOf(word)
    while (at >= 0) {
      var before = at === 0 ? "" : text.charAt(at - 1)
      var after = text.charAt(at + word.length)
      if (!/[a-z0-9]/.test(before) && !/[a-z0-9]/.test(after)) return true
      at = text.indexOf(word, at + 1)
    }
    return false
  }

  // Every window on the desktop, as { wmClass, title }. Hyprland.toplevels is
  // the current name; clients is the older one, kept as a fallback so the
  // plugin still routes on an older Quickshell.
  function openWindows() {
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    if (!list.length && Hyprland.clients) list = Hyprland.clients.values
    var out = []
    for (var i = 0; i < list.length; i++) {
      var ipc = list[i].lastIpcObject
      var wmClass = String((ipc && ipc["class"]) || "")
      if (wmClass) out.push({ wmClass: wmClass,
                              title: String((ipc && ipc.title) || ""),
                              address: String((ipc && ipc.address) || "") })
    }
    return out
  }

  readonly property var browserClasses: /^(chrome|chromium|firefox|zen|brave|edge|vivaldi)/

  // Every Chrome window title ends "- Google Chrome", every Firefox one
  // "- Mozilla Firefox". Left on, a notification from any google.com host
  // matches every Chrome window on the desktop, so the browser's own name
  // comes off before anything is compared.
  readonly property var browserSuffix:
    /\s*[-\u2013\u2014|]\s*(google chrome|chromium|mozilla firefox|firefox|zen browser|brave|microsoft edge|vivaldi)\s*$/

  // Labels that name nobody: the subdomains everyone uses, and public suffixes.
  readonly property var genericLabels: ({ www: 1, app: 1, web: 1, my: 1, m: 1,
                                          mail: 1, com: 1, org: 1, net: 1,
                                          io: 1, co: 1, dev: 1, ai: 1, so: 1,
                                          site: 1, uk: 1 })

  // What to look for in a title, most telling first. "app.slack.com" gives
  // ["slack"]; "news.ycombinator.com" gives ["news", "ycombinator"], because
  // either half can be the one a page actually puts in its title. Tried in
  // order, so the more specific label gets first refusal on every window.
  function brandsOf(host) {
    var labels = String(host || "").toLowerCase().split(".")
    var out = []
    for (var i = 0; i < labels.length; i++) {
      if (labels[i].length >= 4 && !genericLabels[labels[i]]) { out.push(labels[i]); break }
    }
    var registered = labels.length >= 2 ? labels[labels.length - 2] : ""
    if (registered.length >= 4 && !genericLabels[registered] && out.indexOf(registered) < 0)
      out.push(registered)
    return out
  }

  function windowForSource(source) {
    var name = String(source || "").toLowerCase()
    if (!name) return null
    // Compare in lower case, return the class as it actually is: Hyprland's
    // class filter is an exact match, so the lowercased form
    // ("...__-default") would never find the window ("...__-Default").
    var windows = openWindows()
    var i

    if (name.indexOf(".") > 0) {
      for (i = 0; i < windows.length; i++)
        if (windows[i].wmClass.toLowerCase().indexOf(name) >= 0) return windows[i]

      // No class carries it, so the site is a tab in a browser that named
      // itself after something else. Browsers only: "slack" in an editor's
      // title is a filename, not a place to go.
      var brands = brandsOf(name)
      for (var b = 0; b < brands.length; b++) {
        for (i = 0; i < windows.length; i++) {
          if (!browserClasses.test(windows[i].wmClass.toLowerCase())) continue
          var title = windows[i].title.toLowerCase().replace(browserSuffix, "")
          if (wordIn(title, brands[b])) return windows[i]
        }
      }
      return null
    }

    // Not a host - a phone-forwarded notification says "WhatsApp", not
    // "web.whatsapp.com". Match it against the labels of each open web app's
    // host, and against native app classes, so a message forwarded from the
    // phone still lands on the desktop window showing the same thing. Whole
    // labels only, and nothing shorter than four characters: "X" would
    // otherwise match half the desktop.
    var slug = name.replace(/[^a-z0-9]+/g, "")
    if (slug.length < 4) return null
    for (i = 0; i < windows.length; i++) {
      var lower = windows[i].wmClass.toLowerCase()
      if (lower === slug) return windows[i]                    // a native app
      if (lower.indexOf("chrome-") !== 0) continue
      var labels = lower.substring(7).split("__")[0].split(".")
      for (var l = 0; l < labels.length; l++)
        if (labels[l] === slug) return windows[i]
    }
    return null
  }

  // By address, because a class is not an identity: this desktop runs two
  // browser windows both called "chrome-work", and only one of them is showing
  // Slack. The class is the fallback for a window Hyprland gave us no address
  // for. Dispatch arguments are evaluated as Lua here, so this is an
  // expression rather than the classic `dispatch focuswindow ...` string.
  function focusWindow(win) {
    if (!win) return
    var target = win.address
      ? 'hl.get_window("address:' + win.address.replace(/[^0-9a-fx]/gi, "") + '")'
      : 'hl.get_windows({class = "' + win.wmClass.replace(/"/g, "") + '"})[1]'
    Hyprland.dispatch("hl.dsp.focus({window = " + target + "})")
  }

  function activate(key) {
    var ref = refs[key]
    var handled = false
    if (ref && ref.actions) {
      for (var i = 0; i < ref.actions.length; i++) {
        if (String(ref.actions[i].identifier) === "default") {
          try { ref.actions[i].invoke(); handled = true } catch (e) {}
          break
        }
      }
    }

    if (!handled) {
      var at = rowIndexFor(key)
      var row = at >= 0 ? toasts.get(at) : null
      if (row) {
        // Source first, link last. A Slack message quoting a link to
        // somewhere else is still a Slack notification: clicking it should
        // take you to Slack, not to whatever URL happened to be in the text.
        // That link already has its own button. Checked against 300 stored
        // notifications, where the wrong order would have sent 20 clicks to
        // the wrong place - including a Slack card that would have opened
        // axiom.co.
        var win = windowForSource(row.source)
        if (win) focusWindow(win)
        else if (String(row.source || "").indexOf(".") > 0)
          Qt.openUrlExternally("https://" + String(row.source) + "/")
        else if (String(row.link || "")) Qt.openUrlExternally(String(row.link))
      }
    }
    closeToast(key, "activated")
  }

  // ------------------------------------------------------------- replying
  //
  // A message forwarded from the phone can be answered from here. KDE Connect
  // keeps an object per phone notification on its own bus carrying a replyId
  // and a sendReply method - the part the freedesktop spec has no room for -
  // and the helper matches our row to it by app name and text.
  readonly property string kdeBin: Qt.resolvedUrl("bin/omapager-kdeconnect")
                                     .toString().replace(/^file:\/\//, "")
  property string replyingKey: ""        // the card with its reply box open

  Process { id: replyProc; running: false }

  // A reply box holds the keyboard, so it must not be able to hold it
  // indefinitely - a card that expires or is dismissed while you are typing
  // would otherwise leave the desktop deaf.
  Timer {
    id: replyGiveUp
    interval: 120000
    running: service.replyingKey !== ""
    onTriggered: service.replyingKey = ""
  }

  Process {
    id: findProc
    property var job: ({})
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var job = findProc.job || {}
        var path = "", who = ""
        try {
          var found = JSON.parse(String(text) || "{}")
          path = String(found.path || "")
          who = String(found.title || "")
        } catch (e) {}
        var at = service.rowIndexFor(String(job.key || ""))
        if (path && at >= 0) {
          toasts.setProperty(at, "replyPath", path)
          if (who) toasts.setProperty(at, "replyTo", who)
        } else if (!path && at >= 0 && (job.tries || 0) < 1) {
          // Nothing yet. Once more in a moment, in case the phone's side of it
          // had not appeared when we looked.
          job.tries = (job.tries || 0) + 1
          var queue = service.replyQueue.slice()
          queue.push(job)
          service.replyQueue = queue
          replyRetry.restart()
        }
        Qt.callLater(service.pumpReplies)
      }
    }
  }

  // Lookups are queued rather than dropped, and each row is tried twice: KDE
  // Connect posts the desktop notification and publishes the object that backs
  // it at about the same moment, so the first look can arrive before there is
  // anything to find.
  property var replyQueue: []

  function lookForReply(row) {
    if (!/kde\s*connect/i.test(String(row.app || ""))) return
    var queue = replyQueue.slice()
    queue.push({ key: String(row.key || ""), source: String(row.source || ""),
                 body: String(row.bodyLine || row.body || ""), tries: 0 })
    replyQueue = queue
    pumpReplies()
  }

  function pumpReplies() {
    if (findProc.running || replyQueue.length === 0) return
    var queue = replyQueue.slice()
    var job = queue.shift()
    replyQueue = queue
    findProc.job = job
    findProc.command = [kdeBin, "find", job.source, job.body]
    findProc.running = true
  }

  Timer {
    id: replyRetry
    interval: 1500
    onTriggered: service.pumpReplies()
  }

  function sendReply(key, text) {
    var at = rowIndexFor(key)
    if (at < 0) return
    var path = String(toasts.get(at).replyPath || "")
    if (!path || !String(text).trim()) return
    replyProc.running = false
    replyProc.command = [kdeBin, "reply", path, String(text)]
    replyProc.running = true
    replyingKey = ""
    closeToast(key, "activated")           // answered is dealt with
  }

  // ------------------------------------------------------------- offers
  //
  // Acting on what Detect.js found in a card: copy the code, open the link.
  // Nothing here guesses - the card only ever offers what was actually found,
  // and the offer is a click, never automatic.
  Process { id: clipProc; running: false }

  // A verification code is not clipboard history material. wl-copy's
  // --sensitive marks it, and Omarchy's clipboard capture skips anything
  // carrying that hint - so the code is pasteable but never recorded. It is
  // also cleared once it has had time to be used, the way a phone does it.
  property string secretHeld: ""

  function copyText(text, sensitive) {
    var value = String(text || "")
    if (!value) return
    var args = ["wl-copy"]
    if (sensitive) args.push("--sensitive")
    args.push("--")
    args.push(value)
    clipProc.running = false
    clipProc.command = args
    clipProc.running = true
    if (sensitive) { secretHeld = value; secretLife.restart() }
  }

  Timer {
    id: secretLife
    interval: 90000
    onTriggered: clipReader.running = true
  }

  // Only clear it if it is still the thing on the clipboard: taking away
  // something the person copied afterwards would be its own small betrayal.
  Process {
    id: clipReader
    running: false
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text) === service.secretHeld && service.secretHeld) {
          clipProc.running = false
          clipProc.command = ["wl-copy", "--clear"]
          clipProc.running = true
        }
        service.secretHeld = ""
      }
    }
  }

  function takeOffer(kind, value, key) {
    if (kind === "code") copyText(value, true)
    else if (kind === "phone") copyText(value, false)
    else if (kind === "path") Qt.openUrlExternally("file://" + value)
    else Qt.openUrlExternally(value)

    // A copied code is a finished notification: it exists to carry six digits
    // to a login box, and once they are on the clipboard there is nothing left
    // in it. Long enough after the press for the button's tick to be seen,
    // because a card that vanishes the instant you click it leaves you unsure
    // whether it copied or you missed.
    // ...unless it was carrying more than one, in which case the other one is
    // still in there and taking the card away would be taking that with it.
    if (kind === "code" && String(key || "")) {
      var at = rowIndexFor(String(key))
      var several = at >= 0 && String(toasts.get(at).codes || "").indexOf(" ") > 0
      if (!several) {
        codeTaken.key = String(key)
        codeTaken.restart()
      }
    }
  }

  Timer {
    id: codeTaken
    property string key: ""
    interval: 900
    onTriggered: service.closeToast(key, "activated")
  }

  // ------------------------------------------------------------- store
  Process { id: storeProc; running: false }

  Process {
    id: restoreProc
    running: false
    command: [service.storeBin, "restore"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rows = Store.parseList(text)
        // Oldest first out of the store, and insert(0) reverses it, so the
        // deck comes back in the order it was in before the restart.
        for (var i = 0; i < rows.length; i++) {
          var row = Store.restored(rows[i])
          if (row) toasts.insert(0, row)
        }
      }
    }
  }

  Process {
    id: quietRestoreProc
    running: false
    command: [service.storeBin, "quiet"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var read = JSON.parse(String(text) || "{}")
          if (read && typeof read === "object") {
            if (read.snoozes && typeof read.snoozes === "object") service.snoozes = read.snoozes
            service.doNotDisturb = read.dnd === true
            service.silencedSince = Number(read.silencedSince || 0)
            // Turned off in the panel, it stays off - the setting is the
            // default, not a standing instruction to put it back.
            if (read.codesBypassQuiet !== undefined)
              service.codesBypassQuiet = read.codesBypassQuiet === true
          }
        } catch (e) {}
        service.snoozeRevision += 1
      }
    }
  }

  Component.onCompleted: {
    restoreProc.running = true
    quietRestoreProc.running = true
  }

  // ------------------------------------------------------------- server
  NotificationServer {
    id: server
    keepOnReload: false
    imageSupported: true
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    persistenceSupported: true

    onNotification: function(notification) { service.handleNotification(notification) }
  }

  IpcHandler {
    target: "omapager"
    function count(): string { return String(toasts.count) }
    // What the daemon thinks is true, for a script to check against what it
    // can see. Everything here answers a question that has actually been
    // asked in anger: where would a click go, did the reply channel resolve,
    // which of the sender's actions survived, how tall is each card.
    function probe(): string {
      var i, key
      var route = "nothing"
      if (toasts.count > 0) {
        var front = toasts.get(0)
        var win = service.windowForSource(front.source)
        route = win ? ("focus " + win.wmClass + " [" + win.address + "]")
              : (String(front.source || "").indexOf(".") > 0
                 ? ("open https://" + front.source + "/")
                 : (String(front.link || "") ? ("open " + front.link)
                    : "sender's default action"))
      }

      var heights = [], actions = []
      for (i = 0; i < toasts.count; i++) {
        key = toasts.get(i).key
        heights.push(key + "=" + (service.heights[key] || 0))
        actions.push(String(toasts.get(i).summary).slice(0, 14) + "=" +
                     JSON.stringify(service.actionsOf(key, service.refsRevision)))
      }
      return JSON.stringify({
        toasts: toasts.count, route: route, actions: actions, heights: heights,
        replyPath: toasts.count > 0 ? String(toasts.get(0).replyPath || "") : "",
        replying: service.replyingKey !== "",
        expanded: service.expanded, pointerIn: service.pointerIn,
        doNotDisturb: service.doNotDisturb, snoozed: service.liveSnoozes(),
        snoozeOptions: service.snoozeOptions,
        decks: service.layout.decks.length, layoutH: service.layout.height,
        barClearance: service.barClearance
      })
    }
    function clear(): string { service.clearAll("cleared"); return "ok" }
    function dnd(): string {
      service.doNotDisturb = !service.doNotDisturb
      return service.doNotDisturb ? "on" : "off"
    }
    // Drive the deck without a pointer: a headless session has no cursor, and
    // a recording needs the expansion to happen on cue rather than by hand.
    function expand(): string {
      if (service.expanded) { service.expanded = false; service.openDeck = ""; service.hoverKey = "" }
      else if (toasts.count > 0) {
        // Stand in for the pointer being on the front card: its deck opens and
        // it counts as hovered, so anything that only appears under a pointer
        // can be seen without one.
        var front = toasts.get(0)
        service.pointerEntered(Layout.deckKeyFor(front, service.stacking))
        service.hoverKey = String(front.key)
      } else {
        service.pointerEntered(undefined)
      }
      return service.expanded ? "expanded" : "collapsed"
    }
    // Snooze the front card's source, or any source by key. Minutes, because
    // that is how anyone says it out loud.
    function snooze(minutes: string): string {
      if (toasts.count === 0) return "nothing"
      var row = toasts.get(0)
      var mins = Number(minutes) > 0 ? Number(minutes) : 60
      var until = service.snoozeSource(String(row.groupKey || ""),
                                       String(row.source || row.app || ""), mins * 60)
      return until ? (String(row.source || row.app) + " until " + new Date(until * 1000).toTimeString().slice(0, 5)) : "no source"
    }

    // Snooze the lot, which is what the panel's own button does. Separate from
    // `snooze` because that one acts on the front card's source, and the two
    // are easy to confuse at a prompt - with the cost of confusing them being
    // a real source silently going quiet for an hour.
    function snoozeAll(minutes: string): string {
      var mins = Number(minutes) > 0 ? Number(minutes) : 60
      var until = service.snoozeSource(service.globalKey, "Everything", mins * 60, true)
      return until ? ("everything until " + new Date(until * 1000).toTimeString().slice(0, 5)) : "no"
    }

    function unsnooze(key: string): string {
      if (!String(key || "")) { service.unsnoozeAll(); return "all" }
      service.unsnooze(String(key))
      return String(key)
    }

    function snoozes(): string { return JSON.stringify(service.liveSnoozes()) }

    // Whether a verification code gets through the quiet. The panel's key
    // button, from a script.
    function codes(state: string): string {
      var want = String(state || "").toLowerCase()
      if (want === "on" || want === "off")
        service.setCodesBypassQuiet(want === "on")
      return service.codesBypassQuiet ? "on" : "off"
    }
    function open(deckKey: string): string {
      service.pointerEntered(deckKey)
      return service.openDeck
    }
    // Invoke one of the sender's actions on the front card, by identifier.
    // Scriptable, and the only way to exercise the path without a pointer.
    function act(identifier: string): string {
      if (toasts.count === 0) return "nothing"
      var key = String(toasts.get(0).key)
      var available = service.actionsOf(key, service.refsRevision)
      var wanted = String(identifier || "")
      if (!wanted && available.length > 0) wanted = available[0].id
      if (!wanted) return "no actions"
      service.invokeAction(key, wanted)
      return wanted
    }

    // Take one of the front card's offers - "code", "link", "phone", "path".
    // The same thing the little marks do, without a pointer.
    function offer(kind: string): string {
      if (toasts.count === 0) return "nothing"
      var row = toasts.get(0)
      var want = String(kind || "code")
      var value = want === "code" ? String(row.code || "")
                : want === "phone" ? String(row.phone || "")
                : want === "path" ? String(row.filePath || "")
                : String(row.link || "")
      if (!value) return "none"
      service.takeOffer(want, value, String(row.key))
      return value
    }

    function align(side: string): string {
      if (side === "left" || side === "right") service.actionsAlign = side
      return service.actionsAlign
    }

    // Reply to the front card, for scripting and for testing the path without
    // a pointer.
    // With text, answers the front card. Without, just opens the box - which
    // is how the field itself can be looked at without a pointer.
    function reply(text: string): string {
      if (toasts.count === 0) return "nothing"
      var key = String(toasts.get(0).key)
      if (!String(toasts.get(0).replyPath || "")) return "not repliable"
      if (!String(text || "").trim()) {
        service.replyingKey = key
        service.pointerEntered(Layout.deckKeyFor(toasts.get(0), service.stacking))
        service.hoverKey = key
        return "open"
      }
      service.sendReply(key, String(text))
      return "sent"
    }

    // Throw the front card off to the right, as a drag would. Splits the
    // gesture in two for testing: this is everything after the pointer, so if
    // the card leaves when this runs but not when you drag, the fault is in
    // recognising the drag rather than in acting on it.
    function swipe(): string {
      if (toasts.count === 0) return "nothing"
      var key = String(toasts.get(0).key)
      service.swipeMoved(key, Style.space(40))
      swipeDemo.key = key
      swipeDemo.restart()
      return "thrown"
    }

    function stack(mode: string): string {
      if (mode === "all" || mode === "source") service.stacking = mode
      return service.stacking
    }
  }

  // ---------------------------------------------------- the stock keybindings
  //
  // Omarchy ships five global bindings on the comma key, and every one of them
  // talks to the IPC target `notifications` - dismiss one, dismiss all, invoke
  // the last, replay history, and the silencing toggle that
  // omarchy-toggle-notification-silencing drives. Disabling the built-in
  // service to run this one takes that target away with it, so all five go
  // quietly dead: the keys still fire, the shell answers "target not found",
  // and nothing tells you why.
  //
  // So omapager answers to it as well. The names and return values are the
  // built-in service's, not ours, because the callers are Omarchy's.
  IpcHandler {
    target: "notifications"

    function dndState(): string { return service.doNotDisturb ? "on" : "off" }
    function isDnd(): string { return dndState() }

    function toggleDnd(): string {
      service.setDoNotDisturb(!service.doNotDisturb)
      return dndState()
    }

    function setDnd(value: string): string {
      var v = String(value || "").toLowerCase()
      service.setDoNotDisturb(v === "true" || v === "1" || v === "on" || v === "yes")
      return dndState()
    }

    function dismissAll(): string { service.clearAll("dismissed"); return "ok" }

    function dismissOne(): string {
      if (toasts.count === 0) return "none"
      service.closeToast(String(toasts.get(0).key), "dismissed")
      return "ok"
    }

    function invokeLast(): string {
      if (toasts.count === 0) return "none"
      service.activate(String(toasts.get(0).key))
      return "ok"
    }

    function showHistory(): string { service.replayHistory(); return "ok" }

    // Forgets what was recorded. What is on screen stays where it is.
    function clear(): string {
      Store.write(storeProc, storeBin, "forget-all", null)
      service.heldRows = []
      service.heldRevision += 1
      return "ok"
    }

    // Used by Omarchy's first-run notifications to take their own card off
    // the screen once its action has been clicked.
    function dismiss(summary: string): string {
      var needle = String(summary || "")
      if (!needle) return "none"
      var keys = []
      for (var i = 0; i < toasts.count; i++)
        if (String(toasts.get(i).summary || "").indexOf(needle) !== -1)
          keys.push(String(toasts.get(i).key))
      for (var k = 0; k < keys.length; k++) service.closeToast(keys[k], "dismissed")
      return keys.length ? "ok" : "none"
    }

    function ping(): string { return "ok" }
  }

  // Put the last few back on screen, the way the built-in service's
  // "Open notification history" binding does. They come back as restored
  // rows - no live sender, a short grace rather than their original timeout -
  // because the notification they came from is long gone.
  property int replayCount: 6

  Process {
    id: replayProc
    running: false
    command: [service.storeBin, "history", String(service.replayCount)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rows = Store.parseList(text)          // newest first out of the store
        for (var i = rows.length - 1; i >= 0; i--) {
          var row = Store.restored(rows[i])
          // A fresh key, or replaying something still on screen would land on
          // the row that is already there and replace it.
          if (!row) continue
          if (service.rowIndexFor(row.key) >= 0) row.key = service.nextKey()
          service.showRow(row)
        }
      }
    }
  }

  function replayHistory() { if (!replayProc.running) replayProc.running = true }

  // ------------------------------------------------------------- surface
  //
  // One full-screen layer per output. Full-screen and fixed: a surface that
  // resizes as cards come and go lets the compositor scale a stale buffer,
  // which is visible as the cards briefly stretching. The mask keeps every
  // pixel outside the deck click-through.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: surface
      required property var modelData
      screen: modelData
      visible: toasts.count > 0
      color: "transparent"

      // The name the Hyprland layer_rule matches on for blur.
      WlrLayershell.namespace: "omapager"
      WlrLayershell.layer: WlrLayer.Overlay
      // Exclusive while a reply is being typed, and nothing at all otherwise.
      // OnDemand only hands the keyboard over when the surface is clicked,
      // which means anything that opens the box any other way - a keybinding,
      // the IPC verb - gets a field that silently ignores typing. A
      // notification layer holding the keyboard the rest of the time would
      // swallow every keystroke on the desktop, so this is tightly bounded:
      // Escape closes it, so does answering, and so does the timeout below.
      WlrLayershell.keyboardFocus: service.replyingKey !== ""
                                   ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // As wide as the deck needs and no wider. Full-screen was the obvious
      // shape - the deck can sit anywhere in it - but it meant Qt re-rendering
      // a 5120x2880 surface for every frame of every arrival, for a stack
      // 340pt across. The width is a constant, so the buffer is allocated once
      // and never resized under an animation; the height stays full so the
      // deck can grow downwards without the window changing size either.
      anchors { top: true; bottom: true; right: true }
      implicitWidth: clipper.width + Style.space(10)

      // Only the deck takes input; the rest of the surface stays
      // click-through. Tracking the item keeps the region honest as the deck
      // grows and shrinks.
      mask: Region { item: deck }

      // The notification area proper: it begins at the bar's lower edge and is
      // clipped there, so a card arriving from above is revealed as it comes
      // down rather than being seen sliding across the panel. The extra height
      // is room for the bottom card's shadow, which clipping would otherwise
      // cut off square.
      Item {
        id: clipper
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: service.barClearance
        anchors.rightMargin: 0
        // Room for the shadow on both sides. The clip is here to hide a card
        // dropping in from behind the bar, which is a vertical concern only -
        // but an item that clips and is exactly as wide as the card cuts the
        // shadow off flat down both edges. So the clipper is wider than the
        // card and the deck sits inset within it: left by a comfortable
        // margin, right by however much room there is between the card and the
        // screen edge, which is all a shadow can have there anyway.
        readonly property int shadowRoom: Style.space(30)
        // In from the screen's right edge - plus the bar's width, if the bar
        // is the thing occupying that edge.
        readonly property int edgeGap: service.edgeClearance
        width: Style.space(340) + shadowRoom + edgeGap
        height: deck.y + deck.height + Style.space(30)
        clip: true

        Item {
          id: deck
          y: Style.space(6)
        x: clipper.shadowRoom
        width: Style.space(340)
        height: service.layout.height

        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // One hover region for the whole deck. Individual cards must not own
        // this: moving between two of them would leave and re-enter, and the
        // deck would flicker shut between every card.
        MouseArea {
          // Above the cards, not beneath them. A MouseArea that sets a
          // cursorShape accepts hover events whether or not hoverEnabled is
          // set, so every card was swallowing the hover this region needed -
          // and accepting no buttons means clicks still fall through to the
          // card underneath. Cards carry z of 1000-and-up from their
          // placement, so this has to clear that.
          z: 5000
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          propagateComposedEvents: true
          id: hoverArea
          // Containment, not enter/exit events: the deck changes size the
          // moment it expands, and a resize under a stationary pointer was
          // producing an exit that shut it again a frame later.
          // Which card the pointer is over. The hover region sits above the
          // cards (they would otherwise swallow it), so a card cannot work
          // this out for itself - it is told. Done on entry as well as on
          // movement: arriving in the region without moving again inside it -
          // which is what a warped pointer does, and what a slow hand does at
          // the boundary - used to leave the deck thinking no card was under
          // the pointer at all.
          function hoverAt(x, y) {
            // Where the pointer is, for anything inside a card that wants to
            // light up under it. The card cannot find out for itself: this
            // region is above every card, hover goes to the topmost item that
            // accepts it, and so a button's own containsMouse never becomes
            // true. Clicks are fine - this accepts no buttons and they fall
            // through - which is why the buttons worked while looking dead.
            service.hoverX = x
            service.hoverY = y
            var places = service.layout.placements
            var found = ""
            for (var key in places) {
              var pl = places[key]
              if (pl.hidden) continue
              var h = pl.height || Style.space(58)
              if (y >= pl.y && y <= pl.y + h) { found = key; break }
            }
            service.hoverKey = found
          }

          onContainsMouseChanged: {
            service.pointerIn = containsMouse
            if (containsMouse) {
              service.pointerEntered(undefined)
              hoverAt(mouseX, mouseY)
            } else {
              service.hoverKey = ""
              service.pointerLeft()
            }
          }
          onPositionChanged: function(mouse) {
            hoverAt(mouse.x, mouse.y)

            // In source mode, which deck you are over decides which opens.
            if (service.stacking !== "source") return
            var decks = service.layout.decks
            for (var i = 0; i < decks.length; i++) {
              var first = decks[i].rows[0]
              var place = service.layout.placements[first.key]
              if (!place) continue
              var top = place.y
              var bottom = top + (service.heights[first.key] || Style.space(58))
              if (mouse.y >= top - Style.space(6) && mouse.y <= bottom + Style.space(6)) {
                service.pointerEntered(decks[i].key)
                return
              }
            }
          }
        }

        Repeater {
          model: toasts

          Toast {
            id: toast
            required property var model
            row: model
            cardWidth: deck.width
            place: service.layout.placements[model.key]
                   || ({ y: 0, scale: 1, opacity: 0, z: 1, front: false, hidden: true })
            hovered: service.hoverKey === model.key
            // A collapsed deck moves as one; an open one moves card by card.
            swipe: (service.swipeWholeDeck || service.swipeKey === model.key)
                   ? service.swipeX : 0
            actions: service.actionsOf(model.key, service.refsRevision)
            actionsAlign: service.actionsAlign
            replying: service.replyingKey === model.key
            onReplyRequested: {
              service.replyingKey = model.key
              service.pointerEntered(Layout.deckKeyFor(model, service.stacking))
              service.hoverKey = String(model.key)
            }
            onReplySent: function(text) { service.sendReply(model.key, text) }
            onReplyCancelled: service.replyingKey = ""
            hoverX: service.hoverX
            hoverY: service.hoverY
            onActionInvoked: function(identifier) { service.invokeAction(model.key, identifier) }
            onOfferTaken: function(kind, value) { service.takeOffer(kind, value, model.key) }
            onSwipeMoved: function(dx) { service.swipeMoved(model.key, dx) }
            onSwipeEnded: function(away) { service.swipeEnded(model.key, away) }
            now: service.nowTick
            expanded: service.expanded
                      && (service.stacking !== "source" || service.openDeck === Layout.deckKeyFor(model, service.stacking))
            // Nothing counts down while the deck is open, mid-throw, or with
            // an answer half typed into it.
            paused: service.expanded || service.dragging || service.replyingKey !== ""

            onImplicitHeightChanged: service.noteHeight(model.key, implicitHeight)
            Component.onCompleted: service.noteHeight(model.key, implicitHeight)

            onExpired: service.closeToast(model.key, "expired")
            onActivated: service.activate(model.key)
            onDismissed: service.closeToast(model.key, "dismissed")
            snoozeOptions: service.snoozeOptions
            onSnoozeRequested: function(seconds) {
              service.snoozeSource(String(model.groupKey || ""),
                                   String(model.source || model.app || ""), seconds)
            }
            onSilenceRequested: service.doNotDisturb = true

            Connections {
              target: service
              function onCardExit(key, byHand) {
                if (key === toast.model.key) toast.playExit(byHand)
              }
            }
          }
        }
      }
      }
    }
  }
}
