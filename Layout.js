// Where every card sits, in one function.
//
// The deck is not a column: cards are placed absolutely, so a card keeps its
// identity (and its half-finished animation) when the one above it leaves.
// Everything here is pure - rows in, placements out - so the positioning can
// be reasoned about without a compositor.
.pragma library

// Collapsed geometry. Three steps of peek is the floor before a deck stops
// reading as a deck; past that the cards only fade.
var PEEK = 10          // px each card behind the front one drops
var SHRINK = 0.035     // and the scale it loses
var VISIBLE = 3        // cards drawn before the rest just fade out
var FADE = 0.55        // opacity of the last drawn card in a collapsed deck

// Which deck a row belongs to. In "all" mode there is one deck and this is
// constant; in "source" mode it is the sender.
function deckKeyFor(row, stacking) {
  if (stacking !== "source") return "all"
  return String(row.groupKey || row.source || row.app || "?")
}

function groupKeyFor(row) {
  return String(row.groupKey || row.source || row.app || "?")
}

// A deck shows every notification - that is what makes it a stack. Grouping
// is carried as a count on the newest card from each source rather than by
// hiding the rest: folding three notifications into one card left nothing to
// stack and nothing to expand, which reads as broken.
function groupRows(rows) {
  var seen = {}
  var counts = {}
  var i
  for (i = 0; i < rows.length; i++) {
    var k = groupKeyFor(rows[i])
    counts[k] = (counts[k] || 0) + 1
  }
  var items = []
  for (i = 0; i < rows.length; i++) {
    var key = groupKeyFor(rows[i])
    var first = !seen[key]
    seen[key] = true
    items.push({ key: rows[i].key, row: rows[i], groupOf: key,
                 // Only the newest of a group wears the count; the ones
                 // behind it would just be repeating themselves.
                 count: first ? counts[key] : 1,
                 members: [] })
  }
  return items
}

// Rows are newest-first. Returns:
//   decks:      [{ key, rows: [row...] }] in display order, newest deck first
//   placements: { rowKey: { y, scale, opacity, z, front, hidden } }
//   height:     total height the deck area occupies
function compute(rows, opts) {
  var stacking = opts.stacking || "all"
  var expanded = !!opts.expanded
  var gap = opts.gap || 6
  var deckGap = opts.deckGap || 12
  var openGroup = opts.openGroup || ""
  var heightOf = opts.heightOf || function() { return 76 }
  // Every card is its own height, collapsed or not.
  //
  // Collapsed cards used to share one height - the tallest card's - so the
  // stack kept a fixed shape as things arrived. It cost more than it bought:
  // a one-line card was padded out to match a two-line one, content had to be
  // centred in the spare room, and the moment a card grew for its buttons the
  // shared height grew and every card on screen moved. Only the front card of
  // a collapsed deck is really visible anyway; the ones behind it are a peek
  // of an edge, and an edge has no height worth matching.

  // Which deck each row belongs to. One in "all" mode; one per source in
  // "source" mode, where the deck already separates them and grouping inside
  // it would be grouping twice.
  var order = [], byKey = {}
  for (var i = 0; i < rows.length; i++) {
    var key = deckKeyFor(rows[i], stacking)
    if (!byKey[key]) { byKey[key] = { key: key, rows: [] }; order.push(key) }
    byKey[key].rows.push(rows[i])
  }

  var decks = []
  for (var d = 0; d < order.length; d++) {
    var deck = byKey[order[d]]
    deck.items = stacking === "source"
      ? deck.rows.map(function(r) { return { key: r.key, row: r, groupOf: "", count: 1, members: [] } })
      : groupRows(deck.rows)
    decks.push(deck)
  }

  var placements = {}
  var y = 0

  for (var k = 0; k < decks.length; k++) {
    var items = decks[k].items
    var open = expanded && (stacking !== "source" || opts.openDeck === decks[k].key
                            || opts.openDeck === undefined)
    var deckTop = y
    var frontHeight = items.length ? heightOf(items[0].key) : 76
    var shown = 0

    for (var r = 0; r < items.length; r++) {
      var item = items[r]
      if (open) {
        placements[item.key] = {
          y: y, scale: 1, opacity: 1, z: 1000 - shown, front: r === 0,
          hidden: false, height: heightOf(item.key), count: item.count,
          groupOf: item.groupOf, member: false
        }
        y += heightOf(item.key) + gap
        shown += 1

        // Opening the deck opens its groups too. Hovering a stack of three
        // and being shown one card with a "3" on it is the thing people
        // report as "it does not expand" - because from where they are
        // sitting, it did not.
        for (var m = 0; m < item.members.length; m++) {
          var mem = item.members[m]
          placements[mem.key] = {
            y: y, scale: 1, opacity: 1, z: 1000 - shown, front: false,
            hidden: false, height: heightOf(mem.key), count: 1,
            groupOf: item.groupOf, member: true
          }
          y += heightOf(mem.key) + gap
          shown += 1
        }
      } else {
        var drawn = r < VISIBLE
        placements[item.key] = {
          height: heightOf(item.key),
          y: deckTop + r * PEEK,
          scale: Math.max(0.7, 1 - r * SHRINK),
          opacity: r === 0 ? 1 : (drawn ? (r === VISIBLE - 1 ? FADE : 0.85) : 0),
          z: 1000 - r,
          front: r === 0,
          hidden: !drawn,
          count: item.count,
          groupOf: item.groupOf,
          member: false
        }
        // Members of a collapsed group are not on screen at all.
        for (var mm = 0; mm < item.members.length; mm++)
          placements[item.members[mm].key] = { y: deckTop, scale: 0.9, opacity: 0,
                                               z: 0, front: false, hidden: true,
                                               height: frontHeight, count: 1,
                                               groupOf: item.groupOf, member: true }
      }
    }

    if (!open) y = deckTop + frontHeight + Math.min(items.length - 1, VISIBLE - 1) * PEEK
    else y -= gap

    if (k < decks.length - 1) y += (stacking === "source" ? deckGap : gap)
  }

  // Anything the model still holds but no deck placed (a row leaving, or a
  // member of a group that just closed) gets a definite hidden placement
  // rather than the fallback the delegate would otherwise invent.
  for (var q = 0; q < rows.length; q++) {
    if (!placements[rows[q].key])
      placements[rows[q].key] = { y: 0, scale: 0.9, opacity: 0, z: 0, front: false,
                                  hidden: true, height: 0, count: 1, groupOf: "", member: false }
  }

  return { decks: decks, placements: placements, height: Math.max(0, y) }
}
