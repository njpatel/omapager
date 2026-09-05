// The bar indicator, and the panel behind it.
//
// Nothing held back, nothing on the bar. omapager takes a slot only when it is
// keeping something from you - the desktop is silenced, everything is snoozed,
// or one source is - which is Omarchy's own convention for status icons: they
// appear when there is a state to report and are otherwise revealed by
// hovering the centre of the bar. A bell that is always there, always showing
// zero, is a permanent reminder of nothing.
//
// The states worth a glyph are the ones you cannot discover any other way, and
// the ones you can forget you are in. What is on screen needs no icon: it is
// on screen.

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: pager
  moduleName: "njpatel.omapager"

  // The daemon, if it is up. Everything that reads it degrades to empty rather
  // than breaking the bar.
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("njpatel.omapager") : null
  readonly property bool silenced: service ? service.doNotDisturb : false

  // liveSnoozes() reads a plain map, which nothing re-evaluates on its own, so
  // the service bumps a revision whenever that map moves. This is what every
  // binding below actually depends on.
  readonly property int snoozeRevision: service ? service.snoozeRevision : 0
  readonly property int heldRevision: service ? service.heldRevision : 0
  readonly property var snoozed: {
    snoozeRevision
    return service ? service.liveSnoozes() : []
  }
  readonly property double globalUntil: {
    snoozeRevision
    return service ? service.globalSnoozeUntil : 0
  }
  readonly property bool globalSnoozed: globalUntil > 0

  // Quiet by decision, as opposed to quiet because nothing happened.
  readonly property bool quiet: silenced || globalSnoozed
  readonly property bool hasState: quiet || snoozed.length > 0

  // Shown when there is something to say, while the panel is open, and on the
  // same bar-centre gesture that reveals Omarchy's own inactive indicators -
  // otherwise there would be no way back to silence once you left it.
  readonly property bool revealed: hasState || opened
    || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)

  // ------------------------------------------------------------- settings
  //
  // The settings plumbing the daemon has been doing without. Only a bar widget
  // is handed its shell.json entry, and the daemon is a sibling with no way to
  // read one - so this is the single place that can, and it pushes them over.
  function applySettings() {
    if (!service) return
    var stacking = String(setting("stacking", "source"))
    if (stacking === "all" || stacking === "source") service.stacking = stacking
    var align = String(setting("actionsAlign", "right"))
    if (align === "left" || align === "right") service.actionsAlign = align
    service.hideSettingsAction = setting("hideSettingsAction", true) !== false
    service.wakeHour = Number(setting("wakeHour", 8)) || 8
    service.sourceLimit = Number(setting("sourceLimit", 8)) || 8
    service.heldPerSource = Number(setting("heldPerSource", 10)) || 10
    // Empty means "none chosen", not "no snoozing" - fall back rather than
    // leaving a menu with nothing in it.
    var chosen = setting("snoozeDurations", null)
    if (chosen && chosen.length > 0) service.snoozeChoices = chosen
  }

  onSettingsChanged: applySettings()
  onServiceChanged: applySettings()
  Component.onCompleted: applySettings()

  // ------------------------------------------------------------- looks
  readonly property color panelFg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(panelFg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Omarchy's own Dnd indicator draws the crossed-out bell in the bar's plain
  // foreground and never colours it; the action lives in the tooltip. The
  // colour here is a deliberate addition, because silence and snooze are
  // states you can forget you are in and the cost of forgetting is a missed
  // message. It is the theme's own urgent, so it is whatever red that theme
  // has rather than one picked here.
  readonly property color silencedColour: bar ? bar.urgent : Color.urgent

  // No Omarchy theme carries an amber, so snooze takes the same colour turned
  // towards yellow - close enough to read as "less than stopped", and it moves
  // with the palette instead of fighting it. A theme whose urgent has no
  // saturation has no hue to turn, so that one gets a plain amber.
  readonly property color snoozedColour: {
    var u = silencedColour
    if (u.hslSaturation < 0.15) return "#c8913f"
    return Qt.hsla((u.hslHue + 0.09) % 1.0, u.hslSaturation, u.hslLightness, 1.0)
  }

  // nf-md-bell-off, the glyph Omarchy's own Dnd indicator uses, so a silenced
  // desktop looks the same whichever service is running; nf-md-bell-sleep, a
  // bell with a Z in it, for a snooze - which is a bell that will ring later
  // rather than one that has been switched off.
  readonly property string bellOff: "\u{f009b}"
  readonly property string bellSleep: "\u{f00a0}"
  readonly property string bell: "\u{f009a}"

  // Collapsed to nothing when there is nothing to report: an empty slot in the
  // bar is still a gap in the bar. Never animated, and every state is exactly
  // one slot wide, so nothing beside it ever slides - the clock stepping
  // sideways because a notification was snoozed is a worse offence than the
  // icon appearing at all.
  clip: true
  implicitWidth: vertical ? Math.max(glyphs.implicitWidth, barSize)
                          : (revealed ? glyphs.implicitWidth : 0)
  implicitHeight: vertical ? (revealed ? glyphs.implicitHeight : 0)
                           : Math.max(glyphs.implicitHeight, barSize)

  // ------------------------------------------------------------- state
  PanelController { id: controller }
  readonly property bool opened: controller.open

  // KeyboardPanel dismisses itself by calling close() on its owner, and falls
  // back to writing its own `open` property when the owner has no such
  // function - which breaks the binding to this controller and leaves the
  // panel stuck shut. Omarchy's Panel base exposes these three; a bar widget
  // acting as its own panel has to as well.
  function open() { controller.show() }
  function close() { controller.hide() }
  function toggle() { togglePanel() }

  function togglePanel() { controller.open ? controller.hide() : controller.show() }

  function toggleSilence() { if (service) service.setDoNotDisturb(!service.doNotDisturb) }

  // The switch reads as "notifications are on", so turning it back on has to
  // undo every reason they were off: being silenced and having snoozed the lot
  // are the same promise from where the switch is sitting.
  function letEverythingThrough() {
    if (!service) return
    service.setDoNotDisturb(false)
    service.unsnooze(service.globalKey)
  }

  // Left silences, right opens the panel. The fastest thing anyone wants from
  // a notification indicator is for it to stop - and, once it has stopped, for
  // it to start again - so that is the plain click; the panel is where you go
  // to look at something rather than change it, which is what a right-click
  // means everywhere else.
  function pressed(buttonCode) {
    if (buttonCode === Qt.RightButton) togglePanel()
    else if (quiet) letEverythingThrough()
    else toggleSilence()
  }

  // "in 24m", "in 3h", "until 08:00" once it is far enough out that the
  // remaining minutes stop being the useful half.
  function waking(until) {
    var left = Math.max(0, until - Date.now() / 1000)
    if (left < 3600) return "in " + Math.max(1, Math.round(left / 60)) + "m"
    if (left < 8 * 3600) return "in " + Math.round(left / 3600) + "h"
    return "until " + Qt.formatDateTime(new Date(until * 1000), "HH:mm")
  }

  // The other panels put a line under their title that cycles while the thing
  // they are about is doing something. Ours is doing something precisely when
  // it is holding notifications back, so that is when it talks.
  readonly property var quietPhrases: [
    "Holding messages",
    "Hushing apps",
    "Pocketing pings",
    "Absorbing alerts",
    "Muffling mentions",
    "Guarding quiet",
    "Sitting on notices",
    "Deferring drama",
    "Banking interruptions"
  ]
  property int phraseIndex: 0
  readonly property bool rotatingPhrases: opened && hasState

  readonly property string stateLine: {
    if (rotatingPhrases) return quietPhrases[phraseIndex % quietPhrases.length]
    if (silenced) return "Silenced"
    if (globalSnoozed) return "Everything snoozed, back " + waking(globalUntil)
    if (snoozed.length === 1) return snoozed[0].label + ", back " + waking(snoozed[0].until)
    if (snoozed.length > 1) return snoozed.length + " sources snoozed"
    return "Everything comes through"
  }

  Timer {
    interval: 2800
    running: pager.rotatingPhrases
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation { target: hero; property: "metaOpacity"
                        to: 0.0; duration: 180; easing.type: Easing.OutQuad }
    ScriptAction { script: pager.phraseIndex = (pager.phraseIndex + 1) % pager.quietPhrases.length }
    PropertyAnimation { target: hero; property: "metaOpacity"
                        to: 1.0; duration: 260; easing.type: Easing.InQuad }
  }

  // Return types are spelled out because Quickshell wants them, and `string`
  // rather than `void` because this Qt's QML grammar rejects `void` outright.
  IpcHandler {
    target: "omapager.panel"
    function open(): string { pager.open(); return "open" }
    function close(): string { controller.hide(); return "closed" }
    function toggle(): string { pager.togglePanel(); return controller.open ? "open" : "closed" }
    // Open a source's held list without a pointer, the same way the deck's
    // `expand` stands in for hovering it. No argument closes whatever is open.
    function expand(key: string): string {
      var wanted = String(key || "")
      if (!wanted) { pager.expandedKey = ""; return "closed" }
      for (var i = 0; i < pager.sources.length; i++) {
        if (pager.sources[i].key.indexOf(wanted) >= 0 ||
            pager.sources[i].label.indexOf(wanted) >= 0) {
          pager.expandedKey = pager.sources[i].key
          return pager.sources[i].label
        }
      }
      return "no such source"
    }

    function state(): string {
      var held = []
      for (var i = 0; i < pager.sources.length; i++)
        held.push(pager.sources[i].label + "=" + pager.sources[i].held.length)
      return JSON.stringify({ opened: pager.opened, panelVisible: panel.visible,
                              silenced: pager.silenced, globalSnoozed: pager.globalSnoozed,
                              sources: held, expanded: pager.expandedKey,
                              cardX: panel.cardOrigin.x, cardY: panel.cardOrigin.y,
                              cw: panel.contentWidth, ch: panel.contentHeight })
    }
  }

  // ------------------------------------------------------------- the bar
  Row {
    id: glyphs
    anchors.centerIn: parent
    spacing: 0

    Indicator {
      visible: pager.silenced
      text: pager.bellOff
      colour: pager.silencedColour
      tooltipText: "Notifications silenced - click to allow them, right-click for options"
    }

    Indicator {
      visible: !pager.silenced && (pager.globalSnoozed || pager.snoozed.length > 0)
      text: pager.bellSleep
      colour: pager.snoozedColour
      tooltipText: pager.globalSnoozed
                   ? ("Everything snoozed, back " + pager.waking(pager.globalUntil)
                      + " - right-click for options")
                   : ((pager.snoozed.length === 1
                       ? (pager.snoozed[0].label + " snoozed " + pager.waking(pager.snoozed[0].until))
                       : (pager.snoozed.length + " sources snoozed"))
                      + " - right-click for options")
    }

    // The resting state, which only appears while the bar's inactive
    // indicators are being revealed. Same glyph and same dimming as Omarchy's
    // own, so it sits in that row without announcing itself.
    Indicator {
      visible: !pager.hasState
      text: pager.bellOff
      colour: pager.bar ? pager.bar.barForeground : Color.foreground
      quiet: true
      tooltipText: "Silence notifications - right-click for options"
    }
  }

  component Indicator: BarIconButton {
    property bool quiet: false
    property color colour: pager.panelFg
    bar: pager.bar
    foreground: colour
    // The same metrics BarIndicator gives Omarchy's own status glyphs, so this
    // sits in a row with them without being half a pixel out.
    fontSize: Style.font.caption
    horizontalMargin: 5
    verticalPadding: 5
    fixedWidth: pager.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: pager.vertical ? Style.bar.statusSlot : -1
    useActiveColor: false
    dimmed: quiet
    onPressed: function(buttonCode) { pager.pressed(buttonCode) }
  }

  // ------------------------------------------------------------- the panel
  //
  // What is being kept from you, and what it has cost so far. Sources snoozed
  // by name come first, with their own wake time; then, when the whole desktop
  // is quiet, whichever other sources have actually had something held. Each
  // one opens to show what it caught.
  readonly property var sources: {
    snoozeRevision; heldRevision
    return service ? service.quietSources(service.sourceLimit) : []
  }

  property string expandedKey: ""
  property int cursorAt: 0
  property bool cursorLive: false
  property bool globalChoosing: false
  onOpenedChanged: {
    cursorAt = 0; cursorLive = false; expandedKey = ""; globalChoosing = false
    // What has been held back, as of now - read on opening rather than kept
    // up to date, because the panel is the only thing that ever asks.
    if (opened && service) service.refreshHeld()
  }

  function snoozeEverything(seconds) {
    if (service) service.snoozeSource(service.globalKey, "Everything", seconds, true)
    globalChoosing = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: glyphs
    owner: pager
    bar: pager.bar
    open: pager.opened
    focusTarget: keys
    // 380 is what every core Omarchy panel is, bar the two that need to be
    // wider (the clock's calendar, the weather's forecast). A panel that is
    // its own width is the thing you notice about it.
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: controller.hide()
      onMoveRequested: function(dx, dy) {
        if (dy === 0 || pager.sources.length === 0) return
        pager.cursorAt = Math.max(0, Math.min(pager.sources.length - 1, pager.cursorAt + dy))
        pager.cursorLive = true
      }
      // Every key here acts on the row the cursor is on, and nothing acts
      // without one. An open panel holds the keyboard exclusively, so anything
      // typed at another window while it happens to be open arrives here
      // instead - and this panel's shortcuts used to include silencing the
      // desktop. It did exactly what you would fear: someone typing a sentence
      // silenced their notifications, with nothing on screen to say why.
      // Navigation is safe to leave on a stray key. State changes are not.
      onActivateRequested: {
        if (!pager.cursorLive || pager.cursorAt >= pager.sources.length) return
        var key = pager.sources[pager.cursorAt].key
        pager.expandedKey = pager.expandedKey === key ? "" : key
      }
      onDeleteRequested: {
        if (pager.cursorLive && pager.cursorAt < pager.sources.length && pager.service)
          pager.service.unsnooze(pager.sources[pager.cursorAt].key)
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Notifications"
            meta: pager.stateLine
            foreground: pager.panelFg
            fontFamily: pager.fontFamily
            iconOpacity: pager.hasState ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: pager.silenced ? pager.bellOff
                    : (pager.globalSnoozed || pager.snoozed.length > 0) ? pager.bellSleep
                    : pager.bell
                color: pager.silenced ? pager.silencedColour
                     : (pager.globalSnoozed || pager.snoozed.length > 0) ? pager.snoozedColour
                     : pager.panelFg
                font.family: pager.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            // Snoozing everything sits beside the switch rather than in the
            // list below, because it is not a source: it is the same decision
            // as silencing, with an end time on it - which is the one most
            // people actually want. "Not for the next hour", rather than "not
            // until I remember I turned this off".
            trailingControl: Component {
              Row {
                spacing: Style.space(6)

                PanelActionButton {
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: pager.globalSnoozed ? pager.bell : pager.bellSleep
                  tooltipText: pager.globalSnoozed ? "Let everything through now"
                                                   : "Snooze everything for a while"
                  foreground: pager.globalSnoozed ? pager.snoozedColour : pager.panelFg
                  fontFamily: pager.fontFamily
                  onClicked: {
                    if (pager.globalSnoozed) pager.service.unsnooze(pager.service.globalKey)
                    else pager.globalChoosing = !pager.globalChoosing
                  }
                }

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  // On means notifications are coming through, which is the
                  // way round anyone reads a switch on a thing called
                  // Notifications. Off is a state you chose.
                  checked: !pager.quiet
                  foreground: pager.panelFg
                  onToggled: pager.quiet ? pager.letEverythingThrough() : pager.toggleSilence()
                }
              }
            }
          }

          // The lengths, revealed by the snooze button rather than sitting
          // under the title the whole time.
          Row {
            width: parent.width
            spacing: Style.space(5)
            visible: pager.globalChoosing && !pager.globalSnoozed

            Repeater {
              model: pager.globalChoosing && pager.service ? pager.service.snoozeOptions : []

              Button {
                required property var modelData
                text: String(modelData.short)
                bordered: true
                foreground: pager.panelFg
                accent: pager.panelFg
                fontFamily: pager.fontFamily
                fontSize: Style.font.caption
                verticalPadding: 1
                onClicked: pager.snoozeEverything(Number(modelData.seconds))
              }
            }
          }

          PanelSeparator { foreground: pager.panelFg }

          PanelSectionHeader {
            text: pager.quiet ? "HELD BACK" : "SNOOZED SOURCES"
            foreground: pager.panelFg
            fontFamily: pager.fontFamily
          }

          Text {
            visible: pager.sources.length === 0
            width: parent.width
            text: pager.quiet
                  ? "Nothing has been held back yet."
                  : "Nothing is snoozed. Right-click a notification to quieten the app or site it came from."
            color: pager.dim
            font.family: pager.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: pager.sources

              Column {
                id: line
                required property var modelData
                required property int index
                readonly property bool expanded: pager.expandedKey === modelData.key
                readonly property bool snoozedByName: modelData.until > 0
                property bool choosing: false
                width: parent.width
                spacing: 0

                Item {
                  width: parent.width
                  height: Math.max(label.implicitHeight, Style.space(24))

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: -Style.space(3)
                    radius: Style.cornerRadius
                    visible: pager.cursorLive && pager.cursorAt === line.index
                    color: Qt.rgba(pager.panelFg.r, pager.panelFg.g, pager.panelFg.b, 0.08)
                  }

                  Column {
                    id: label
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - controls.width - Style.space(10)

                    Text {
                      width: parent.width
                      text: line.modelData.label
                      color: pager.panelFg
                      font.family: pager.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      // Two facts, and both are worth saying: when it comes
                      // back, and what it has cost so far.
                      text: {
                        var count = line.modelData.held.length
                        var caught = count === 0 ? "" : (count === 1 ? "1 held" : count + " held")
                        if (!line.snoozedByName) return caught
                        var back = "back " + pager.waking(line.modelData.until)
                        return caught ? (back + " · " + caught) : back
                      }
                      color: pager.dim
                      font.family: pager.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: label
                    enabled: line.modelData.held.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pager.expandedKey = line.expanded ? "" : line.modelData.key
                  }

                  Row {
                    id: controls
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)

                    // The lengths on offer, revealed rather than always
                    // present: four numbers on every row is a wall, and most
                    // of the time the button you want is the one that wakes it.
                    Row {
                      spacing: Style.space(3)
                      visible: line.choosing

                      Repeater {
                        model: line.choosing && pager.service ? pager.service.snoozeOptions : []

                        Button {
                          required property var modelData
                          text: String(modelData.short)
                          bordered: true
                          foreground: pager.panelFg
                          accent: pager.panelFg
                          fontFamily: pager.fontFamily
                          fontSize: Style.font.caption
                          verticalPadding: 1
                          // From now, not on top of what is left: the button
                          // says four hours, so it had better mean four hours.
                          onClicked: {
                            pager.service.snoozeSource(line.modelData.key, line.modelData.label,
                                                       Number(modelData.seconds), true)
                            line.choosing = false
                          }
                        }
                      }
                    }

                    PanelActionButton {
                      visible: line.modelData.held.length > 0
                      iconText: line.expanded ? "\u{f0143}" : "\u{f0140}"   // chevron up / down
                      tooltipText: line.expanded ? "Hide what it held" : "See what it held"
                      foreground: pager.panelFg
                      fontFamily: pager.fontFamily
                      onClicked: pager.expandedKey = line.expanded ? "" : line.modelData.key
                    }

                    PanelActionButton {
                      iconText: line.choosing ? "✕" : "\u{f0150}"     // close / clock
                      tooltipText: line.choosing ? "Leave it as it is"
                                 : (line.snoozedByName ? "Snooze for longer" : "Snooze this source")
                      foreground: pager.panelFg
                      fontFamily: pager.fontFamily
                      onClicked: line.choosing = !line.choosing
                    }

                    PanelActionButton {
                      visible: line.snoozedByName
                      iconText: "\u{f009a}"                 // nf-md-bell
                      tooltipText: "Wake it now"
                      foreground: pager.panelFg
                      fontFamily: pager.fontFamily
                      onClicked: pager.service.unsnooze(line.modelData.key)
                    }
                  }
                }

                // What it caught while you were not being told. Capped, and
                // one line each: this is for recognising what you missed, not
                // for reading it - those notifications are gone.
                Item {
                  width: parent.width
                  height: line.expanded ? heldList.implicitHeight + Style.space(8) : 0
                  visible: height > 0
                  clip: true
                  Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                  Column {
                    id: heldList
                    width: parent.width - Style.space(12)
                    x: Style.space(12)
                    y: Style.space(4)
                    spacing: Style.space(1)

                    Repeater {
                      model: line.expanded ? line.modelData.held : []

                      // The time, the headline, and as much of the message as
                      // fits. Three notifications from the same person all say
                      // that person's name and nothing else, so the headline
                      // alone is not enough to tell them apart.
                      Text {
                        required property var modelData
                        width: parent.width
                        text: {
                          var when = Qt.formatDateTime(new Date(Number(modelData.ts) * 1000), "HH:mm")
                          var head = String(modelData.summary || "")
                          var rest = String(modelData.bodyLine || "")
                          if (head && rest) return when + "  " + head + " · " + rest
                          return when + "  " + (head || rest)
                        }
                        color: pager.dim
                        font.family: pager.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }
                }
              }
            }
          }

          Button {
            visible: pager.quiet || pager.snoozed.length > 1
            width: parent.width
            text: "Let everything through"
            bordered: true
            foreground: pager.panelFg
            fontFamily: pager.fontFamily
            fontSize: Style.font.caption
            onClicked: {
              pager.letEverythingThrough()
              if (pager.service) pager.service.unsnoozeAll()
            }
          }
        }
      }
    }
  }
}
