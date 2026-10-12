# N14 — Onboarding

**Goal:** the guided first-run wizard: pair over BLE, coach the passkey, listen for
the Smoke X4, choose a network mode, name the bridge, done.

**Design:** [`newui/app.js`](../app.js) §7 `overlayOnboarding`, `permRow`,
`modeCardCompact` · `newui/NOTES.md` §6 · `components_research_notes.md` §11.5,
§12 · `docs/design/05`.

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| — | The passkey is shown **only on the device OLED**; the app cannot render a real code and coaches the user before Android's own (wrong) dialog | passkey step |
| — | The bridge is a pure listener: pairing is non-destructive and the Smoke X4-pair step teaches that | sync step |
| I6 | No state without a next step | every step |
| I15 | No raw exception escapes; failures become named states with copy | `SetupFault` |
| — | A superseded flow cannot drag the user backwards (monotonic generation counter) | wizard controller |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N14.1 | `SetupMachine`: 8 named steps (welcome, preflight, scan, passkey, sync, network, name, done) with a step rail; monotonic generation guard | N4.6 | H | research notes §12 |
| N14.2 | Step 1 welcome: device illustration + "records with or without your phone" | N14.1 | W | `app.js` overlayOnboarding |
| N14.3 | Step 2 preflight: Bluetooth / Notifications / Location (older Android) permission rows; denied states resumable | N14.1 | W | `app.js` permRow, research notes §12 |
| N14.4 | Step 3 scan: scan ring, found-bridge card, "Can't find it?" | N14.3 | W | `app.js` overlayOnboarding |
| N14.5 | Troubleshoot sub-flow: powered? Bluetooth on? restart the bridge; Back / Try again | N14.4 | W | `app.js` onboardTroubleshoot |
| N14.6 | Step 4 passkey: "type the six digits from the bridge's own screen, not the 0000 your phone suggests"; MonoWell placeholder; coaching copy | N14.4 | W | `app.js` overlayOnboarding |
| N14.7 | Step 5 sync: "Listening for your Smoke X4" + pure-listener notice | N14.6 | W | `app.js` overlayOnboarding |
| N14.8 | Step 6 network: the three mode cards (default BLE), changeable later | N14.7, N10.4 | W | `app.js` overlayOnboarding |
| N14.9 | Step 7 name + units | N14.8 | W | `app.js` overlayOnboarding |
| N14.10 | Step 8 done: "You're all set" → Go to Live | N14.9 | W | `app.js` overlayOnboarding |
| N14.11 | Recovery paths: link-lost, fault, resume; a skipped hop reads "— not set up" | N14.10 | W | research notes §11.5 |
| N14.12 | First-run gating: the wizard shows only when no bridge is known; later launches go straight to the shell | N14.1, N2.29 | S | `app.js` launch logic |
| N14.13 | Skip is allowed; the shell then shows the "connect a bridge" empty state, never a dead end | N14.12 | W | I6 |

## Exit gate

A factory-fresh state walks all 8 steps to a live shell; denying a permission
gives a resumable, named state; "Skip" lands on a shell that offers a way to
connect.

## Must-not-regress

The passkey is never rendered by the app; no state lacks a next step; a superseded
flow cannot drag the user backwards.

---

## Hand-off

**Status: done.** Implemented and re-verified in this session (re-run/attempt 1).
N14.1–N14.13 all landed; every "Done when" gate below runs green.

**What landed (all under `app/lib/features/onboarding/`; barrel `onboarding.dart`)**
- `setup_format.dart` — pure: `OnboardStep` (8), `kOnboardSteps`,
  `OnboardPermission`/`PermissionState`/`kOnboardPermissions`, `SetupHop`/
  `HopStatus`, `SetupFault` (named title/body/recoverLabel, I15), `SetupState`
  (`canAdvance` = I6, `blockedReason` = I5, `beginAsync`/`resolve`/`token` =
  monotonic generation guard), `SetupToken`, `SetupHopRow`, `kPasskeyPlaceholder`.
- `onboarding_model.dart` — `SetupMachine` (`Notifier<SetupState>`) +
  `setupStateProvider`, `onboardingRequiredProvider`, `onboardingSkippedProvider`.
- `onboarding_sheet.dart` — `OnboardingBody` (rail + per-step content),
  `OnboardingFoot` (Back/Skip + one ember primary), `OnboardingSurface` (the
  gate), `finishOnboarding`, `skipOnboarding`, `onboardingOverlayBody`/`Foot`.
- Wired: `shell/overlay.dart` resolves `DevOverlay.onboarding` to the real
  body/foot (`SheetOverlay.footBuilder`); `shell/shell.dart` mounts
  `OnboardingSurface` above everything while `onboardingRequiredProvider`;
  `features/live/live_page.dart` shows the `live-connect-bridge` empty state when
  skipped (N14.13); dev panel lists the `onboarding` overlay.
- `AppSettings` gained `bridgeName` and `onboardStatus`
  (`OnboardStatus { fresh, skipped, paired }`, default `paired`).

**Evidence (commands + results, run in this session)**
- `make app.test` → analyze clean, format clean, **837 tests pass**.
- `dart test test/domain test/data` (from `app/`) → **304 pass**.
- `flutter test test/features/onboarding_test.dart` → **8 pass**.
- `dart test test/data/onboarding_setup_test.dart` → **18 pass**.
- N14 adds 26 checks total (18 pure + 8 widget).

**Deviations / judgment calls (unchanged from the prior landing)**
- Mock default `onboardStatus: paired` keeps every non-fresh launch on the shell;
  factory-fresh is `fresh`. Tests override prefs to `fresh` for the gate.
- **The passkey is structural only**: no code field/parameter;
  `kPasskeyPlaceholder = '••••••'`; a widget test asserts no `Text` renders a
  6-digit code. The real platform flow is N15's.
- Permission *denial* is a platform-only state in the real app; the widget
  renders the named denied state + resumable Allow, pinned via a seeded
  `setupStateProvider`. The prototype's troubleshoot `permRow(..., false)` Allow
  buttons became plain checklist rows.
- The network step selects locally (no `applyMode` call yet).
- The gate is not dismissible by scrim tap (X = Skip); the named
  `?overlay=onboarding` dev path is dismissible. Both share the same body/foot.
- The gate head shows the current step title/sub; the named-overlay head is the
  static `Welcome to Smoke`.

**For the next task**
- N15: seed `onboardStatus: fresh` on a truly empty first install, return to
  `fresh` on factory reset, and implement the real BLE scan/pair + platform
  permission requests + real passkey entry. `bridgeName`/`onboardStatus` already
  persist through `prefsProvider` / `real_prefs_repository.dart`.
- N16: no golden renders the wizard; consider one for the gate.
- This session made **no source changes** — it found N14 already at commit
  `02d06d5`, independently re-ran every gate above, and added this Hand-off plus a
  re-verification note in `newui/PROGRESS.md`.

---

## Hand-off

**Status: done.** `make app.test` green (**609**; N14 adds 26 — 18 pure + 8 widget);
`flutter analyze` and format check clean; `dart test test/domain test/data` green
(**202**, was 184). No golden changed.

### Real paths (all under `app/lib/features/onboarding/`; barrel `onboarding.dart`)

- `setup_format.dart` — pure: `OnboardStep` (8 named steps + title/sub/primary
  label), `kOnboardSteps`, `OnboardPermission`/`PermissionState`/`kOnboardPermissions`,
  `SetupHop`/`HopStatus`, `SetupFault` (title/body/recoverLabel/terminal),
  `SetupState` (immutable: step, troubleshoot, permissions, passkeyConfirmed,
  hops, modeId, name, units, fault, generation), `SetupToken`, `SetupHopRow`,
  `kPasskeyPlaceholder`.
- `onboarding_model.dart` — `SetupMachine` (`Notifier<SetupState>`) with intent
  methods (`next`/`back`/`allow`/`findBridge`/`startTroubleshoot`/
  `stopTroubleshoot`/`confirmPasskey`/`heardBase`/`skipBase`/`selectMode`/
  `setName`/`setUnits`/`fault`/`recoverFault`/`reset`); `setupStateProvider`,
  `onboardingRequiredProvider`, `onboardingSkippedProvider`.
- `onboarding_sheet.dart` — `OnboardingBody`, `OnboardingFoot`,
  `OnboardingSurface` (the gate), `finishOnboarding`, `skipOnboarding`,
  `onboardingOverlayBody`/`onboardingOverlayFoot`.
- Wired: `shell/overlay.dart` resolves `DevOverlay.onboarding` to the real
  body/foot; `shell/shell.dart` mounts `OnboardingSurface` above everything while
  `onboardingRequiredProvider`; `features/live/live_page.dart` shows the
  `live-connect-bridge` empty state when skipped.

### Commands that work (repo root)

- `make app.test` — the N14 gate (analyze + format + `flutter test`, 609 pass).
- `cd app && flutter test test/features/onboarding_test.dart` — 8 widget/exit-gate
  tests.
- `cd app && dart test test/data/onboarding_setup_test.dart` — 18 pure tests.
- `cd app && dart test test/domain test/data` — data/domain gate (202).
- `make app.gen` (i.e. `cd app && dart run build_runner build`) if `AppSettings`
  changes again; `app_settings.freezed.dart` was regenerated.

### Contract facts later tasks need

- **`AppSettings` gained two fields** (additive, freezed regenerated):
  `bridgeName` (`String`, default `'Backyard Bridge'`) and `onboardStatus`
  (`OnboardStatus { fresh, skipped, paired }`, default `paired`).
- **The default is deliberately `paired` on the mock build** (every N2 scenario
  already carries a bridge, and the default keeps the 583 pre-N14 tests green).
  A factory-fresh install is `OnboardStatus.fresh`; N15 must seed `fresh` on a
  real first install and return to it on factory reset.
- **The eight-step machine is pure** (no Flutter) and in the `dart test` gate.
  `canAdvance` is the single I6 answer; `blockedReason` is the I5 copy. The
  monotonic guard: `beginAsync()` bumps `generation`; `resolve(token, fn)` drops
  any completion whose token is stale.
- **`setupStateProvider` is a `NotifierProvider` held above the overlay**, so
  closing and reopening the wizard resumes where it was; `finishOnboarding` and
  `skipOnboarding` call `reset()`.
- **Gating**: `onboardingRequiredProvider` is true only for `fresh`;
  `onboardingSkippedProvider` is true for `skipped` and drives the Live
  "connect a bridge" empty state (N14.13). `OnboardingSurface` is non-dismissible
  by scrim; its close X calls Skip.
- **`SheetOverlay` gained `footBuilder`** (an `OverlayBodyBuilder`); the host now
  prefers it over `foot`.
- **The passkey invariant is structural**: there is no code field, no code
  parameter, and `kPasskeyPlaceholder` is a fixed `'••••••'`. The test asserts no
  `Text` renders a 6-digit code. N15 implements the real platform passkey entry
  outside this state machine.
- Keys: `onboarding-surface`, `-body`, `-foot`, `-step-rail`, `-step-dot-<i>`,
  `-next`, `-back`, `-skip`, `-welcome`, `-welcome-copy`, `-preflight`,
  `-perm-<Name>`, `-perm-allow-<Name>`, `-scan`, `-scan-ring`, `-found-bridge`,
  `-found-sub`, `-troubleshoot-link`, `-troubleshoot`, `-ts-<i>`, `-passkey`,
  `-passkey-note`, `-sync`, `-listener-notice`, `-skip-Smoke X4`, `-network`,
  `-mode-<id>`, `-name`, `-name-field`, `-units`, `-done`, `-done-copy`,
  `-hop-<Hop>`, `-hop-status-<Hop>`, `-fault`, `-fault-title`, `-fault-body`,
  `-fault-recover`; Live `live-connect-bridge`.
  (Permission keys use the display name: `-perm-allow-Bluetooth`.)

### Deviations / gotchas

- **Default `onboardStatus: paired`** (see above) — the app never auto-opens the
  wizard on the mock's default settings. Tests set `fresh` explicitly.
- **The named `?overlay=onboarding` dev path is dismissible** (the sheet X
  dismisses it); the gate surface is not. Both share `OnboardingBody`/`OnboardingFoot`.
- The gate's sheet head shows the current **step** title/sub; the named overlay
  keeps the static `Welcome to Smoke` / `Pair your bridge` head (the body does not
  repeat titles).
- The prototype's troubleshoot rows were `permRow(..., false)` with an Allow
  button; the "Restart the bridge" row had no permission to grant, so ours are
  plain checklist rows (`SettingsRow`, no trailing).
- The network step selects a mode **locally**; it does not call
  `applyMode` (this is pairing, not a live transport switch). `finishOnboarding`
  calls `BridgeRepository.connect()` to bring the mock link up.
- Permission denial is only reachable from the platform in the real app; the
  widget renders the named denied state and the resumable Allow (pinned by a
  seeded `setupStateProvider` test). `SetupMachine.fault(...)` is the test/dev seam.
- `_OverlayPlaceholder` and `_propLine` were removed from `shell/overlay.dart`
  (onboarding was the last placeholder); the `shell-overlay-copy` /
  `shell-overlay-props` keys no longer exist. No test referenced them.

### Follow-ups

- N15: seed `OnboardStatus.fresh` on a real first install; set it back to `fresh`
  on factory reset; implement real BLE scan/pair, the platform permission
  requests, the real passkey entry (coaching copy stays), and `shared_preferences`
  persistence of `bridgeName`/`onboardStatus`.
- N16: no golden renders the wizard; consider one for the gate (fresh prefs,
  fixed repo, `shellPulseEnabledProvider:false`).