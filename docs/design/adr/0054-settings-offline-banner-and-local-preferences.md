# 0054 — Settings owns one offline banner; preferences are local rows

**Status:** Accepted

**Context:** The approved Settings root (06 §6.7) shows last-connected context
when the Bridge is offline but explicitly forbids a `Connect to edit` notice on
every subscreen and duplicate sync/repair actions on the root. T50 also needed
`Live change window` to read as its own preference rather than being buried in
the Temperature units tile.

**Decision:**
- The Settings root renders exactly one offline banner above the Bridge group,
  only while disconnected. Its text is `SettingsViewState.connectionSummary`
  (`Bridge disconnected · last connected …` or `… nothing saved yet`), and it
  deliberately has **no** Retry/Connect action. `Sync now`/`Reconnect` and
  `Disconnect` stay in Bridge details.
- Disabled Bridge-only controls keep their short inline reasons inside Bridge
  details; they do not add another global banner.
- `Live change window` is a separate Preferences row with its own sheet
  (`1 / 5 / 10 / 15 / 30 / 60 min`, default 5). It is local-only and never a
  Bridge config field. T53 persists it with units and theme.

**Consequences:**
- `SettingsViewState` carries `connectionSummary`; any future Settings surface
  that needs offline copy should reuse it instead of re-deriving the state.
- Widget tests can assert one `settings.offlineBanner` and the absence of a
  root-level retry action.
- Adding a retry action to the banner would violate the no-duplicate-repair
  rule; route the user to Bridge details instead.
