# Upstream synchronization and release review

- Fetch upstream deliberately and inspect the exact diff before merging.
- Inspect Service.qml, Toast.qml, Widget.qml, Security.js, Markup.js, Detect.js,
  Store.js and every bin/omapager helper for new inputs or capability sinks.
- Run static invariants before conflict resolution. Never resolve conflicts by
  dropping a security broker/wrapper in favor of an upstream direct call.
- Add synthetic regression cases for new behavior; run the full suite afterwards.
- Answer: input, capability, filesystem/network/URL/D-Bus/process/clipboard use,
  persistence of codes/reset links, bounds, malformed-input behavior, fail-closed
  behavior, isolation opportunity, malicious website/local-app abuse, dependency
  changes, uninstall/data removal, and tests for each new feature.
- Review CI action SHA updates and regenerate scanner hash locks deliberately.
  No scanner auto-fix or privileged PR execution.
- Enable private vulnerability reporting, secret scanning/push protection and
  branch review rules in the hosting repository; these cannot be enabled by a
  source-only patch. Never run untrusted PR code on a personal desktop runner.
- Before release, exercise the synthetic UI scenarios in a disposable Omarchy
  session and test a real consenting KDE Connect device. Do not use personal
  notification captures. Check history off, DND, snooze, restore and uninstall.
- Publish reviewed immutable tag, exact commit and SHA-256 checksums if packaging
  artifacts. Attestation/signing requires the release maintainer's identity and
  repository configuration; do not invent one in this patch.
- Do not recommend unattended git-pull-and-restart updates. No automatic updater
  is added until release verification is implemented.
- Evaluate OpenSSF Scorecard CLI once the repository owner/fork is established;
  do not claim an Action audit or repository settings that have not been run.
