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
  property bool doNotDisturb: false
  readonly property int maxVisible: 3    // cards drawn in a collapsed deck
  readonly property int gap: Style.space(6)

  readonly property int lowDuration: 5000
  readonly property int normalDuration: 8000
  readonly property int maxDuration: 30000

  function durationFor(urgency, requested) {
    if (urgency === NotificationUrgency.Critical) return 0        // never expires
    var base = urgency === NotificationUrgency.Low ? lowDuration : normalDuration
    if (requested > 0) return Math.min(requested, maxDuration)
    return base
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
  property int deckHits: 0
  property bool expanded: false
  property string openDeck: ""
  property string openGroup: ""    // the group listing its members, if any
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
  property var heights: ({})          // key -> measured card height, as it is
  property var restHeights: ({})      // key -> the same, with nothing hovering
  property int layoutRevision: 0

  Timer {
    id: collapseGrace
    interval: 120
    onTriggered: {
      if (service.dragging) return
      service.expanded = false; service.openDeck = ""; service.openGroup = ""
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
  function holding() { return (pointerIn && expanded) || dragging }

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

  // Two numbers per card, because two different things need them. `heights`
  // is what the card is right now - what an opened deck lays out against, so a
  // card that grew to show its buttons actually gets the room. `restHeights`
  // is what it would be with nothing hovering over it, which is what the
  // collapsed banner height is taken from: measure that from the current
  // heights instead and hovering one card resizes every card on screen.
  function noteHeight(key, h) {
    if (Math.abs((heights[key] || 0) - h) < 0.5) return
    heights[key] = h
    layoutRevision += 1
  }

  function noteResting(key, h) {
    if (Math.abs((restHeights[key] || 0) - h) < 0.5) return
    restHeights[key] = h
    layoutRevision += 1
  }

  // The tallest card at rest. Collapsed cards all take this, so an arrival
  // moves the stack by exactly one peek instead of resizing it.
  readonly property real uniformHeight: {
    layoutRevision
    var tallest = Style.space(58)
    for (var i = 0; i < toasts.count; i++) {
      var h = restHeights[toasts.get(i).key] || 0
      if (h > tallest) tallest = h
    }
    return tallest
  }

  readonly property var layout: {
    layoutRevision                      // recompute when a card is measured
    var rows = []
    for (var i = 0; i < toasts.count; i++) rows.push(toasts.get(i))
    return Layout.compute(rows, {
      stacking: stacking,
      expanded: expanded,
      openDeck: stacking === "source" ? openDeck : undefined,
      openGroup: openGroup,
      gap: gap,
      uniform: uniformHeight,
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

    if (doNotDisturb && notification.urgency !== NotificationUrgency.Critical) {
      // Silenced still means recorded: "what did I miss" is the whole point of
      // anyone. It goes straight to history without ever being on screen.
      Store.write(storeProc, storeBin, "put", row)
      Store.write(storeProc, storeBin, "close", null, [key, "silenced"])
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
    delete restHeights[key]
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
      out.push({ id: identifier, text: String(a.text || identifier) })
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

  // The default action, or failing that whatever the sender left us.
  // Clicking a notification should put you back where it came from.
  //
  // The sender's own default action is the best answer when there is one - a
  // browser knows which tab it meant. Failing that, the window is usually
  // already open and findable: an Omarchy web app carries its host in its
  // Hyprland class ("chrome-web.whatsapp.com__-Default"), so a notification
  // that identified itself as web.whatsapp.com can be matched to the window
  // showing it. Only if there is no such window do we open anything new.
  function openClasses() {
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    if (!list.length && Hyprland.clients) list = Hyprland.clients.values
    var out = []
    for (var i = 0; i < list.length; i++) {
      var ipc = list[i].lastIpcObject
      var wmClass = String((ipc && ipc["class"]) || "")
      if (wmClass) out.push(wmClass)
    }
    return out
  }

  function windowForSource(source) {
    var name = String(source || "").toLowerCase()
    if (!name) return null
    var classes = openClasses()
    var i

    // Compare in lower case, return the class as it actually is: Hyprland's
    // class filter is an exact match, so the lowercased form
    // ("...__-default") would never find the window ("...__-Default").
    if (name.indexOf(".") > 0) {
      for (i = 0; i < classes.length; i++)
        if (classes[i].toLowerCase().indexOf(name) >= 0) return classes[i]
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
    for (i = 0; i < classes.length; i++) {
      var wmClass = classes[i]
      var lower = wmClass.toLowerCase()
      if (lower === slug) return wmClass                       // a native app
      if (lower.indexOf("chrome-") !== 0) continue
      var host = lower.substring(7).split("__")[0]
      var labels = host.split(".")
      for (var l = 0; l < labels.length; l++)
        if (labels[l] === slug) return wmClass
    }
    return null
  }

  function focusClass(wmClass) {
    // The class filter is an exact match, not a pattern, which is why the
    // class is looked up here rather than guessed at with a regex. And the
    // dispatcher takes Lua on this machine: `hyprctl dispatch focuswindow ...`
    // is parsed as an expression and fails.
    Hyprland.dispatch('hl.dsp.focus({window = hl.get_windows({class = "'
                      + wmClass.replace(/"/g, "") + '"})[1]})')
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
        var wmClass = windowForSource(row.source)
        if (wmClass) focusClass(wmClass)
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

  function takeOffer(kind, value) {
    if (kind === "code") copyText(value, true)
    else if (kind === "phone") copyText(value, false)
    else if (kind === "path") Qt.openUrlExternally("file://" + value)
    else Qt.openUrlExternally(value)
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

  Component.onCompleted: restoreProc.running = true

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

  // Temporary while bringing the surface up.
  property int surfacesMade: 0
  property string surfaceNote: ""

  IpcHandler {
    target: "omapager"
    function count(): string { return String(toasts.count) }
    function probe(): string {
      var hs = []
      for (var i = 0; i < toasts.count; i++) {
        var k = toasts.get(i).key
        hs.push(k + "=" + (service.heights[k] || 0))
      }
      // What clicking the front card would do, without doing it.
      var route = "nothing"
      if (toasts.count > 0) {
        var front = toasts.get(0)
        var wmClass = service.windowForSource(front.source)
        route = wmClass ? ("focus " + wmClass)
              : (String(front.source || "").indexOf(".") > 0
                 ? ("open https://" + front.source + "/")
                 : (String(front.link || "") ? ("open " + front.link)
                    : "sender's default action"))
      }

      var replyTo = toasts.count > 0 ? String(toasts.get(0).replyPath || "") : ""

      var acts = []
      for (var j = 0; j < toasts.count; j++) {
        var k = toasts.get(j).key
        acts.push(String(toasts.get(j).summary).slice(0, 14) + "=" +
                  JSON.stringify(service.actionsOf(k)))
      }
      return JSON.stringify({ replyPath: replyTo, route: route, actions: acts,
                              toasts: toasts.count, expanded: service.expanded,
                              pointerIn: service.pointerIn, deckHits: service.deckHits,
                              deckW: Style.space(340), pad20: Style.space(20),
                              gapsOut: Style.gapsOut,
                              barSize: (service.shell && service.shell.bar) ? service.shell.bar.barSize : -1,
                              barDefault: Style.bar.sizeHorizontal,
                              screenW: Quickshell.screens.length ? Quickshell.screens[0].width : -1,
                              layoutH: service.layout.height,
                              decks: service.layout.decks.length, heights: hs,
                              note: service.surfaceNote })
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
    function group(key: string): string {
      service.openGroup = service.openGroup === key ? "" : key
      service.layoutRevision += 1
      return service.openGroup
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
      service.takeOffer(want, value)
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
      implicitWidth: Style.space(340) + Style.space(14) + Style.space(40)

      // Only the deck takes input; the rest of the surface stays
      // click-through. Tracking the item keeps the region honest as the deck
      // grows and shrinks.
      mask: Region { item: deck }

      readonly property int barClearance: {
        var b = service.shell && service.shell.bar ? service.shell.bar : null
        var size = b && !b.barHidden ? Math.max(0, b.barSize) : Style.bar.sizeHorizontal
        return size + Style.gapsOut
      }

      // The notification area proper: it begins at the bar's lower edge and is
      // clipped there, so a card arriving from above is revealed as it comes
      // down rather than being seen sliding across the panel. The extra height
      // is room for the bottom card's shadow, which clipping would otherwise
      // cut off square.
      Item {
        id: clipper
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: surface.barClearance
        anchors.rightMargin: 0
        // Room for the shadow on both sides. The clip is here to hide a card
        // dropping in from behind the bar, which is a vertical concern only -
        // but an item that clips and is exactly as wide as the card cuts the
        // shadow off flat down both edges. So the clipper is wider than the
        // card and the deck sits inset within it: left by a comfortable
        // margin, right by however much room there is between the card and the
        // screen edge, which is all a shadow can have there anyway.
        readonly property int shadowRoom: Style.space(30)
        readonly property int edgeGap: Style.space(14)
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
              service.deckHits += 1
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
            onOfferTaken: function(kind, value) { service.takeOffer(kind, value) }
            onSwipeMoved: function(dx) { service.swipeMoved(model.key, dx) }
            onSwipeEnded: function(away) { service.swipeEnded(model.key, away) }
            now: service.nowTick
            expanded: service.expanded
                      && (service.stacking !== "source" || service.openDeck === Layout.deckKeyFor(model, service.stacking))
            paused: service.expanded || service.dragging

            onImplicitHeightChanged: service.noteHeight(model.key, implicitHeight)
            onRestingHeightChanged: service.noteResting(model.key, restingHeight)
            Component.onCompleted: {
              service.noteHeight(model.key, implicitHeight)
              service.noteResting(model.key, restingHeight)
            }

            onExpired: service.closeToast(model.key, "expired")
            onActivated: service.activate(model.key)
            onDismissed: service.closeToast(model.key, "dismissed")
            onGroupToggled: {
              var key = Layout.groupKeyFor(model)
              service.openGroup = service.openGroup === key ? "" : key
              service.layoutRevision += 1
            }

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
