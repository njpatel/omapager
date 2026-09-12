import QtQuick
import Quickshell
import qs.Commons
import "Plugin" as Plugin

Window {
  id: test
  visible: true
  width: 500
  height: 1600
  color: "#eeeeee"

  property int requestedReplies: 0
  property string invokedAction: ""
  property var cases: []
  property int index: -1
  property string phase: "start"
  readonly property string profile: Quickshell.env("OMAPAGER_TEST_PROFILE") || "default"

  Plugin.Toast {
    id: toast
    cardWidth: 340
    place: ({front: true, count: 1, z: 1})
    expanded: true
    hovered: true
    paused: true
    onReplyRequested: test.requestedReplies++
    onActionInvoked: identifier => test.invokedAction = identifier
  }

  TextMetrics {
    id: titleMeasure
    text: String(toast.row.summary || "")
    font.family: Style.font.family
    font.pixelSize: Style.font.body * toast.fontScale
    font.weight: Font.DemiBold
  }

  function check(ok, message) {
    if (!ok) throw new Error(profile + " case " + index + " " + phase + ": " + message)
  }
  function walk(item, out) {
    out.push(item)
    if (item.children) for (var child of item.children) walk(child, out)
  }
  function nodes(item) { var out=[]; walk(item, out); return out }
  function buttons() { return nodes(toast).filter(n => n.deed !== undefined && n.visible) }
  function labelOf(button) {
    var text = button.labelText === undefined ? button.text : button.labelText
    var labels = nodes(button).filter(n => n !== button && n.text === text && n.lineCount !== undefined && n.visible)
    check(labels.length === 1, "expected one rendered label for " + text)
    return labels[0]
  }
  function inside(item, ancestor, message) {
    var p=item.mapToItem(ancestor,0,0), eps=0.5
    check(p.x >= -eps && p.y >= -eps && p.x+item.width <= ancestor.width+eps
          && p.y+item.height <= ancestor.height+eps, message)
  }
  function checkGeometry() {
    var bs=buttons()
    for (var button of bs) {
      var label=labelOf(button)
      inside(label,button,"label outside button: " + label.text)
      check(!label.truncated, "truncated label: " + label.text)
      check(label.contentWidth <= label.width+0.5 && label.contentHeight <= label.height+0.5,
            "text exceeds label geometry: " + label.text)
      // The card's outer edge is insufficient: the action area clips inside it.
      for (var ancestor=button.parent; ancestor; ancestor=ancestor.parent) {
        if (ancestor.clip || ancestor === toast) {
          inside(button,ancestor,"button crosses clipping boundary: " + label.text)
          inside(label,ancestor,"label crosses clipping boundary: " + label.text)
        }
        if (ancestor === toast) break
      }
    }
    return bs
  }
  function baseRow() { return {summary:"Ready",body:"Synthetic test message"} }
  function configure(c) {
    toast.deedsOpen=false; toast.menuOpen=false; toast.replying=false; toast.takenKind=""
    toast.fontScale=c.scale; toast.actionsAlign=c.align || "right"
    toast.actions=[]
    var row=baseRow()
    if (c.kind === "three") {
      row.code="123456"; row.codes="123456"; row.link="https://example.com"; row.replyPath="fake:0"
    } else if (c.kind === "long") {
      toast.actions=[{id:"long",text:c.label},{id:"second",text:"Second action"}]
    } else if (c.kind === "title") {
      row.summary=c.title
    }
    toast.row=row
  }
  function next() {
    index++
    if (index === cases.length) {
      console.log("PASS",profile,cases.length,"cases: row/list geometry, activation, replacements and titles")
      Qt.quit(); return
    }
    configure(cases[index]); phase="row"
  }
  Component.onCompleted: {
    // Explicit typography makes the check independent of the user's current theme.
    Style.fontBaseSize=profile === "large" ? 14 : 12
    Style.fontFamily=profile === "proportional" ? "sans-serif" : "monospace"
    Style.fontOverrides={}; Style.spacingOverrides={}; Style.styleOverrides={}
    Style.spacingScale=1; Style.spacingScaleWithFont=true
    var out=[]
    for (var percent=75; percent<=200; percent+=5)
      for (var align of ["left","right"])
        out.push({kind:"three",scale:percent/100,align:align})
    for (var label of ["A much longer action label",
                       "A very long action label that must wrap across several lines inside the notification card",
                       "AnUnbrokenActionIdentifierThatMustWrapWithoutLosingAnyCharacters",
                       "إجراء طويل لاختبار التفاف النص داخل زر الإشعار",
                       "<b>Literal action label</b>"])
      for (var scale of [0.75,1,2]) out.push({kind:"long",scale:scale,label:label})
    for (var size of [0.75,1,1.25,1.5,2]) {
      out.push({kind:"title",scale:size,title:"Ready",wrap:false})
      out.push({kind:"title",scale:size,title:"Workspace layout set to scrolling and ready for the next application window",wrap:true})
    }
    cases=out
  }
  Timer {
    interval: 180; running: true; repeat: true
    onTriggered: {
      try {
        if (test.phase === "start") { test.next(); return }
        var c=test.cases[test.index], bs=test.checkGeometry()
        var title=test.nodes(toast).find(n=>n.text===toast.row.summary && n.lineCount !== undefined)
        test.check(title && !title.truncated,"title unexpectedly truncated")
        if (c.kind === "title") {
          // Build a genuinely overflowing fixture under the current font metrics.
          // A naturally fitting summary must remain a valid single-line title.
          if (c.wrap && titleMeasure.advanceWidth <= title.width) {
            toast.row={summary:toast.row.summary + " and another workspace",body:"Synthetic test message"}
            return
          }
          test.check(c.wrap ? title.lineCount>1 : title.lineCount===1,"incorrect wrapping for title fixture")
          test.check(bs.length===0,"unexpected actions on title fixture")
          test.next(); return
        }
        if (test.phase === "row") {
          test.check(bs.length>0,"no reachable actions")
          var more=bs.find(b=>b.deed.kind==="more")
          test.check(!!more===toast.overflows,"More visibility does not match overflow")
          if (more) {
            more.clicked(); test.phase="list"; return
          }
          test.check(bs.length===toast.allDeeds.length,"missing row actions")
          // Also exercise full-width labels when the current row happens to fit.
          toast.doDeed({kind:"more"}); test.phase="list"; return
        }
        if (test.phase === "list") {
          test.check(bs.length===toast.allDeeds.length && bs.every(b=>b.wide),"More must expose every action")
          if (c.kind === "long" && toast.fontScale < 2) {
            toast.fontScale=2; test.phase="resized"; return
          }
        }
        if (test.phase === "list" || test.phase === "resized") {
          if (c.kind === "three") {
            var replies=test.requestedReplies
            bs.find(b=>b.deed.kind==="reply").clicked()
            test.check(test.requestedReplies===replies+1,"Reply is not reachable through More")
          } else {
            test.invokedAction=""
            bs.find(b=>b.deed.value==="long").clicked()
            test.check(test.invokedAction==="long","wrapped action does not activate")
          }
          // Replace actions on the same card while its list is open.
          toast.row=test.baseRow(); toast.actions=[{id:"replacement",text:"Replacement action"}]
          test.phase="replacement"; return
        }
        test.check(bs.length===1 && bs[0].deed.value==="replacement","stale actions after replacement")
        test.next()
      } catch(e) { console.error("FAIL",e); Qt.exit(1) }
    }
  }
}
