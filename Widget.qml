// The bar indicator, and the panel behind it.
//
// Nothing held back, nothing on the bar. omapager takes a slot only when it is
// keeping something from you - the desktop is silenced, or a source has been
// snoozed - which is Omarchy's own convention for status icons: they appear
// when there is a state to report and are otherwise revealed by hovering the
// centre of the bar. A bell that is always there, always showing zero, is a
// permanent reminder of nothing.
//
// So there are exactly two states worth a glyph, and they are the two you
// cannot discover any other way. What is on screen needs no icon: it is on
// screen.

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
  readonly property var snoozed: {
    snoozeRevision
    return service ? service.liveSnoozes() : []
  }

  readonly property bool hasState: silenced || snoozed.length > 0

  // Shown when there is something to say, while the panel is open, and on the
  // same bar-centre gesture that reveals Omarchy's own inactive indicators -
  // otherwise there would be no way back to silence once you left it.
  readonly property bool revealed: hasState || opened
    || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)

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
    // Empty means "none chosen", not "no snoozing" - fall back rather than
    // leaving a menu with nothing in it.
    var chosen = setting("snoozeDurations", null)
    if (chosen && chosen.length > 0) service.snoozeChoices = chosen
  }

  onSettingsChanged: applySettings()
  onServiceChanged: applySettings()
  Component.onCompleted: applySettings()

  readonly property color panelFg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(panelFg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // nf-md-bell-off, the glyph Omarchy's own Dnd indicator uses, so a silenced
  // desktop looks the same whichever service is running; nf-md-sleep, which is
  // a literal "zzz"; nf-md-bell-outline for the resting state.
  readonly property string bellOff: "\u{f009b}"
  readonly property string zzz: "\u{f04b2}"
  readonly property string bell: "\u{f009c}"

  // Collapsed to nothing when there is nothing to report: an empty slot in the
  // bar is still a gap in the bar.
  clip: true
  implicitWidth: vertical ? Math.max(glyphs.implicitWidth, barSize)
                          : (revealed ? glyphs.implicitWidth : 0)
  implicitHeight: vertical ? (revealed ? glyphs.implicitHeight : 0)
                           : Math.max(glyphs.implicitHeight, barSize)

  Behavior on implicitWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

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

  // Left silences, right opens the panel. The fastest thing anyone wants from
  // a notification indicator is for it to stop, so that is the plain click;
  // the panel is where you go when you want to look at something rather than
  // change it, which is what a right-click means everywhere else.
  function pressed(buttonCode) {
    if (buttonCode === Qt.RightButton) togglePanel()
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
    function open(): string { controller.show(); return "open" }
    function close(): string { controller.hide(); return "closed" }
    function toggle(): string { pager.togglePanel(); return controller.open ? "open" : "closed" }
    function state(): string {
      return JSON.stringify({ opened: pager.opened, panelVisible: panel.visible,
                              panelOpen: panel.open, hasBar: !!pager.bar,
                              hasScreen: !!panel.screen,
                              anchorW: glyphs.width, revealed: pager.revealed,
                              widgetW: pager.width,
                              cardX: panel.cardOrigin.x, cardY: panel.cardOrigin.y,
                              cw: panel.contentWidth, ch: panel.contentHeight,
                              colH: column.implicitHeight, colW: column.width })
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
      tooltipText: "Silenced - click to let them through, right-click for options"
    }

    Indicator {
      visible: pager.snoozed.length > 0 && !pager.silenced
      text: pager.zzz
      tooltipText: (pager.snoozed.length === 1
                    ? (pager.snoozed[0].label + " snoozed " + pager.waking(pager.snoozed[0].until))
                    : (pager.snoozed.length + " sources snoozed"))
                   + " - right-click for options"
    }

    // The resting bell, which only ever appears while the bar's inactive
    // indicators are being revealed. It is the way back into silence.
    Indicator {
      visible: !pager.hasState
      text: pager.bell
      quiet: true
      tooltipText: "Silence notifications - right-click for options"
    }
  }

  component Indicator: BarIconButton {
    property bool quiet: false
    bar: pager.bar
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: controller.hide()
      onMoveRequested: function(dx, dy) {
        if (dy === 0 || pager.snoozed.length === 0) return
        pager.cursorAt = Math.max(0, Math.min(pager.snoozed.length - 1, pager.cursorAt + dy))
        pager.cursorLive = true
      }
      onActivateRequested: {
        if (pager.cursorLive && pager.cursorAt < pager.snoozed.length)
          pager.service.unsnooze(pager.snoozed[pager.cursorAt].key)
        else pager.toggleSilence()
      }
      onTextKey: function(t) {
        if (t === "s" || t === "S") pager.toggleSilence()
        else if (t === "w" || t === "W") pager.service.unsnoozeAll()
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
                text: pager.silenced ? pager.bellOff : (pager.snoozed.length > 0 ? pager.zzz : pager.bell)
                color: pager.panelFg
                font.family: pager.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                checked: pager.silenced
                foreground: pager.panelFg
                onToggled: pager.toggleSilence()
              }
            }
          }

          PanelSeparator { foreground: pager.panelFg }

          PanelSectionHeader {
            text: "SNOOZED SOURCES"
            foreground: pager.panelFg
            fontFamily: pager.fontFamily
          }

          Text {
            visible: pager.snoozed.length === 0
            width: parent.width
            text: "Nothing is snoozed. Right-click a notification to quieten the app or site it came from."
            color: pager.dim
            font.family: pager.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: pager.snoozed

              Item {
                id: line
                required property var modelData
                required property int index
                property bool choosing: false
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
                    text: "back " + pager.waking(line.modelData.until)
                    color: pager.dim
                    font.family: pager.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: controls
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  // The lengths on offer, revealed rather than always present:
                  // four numbers on every row is a wall, and most of the time
                  // the button you want is the one that wakes it.
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
                    iconText: line.choosing ? "\u2715" : "\u{f0150}"    // close / clock
                    tooltipText: line.choosing ? "Leave it as it is" : "Snooze for longer"
                    foreground: pager.panelFg
                    fontFamily: pager.fontFamily
                    onClicked: line.choosing = !line.choosing
                  }

                  PanelActionButton {
                    iconText: "\u{f009a}"                 // nf-md-bell
                    tooltipText: "Wake it now"
                    foreground: pager.panelFg
                    fontFamily: pager.fontFamily
                    onClicked: pager.service.unsnooze(line.modelData.key)
                  }
                }
              }
            }
          }

          Button {
            visible: pager.snoozed.length > 1
            width: parent.width
            text: "Wake everything"
            bordered: true
            foreground: pager.panelFg
            fontFamily: pager.fontFamily
            fontSize: Style.font.caption
            onClicked: pager.service.unsnoozeAll()
          }
        }
      }
    }
  }

  // Which snoozed source the keyboard is on. Dormant until an arrow key is
  // pressed, so opening the panel with the pointer does not put a highlight
  // on a row nobody asked about.
  property int cursorAt: 0
  property bool cursorLive: false
  onOpenedChanged: { cursorAt = 0; cursorLive = false }
}
