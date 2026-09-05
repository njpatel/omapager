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

  // Left opens the panel, right silences. The fastest thing anyone can want
  // from a notification bell is for it to stop, so it stays one click away.
  function pressed(buttonCode) {
    if (buttonCode === Qt.RightButton) toggleSilence()
    else togglePanel()
  }

  // "in 24m", "in 3h", "until 08:00" once it is far enough out that the
  // remaining minutes stop being the useful half.
  function waking(until) {
    var left = Math.max(0, until - Date.now() / 1000)
    if (left < 3600) return "in " + Math.max(1, Math.round(left / 60)) + "m"
    if (left < 8 * 3600) return "in " + Math.round(left / 3600) + "h"
    return "until " + Qt.formatDateTime(new Date(until * 1000), "HH:mm")
  }

  readonly property string stateLine: {
    if (silenced) return "Silenced"
    if (snoozed.length === 1) return snoozed[0].label + ", back " + waking(snoozed[0].until)
    if (snoozed.length > 1) return snoozed.length + " sources snoozed"
    return "Everything comes through"
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
      tooltipText: "Notifications silenced - click for options"
    }

    Indicator {
      visible: pager.snoozed.length > 0 && !pager.silenced
      text: pager.zzz
      tooltipText: pager.snoozed.length === 1
                   ? (pager.snoozed[0].label + " snoozed " + pager.waking(pager.snoozed[0].until))
                   : (pager.snoozed.length + " sources snoozed")
    }

    // The resting bell, which only ever appears while the bar's inactive
    // indicators are being revealed. It is the way back into silence.
    Indicator {
      visible: !pager.hasState
      text: pager.bell
      quiet: true
      tooltipText: "Silence notifications"
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
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

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
                  spacing: Style.space(2)

                  PanelActionButton {
                    iconText: "\u{f0415}"                 // nf-md-clock-plus
                    tooltipText: "Another half hour"
                    foreground: pager.panelFg
                    fontFamily: pager.fontFamily
                    onClicked: pager.service.snoozeSource(line.modelData.key,
                                                         line.modelData.label, 1800)
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
