const assert=require('node:assert/strict'), fs=require('node:fs'), load=require('./js-loader.cjs');
const S=load('Security'), M=load('Markup'), D=load('Detect'), Store=load('Store');
const bad=['https://paypal.com@evil.example','https://user:pass@example.com','javascript:alert(1)','file:///etc/passwd','smb://server/share','data:text/html,test','https://example.com/\n','https://example.com/%0d%0a','https://example.com/%250a','https://example.com%40evil.example','https://[::1]','https://127.1','https://éxample.com','https://example..com','https://example.com:99999','https://example.com\\@evil.example','https://example.com/'+ 'x'.repeat(4096)];
for (const u of bad) {
 assert.equal(S.safeExternalUrl(u),'',u);
 assert.equal(M.linkable(u),false,u);
 assert.equal(S.openExternalUrl(u),false,u);
 assert.ok(!M.render('<a href="'+u+'">click</a>').includes('<a href='),u);
 for (const detected of D.links(u)) assert.ok(S.safeHttpUrl(detected));
}
for (const u of ['https://example.com','http://example.com/path?q=1','https://xn--bcher-kva.example','https://example.com/a%40b','mailto:user@example.com']) assert.ok(S.safeExternalUrl(u),u);
assert.equal(S.safeHttpUrl('HTTPS://Example.COM.:443/a'),'https://example.com:443/a');
assert.equal(S.safeMailtoUrl('mailto:user@example.com?attach=/etc/passwd'),'');
for(const payload of ['<img src="file:///etc/passwd">','<svg><image href="https://example.com"/></svg>','<script>alert(1)</script>','<iframe src="x">','https://example.com/"onmouseover="x']) {
 const rendered=M.render(payload);
 assert.ok(!/<(?:img|svg|script|iframe|object|embed|style)\b/i.test(rendered),rendered);
 assert.ok(!/<a[^>]+onmouseover=/i.test(rendered),rendered);
}
for (const body of ['Your verification code is 938271','Your code is 938 271','Your code is 938-271','Your code is &#57;38271','Your code is A9F3K2']) {
 const row=Store.snapshot({appName:'Test',summary:'Verification',body},'test', {Normal:1});
 const saved=Store.sanitiseForPersistence(row);
 for(const secret of ['938271','938 271','938-271','A9F3K2']) assert.ok(!JSON.stringify(saved).includes(secret));
}
assert.equal(Store.snapshot({body:'x'.repeat(100000),summary:'y'.repeat(3000)},'test',{Normal:1}).body.length,32768);
assert.equal(Store.normalise({image:'file:///etc/passwd',stored_image:'/etc/passwd'}).image,'');
assert.equal(Store.normalise({body:'hello',bodyRich:'<img src="x">'}).bodyRich,'hello');
const start=Date.now();
for (const text of ['<'.repeat(32768),'&amp;'.repeat(6500),'9'.repeat(32768), 'https://'.repeat(4000)]) { M.render(text); D.scan('',text); }
assert.ok(Date.now()-start < 3000,'parsers exceeded 3-second budget');
// Deterministic generated corpus, never personal notifications.
let seed=17;
for(let i=0;i<1000;i++) {
 let s=''; for(let j=0;j<80;j++){seed=(seed*1664525+1013904223)>>>0;s+=String.fromCharCode(seed%128);}
 const u=S.safeExternalUrl(s); if(u) assert.equal(S.safeExternalUrl(u),u);
 assert.ok(!/<(?:img|script|iframe|object|svg)\b/i.test(M.render(s)));
}
for (const u of JSON.parse(fs.readFileSync(__dirname+'/../security/corpus/urls/cases.json'))) assert.equal(S.safeExternalUrl(u),'');
for (const text of JSON.parse(fs.readFileSync(__dirname+'/../security/corpus/markup/cases.json'))) assert.ok(!/<(?:img|svg|script|iframe|object)\b/i.test(M.render(text)));
for (const text of JSON.parse(fs.readFileSync(__dirname+'/../security/corpus/codes/cases.json'))) {
 const row=Store.snapshot({summary:'Verification',body:text},'fixture',{Normal:1});
 assert.equal(Store.sanitiseForPersistence(row).body,'[redacted]');
}
for (const row of JSON.parse(fs.readFileSync(__dirname+'/../security/corpus/notifications/cases.json'))) assert.equal(Store.snapshot(row,'fixture',{Normal:1}).summary,'Synthetic');
// Execute the production focus function: hostile compositor metadata must not
// become Lua syntax. The only dispatchable value is a validated hex address.
const vm=require('node:vm'), source=fs.readFileSync(__dirname+'/../Service.qml','utf8');
const focus=source.match(/function focusWindow\(win\) \{[\s\S]*?\n  \}/)[0];
const calls=[], scope={Hyprland:{dispatch:x=>calls.push(x)}};
vm.createContext(scope);vm.runInContext(focus,scope);
scope.focusWindow({wmClass:'x\\"}); os.execute("bad") --'});
scope.focusWindow({address:'0x123);bad()',wmClass:'x'});
assert.equal(calls.length,0);
scope.focusWindow({address:'0x123abc'});assert.equal(calls.length,1);
assert.equal(calls[0],'hl.dsp.focus({window = hl.get_window("address:0x123abc")})');

// PR 4 review finding 3 (P2): the arrival cap used to check toasts.count
// alone, which a notification sitting in `held` (queued while the pointer is
// over the deck) or mid-flight inside Qt.callLater (queued for insertion)
// never incremented. 150 notifications could be accepted with toasts.count
// at 0 the whole time, then all land on screen the moment the deck let go or
// the event loop drained. This runs the actual production functions -
// handleNotification, showRow, finishClose, releaseHeld, reserveLive/
// releaseLive - out of Service.qml against a minimal fake Quickshell/Store,
// not a reimplementation of the accounting.
function extract(src, startMarker, endMarker) {
  const s = src.indexOf(startMarker);
  if (s < 0) throw new Error('start marker not found: ' + startMarker);
  const e = src.indexOf(endMarker, s + startMarker.length);
  if (e < 0) throw new Error('end marker not found: ' + endMarker);
  return src.slice(s, e);
}
const capacitySource = [
  extract(source, 'function liveCount()', '// ------------------------------------------------------------- icons'),
  extract(source, 'function nextKey()', 'function rowIndexFor(key)'),
  extract(source, 'function rowIndexFor(key)', 'function rowIndexForOriginal(id)'),
  extract(source, 'function rowIndexForOriginal(id)', '// ------------------------------------------------------------- arrival'),
  extract(source, 'function handleNotification(notification)', '// Qt.callLater: mutating the model'),
  extract(source, 'function showRow(row)', "// Let go of the sender's object"),
  extract(source, 'function release(key)', '// ------------------------------------------------------------- departure'),
  extract(source, 'function finishClose(key, reason)', 'function clearAll(reason)'),
  extract(source, 'function releaseHeld()', '// Nothing waits forever'),
].join('\n');

function newCapacityScope() {
  const fakeToasts = { rows: [],
    get count() { return this.rows.length; },
    get(i) { return this.rows[i]; },
    insert(i, row) { this.rows.splice(i, 0, row); },
    remove(i) { this.rows.splice(i, 1); } };
  const callLaterQueue = [];
  const s = {
    toasts: fakeToasts, refs: {}, refsRevision: 0, keySeed: 0, liveKeys: {},
    heights: {}, leaving: {}, layoutRevision: 0, replyingKey: '', held: [],
    doNotDisturb: false, globalSnoozeUntil: 0, codesBypassQuiet: false,
    snoozedUntil: () => 0, storeProc: {}, storeBin: '', wantIcon: () => {},
    lookForReply: () => {}, Store: { snapshot: (n, k) => ({ key: k, originalId: n.id, urgency: n.urgency, groupKey: '', expireTimeout: -1 }),
      write: () => {}, applyTo: () => {} },
    durationFor: () => 5000, NotificationUrgency: { Critical: 2, Normal: 1, Low: 0 },
    Qt: { callLater: fn => callLaterQueue.push(fn) },
    Style: { space: n => n },
  };
  // `handleNotification`/`releaseHeld`/`finishClose` reach the same
  // properties both bare (they are defined on `service` itself in the real
  // QML) and as `service.x` (called from elsewhere), so both spellings must
  // resolve to the same storage here too - a shared object reference for
  // anything only ever mutated in place (refs), a getter/setter for
  // anything reassigned wholesale (held).
  s.service = {
    refs: s.refs,
    maxLiveNotifications: 100,
    liveCount: () => s.liveCount(), reserveLive: k => s.reserveLive(k), releaseLive: k => s.releaseLive(k),
    holding: () => s.pointerHolding === true,
    get held() { return s.held; }, set held(v) { s.held = v; },
    rowIndexFor: k => s.rowIndexFor(k), showRow: row => s.showRow(row),
    releaseHeld: () => s.releaseHeld(),
    snapshot: () => ({}), deckHeight: 0, retarget: () => {}, layout: { placements: {} },
  };
  vm.createContext(s);
  vm.runInContext(capacitySource, s);
  s.drainCallLater = () => { while (callLaterQueue.length) callLaterQueue.shift()(); };
  s.fakeNotification = (id, urgency) => ({ id: id || 0, urgency: urgency === undefined ? 1 : urgency,
    tracked: false, closed: { connect: () => {} } });
  return s;
}

{ // review_p2_held_notifications_count_toward_limit
  const s = newCapacityScope();
  s.pointerHolding = true;             // every arrival queues into service.held, none reach toasts
  for (let i = 0; i < 150; i++) s.handleNotification(s.fakeNotification());
  assert.equal(s.toasts.count, 0, 'nothing is shown while the deck is held');
  assert.equal(s.service.held.length, 100, 'held notifications must themselves be capped at the limit');
  assert.equal(s.liveCount(), 100, 'held rows must count toward the live cap even though toasts.count is 0');
  s.pointerHolding = false;
  s.service.releaseHeld();
  s.drainCallLater();
  assert.equal(s.toasts.count, 100, 'released rows land on screen, still capped at 100, never the full 150 offered');
}

{ // review_p2_deferred_notifications_count_toward_limit
  const s = newCapacityScope();       // not held: each arrival schedules a Qt.callLater insertion
  for (let i = 0; i < 150; i++) s.handleNotification(s.fakeNotification());
  assert.equal(s.toasts.count, 0, 'no callback has run yet - a burst arriving faster than the event loop drains');
  assert.equal(s.liveCount(), 100, 'in-flight (not yet inserted) rows must still count toward the live cap');
  s.drainCallLater();
  assert.equal(s.toasts.count, 100, 'draining the queue must never produce more than the cap once admitted');
}

{ // review_p2_replacement_at_capacity_does_not_consume_slot
  const s = newCapacityScope();
  for (let i = 1; i <= 100; i++) { s.handleNotification(s.fakeNotification(i)); s.drainCallLater(); }
  assert.equal(s.toasts.count, 100);
  assert.equal(s.liveCount(), 100);
  // At capacity: an update to an existing id (replaces_id) must still go
  // through and must not be rejected or consume a second reservation.
  const updated = s.fakeNotification(1);
  s.handleNotification(updated);
  assert.equal(updated.tracked, true, 'a replacement of an existing row must not be turned away at capacity');
  s.drainCallLater();
  assert.equal(s.toasts.count, 100, 'a replacement must not grow the deck past the cap');
  assert.equal(s.liveCount(), 100, 'a replacement must not consume a second reservation');
  // A genuinely new notification, still at capacity, must be rejected.
  const rejected = s.fakeNotification(9999);
  s.handleNotification(rejected);
  assert.equal(rejected.tracked, false, 'a new notification at capacity must be rejected');
  assert.equal(s.toasts.count, 100);
}

console.log('security JS: passed');
