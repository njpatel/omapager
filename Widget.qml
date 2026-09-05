// The bar bell.
//
// State and two actions, nothing behind it. There used to be a notification
// centre here - a list of everything the store had kept, grouped by source -
// and it was removed on purpose. On Android and macOS a notification centre
// works because the app owns the notification: read the message in Slack and
// the entry disappears everywhere, because Slack tells the system it has been
// handled. Freedesktop has CloseNotification for that, and almost nobody calls
// it: Chrome does not close a web notification when you read the tab,
// notify-send cannot, and a script that fired one has already exited. So
// "outstanding" could only ever mean "omapager has not seen you click it",
// which stops matching reality within minutes, and the centre fills up with
// things already dealt with. A list you have to prune by hand is worse than no
// list. What the daemon *can* know honestly is what is on screen right now,
// and that is the deck.

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "njpatel.omapager"

  // The daemon, if it is up. Everything that reads it degrades to empty rather
  // than breaking the bar.
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("njpatel.omapager") : null
  readonly property bool dnd: service ? service.doNotDisturb : false
  readonly property int liveCount: service ? service.toastCount : 0

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: row.implicitWidth
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Row {
    id: row
    anchors.centerIn: parent

    BarIconButton {
      id: bell
      bar: root.bar
      // nf-md-bell-off-outline / nf-md-bell (solid) / nf-md-bell-outline.
      // Hollow means nothing waiting, filled means something is. The first two
      // used to be F09A2 and F00FA, which are not bells at all in this font -
      // they render as a Bluetooth speaker and a down-left arrow, so the bar
      // spent nearly all its time showing an arrow nobody could explain.
      text: root.dnd ? "\u{f0a91}" : (root.liveCount > 0 ? "\u{f009a}" : "\u{f009c}")
      active: root.liveCount > 0 && !root.dnd
      onPressed: function(buttonCode) { root.bellPressed(buttonCode) }
    }

    Text {
      id: count
      anchors.verticalCenter: parent.verticalCenter
      visible: root.liveCount > 0 && !(root.bar && root.bar.vertical)
      text: String(root.liveCount)
      color: root.bar ? root.bar.barForeground : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      rightPadding: Style.space(6)

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: function(mouse) { root.bellPressed(mouse.button) }
      }
    }
  }

  // Both actions are things the daemon actually knows: what is on screen, and
  // whether to show the next one. Right-click silences, because the fastest
  // thing you can want from a notification bell is for it to stop.
  function bellPressed(buttonCode) {
    if (!service) return
    if (buttonCode === Qt.RightButton) service.doNotDisturb = !service.doNotDisturb
    else service.clearAll("dismissed")
  }
}
