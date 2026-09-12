# Baseline
Frozen at 29548e5761f1b9f419afe988d77f67e3dd3e81cb, containing
 e0fa1128dcb317641a47a98dd3fb365e67025ae1. No desktop plugin is installed by these tests.

`node tests/baseline.cjs` records normalisation, Chrome source lifting, body
links, one/multiple OTPs, phone detection, KDE forwarding and restored rows.
`bin/omapager-demo --list` describes synthetic interactive scenes for normal,
web, actions/default action, snooze, DND, history, phone reply and icon cards.
Those scenes require a separately installed disposable Quickshell session;
never replay personal history into tests. Local icon resolution uses installed
icon themes; remote resolution requires explicit opt-in in the hardened fork.
