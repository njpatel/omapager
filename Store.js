// Pure functions over notifications: what to keep from one, how to write it
// out, how to read it back. Nothing here touches the UI or the bus, so it can
// be reasoned about (and later tested) on its own.
.pragma library
.import "Security.js" as Security
.import "Markup.js" as Markup
.import "Detect.js" as Detect

// Everything a card draws and a history entry needs. Read defensively: these
// come off the bus from arbitrary senders.
function snapshot(n, key, urgencyEnum) {
  var expire = Number(n.expireTimeout || 0)
  if (!isFinite(expire) || expire < 0) expire = 0
  // An `-i some-icon` arrives as image = "image://icon/some-icon" with appIcon
  // empty. That is a name to look up, not a picture the sender sent: treating
  // it as one skipped icon resolution altogether, and handing the URL straight
  // to an Image draws a broken-texture checkerboard for any name the icon
  // theme does not have.
  var img = Security.bounded(n.image, 256)
  var named = ""
  // The name has to be pulled out before the qsimage-only shape check below,
  // or that check throws it away first (it is never a qsimage handle) and
  // "image://icon/kitty" is indistinguishable from having sent no icon at
  // all - a real regression a prior ordering of these two checks had.
  // Everything past "image://icon/" is a local icon-theme name to look up,
  // never a path: the strict appIcon charset a few lines down
  // (/^[a-zA-Z0-9_.-]{1,256}$/, no "/") is what actually keeps
  // "../../etc/passwd" or a "file://" URL from being promoted into one.
  if (img.indexOf("image://icon/") === 0) {
    named = img.substring("image://icon/".length)
    img = ""
  } else if (!/^image:\/\/qsimage\/[0-9]+\/[0-9]+$/.test(img)) {
    img = ""
  }
  // Who actually sent it. The one identity that is never a guess: a terminal
  // relaying a notification from something running inside it owns a window,
  // and its pid says which one.
  var hints = n.hints || {}
  var senderPid = Number(hints["sender-pid"] || 0) || 0
  var raw = { app: Security.bounded(n.appName, Security.MAX_APP_NAME), summary: Security.bounded(n.summary, Security.MAX_SUMMARY),
              body: Security.bounded(n.body, Security.MAX_BODY) }
  // Who this is really from, and what the body says once the sender's own
  // labelling has been taken off the front of it.
  var id = Markup.identify(raw, n.hints)
  // What the card can offer to do. Scanned from the lifted body, so a Chrome
  // notification does not offer to open the site it announced itself with.
  var found = Detect.scan(id.summary, id.body)
  return normalise({
    key: key,
    originalId: n.id || 0,
    senderPid: senderPid,
    app: Security.bounded(n.appName, Security.MAX_APP_NAME),
    appIcon: Security.bounded(n.appIcon || named, 256),
    summary: id.summary,
    body: id.body,
    // What the sender actually sent, kept so a replay is faithful: the body
    // above has had the source anchor lifted off the front of it, and
    // re-sending that version loses the only thing that says which site it
    // came from.
    rawBody: Security.bounded(n.body, Security.MAX_BODY),
    bodyRich: Markup.render(id.body),
    bodyLine: Markup.oneLine(id.body),
    source: id.source,
    groupKey: id.groupKey,
    code: found.code,
    codes: found.codes,
    replyPath: "",
    replyTo: "",
    link: found.link,
    meeting: found.meeting,
    phone: found.phone,
    image: img,
    urgency: typeof n.urgency === "number" ? n.urgency : urgencyEnum.Normal,
    expireTimeout: expire,
    duration: 0,
    ts: Date.now() / 1000
  })
}

// The fields an in-place update (replaces_id) must write through to the row.
var ROLES = ["originalId", "senderPid", "app", "appIcon", "summary", "body", "rawBody", "bodyRich",
             "bodyLine", "source", "groupKey", "image", "urgency",
             "expireTimeout", "duration", "ts",
             "code", "codes", "link", "meeting", "phone", "replyPath", "replyTo"]

function applyTo(model, index, row) {
  var current = model.get(index)
  for (var i = 0; i < ROLES.length; i++) {
    var role = ROLES[i]
    if (current[role] !== row[role]) model.setProperty(index, role, row[role])
  }
}

// A restored row has no live sender behind it: its actions died with the last
// shell, and re-arming the original timeout would make a notification from
// before the restart expire instantly. It gets a short grace instead - long
// enough to say "this arrived while the shell was down", short enough that a
// restart does not leave yesterday's cards sitting on the screen. Critical
// notifications still wait for you, because that is what critical means.
var RESTORE_GRACE = 20000     // 20s for a notification that outlived its sender

// Every field a row can have, with a default for each. A ListModel fixes its
// roles from the first row it is handed and silently drops keys that row did
// not carry - so one row restored from an older build could define the model
// without `source`, and every notification for the rest of the session lost
// it. Everything goes through normalise() so they all have every field.
var SHAPE = {
  key: "", originalId: 0, senderPid: 0, app: "", appIcon: "", summary: "", body: "",
  bodyRich: "", bodyLine: "", rawBody: "", source: "", groupKey: "", image: "",
  code: "", codes: "", link: "", meeting: false, phone: "", replyPath: "", replyTo: "",
  stored_image: "", urgency: 1, expireTimeout: 0, duration: 0, ts: 0,
  restored: false
}

function normalise(row) {
  var out = {}
  for (var k in SHAPE) out[k] = (row && row[k] !== undefined) ? row[k] : SHAPE[k]
  // The group key is derived, never trusted. Rows written by an older build
  // carry whatever the grouping rule was that week - and one of those rules
  // keyed on Chrome's desktop-entry hint, which is a per-session temp path, so
  // history came back holding one group per notification. Recomputing here
  // means a change to the rule fixes what is already stored instead of only
  // applying to whatever arrives next.
  for (var field in SHAPE) {
    if (typeof SHAPE[field] === "string") out[field] = Security.bounded(out[field], Security.MAX_BODY)
    else if (typeof SHAPE[field] === "number") out[field] = typeof out[field] === "number" && isFinite(out[field]) ? out[field] : SHAPE[field]
    else out[field] = out[field] === true
  }
  out.app = out.app.slice(0, Security.MAX_APP_NAME)
  out.summary = out.summary.slice(0, Security.MAX_SUMMARY)
  out.source = out.source.slice(0, Security.MAX_SOURCE)
  out.appIcon = /^[a-zA-Z0-9_.-]{1,256}$/.test(out.appIcon) ? out.appIcon : ""
  out.link = Security.safeHttpUrl(out.link)
  out.phone = out.phone.slice(0, Security.MAX_PHONE)
  out.codes = out.codes.split(" ").slice(0, Security.MAX_CODES).join(" ")
  out.image = /^image:\/\/qsimage\/[0-9]+\/[0-9]+$/.test(out.image) ? out.image : ""
  out.stored_image = ""
  out.bodyRich = Markup.render(out.body)
  out.bodyLine = Markup.oneLine(out.body)
  out.groupKey = Markup.regroup(out)
  return out
}

function restored(entry) {
  if (!entry || !entry.key) return null
  var row = normalise(entry)
  row.duration = row.urgency === 2 ? 0 : RESTORE_GRACE
  row.restored = true
  return row
}

function parseList(text) {
  try {
    if (String(text || "").length > 100 * Security.MAX_HISTORY_ENTRY_BYTES) return []
    var value = JSON.parse(String(text || "[]"))
    if (!Array.isArray(value)) return []
    value = value.slice(0, 100)
    for (var i = 0; i < value.length; i++) value[i] = normalise(revive(value[i]))
    return value
  } catch (e) {
    return []
  }
}

// A sender that hands over raw pixels rather than an icon name gets an
// "image://qsimage/12/1" handle, which lives inside the running shell and dies
// with it. Read back tomorrow it is a broken-image box - and worse, it looked
// like the sender had provided a picture, so no icon was ever looked up. KDE
// Connect does this for every notification it forwards, which is why phone
// Slack had no Slack icon while desktop Slack did. Dropping the dead handle
// puts those rows back in the queue for a real icon.
function revive(row) {
  if (row && String(row.image || "").indexOf("image://") === 0) row.image = ""
  return row
}

// One writer, one queue. Two Processes racing on the same key would let the
// close overtake the put and leave a live file with nothing to close it.
var _queue = []
var _busy = false

function write(proc, bin, verb, payload, args) {
  if (_queue.length >= 256) return
  _queue.push({ bin: bin, verb: verb, payload: verb === "put" ? sanitiseForPersistence(payload) : payload, args: args || [] })
  _pump(proc)
}

function _pump(proc) {
  if (_busy || _queue.length === 0) return
  var job = _queue.shift()
  _busy = true
  proc.command = [job.bin, job.verb].concat(job.args)
  proc.exited.connect(function done() {
    proc.exited.disconnect(done)
    _busy = false
    _pump(proc)
  })
  // stdin has to be opened before the process starts, and closed after the
  // payload, or the store sits waiting on an EOF that never comes.
  proc.stdinEnabled = !!job.payload
  proc.running = true
  if (job.payload) {
    proc.write(JSON.stringify(job.payload))
    proc.stdinEnabled = false
  }
}

// Persistence is a separate boundary. A secret-bearing notification keeps only
// a placeholder: encoded variants, URLs and sender metadata cannot leak it.
function sanitiseForPersistence(row) {
  var out = normalise(row)
  var secret = out.codes || out.code || Detect.codes(Markup.oneLine(out.summary + " " + out.rawBody + " " + out.body)).length
  if (secret) {
    for (var k in SHAPE) if (typeof SHAPE[k] === "string" && k !== "key") out[k] = ""
    out.summary = "Verification notification"
    out.body = "[redacted]"
    out.rawBody = out.body
    out.bodyLine = out.body
    out.bodyRich = out.body
  }
  out.replyPath = ""; out.replyTo = ""; out.image = ""; out.stored_image = ""
  return out
}
