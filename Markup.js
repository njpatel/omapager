// Reading what senders actually put in a notification.
//
// The spec allows a small HTML subset in the body. Senders use it for things
// the spec did not intend - Chrome glues a link to its own origin onto the
// front of every message, which renders as a blue "app.slack.com" above text
// you actually care about. So this does two jobs: work out where a
// notification really came from, and render only what is safe to render.
.pragma library

var ALLOWED = ["b", "i", "u", "s", "em", "strong"]

var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " }

// Senders escape their text before handing it over - the spec says the body is
// markup, so "Tom & Jerry" arrives as "Tom &amp; Jerry". Escaping that again
// turns it into "&amp;amp;" and the reader sees "&amp;". Decode first, so
// everything downstream is working with the text the sender meant.
function decodeEntities(text) {
  // Twice over, because senders stack escapes. A WhatsApp message quoting
  // someone arrives at the phone already carrying &quot;, KDE Connect escapes
  // the whole body again on its way to the desktop, and what lands here is
  // &amp;quot;. One pass turns that into &quot; and the card shows the entity
  // rather than the quote mark. Bounded, and it stops as soon as a pass
  // changes nothing.
  var out = String(text || "")
  for (var i = 0; i < 3; i++) {
    var once = decodeOnce(out)
    if (once === out) break
    out = once
  }
  return out
}

function decodeOnce(text) {
  return String(text || "")
    .replace(/&#(\d{1,7});/g, function(_, n) {
      var code = parseInt(n, 10)
      return (code > 0 && code < 0x110000) ? String.fromCharCode(code) : _
    })
    .replace(/&#x([0-9a-f]{1,6});/gi, function(_, n) {
      var code = parseInt(n, 16)
      return (code > 0 && code < 0x110000) ? String.fromCharCode(code) : _
    })
    .replace(/&([a-z]+);/gi, function(whole, name) {
      var hit = ENTITIES[String(name).toLowerCase()]
      return hit === undefined ? whole : hit
    })
}

function escapeAll(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

// Put back only the tags we are willing to render. Everything the sender wrote
// is escaped first, so anything not on this list survives as literal text -
// which is how "<3" stays "<3" instead of vanishing into a broken tag.
function unescapeAllowed(text) {
  var out = text
  for (var i = 0; i < ALLOWED.length; i++) {
    var tag = ALLOWED[i]
    out = out.replace(new RegExp("&lt;" + tag + "&gt;", "gi"), "<" + tag + ">")
    out = out.replace(new RegExp("&lt;/" + tag + "&gt;", "gi"), "</" + tag + ">")
  }
  out = out.replace(/&lt;br\s*\/?&gt;/gi, "<br/>")
  // Anchors keep their href, and nothing else: no target, no style, no event
  // handlers smuggled through an attribute we did not ask about.
  out = out.replace(/&lt;a\s+href=(?:&quot;|")([^"&]+)(?:&quot;|")[^&]*&gt;([\s\S]*?)&lt;\/a&gt;/gi,
                    '<a href="$1">$2</a>')
  return out
}

function hostOf(url) {
  var m = String(url || "").match(/^[a-z]+:\/\/([^\/\?#:]+)/i)
  if (!m) return ""
  return m[1].replace(/^www\./i, "")
}

// A body that opens with a link to the sender's own origin is not a message
// with a link in it - it is the sender labelling itself. Lift it out.
function liftSource(body) {
  var text = String(body || "")
  var m = text.match(/^\s*<a\s+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>\s*/i)
  if (!m) return { source: "", body: text }
  var label = String(m[2]).trim()
  var host = hostOf(m[1])
  // Only when the anchor is standing in for a source: its text is the host,
  // or a bare domain. A real in-body link stays where the sender put it.
  var looksLikeSource = label === host || /^[\w.-]+\.[a-z]{2,}$/i.test(label)
  if (!looksLikeSource) return { source: "", body: text }
  return { source: host || label, body: text.slice(m[0].length) }
}

function linkify(escaped) {
  return escaped.replace(/(https?:\/\/[^\s<]+)/g, function(url) {
    return '<a href="' + url + '">' + url + '</a>'
  })
}

// The body as it should be drawn: rich text with only the permitted subset,
// newlines honoured, and bare URLs made clickable when the sender did not
// already mark them up.
function render(body) {
  var text = decodeEntities(body)
  var hadMarkup = /<\/?(a|b|i|u|s|em|strong|br)\b/i.test(text)
  var out = escapeAll(text)
  out = unescapeAllowed(out)
  if (!hadMarkup) out = linkify(out)
  return out.replace(/\r?\n/g, "<br/>")
}

// Flatten to one line, for a card that is not the one being read.
function oneLine(body) {
  return decodeEntities(String(body || "").replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim()
}

// KDE Connect names the device and the app in the summary, separated by a
// middle dot: "Pixel · Calendar". The device belongs in the chip, not in the
// headline you are trying to read.
function splitDevice(app, summary) {
  var text = String(summary || "")
  if (!/kde\s*connect/i.test(String(app || ""))) return { device: "", summary: text }
  // "Pixel · Calendar": device first, app second.
  var m = text.match(/^(.{1,28}?)\s*[·|]\s*(.+)$/)
  if (m) return { device: m[1].trim(), summary: m[2].trim() }
  // More often it is just the originating app: a Linear notification forwarded
  // from the phone arrives as summary "Linear". That name is the most useful
  // thing about it - it is what the notification is really from, and the only
  // thing that will find the right icon - so it becomes the source.
  if (text && text.length <= 28 && text.indexOf(" ") === -1)
    return { device: text, summary: text }
  return { device: "", summary: text }
}

// Where a notification came from, in the terms a person would use. The
// desktop-entry hint is the sender saying so itself and is trusted first;
// Chrome is the awkward one, because every web app announces itself as
// "Google Chrome" and only the lifted anchor tells them apart.
function identify(row, hints) {
  var app = String(row.app || "")
  var lifted = liftSource(row.body)
  var device = splitDevice(app, row.summary)

  var source = lifted.source || device.device || app

  var key
  if (lifted.source) key = "web:" + lifted.source          // per site, not per browser
  else if (device.device) key = "kdeconnect:" + device.device
  else key = "app:" + slug(app)

  return {
    source: source,
    groupKey: key,
    body: lifted.body,
    summary: device.summary || row.summary
  }
}

// The name of a thing, reduced to something that can be compared. Grouping on
// the desktop-entry hint looked more principled and was worse in practice:
// Chrome passes a per-session temp path ("file:///tmp/com.google.chrome.
// scoped_dir.sadmdx/logo.png") so every notification became its own group, and
// KDE Connect alternates between "kdeconnect" and
// "org.kde.kdeconnect.daemon", splitting one app in two. The application's own
// name is dull, stable, and the same every time.
function slug(text) {
  return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
}

// The group key for a row that has already been through identify() once - a
// row read back from the store, where the body no longer has the source anchor
// on it. Everything the key needs was kept as fields, so it can be rebuilt
// from those rather than by parsing the body a second time.
function regroup(row) {
  var app = String(row.app || "")
  var source = String(row.source || "")
  // A source with a dot in it is a hostname: the site is the sender, not the
  // browser showing it.
  if (source && source !== app && /\.[a-z]{2,}$/i.test(source)) return "web:" + source
  if (/kde\s*connect/i.test(app) && source && source !== app) return "kdeconnect:" + source
  return "app:" + slug(app)
}

// Qt's Text ignores `linkColor` for rich text - anchors come out in its own
// default blue no matter what the property says - so the colour has to be in
// the markup itself. It cannot be baked in at store time: a notification
// written under one theme is read back under whatever theme is current.
function colourLinks(html, colour) {
  if (!colour) return String(html || "")
  return String(html || "").replace(/<a\s+href="([^"]*)"[^>]*>/gi,
                                    '<a href="$1" style="color:' + colour + ';">')
}
