# 0059 — UI evidence gates: state matrix, copy lint and reviewed screenshots

**Status:** accepted (T54)

## Context

The prototype review left three kinds of evidence informal: some post-T36 Live
states had no contract test, copy was hard-coded and could drift back to banned
vocabulary, and the committed screenshot set could change without a reviewer
noticing. Accessibility was checked by inspection rather than by CI.

## Decision

1. **State matrix.** `app/test/ui_state_matrix_test.dart` renders every 13 §13.4
   state reachable without hardware at 320 dp and 390 dp in dark and light. It
   asserts a state marker, no overflow, the connection card with two radio
   meters on Live, the chart on History, and the 13 §13.8 stable keys.
2. **Copy catalogue and lint.** `app/lib/app/strings.dart` holds shared product
   copy. `app/test/copy_lint_test.dart` scans string literals in the product UI
   layer (not debug/lab or data), strips interpolations, and fails on the
   12 §12.6 banned terms case-insensitively. Only the Technical details labels
   (`MTU`, `RSSI`) and the approved verb sentence “The Bridge records whenever…”
   are allow-listed.
3. **Accessibility gate.** `app/test/accessibility_test.dart` checks WCAG AA
   contrast (4.5:1) for primary, error, status and probe colours on every light
   and dark surface; 48 dp targets for chart controls, filters and destructive
   confirmations; semantics for the connection card, radio links, probe tiles,
   chart summary, filters, Summary rows and destructive sheets; reduced motion
   through `AppMotion`; and a label plus icon for non-healthy status.
4. **Reviewed screenshots.** `app/tool/ui_screenshots_test.dart` is the only
   generator. `screenshots/manifest.json` records the 390 × 844 size and a
   content hash of each PNG; `app/test/screenshot_manifest_test.dart` runs in
   `flutter test` and fails when a pixel changes, a shot disappears or a new PNG
   is added without regenerating the manifest. The reviewed update sequence is
   the screenshot test with `--update-goldens`, then
   `dart run tool/screenshot_manifest.dart`, then a visual diff review.

## Consequences

- A banned word or a one-byte screenshot change fails the normal `app-test`
  gate, so both must be fixed or reviewed deliberately.
- New screenshots require a manifest update; the manifest diff is the review
  record.
- The light theme needed darker primary, error, status and probe colours to
  clear 4.5:1 on `surfaceContainerHighest`; those values are now the theme
  contract, not per-widget overrides.
