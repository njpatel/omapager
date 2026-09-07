# Security changelog

## Unreleased — hardening/main, 2026-09-06

Baseline: 29548e5761f1b9f419afe988d77f67e3dd3e81cb; predecessor fix verified.

- Centralized URL authorization for body links, detected offers and card clicks.
- Bounded notification fields, collections, parsing and persistent entries.
- Regenerated stored markup and denied sender-controlled file/network images.
- Redacted detected OTP notifications before persistence; reduced retention and
  added private atomic writes, symlink refusal and legacy-state sanitisation.
- Made remote icons opt-in; pinned connections to public DNS answers; validated
  every redirect and raster decode; removed guessed brand/parent-domain requests.
- Required fail-closed Bubblewrap wrappers for storage, icon and KDE helpers.
- Disabled implicit sender default actions; bounded explicit actions and clipboard.
- Replaced fuzzy reply guesses with unique exact matches, rechecked before send.
- Removed the shell capability probe and window-class-to-Lua fallback.
- Removed notification text/URLs/actions from diagnostic probe and OTP IPC return.
- Added synthetic tests, actual Qt policy tests, isolation tests, static gates,
  pinned CI actions and hash-locked development scanner dependencies.

See UPSTREAM_HANDOFF.md for rationale, compatibility effects, validation evidence
and the distinction between implemented changes and deferred release/integration work.
