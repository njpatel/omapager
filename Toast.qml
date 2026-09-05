// One notification card, in every state it has.
//
// The card never decides where it goes - Layout.js does that and hands it a
// placement. What the card owns is how it gets there (springs for anything the
// pointer caused, curves for anything the clock caused) and how long it lives.

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

import qs.Ui

import "Markup.js" as Markup

Item {
  id: card

  property var row: ({})
  property var place: ({ y: 0, scale: 1, opacity: 1, z: 1, front: true, hidden: false })
  property bool expanded: false
  property bool paused: false
  property bool hovered: false
  property double now: Date.now()

  // "now" for the first minute, then minutes, then the clock time it arrived
  // at, then the day. Long enough ago and the exact minute stops mattering.
  function ago() {
    var t = Number(row.ts || 0) * 1000
    if (!t) return ""
    var s = Math.max(0, (now - t) / 1000)
    if (s < 50) return "now"
    if (s < 3600) return Math.round(s / 60) + "m"
    var then = new Date(t)
    var sameDay = new Date(now).toDateString() === then.toDateString()
    if (sameDay) return Qt.formatDateTime(then, "HH:mm")
    var yest = new Date(now - 86400000).toDateString() === then.toDateString()
    if (yest) return "yesterday"
    return Qt.formatDateTime(then, "ddd")
  }
  property real cardWidth: Style.space(340)

  signal expired()
  signal swipeMoved(real dx)
  signal swipeEnded(bool away)
  signal activated()
  signal dismissed()
  signal snoozeRequested(int seconds)
  signal silenceRequested()

  readonly property bool critical: row.urgency === 2
  // A card behind the front one in a collapsed deck is a shape, not a message:
  // the cards are translucent, so its text would otherwise read straight
  // through the card in front of it.
  readonly property bool showsContent: expanded || place.front
  readonly property int stands: place.count || 1     // how many this card speaks for

  // Everything this card can do, in one row: what it found in its own text
  // first, then what the sender said it supports. Spelled out rather than
  // hinted at with an icon - a verification code hiding behind a key glyph is
  // a puzzle, and on a desktop where almost nothing carries actions, nobody
  // thinks to hover looking for them. What is written on the button is what
  // happens when you press it.
  readonly property var allDeeds: {
    var out = []
    if (String(row.code || ""))
      out.push({ kind: "code", label: "Copy code", value: String(row.code) })
    if (String(row.link || ""))
      out.push({ kind: row.meeting ? "meeting" : "link",
                 label: row.meeting ? "Join" : "Open link", value: String(row.link) })
    if (String(row.phone || ""))
      out.push({ kind: "phone", label: "Copy number", value: String(row.phone) })
    if (String(row.filePath || ""))
      out.push({ kind: "path", label: "Open file", value: String(row.filePath) })
    if (String(row.replyPath || ""))
      out.push({ kind: "reply", label: "Reply", value: "" })
    for (var i = 0; i < actions.length; i++) {
      // The phone's own "Reply" action opens a window somewhere else; ours
      // types the answer here, so it wins and the duplicate is dropped.
      if (String(row.replyPath || "") && /^reply$/i.test(String(actions[i].text || "")))
        continue
      out.push({ kind: "action", label: String(actions[i].text || ""), value: String(actions[i].id) })
    }
    return out
  }

  // What the card is holding, as marks rather than buttons. Buttons cost
  // height, and a collapsed deck draws every card at the height of the
  // tallest - so one card with two buttons padded out every other card on
  // screen. A mark says "there is something here" for free, and the buttons
  // themselves appear when the pointer is actually on the card.
  readonly property var marks: {
    var out = []
    if (String(row.code || "")) out.push("\u{f0306}")
    if (String(row.link || "")) out.push(row.meeting ? "\u{f0567}" : "\u{f0339}")
    if (String(row.phone || "")) out.push("\u{f03f2}")
    if (String(row.filePath || "")) out.push("\u{f0214}")
    if (actions.length > 0) out.push("\u{f01d9}")
    return out
  }

  // Three buttons is what fits across a card without the labels shrinking.
  // Past that the last slot becomes "More", which opens the lot as a list
  // rather than a floating menu: this surface is clipped, and a popup that can
  // be cut off is worse than one more row.
  readonly property int fits: 3
  readonly property bool overflows: allDeeds.length > fits
  readonly property var deeds: allDeeds.slice(0, overflows ? fits - 1 : fits)
  readonly property var spare: overflows ? allDeeds.slice(fits - 1) : []
  property bool deedsOpen: false
  property bool menuOpen: false
  property string actionsAlign: "right"      // right | left

  // Right-clicking a card asks about the source rather than about the message:
  // stop this one talking for a while, or stop everything. The lengths on
  // offer are the daemon's, which are the ones from settings - a desktop where
  // half an hour is the useful unit and one where half a day is are both real.
  property var snoozeOptions: []

  readonly property var menuDeeds: {
    var out = []
    for (var i = 0; i < snoozeOptions.length; i++)
      out.push({ kind: "snooze", label: String(snoozeOptions[i].menuLabel),
                 value: Number(snoozeOptions[i].seconds) })
    out.push({ kind: "silence", label: "Silence everything", value: 0 })
    return out
  }

  // The pointer, in the deck's coordinates, handed down from the one region
  // that is allowed to see it. Cards convert it to their own space so the
  // buttons inside them can light up.
  property real hoverX: -1
  property real hoverY: -1
  readonly property real localHoverX: hoverX - x
  readonly property real localHoverY: hoverY - y

  function doDeed(deed) {
    var kind = String(deed.kind || "")
    if (kind === "more") { deedsOpen = !deedsOpen; return }
    if (kind === "snooze") { menuOpen = false; snoozeRequested(Number(deed.value)); return }
    if (kind === "silence") { menuOpen = false; silenceRequested(); return }
    if (kind === "reply") { menuOpen = false; replyRequested(); return }
    if (kind === "action") { actionInvoked(String(deed.value)); return }
    offerTaken(kind, String(deed.value))
    takenKind = kind
    tick.restart()
  }

  signal offerTaken(string kind, string value)

  // What the sender itself said can be done. These are not guesses: the app
  // put them on the wire. A restored card has none, because the sender that
  // would have to carry them out is gone.
  property var actions: []
  signal actionInvoked(string identifier)

  // Replying to a message forwarded from the phone.
  property bool replying: false
  signal replyRequested()
  signal replySent(string text)
  signal replyCancelled()

  // Which one was just pressed, so its label can say so for a moment. Copying
  // to a clipboard is completely silent otherwise: you click, nothing moves,
  // and you click again to be sure.
  property string takenKind: ""
  Timer { id: tick; interval: 1400; onTriggered: card.takenKind = "" }

  // The card's own clock. One ticker drives both the countdown and the expiry,
  // so what you see and what happens cannot drift apart; pausing holds the
  // remaining time rather than restarting it, because a card you stopped to
  // read should not lose the seconds you spent reading it.
  property real remaining: Number(row.duration || 0)
  readonly property bool ticking: Number(row.duration || 0) > 0 && !paused && !replying
  onRowChanged: remaining = Number(row.duration || 0)

  Timer {
    interval: 100
    repeat: true
    running: card.ticking && card.remaining > 0
    onTriggered: {
      card.remaining -= interval
      if (card.remaining <= 0) card.expired()
    }
  }

  width: cardWidth
  height: body.height
  implicitHeight: body.implicitHeight

  onHoveredChanged: if (!hovered) menuOpen = false
  onExpandedChanged: if (!expanded) menuOpen = false

  y: place.y
  z: place.z
  opacity: place.hidden ? 0 : place.opacity
  scale: place.scale
  transformOrigin: Item.Top
  visible: opacity > 0.01

  // Every card in the deck moves on the same curve for the same length of
  // time, so an arrival reads as the stack being pushed down together rather
  // than as each card springing independently. Springs were the "hectic"
  // feeling: each card oscillating on its own schedule.
  readonly property var deckCurve: [0.21, 1.02, 0.73, 1.0, 1.0, 1.0]
  readonly property int deckDuration: 400

  Behavior on y {
    NumberAnimation { duration: card.deckDuration; easing.type: Easing.Bezier
                      easing.bezierCurve: card.deckCurve }
  }
  Behavior on scale {
    NumberAnimation { duration: card.deckDuration; easing.type: Easing.Bezier
                      easing.bezierCurve: card.deckCurve }
  }
  Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

  // Arrival: it lands. The card drops the short distance into its place at
  // the front of the deck while the cards already there move down by exactly
  // one peek - one motion, one curve, no overshoot. Coming in from the side
  // made every arrival look like it had knocked the stack over.
  property real slide: 0          // horizontal, used only for dismissal
  property real drop: 0           // vertical, used only for arrival
  property real enterFade: 1      // multiplied into both halves of the card
  property real swipe: 0          // how far it has been dragged toward the edge
  transform: Translate { x: card.slide + card.swipe; y: card.drop }

  Component.onCompleted: enterAnim.start()

  ParallelAnimation {
    id: enterAnim
    // It comes down from the bar and settles - a short, unhurried fall from
    // just under the panel rather than a dart in from the edge of the screen.
    NumberAnimation {
      target: card; property: "drop"; from: -Style.space(30); to: 0
      duration: 480; easing.type: Easing.Bezier
      easing.bezierCurve: card.deckCurve
    }
    NumberAnimation {
      target: card; property: "enterFade"; from: 0; to: 1
      duration: 380; easing.type: Easing.OutCubic
    }
    // Fades the body, not the card: the card's opacity carries a Behavior,
    // and animating a property that has one restarts it every frame.
    NumberAnimation {
      target: body; property: "opacity"; from: 0; to: 1
      duration: 260; easing.type: Easing.OutQuad
    }
  }

  // Departure by hand goes right, out the way it came in; an expiry just
  // fades. A deliberate action should not look like a timeout.
  function playExit(byHand) {
    exitAnim.toX = byHand ? Style.space(34) : 0
    exitAnim.start()
  }
  ParallelAnimation {
    id: exitAnim
    property real toX: 0
    NumberAnimation { target: card; property: "slide"; to: exitAnim.toX; duration: 200; easing.type: Easing.OutQuad }
    NumberAnimation { target: card; property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutQuad }
  }

  // The card is drawn in two pieces. This one is the plate: the background,
  // the border and - crucially - the shadow, with no children at all. A
  // MultiEffect re-renders its entire blurred source whenever the item it is
  // attached to repaints, and the countdown ticks ten times a second, so with
  // the shadow on the card itself every tick re-blurred the whole card. Eight
  // notifications was enough to peg the shell at 60% of a core.
  // Two shadows, not one.
  //
  // A single blur at a single offset is the giveaway of a drawn shadow: real
  // light gives an object a wide, weak cast from the room and a small, darker
  // one where it nearly touches the surface. Two layers cost two static
  // textures per card and are the whole difference between "there is a shadow
  // here" and the card sitting on the desktop.
  Rectangle {
    id: farShadow
    x: plate.x
    y: plate.y
    width: plate.width
    height: plate.height
    radius: plate.radius
    color: plate.color
    opacity: card.enterFade
    visible: !card.place.hidden

    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: Qt.rgba(0, 0, 0, card.place.front ? 0.26 : 0.16)
      shadowBlur: 1.0
      shadowVerticalOffset: Style.space(7)
      shadowHorizontalOffset: 0
      shadowScale: 1.01
    }
  }

  Rectangle {
    id: plate
    x: body.x
    width: body.width
    height: body.height
    radius: Math.max(Style.cornerRadius, Style.space(4))
    antialiasing: true
    // Solid. Translucency over blur looked good for one card and turned a
    // stack into something you could not read: the card behind showed through
    // the one in front of it, and every deck became a smear.
    color: Color.notifications.background
    border.width: card.place.front && !card.expanded ? 2 : 1
    // Only the card you are dealing with is outlined: the front one when the
    // deck is shut, the one under the pointer when it is open. On the rest a
    // full-strength border just draws a box around something you are not
    // reading. Critical keeps its edge wherever it sits.
    readonly property bool outlined: card.critical
                                     || (card.expanded ? card.hovered : card.place.front)
    border.color: card.critical
                  ? Qt.rgba(Color.notifications.countdown.r, Color.notifications.countdown.g,
                            Color.notifications.countdown.b, 0.85)
                  : Qt.rgba(Color.notifications.border.r, Color.notifications.border.g,
                            Color.notifications.border.b, outlined ? 0.38 : 0.10)
    Behavior on border.color { ColorAnimation { duration: 180 } }

    opacity: card.enterFade

    layer.enabled: true
    layer.effect: MultiEffect {
      // The near shadow: small, tight, and the darkest of the two. This is
      // the one that says the card is resting just above the desktop rather
      // than floating somewhere above it.
      shadowEnabled: true
      shadowColor: Qt.rgba(0, 0, 0, card.place.front ? 0.34 : 0.22)
      shadowBlur: 0.34
      shadowVerticalOffset: Style.space(2)
      shadowHorizontalOffset: 0
      shadowScale: 1.0
    }
  }

  // And this one is everything that changes: text, icon, countdown. No layer,
  // so it can repaint as often as it likes.
  Item {
    id: body
    opacity: card.enterFade
    x: 0
    width: parent.width
    // Twice the inset the row sits at, so the space above the content and the
    // space below it are the same number. A flat 18 against an inset of 12
    // left 12 above and 6 below, which is invisible on a one-line card and
    // obvious on a two-line one.
    implicitHeight: layout.implicitHeight + Style.space(12) * 2
    height: card.place.height || implicitHeight

    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Row {
      id: layout
      // Anchored to the top, not centred. A card grows downwards when its
      // buttons or its reply field appear, and content hung off the centre
      // line slides up by half of whatever was added - so the words move while
      // you are reading them.
      anchors { left: parent.left; right: parent.right; top: parent.top
                leftMargin: Style.space(12); rightMargin: Style.space(12)
                topMargin: Style.space(12) }
      spacing: Style.space(11)

      // Every notification gets a mark, whether or not the sender sent one:
      // the sender's image, else its themed icon, else the first letter of
      // wherever it came from. A card with a hole where the icon should be
      // reads as broken rather than as minimal.
      Item {
        id: thumb
        width: Style.space(32)
        height: width
        // Centred against the text beside it: pinned to the top, it floats
        // above nothing on a two-line card.
        y: Math.max(0, (layout.implicitHeight - height) / 2)
        opacity: card.showsContent ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        readonly property bool mono: String(picture.source).indexOf("-mono.png") >= 0

        readonly property string sent: {
          var src = String(card.row.stored_image || card.row.image || "")
          if (!src) return ""
          return src.indexOf("file://") === 0 || src.indexOf("image://") === 0 ? src : "file://" + src
        }
        // The sender's own picture, or whatever omapager-icon resolved for
        // this source - which includes looking up the name the sender gave.
        // Nothing else: Quickshell.iconPath happily returns a provider URL for
        // an icon that does not exist, and that draws as a checkerboard.
        readonly property string best: sent

        Rectangle {
          anchors.fill: parent
          radius: Style.space(4)
          visible: picture.status !== Image.Ready
          color: Qt.rgba(Color.notifications.text.r, Color.notifications.text.g,
                         Color.notifications.text.b, 0.10)

          Text {
            anchors.centerIn: parent
            text: String(card.row.source || card.row.app || "?").substring(0, 1).toUpperCase()
            color: Color.notifications.text
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
          }
        }

        // A one-colour glyph is painted in the theme's text colour rather
        // than drawn as it came, or a dark mark disappears into a dark card.
        Rectangle {
          anchors.fill: parent
          visible: thumb.mono && picture.status === Image.Ready
          color: Color.notifications.text
          opacity: 0.85
          layer.enabled: visible
          layer.effect: MultiEffect { maskEnabled: true; maskSource: picture }
        }

        Image {
          id: picture
          anchors.fill: parent
          visible: status === Image.Ready && !thumb.mono
          source: thumb.best
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: Style.space(64)
          sourceSize.height: Style.space(64)
          layer.enabled: visible
          layer.effect: MultiEffect { maskEnabled: true; maskSource: mask }
        }

        Rectangle {
          id: mask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          radius: Style.space(4)
          color: "black"
        }
      }

      Column {
        width: layout.width - thumb.width - layout.spacing
        spacing: Style.space(3)

        // Title, then how many this one stands for, then when it arrived.
        // The sender's name used to sit above this; it says "notify-send" more
        // often than it says anything useful, so it now only picks the icon.
        Item {
          width: parent.width
          height: title.implicitHeight
          opacity: card.showsContent ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 160 } }

          Text {
            id: title
            anchors.left: parent.left
            width: parent.width - rightSide.width
                   - (badge.visible ? badge.width + Style.space(6) : 0)
                   - (titleMarks.visible ? titleMarks.width + Style.space(7) : 0)
                   - Style.space(8)
            text: String(card.row.summary || "")
            color: Color.notifications.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            maximumLineCount: 1
            elide: Text.ElideRight
          }

          // Straight after the title, at the title's size and in the theme's
          // foreground. No chip: tried as an inverted pill beside the time and
          // as a badge on the corner of the app icon, and both read as heavy -
          // the badge version also stacked leftwards off the icon as soon as a
          // card had more than one thing to offer, which is the normal case.
          // As glyphs on the headline they are part of the sentence.
          Row {
            id: titleMarks
            visible: card.marks.length > 0
            anchors.verticalCenter: title.verticalCenter
            x: title.x + Math.min(title.implicitWidth, title.width) + Style.space(7)
            spacing: Style.space(5)

            Repeater {
              model: card.marks
              Text {
                required property var modelData
                text: modelData
                color: Color.notifications.text
                opacity: 0.9
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          Rectangle {
            id: badge
            // The row, not the time inside it: anchoring across into another
            // item's children is not a sibling relationship and Qt refuses it.
            anchors.right: rightSide.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: title.verticalCenter
            visible: card.stands > 1
            width: badgeText.implicitWidth + Style.space(9)
            height: badgeText.implicitHeight + Style.space(3)
            radius: height / 2
            color: Qt.rgba(Color.notifications.text.r, Color.notifications.text.g,
                           Color.notifications.text.b, 0.16)

            Text {
              id: badgeText
              anchors.centerIn: parent
              text: String(card.stands)
              color: Color.notifications.text
              opacity: 0.85
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

          }

          // The time slides aside to make room for the dismiss control, and
          // slides back when the pointer goes. Two things swapping in the same
          // spot read as one thing changing its mind; moving one out of the
          // way of the other reads as an offer.
          // Everything at this end of the title sits in one row on the
          // title's centre line: the marks for what was found, the time, and
          // the close control. They used to be anchored separately, one to the
          // title's baseline and one to its centre, which put them at two
          // different heights.
          Row {
            id: rightSide
            anchors.right: parent.right
            anchors.verticalCenter: title.verticalCenter
            spacing: Style.space(5)

            // The time and the close control occupy the same square. Hover
            // crossfades between them rather than sliding the time aside: one
            // thing changing into another reads as a single control, and
            // nothing has to move to make room.
            Item {
              width: Math.max(stamp.implicitWidth, Style.space(18))
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: stamp
                anchors.centerIn: parent
                text: card.ago()
                color: Color.notifications.text
                opacity: card.hovered ? 0 : 0.6
                visible: opacity > 0.01
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                Behavior on opacity { NumberAnimation { duration: 150 } }
              }

              Rectangle {
                id: shut
                anchors.centerIn: parent
                width: Style.space(18)
                height: width
                radius: Math.max(2, Style.cornerRadius - 1)
                color: Qt.rgba(Color.notifications.text.r, Color.notifications.text.g,
                               Color.notifications.text.b, shutHit.containsMouse ? 0.22 : 0.12)
                opacity: card.hovered ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 140 } }

                Text {
                  anchors.centerIn: parent
                  text: "\u2715"
                  color: Color.notifications.text
                  opacity: shutHit.containsMouse ? 1.0 : 0.75
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: shutHit
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  enabled: card.hovered
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: card.dismissed()
                }
              }
            }
          }
        }

        // Two lines, always. Qt only elides plain text - a Text in RichText
        // mode ignores `elide` entirely - so a marked-up body just kept
        // growing. When the rich version does not fit, the flattened one is
        // shown instead, which can elide properly and ends in an ellipsis.
        FontMetrics {
          id: metrics
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        // Two lines of a notification body are one sentence that happened to
        // wrap, not two paragraphs, and the font's default leading makes them
        // read as further apart than they are.
        readonly property real bodyLeading: 0.92

        Item {
          id: bodyBox
          clip: true
          width: parent.width
          // As tall as the text actually is, one line or two - not a fixed
          // two, which left an empty second line under every one-line body and
          // made those cards read as top-heavy however carefully the padding
          // above and below was balanced.
          //
          // Measured from the laid-out height, never from `lineCount`: in
          // RichText mode lineCount counts paragraphs rather than wrapped
          // lines, so a single sentence that visibly takes two lines still
          // reports one - which sized the box to one line and clipped the rest.
          readonly property real lineH: Math.max(1, metrics.height * parent.bodyLeading)
          readonly property bool overflow: rich.contentHeight > lineH * 2.4
          // The height of the text that is actually on screen, capped at two
          // lines - not a line count derived from it. Rounding a measurement
          // into 1 or 2 and multiplying back out is where the clipped second
          // line came from: a body that needed a hair over one line rounded
          // down, and the rest was cut off inside a clipped box.
          readonly property real shown: overflow ? plain.contentHeight : rich.contentHeight
          height: Math.min(Math.ceil(lineH * 2), Math.ceil(shown))
          visible: String(card.row.body || "").length > 0
          opacity: card.showsContent ? 0.72 : 0
          Behavior on opacity { NumberAnimation { duration: 160 } }

          Text {
            id: rich
            width: parent.width
            visible: !bodyBox.overflow
            textFormat: Text.RichText
            text: Markup.colourLinks(String(card.row.bodyRich || card.row.body || ""),
                                     String(Color.notifications.countdown))
            color: Color.notifications.text
            lineHeight: bodyBox.parent.bodyLeading
            lineHeightMode: Text.ProportionalHeight
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            onLinkActivated: function(url) { Qt.openUrlExternally(url) }
          }

          Text {
            id: plain
            width: parent.width
            visible: bodyBox.overflow
            text: String(card.row.bodyLine || card.row.body || "")
            color: Color.notifications.text
            lineHeight: bodyBox.parent.bodyLeading
            lineHeightMode: Text.ProportionalHeight
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }


        }

        // Everything the card can do, written out. Visible whenever the card's
        // content is - not on hover - because an action nobody knows is there
        // may as well not exist. Three across is what fits; anything beyond
        // that folds into "More", which opens the lot as a list rather than a
        // floating menu: this surface is clipped, and a popup that can be cut
        // off is worse than one more row.
        Item {
          id: deedArea
          width: parent.width

          // The space under the body does one job at a time. Answering used to
          // leave the buttons stacked above the field, which read as a form
          // rather than as a reply - and put "Reply" directly above the box it
          // had just opened. Escape puts them back, because it puts the card
          // back to not replying.
          //
          // The row is under the pointer only, and only in an open deck: a
          // collapsed deck is a peek of an edge, and buttons appearing inside
          // one would be clipped to nothing.
          readonly property string mode: card.replying ? "reply"
                                       : card.menuOpen ? "menu"
                                       : card.deedsOpen ? "list"
                                       : (card.hovered && card.expanded
                                          && card.deeds.length > 0) ? "row" : ""

          readonly property real contentHeight: mode === "reply" ? replyBox.height
                                              : mode === "menu" ? menuColumn.implicitHeight
                                              : mode === "list" ? deedColumn.implicitHeight
                                              : mode === "row" ? deedRow.implicitHeight : 0
          height: mode === "" ? 0 : contentHeight + Style.space(7)
          visible: height > 0
          clip: true
          Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

          Row {
            id: deedRow
            anchors.bottom: parent.bottom
            // Right by default: the buttons line up under the time and the
            // close control rather than under the icon, which keeps the left
            // edge of every card reading as one column of text.
            anchors.right: card.actionsAlign === "right" ? parent.right : undefined
            anchors.left: card.actionsAlign === "right" ? undefined : parent.left
            spacing: Style.space(6)
            opacity: deedArea.mode === "row" ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Repeater {
              model: card.deeds
              DeedButton {
                required property var modelData
                deed: modelData
                toast: card
              }
            }

            DeedButton {
              visible: card.spare.length > 0
              deed: ({ kind: "more", label: "More", value: "" })
              toast: card
            }
          }

          // Typing an answer, in the card the message arrived in. Only the
          // phone can actually deliver it - this is the near end of a
          // conversation that lives on the device.
          Item {
            id: replyBox
            width: parent.width
            height: card.replying ? Style.space(24) : 0
            visible: height > 0
            anchors.bottom: parent.bottom
            clip: true
            Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

            // The kit's own text input: same focus ring, selection tint and
            // padding as every other field in the desktop, and it follows
            // [controls] in the theme rather than a shape invented here.
            TextField {
              id: replyInput
              anchors.fill: parent
              anchors.topMargin: Style.space(3)
              foreground: Color.notifications.text
              accent: Color.notifications.border
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              verticalPadding: 2
              placeholderText: "Reply to " + String(card.row.replyTo || card.row.summary || "")
              onAccepted: { card.replySent(text); text = "" }
              Keys.onEscapePressed: { text = ""; card.replyCancelled() }

              // Enter sends, but an affordance nobody can see is not one.
              Button {
                id: sendButton
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                visible: replyInput.text.length > 0
                text: "Send"
                bordered: false
                foreground: Color.notifications.text
                accent: Color.notifications.border
                fontFamily: Style.font.family
                fontSize: Style.font.caption
                verticalPadding: 1
                onClicked: { card.replySent(replyInput.text); replyInput.text = "" }
              }
            }

            onVisibleChanged: if (visible) replyInput.forceActiveFocus()
          }

          Column {
            id: deedColumn
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Style.space(4)
            opacity: deedArea.mode === "list" ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Repeater {
              model: card.deedsOpen ? card.allDeeds : []
              DeedButton {
                required property var modelData
                deed: modelData
                toast: card
                wide: true
              }
            }
          }

          // Right-click: what to do about this sender, rather than about this
          // message. Drawn in the card rather than as a popup for the same
          // reason "More" is - the notification surface is clipped, and a menu
          // that can be cut in half is worse than one that pushes the card
          // down by four rows.
          Column {
            id: menuColumn
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Style.space(4)
            opacity: deedArea.mode === "menu" ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Repeater {
              model: card.menuOpen ? card.menuDeeds : []
              DeedButton {
                required property var modelData
                deed: modelData
                toast: card
                wide: true
              }
            }
          }
        }
      }
    }

    // The countdown, barely there. It was a solid line before and every card
    // had one ticking away in the corner of your eye; the information is worth
    // almost nothing next to the distraction of watching it move.
    Rectangle {
      visible: card.row.duration > 0 && card.place.front && card.remaining > 0
               && !card.expanded
      anchors { left: parent.left; bottom: parent.bottom
                leftMargin: Style.space(7); bottomMargin: 1 }
      height: 1
      color: Color.notifications.text
      opacity: 0.12
      width: Math.max(0, (body.width - Style.space(14))
                         * (card.remaining / Math.max(1, card.row.duration)))
    }

    // Push it off to the right to be rid of it - the one gesture worth
    // stealing wholesale from macOS. Collapsed, the whole deck goes with the
    // card you are pushing; expanded, only the one under your hand does.
    MouseArea {
      anchors.fill: parent
      // Underneath the card's own content. This covers the whole card and is
      // declared after it, so it sat on top and swallowed every click before a
      // button could see one - the buttons highlighted on hover and then did
      // nothing when pressed. Items above that do not accept a click still let
      // it fall through to here, so the swipe and the click-to-open keep
      // working everywhere except on an actual button.
      z: -1
      // Deliberately NOT hoverEnabled: hover goes to the topmost item that
      // wants it, so a card that took hover would starve the deck's own
      // region and the stack would never expand.
      hoverEnabled: false
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      property real from: 0
      property bool dragging: false
      readonly property real threshold: card.width * 0.3

      // Measured in the scene, not in the card.
      //
      // `mouse.x` is a coordinate inside this card - and the card slides right
      // as you drag it, carrying its own coordinate system along. So the
      // pointer stays at roughly the same local x however far you pull, dx
      // stops growing after the first few pixels, and the card creeps and then
      // stops. Scene coordinates do not move with the thing being dragged.
      function sceneX(mouse) { return mapToItem(null, mouse.x, mouse.y).x }

      onPressed: function(mouse) {
        from = sceneX(mouse)
        dragging = false
      }
      onPositionChanged: function(mouse) {
        if (!pressed || mouse.buttons !== Qt.LeftButton) return
        var dx = sceneX(mouse) - from
        // Only rightwards, and only after enough travel to be a decision
        // rather than a wobble on the way to a click.
        if (!dragging && dx > Style.space(7)) dragging = true
        if (dragging) card.swipeMoved(Math.max(0, dx))
      }
      onReleased: function(mouse) {
        if (!dragging) return
        dragging = false
        card.swipeEnded(card.swipe > threshold)
      }
      onCanceled: { dragging = false; card.swipeEnded(false) }

      onClicked: function(mouse) {
        if (dragging) return                 // that was a swipe, not a click
        if (mouse.button === Qt.RightButton) { card.menuOpen = !card.menuOpen; return }
        // With the menu open, a click anywhere else on the card is a way out
        // of it rather than a way into the app - the surface takes no keyboard
        // focus while it is open, so Escape never reaches us.
        if (card.menuOpen) { card.menuOpen = false; return }
        if (mouse.button === Qt.MiddleButton) card.dismissed()
        else card.activated()
      }
    }
  }
}
