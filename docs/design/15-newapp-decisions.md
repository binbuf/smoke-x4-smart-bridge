# 15. The newapp redesign — decisions taken, and what is left

`docs/newapp.md` is the advisor's spec. This is the record of **what was actually
built, what was decided differently and why, and what remains**. It exists
because §J.9 routes eight open decisions to the codebase owner, and a decision
made in a commit message is a decision nobody can find later.

---

## 15.1 The eight open decisions (§J.9)

| # | Decision | Taken | Why |
|---|---|---|---|
| 1 | Samples session-agnostic (§D.2 Option A) vs keep the `session` FK | **Neither, exactly — the property without the mechanism** | See §15.2. |
| 2 | Combustion-style virtual core (§D.5) | **No for v1**, as recommended | The upstream is a single-point probe at ~30 s. A virtual core needs multi-point or edge sensing; building one on this input would be a physics model fitted to data that cannot constrain it. The OLS-rate + Newton-cooling ETA stays, with its guardrails. |
| 3 | Charting: keep `fl_chart` vs migrate (§H.2) | **Keep**, as recommended | LTTB decimation plus the min/max envelope already carries the 15-hour case. The migration is a profiling-led decision and no profile has been taken; taking it on spec would be rewriting the one part of the app nobody has complained about. |
| 4 | Daylight theme now vs later (§H.3) | **Now**, as recommended | The token architecture was built for it (14 §14.3.3) — it cost a preference and a `ThemeMode` switch, not a second design pass. |
| 5 | How much transport detail to expose (§F) | **Health chip everywhere + a Diagnostics page**, as recommended | Lane-by-lane race internals stay off normal screens. Diagnostics now carries real read-outs instead of the two-row stub. |
| 6 | Riverpod migration scope (J8) | **Deferred, deliberately** | See §15.4. |
| 7 | BLE full history vs the honest-copy fallback (§E.6) | **Built** — it landed with the v1.1 GATT work | `BleTransport.capabilities.fullHistory` is read from the device's `caps` b6 rather than declared, so the "full history needs Wi-Fi" copy is still correct in front of an older bridge. |
| 8 | Converge the live and history chart (§C.2) | **Yes**, as recommended | `/live/probe/:jack` uses the same `CookChart` + `ChartControls` + `CrosshairReadout` trio History uses. Two chart experiences for the same data is a seam a user feels and cannot name. |

---

## 15.2 Decision 1, in full: why samples keep their session key

§D.2 recommends Option A — make samples session-agnostic so a cook is a pure
range query and backdating rewrites nothing. §E.7 requires the opposite:
*"key everything on device-authoritative IDs `(bridgeId, sessionId, t)`; never
mint phone-side session IDs."*

They are both right about the thing they are protecting:

* §D.2 is protecting **edit cost**. A cook that owns a foreign key on every
  sample makes backdating an eighteen-hour cook a write of thousands of rows,
  which is a progress bar and a race.
* §E.7 is protecting **idempotency**. That key is what lets the delta sync
  upsert blindly, resume mid-transfer, and reconcile the same session seen over
  two transports without duplicating a row.

Taking either literally loses the other. So the build takes §D.2's *property*
via a different mechanism: samples keep the device's key and gain an indexed
**`unixMs`** column — a projection of `(session, t)` onto the wall clock. A cook
resolves membership by range query; no sample carries a cook id; backdating,
splitting and merging touch no sample row. `test/data/cook_repository_test.dart`
asserts the sample count before and after every verb, which is the invariant
this design exists to hold.

Two consequences worth knowing:

* **A bridge with no clock stores NULL**, never a fabricated epoch time (§E.7's
  "never silently rewrite historical device timestamps"). A cook over such a
  session pins itself with `cooks.anchorSessionId` and its range degenerates to
  "all of it".
* **A cook can span two device sessions** — the bridge restarting mid-brisket no
  longer splits the cook, because membership is time, not session id.

---

## 15.3 Where the spec was followed against its own letter

Three more places where the built thing differs from the written thing, each
because the written thing would have produced a control that lies.

### The alarm-rule patch (§G.2)

§D.2's `AlarmRules` table implies a per-rule `threshold` and `window`. The
firmware's `/api/v1/config/alarms` carries a rules array of
`{rule, enabled, severity}` **plus twelve global tunables** — `pit_band_f10`,
`pit_crash_sustain_s`, `battery_warn_pct` and so on. Writing a per-rule
threshold would have produced a settings screen posting JSON the bridge
discards, while the UI said "saved": the same class of bug as the settings
tree's silent no-op that §F exists to fix.

So the app's `AlarmRuleSpec` keeps its per-rule shape (it is the right shape for
the *app* tier, which has no such constraint) and maps onto the firmware's
tunables at the wire boundary. `AlarmRuleType.tiers` is **derived** from whether
the firmware has the rule at all, so the editor cannot offer a tenth rule the
bridge would ignore.

### `USE_FULL_SCREEN_INTENT` and the foreground service (§G.4)

§G.4 is right that the `dataSync` service type is fatal — Android 15 caps it at
six hours per twenty-four and then calls `onTimeout()`, which is a third of a
brisket. What §G.4 could not know is that **the service was not declared in the
manifest at all**: `flutter_foreground_task` does not declare its own, so the
Dart-side `connectedDevice` request had nothing to bind to. It is declared now,
and `test/platform/manifest_test.dart` pins the type as an *attribute* rather
than a substring, so the capped types cannot creep back in on a dependency bump.

`canUseFullScreenIntent()` returns the unknown answer rather than prompting:
`flutter_local_notifications` 22 exposes only `requestFullScreenIntentPermission`,
which shows a dialog, and spending a permission prompt to render a banner is the
mistake the notifications permission already taught.

### The rollback timer's clock (§E.3)

§E.3 specifies `revertAfterS: 120` from the request. The firmware starts the
deadline from when the new mode is **applied**, not when the request arrives, so
the existing 500 ms deferred apply does not eat the window. Re-arming keeps the
*original* known-good snapshot: two unconfirmed switches in a row must roll back
to the config that worked, not to the first typo.

---

## 15.4 Decision 6: Riverpod

`ProviderScope` wraps the app and nothing reads it; `ChangeNotifier` is the
de-facto container. J8 offers migrating the live session to a `StreamNotifier`
or removing the unused scope.

**Neither was done, and that is the decision.** The scope costs one widget and
removing it would be churn with no user-visible effect; migrating the live
session mid-redesign would put the app's most load-bearing object — the one that
owns the connection supervisor, the snapshot stream and the running cook — under
a rewrite in the same change as the IA, the schema and the cook model. J8 itself
notes Riverpod calls 3.0 *"a transition version"* with 4.0 expected soon.

The right moment is a change that is only that change. It is not blocked by
anything here.

---

## 15.5 What is not built

Honest list, so nobody looks for these.

| Item | Spec | Why not |
|---|---|---|
| **Android 16 Live Update** (`Notification.ProgressStyle`) | §G.4, §H.2 | Needs a platform channel and an Android 16 device to prove on. The ongoing notification is already built from the same `buildDashboard()` projection, so this is an upgrade to its rendering rather than new plumbing. |
| **CompanionDeviceManager association** | §G.4, J1 | Native Kotlin, and it changes the pairing flow — a `connectedDevice` foreground service already lifts the background-BLE restriction it was wanted for. Worth doing; not worth doing untested. |
| **Glance home-screen widget, Wear tile** | §H.2 | Separate build targets. |
| **SoftAP `WifiNetworkSpecifier` + `bindProcessToNetwork`** | §E.2 | `bindProcessToNetwork` is already wired for the hosted-AP join in setup (`platform/network_binder.dart`); the network-*request* API and its coach-mark copy are not. The mode-switch wizard works without it — it races the endpoint rather than requesting the network — but a phone that wanders back to cellular will fail the race. |
| **Escalation: repeat sound if unacknowledged after N minutes** | §G.5 | The four channels, quiet hours and the ack-from-notification action exist; the timed re-post does not. |
| **Photo attach on a cook** | §C.4 | Flagged nice-to-have in the spec. |
| **Localisation** | — | English only, as before. |

Two behaviours are pinned by tests but have **never run on hardware**: the
§E.3 rollback (27/27 host suites, but no board) and the alarm-rule push, whose
read-back has only been exercised against `MockTransport`. Both belong on the
next bench sitting.

---

## 15.6 Test posture

`app`: 1,177 tests. Two `sim_e2e` WebSocket integration tests fail in this
sandbox regardless of code and are a known environmental flake, not a
regression. `firmware`: 27/27 host suites. `tools/{sim,protogen,bridge_protocol}`:
all green.

The layering tests (§I.2's safety net) are unchanged and still hold: `domain/`
has zero Flutter imports, `ui/` is stateless over plain values, `features/`
composes, `data/` owns transports and the cache. The one place that was
inverted during this work — `data/transport/http_transport.dart` reaching into
`features/settings/` for an exception shape — was caught and fixed by moving
`BridgeRefusal` into the transport contract where it belonged.

Goldens were regenerated **once**, in the phase that changed them (§I.2's rule),
and the dashboard suite was repointed from the deleted pre-shell `DashboardView`
to the shipping `CookView` — same six shapes, both themes, now over the widget
that actually renders.
