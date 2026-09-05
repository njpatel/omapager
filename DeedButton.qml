// One thing a notification can do, as a button with its name on it.
//
// Omarchy's own Button, not a shape of our own: it carries the theme's control
// fills, border specs, focus ring and padding, all of which come from
// [controls] in the theme's shell.toml. A hand-rolled pill looked close on one
// theme and wrong on the next, and it quietly ignored every control token the
// desktop has.

import QtQuick
import qs.Commons
import qs.Ui

Button {
  id: button

  property var deed: ({})
  // Not "card": the toast's id is `card`, so a property of that name binds to
  // itself rather than to the toast, sits there as null, and every click dies
  // on it silently.
  property var toast: null
  property bool wide: false

  readonly property bool taken: toast && toast.takenKind === String(deed.kind)

  // Under the pointer? Worked out from where the deck says the pointer is,
  // because this button never receives hover itself - the deck's hover region
  // is above every card and takes it first.
  readonly property bool hot: {
    if (!toast || !toast.hovered) return false
    var origin = mapToItem(toast, 0, 0)
    var px = toast.localHoverX, py = toast.localHoverY
    return px >= origin.x && px <= origin.x + width
        && py >= origin.y && py <= origin.y + height
  }

  // A tick, not a word: "Copied" was being shown for "Open link" too, and a
  // per-verb past tense would change the button's width the moment you
  // pressed it. The mark means "that happened" whatever the verb was.
  text: taken ? "\u{f012c}" : String(deed.label || "")

  bordered: true
  hasCursor: hot                      // paints the theme's hover state
  foreground: Color.notifications.text
  accent: Color.notifications.border
  fontFamily: Style.font.family
  fontSize: Style.font.caption
  verticalPadding: Math.max(2, Style.spacing.controlPaddingY - 2)

  // Full width in the "More" list, its own width in the row.
  leftAlign: wide
  width: wide && parent ? parent.width : implicitWidth

  onClicked: button.toast.doDeed(button.deed)
}
