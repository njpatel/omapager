import QtQuick
import Quickshell
import "Plugin" as Plugin

Window {
  id: test
  visible: true
  width: 500
  height: 900
  color: "#eeeeee"
  Plugin.Toast {
    id: toast
    x: 20; y: 20
    cardWidth: 340
    row: ({summary: "Workspace layout set to scrolling", body: "Synthetic test message", codes: "123456", code: "123456", link: "https://example.com", replyPath: "fake:0"})
    place: ({front: true, count: 1, z: 1})
    expanded: true
    hovered: true
    paused: true
  }
  property int step: 0
  property var sizes: [0.75, 1, 1.25, 1.5, 2]
  function walk(item, out) {
    if (!item) return
    out.push(item)
    if (item.children) for (var i=0; i<item.children.length; i++) walk(item.children[i], out)
  }
  function check(ok, message) { if (!ok) throw new Error(message) }
  Timer {
    interval: 200; running: true; repeat: true
    onTriggered: {
      try {
        if (test.step === 0) { toast.fontScale = test.sizes[0]; test.step++; return }
        var nodes=[]; test.walk(toast,nodes)
        var title=nodes.find(n => n.text === toast.row.summary)
        test.check(title && !title.truncated && title.lineCount > 1, "Title should wrap without truncation at " + toast.fontScale)
        var visibleButtons=nodes.filter(n => n.deed !== undefined && n.visible)
        for (var b of visibleButtons) {
          var p=b.mapToItem(toast,0,0)
          test.check(p.x >= 0 && p.x+b.width <= toast.width+0.1, "Button outside card: " + b.text)
          var labels=[]; test.walk(b,labels)
          for (var label of labels.filter(n=>n.text === b.text && n !== b && n.visible)) {
            var lp=label.mapToItem(b,0,0)
            test.check(lp.x >= -0.1 && lp.x+label.width <= b.width+0.1, "Label outside button: " + b.text)
          }
        }
        test.check(visibleButtons.length > 0, "No reachable actions")
        if (toast.fontScale === 2 && !toast.deedsOpen) test.check(toast.overflows, "200% needs More")
        if (test.step <= test.sizes.length) {
          console.log("PASS row",toast.fontScale,"fits",toast.fits,"buttons",visibleButtons.map(b=>b.text).join(","))
          if (test.step < test.sizes.length) toast.fontScale=test.sizes[test.step]
          else toast.doDeed({kind:"more"})
        } else if (test.step === test.sizes.length+1) {
          test.check(visibleButtons.length === 3 && visibleButtons.every(b=>b.wide),"More must expose all three actions")
          console.log("PASS More list at 200%")
          toast.deedsOpen=false; toast.actionsAlign="left"
        } else if (test.step === test.sizes.length+2) {
          console.log("PASS left aligned row at 200%")
          toast.row={summary:"Workspace layout set to scrolling",body:"Sample",codes:"",link:"",replyPath:""}
          toast.actions=[{id:"long",text:"A much longer action label"}]
        } else if (test.step === test.sizes.length+3) {
          test.check(toast.fits===0 && visibleButtons.length===1 && visibleButtons[0].text==="More", "Oversize first action needs More")
          console.log("PASS More-only row")
          Qt.quit()
        }
        test.step++
      } catch(e) { console.error("FAIL",e); Qt.exit(1) }
    }
  }
}
