# Security policy

Notification text, identities, images, actions, hints, URLs and phone messages
are untrusted, including those sent by local applications.

## Supported versions and reporting

This is an unreleased hardening branch based on upstream commit
`29548e5761f1b9f419afe988d77f67e3dd3e81cb`. Only the reviewed tip of
`hardening/main` is currently maintained; there are no supported binary releases.
Do not describe it as fully secure or as an upstream-approved release.

For upstream vulnerabilities use GitHub's **Report a vulnerability** facility
on the upstream repository if enabled (it was disabled when checked on
2026-09-07). For this fork, a maintainer must enable
private vulnerability reporting and establish a private contact before publishing
releases. No unverified email address or public issue should be used for secrets.
If private reporting is unavailable, contact the maintainer privately to arrange
a channel before sending a reproduction. Do not disclose credentials, real OTPs,
personal notification histories or private D-Bus captures in public issues.

Provide the exact commit, Omarchy/Qt/Python versions, a synthetic reproduction,
expected/actual behavior, affected capability and redacted sandbox probe status.
Coordinate disclosure after a fix and regression test are available. There is
currently no staffed response-time guarantee. Maintainers should acknowledge
reports promptly and agree a disclosure schedule with the reporter.

Security fixes require regression tests and review. Use reviewed immutable tags
or commits, not an unattended pull-and-restart update. See
[architecture](docs/SECURITY_ARCHITECTURE.md), [threat model](docs/THREAT_MODEL.md)
and [validation](docs/VALIDATION.md) for precise boundaries and limitations.
