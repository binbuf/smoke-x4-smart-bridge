# M6 — Hardening and release

**The milestone where the project stops being a build and becomes a thing you can give someone.**
Five milestones produced a bridge that receives, records, serves, provisions, renders and alarms —
and every one of them was installed the same way: a USB cable, an ESP-IDF toolchain, and someone who
knows what `idf.py -B build/heltec-v3 flash` means. M6 removes that requirement in both directions.
**T5** puts a merged image behind a browser button; **F14** lets the next version arrive over Wi-Fi
without the cable at all. **V3** and **V4** are what make either of those defensible: an update path
you cannot verify is a way to brick a device remotely.

The through-line is [§12.6 rule 8](../design/12-task-planning-notes.md), and in this milestone it is
not advice, it is the constraint the plan is shaped around:

> **Never OTA the only board with an image that has not been flashed over USB first.**

There is no spare board. An unbootable one is a total halt until it is recovered over USB, and the
recovery costs whatever cook was running. That single sentence is why F14 splits the way it does:
the image validator, the session machine, the health gate and the whole OTA path are **pure C with
injected ops, driven end to end on the host**, and the first byte that reaches real flash does so in
a bench sitting with a human watching. It is also why the health gate exists at all — LittleFS
mounted, Wi-Fi at its configured state, httpd listening, 120 s of uptime with no panic; fail any and
the next reset rolls back.

**Exit gate** ([M6 outline](M2-M6-outline.md), [11 §11.1](../design/11-roadmap-and-risks.md)):

- **v1.0.0 tagged**, with a merged binary, an APK, and a working web installer

22 tasks — **18 `board: no`, 4 `board: yes`**. The four board rows (F14.9, T5.6, V3.3, V4.3) are
**one sitting** ([§12.6 rule 7](../design/12-task-planning-notes.md)) at the end, in that order,
because each is the precondition of the next: you cannot OTA an image you have not flashed over USB
(rule 8), you cannot soak an image you have not confirmed boots, and you cannot sign off a release
checklist whose soak has not run. **The tag is the last thing that happens, and a human does it** —
nothing in this plan tags anything.

The lanes are F14 (device) and T5 (host tooling) running in parallel, V3 joining once F14.8 gives
the soak something to read, and V4 last because it is the audit of everything above it.

> **Status 2026-07-23 — all 18 `board: no` tasks are done.** Firmware host suite 24/24 → **25/25**
> (`test_app_ota` adds ~1,500 checks — the image inspector against the first 288 bytes of the real
> builds, admission, the phase machine, the injected flash seam, and the §3.7 gate; `test_app_api`
> grows with the `/ota` route, `/status.ota` and `/debug/tasks`). App suite 496/496 → **501/501**.
> Two new tool packages — `tools/flash` (20 tests) and `tools/soak` (8) — are green, `tools/sim`'s
> OTA test is reconciled to the real contract, analyzer and formatter clean across app and tools,
> `protogen --check` green, and **both images build** (product 0x1437d0, bench 0xcd6f0). The four
> `board: yes` rows (F14.9, T5.6, V3.3, V4.3) are the only remainder and are the single sitting
> above; their runbook is the M6 section of [hardware-verified](../hardware-verified.md).
>
> The merged image `tools/flash` builds was checked **byte-identical to `esptool merge-bin`**
> (SHA-256 match) as an independent cross-check, and the soak recorder was run against the sim and
> the live bridge to confirm it polls, resumes across a kill, and reports.
>
> Decisions this milestone was asked to make, and made — beyond the section below:
>
> | Question | Answer | Recorded in |
> | --- | --- | --- |
> | Q-F: public or private repo | **Public.** The docs were the safe superset already; `release.yml` targets Pages and `T5.5`'s sweep is a repeatable test, not a one-off read | [standing-work](standing-work.md), `tools/flash/test/version_test.dart` |
> | The gate's "both partitions" clause | **`cooks`, not "both".** Taken literally the clause can never pass — D13 leaves `www` unformatted on purpose — so it would roll back every image forever | `ota_gate.c`, `main.c` |
> | Passive rollback or an active reboot-and-invalidate on gate failure | **Passive** — three of the four clauses fail for reasons that are not the firmware's (dark router, jammed channel, pulled antenna), and forcing a reboot turns that into a rollback loop that costs the cook | `app_ota.c`, asserted in `test_app_ota.c` |
> | Where the version string comes from | **The app descriptor** (`CONFIG_APP_PROJECT_VER`), read by `esp_app_get_description()`. `/status.fw`, the mDNS TXT, the `hello` frame and the OTA reply were four literals that had already drifted from the image's own `e32feb0` | `sdkconfig.defaults`, `app_api.c`, `app_net.c` |
> | How the soak reads watermarks | **`GET /api/v1/debug/tasks`**, not a serial log — a 24 h unattended run cannot hold a cable — carrying the one field `/status` lacks and R2 needs: `largest_free_block` | `app_api_core.c`, `app_api.c` |
> | The heap question's closing criteria | **Fixed before the run**: an 80 KB floor, a −256 B/h slope, a 32 KB fragmentation floor, a 512 B stack margin. Reading a 24 h trace and picking the threshold afterwards is the hazard | this plan's decisions, `tools/soak/lib/src/report.dart` |
> | The app's file picker | **v1.1.** A12.6 finishes the transport half (real, sim-tested); with no `FirmwareImageSource` the screen explains where to get an image rather than showing a dead button | `bridge_transport.dart`, `settings_route.dart` |
> | D13 (fallback web UI) | **No, and the partition is kept** (V4.2) | [00 §Decisions](../design/00-overview.md) |
>
> **Two things worth flagging for the bench, found while building:** the sim had been emitting a
> `done` OTA phase that is **not in `WsOtaFrame`'s enum**, and replying `{ok, bytes, rebooting}`
> where the spec says `OtaAccepted` — two of the three OTA contract sites disagreed and nothing
> forced them together until the device half existed (F14.6 fixed both). And `/status.fw` was a
> string literal disagreeing with the image's own descriptor since M2 — the same
> shape-complete-placeholder trap `/status.ble` was, caught before the board could bill for it.

> **Read this before writing a line of F14.** `POST /api/v1/ota` is currently **deliberately
> unregistered**, and the router says so in a comment: *"an honest 404 rather than a lying 503
> stub"*. That comment is the task. The endpoint's whole contract already exists in three places
> that must agree when it lands — [openapi.yaml](../../protocol/openapi.yaml)'s `uploadOta`
> operation and its `OtaAccepted` / `WsOtaFrame` schemas, `tools/sim`'s `_ota` handler, and the
> app's `FirmwareSettingsView` — and **two of the three are already wrong** (F14.6 is that
> reconciliation). Write the device against the spec, not against the sim.

---

## Decisions to carry into planning

The design docs settle the partition table, the health gate's four clauses, and the shape of the
release artifacts. They do not settle the following, and each was decided here rather than
improvised at a call site.

### Q-F is answered: **the repo is public**

[§12.9](../design/12-task-planning-notes.md) and [standing-work](standing-work.md) both flag this as
the one open decision gating T5, because a private repo cannot serve an installer from GitHub Pages
and `esp-web-tools` needs the firmware assets fetchable over plain HTTPS with no token.

**Public.** The docs have been written as though public since M0 — the upstream parser is carried
under MIT with attribution ([D9](../design/00-overview.md)), `docs/reference/` is vendored
read-only, and nothing anywhere assumes privacy — which is the safe superset either way. Choosing
private now would mean either abandoning the browser installer or hosting the assets somewhere else,
and neither is a trade worth making for a BBQ thermometer bridge. T5 plans for Pages.

The one obligation this creates is stated as a task rather than a hope: **T5.5 sweeps the tree for
anything that should not be public** — a committed PSK, a home SSID, a token, a MAC address in a
fixture — before the first release workflow runs.

### The health gate asks for `cooks`, not "both partitions"

[03 §3.7](../design/03-firmware-architecture.md) lists the first clause as *"LittleFS mounted, both
partitions"*. **Taken literally that clause can never pass**, and would roll back every image
forever: [D13](../design/00-overview.md) declares `www` and leaves it **unformatted on purpose**,
`app_api` deliberately does not mount it, and `ops_www_available()` returns a hardcoded `false` with
a comment saying why. A gate that requires a mount the product intentionally does not perform is not
a safety feature, it is a brick.

So the clause is **`cooks` mounted and writable** — the partition the product actually needs, and
the one whose absence means the bridge has stopped being a recorder. If D13 ever flips and `www`
gets content, the gate grows a second clause with it. This is written down rather than quietly
implemented because the difference between the doc's sentence and the code's behaviour is exactly
the kind of thing a future reader would file as a bug.

### A crash fails the gate immediately; a brownout does not

*"120 s of uptime with no panic"* is only observable as one thing: **this boot's reset reason.** A
panic reboots the device, so a running image cannot report a panic it suffered — it can only report
that the boot before it ended in one.

The split matters. `ESP_RST_PANIC`, `ESP_RST_TASK_WDT` and `ESP_RST_INT_WDT` are **the image's
fault** and fail the gate the instant they are seen, without waiting out the 120 s — waiting serves
no purpose when the verdict is already known. `ESP_RST_BROWNOUT`, `ESP_RST_POWERON` and
`ESP_RST_SW` are **the world's**: a pack that sagged during a Wi-Fi TX burst
([01 §1.6](../design/01-hardware.md)) says nothing about whether the new firmware is sound, and
rolling back over it would punish a good image for a flat battery.

A coredump *stored* from some previous boot is likewise not evidence — it can be months old and
belong to an image that is no longer installed. The gate reads the reset reason, not the coredump
partition.

### The gate does not force a reboot when it fails

Two readings of §3.7 are available: *don't mark valid and let the next reset roll back* (passive), or
*call `esp_ota_mark_app_invalid_rollback_and_reboot()` now* (active). The doc's own words are
**"fail any of these and the next reset rolls back"** — passive — and that is what gets implemented,
for a reason worth keeping:

**Three of the four clauses can fail for reasons that are not the firmware's.** The router is off,
so STA never gets an IP. The AP channel is jammed. Someone pulled the antenna. Forcing a reboot on
those turns an environmental problem into a **rollback loop that costs the cook**, and the previous
image would have failed the same gate for the same reason. Not marking valid preserves the safety
property — the bad image cannot survive a power cut — while a bridge that is still recording keeps
recording. The failure is logged loudly, raised as a `system_fault` alarm so the app can say
*"the update did not confirm"*, and reported in `/status`.

### The image is validated before a single byte reaches flash

[06 §6.2](../design/06-device-api.md) says the endpoint *"verifies the image header and SHA-256"*.
The SHA-256 is `esp_ota_end()`'s job and arrives at the *end* of a 1.3 MB upload. The header check
is ours and arrives in the **first 288 bytes**, which is where it earns its keep.

The most likely mis-upload is not a corrupt file, it is **the wrong one of the two files this
project ships**: `smoke-bridge-heltec-v3-1.0.0.bin` (merged, flashable at `0x0`) instead of
`smoke-bridge-1.0.0-ota.bin` (app only). The merged image starts with the *bootloader*, and writing
it into an OTA slot produces a device that cannot boot. Three checks against the real layout catch
it and every other realistic mistake:

| Check | Offset | Catches |
| --- | --- | --- |
| `magic == 0xE9` | 0 | `partition-table.bin` (starts `AA 50`), a `.zip`, an APK, an ELF |
| `chip_id == 0x0009` | 12 (u16 LE) | an ESP32 or ESP32-C3 image built for another board |
| app-desc `magic == 0xABCD5432` | 32 (u32 LE) | **the merged image**, and `bootloader.bin` — both have `0xE9` and the right chip id, and neither carries an `esp_app_desc_t` |

`project_name` (offset 80) and `version` (offset 48) are **read and reported, not enforced.** A fork
that renames its CMake project should not be locked out of its own hardware, and the SHA-256, the
rollback gate and rule 8 are the real protections. The reply names what it is about to install so
the human can see it is what they meant.

### One version string, and it comes from the app descriptor

Today `/status.fw` is the string literal `"1.0.0"` in `ops_sysinfo`, while the image's own descriptor
carries `e32feb0` — a git-describe abbreviation. **Two sources of truth for "what is running"**, and
the OTA reply is about to become a third. [10 §10.8](../design/10-repo-tooling-and-testing.md) is
explicit that firmware and app share a version because the API contract binds them.

`CONFIG_APP_PROJECT_VER_FROM_CONFIG=y` plus `CONFIG_APP_PROJECT_VER="1.0.0"` pins the descriptor;
`ops_sysinfo` reads `esp_app_get_description()->version` instead of a literal. After that there is
one place to bump for a release, the mDNS TXT record and `/status` and the OTA reply cannot
disagree, and the version the app enforces a minimum against ([06 §6.5](../design/06-device-api.md))
is the version the image actually is.

### The soak reads watermarks over HTTP, not over a serial cable

[01 §1.4](../design/01-hardware.md) and [standing-work](standing-work.md) specify per-task stack
watermarks *"logged once a minute at debug level"*. That is right for a bench session and useless
for **V3**: a 24-hour unattended soak cannot hold a serial cable, and a log line that nobody
captures is not a measurement.

`GET /api/v1/debug/tasks` is added — additive, which [06 §6.5](../design/06-device-api.md) states is
not breaking — carrying every task's declared stack against its high-water mark, plus the two heap
numbers `/status` already has **and the one it does not: the largest free block.** That last field is
the point. [R2](../design/11-roadmap-and-risks.md) names fragmentation specifically —
*"heap fragmentation on a device that runs for 24 hours is its own problem"* — and total free heap
cannot see it. A bridge with 80 KB free in 2 KB pieces cannot allocate a TLS buffer and will fail in
a way that looks like a heap problem while every heap number looks fine.

The once-a-minute debug log is implemented too. It is just not what the evidence rests on.

### The heap question closes on stated criteria, chosen **before** the run

[hardware-verified](../hardware-verified.md)'s open question has been waiting since M3 for exactly
this soak, and M5 declined to pre-empt it. The hazard now is the opposite one: reading a 24-hour
trace and deciding afterwards which number was the target. So the criteria are fixed here, in
advance, and V3.3 either meets them or does not.

| Criterion | Threshold | Why this number |
| --- | --- | --- |
| `min_free_heap` floor | **≥ 80 KB** for the whole run | [standing-work](standing-work.md) already commits CI to failing below 80 KB. The measured 69–78 KB sits *under* it, so this is the clause most likely to bite — and if it does, the answer is not "lower the bar" |
| `free_heap` trend | least-squares slope over 24 h **≥ −256 B/h**, i.e. under 6 KB lost per day | A leak is a slope, not a level. V3a.1 saw < 0.6 KB of movement over 165 s, which cannot distinguish a leak from noise; 24 h can |
| `largest_free_block` floor | **≥ 32 KB** | Fragmentation, per R2. 32 KB is the largest single allocation the system makes in normal operation (an httpd socket's buffers plus a LittleFS cache) |
| Task stack headroom | every task **≥ 512 B** high-water margin | `ws_push` overflowed at 3072 on the board once already. A margin under 512 B is a row to renegotiate in `tasks.h`, not a pass |

**All four hold → the 150 KB target was wrong** (option 1 in the open question), and
[01 §1.4](../design/01-hardware.md)'s estimate is corrected to the measured floor with NimBLE's real
≈ 90–100 KB cost written in beside it. **Any one fails → options 2 and 3** (buffer counts,
concurrency caps) become a design conversation with a 24-hour trace to argue from, which is exactly
what M3 said it wanted and could not have. Either way the question closes with evidence rather than
with a shrug.

### The merged image is built here, not shelled out to esptool

`esptool merge-bin` would work. It also puts Python and an esptool version on the critical path of
every release and every CI run, for an operation that is **arithmetic**: place four files at four
offsets in a `0xFF`-filled buffer.

Doing it in Dart makes it a **host-tested unit** — offsets read from the build's own
`flasher_args.json` rather than transcribed, overlap detection, and an assertion that the byte at
`0x20000` in the merged image is the app image's first byte. The one thing esptool does beyond
concatenation is patch flash mode / size / frequency into bytes 2–3 of the image at offset 0; that is
implemented, and asserted to be a **no-op for our build**, because the bootloader was already built
with `dio / 80m / 8MB`. If it ever stops being a no-op, a test says so.

[10 §10.8](../design/10-repo-tooling-and-testing.md)'s manual `esptool` command stays documented for
people who prefer it, and T5.2 emits it verbatim so the copy in the README cannot drift from the
offsets the build actually produced.

### D13 is decided: the fallback web UI does **not** ship in v1.0.0, and the partition stays

The outline is explicit that this is decided in M6 and built (if at all) in v1.1. Deciding it:

**No.** Every argument [06 §6.4](../design/06-device-api.md) makes for it is now covered elsewhere.
*"Setup and recovery from a laptop when the app isn't installed"* — that is what T5's browser
installer and the BLE onboarding do. *"A browser target for the captive portal"* — the built-in page
plus the flash-resident probe answers already do that, and were verified on the board in M2.
*"Debugging without a build toolchain"* — `curl` against a documented OpenAPI spec, plus
`/debug/packets`, `/debug/novelty`, `/debug/coredump` and now `/debug/tasks`.

**And the partition is not reclaimed either.** Handing 512 KB back to `cooks` is a one-line change
that costs a **repartition**, and a repartition erases every stored cook — the precise cost the
reservation was made to avoid. 2,432 KB is already 54 days of history; nobody is short. The
partition stays declared and unformatted, `ops_www_available()` keeps returning `false` with its
comment, and v1.1 can revisit it for free. Recorded against D13 in
[00 §Decisions](../design/00-overview.md) rather than left in this plan.

### The app's upload path becomes real; its file picker is v1.1

A12.5 shipped `FirmwareSettingsView` in M4 with the `409` copy, the force path, and progress
rendering — and its `onUpload` callback is **wired to nothing**. `HttpTransport` advertises
`ota: true` and has no method that uploads. The button is decoration.

M6 makes the transport half real: `HttpTransport.uploadFirmware()` streams a `.bin` to
`POST /api/v1/ota`, surfaces the `409` the device now actually returns, and reports progress from
the WebSocket's `ota` frames — all of it drivable against `tools/sim`, which is the point.

What it does **not** add is a file-picker plugin. Choosing a `.bin` on Android means SAF, a new
dependency, an Android-side integration `flutter test` cannot execute, and a manifest change — real
scope, none of it in M6's epic table, and none of it needed for the exit gate. Instead the screen
takes an optional `FirmwareImageSource` from `AppEnv` exactly the way it takes `notifications`
(nullable, *"every consumer degrades to in-app surfacing rather than throwing"*), and with none
registered it says plainly where to get an image and how to install it. **A button that explains
itself beats a button that does nothing**, and the transport underneath it is finished and tested
for whenever v1.1 adds the picker.

### No new task rows, again

The health gate runs on an `esp_timer` callback; the OTA write runs on the **httpd task**, which
already has the board-found 8192-byte stack. `tasks.h` does not grow, the 32 KB assert is untouched,
and `test_tasks_table.c`'s pinned sum does not move. M6's own heap cost is a single `esp_ota_begin()`
partition handle and one 4 KB receive buffer on the httpd stack — and it exists only while an upload
is in flight, which by construction is never during a cook unless someone forced it.

---

## F14 — OTA and the rollback health gate

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** §12.8 does not list F14,
> because when it was written the risk here looked like plumbing. It is not. **F14 is the only epic
> in the project whose failure mode is losing the hardware.** Every other bug costs a cook, a
> session file, or an afternoon; a bad OTA costs the board, and there is no second one.
>
> That shapes the whole epic. The image validator, the session machine and the health gate are
> **pure C driven from the host with fakes** (F14.1–F14.3), the IDF glue is a thin seam over
> `esp_ota_*` that is *itself* host-driven through injected ops (F14.4), and the first real write to
> flash happens in F14.9 with a human watching and a USB cable in reach. Not one task before F14.9
> touches the board.
>
> The second flag is that **the contract already exists in three places and two of them are wrong.**
> `openapi.yaml` documents `OtaAccepted` and a five-value `WsOtaFrame.phase` enum; the sim returns
> `{ok, bytes, rebooting}` and emits a `done` phase that is not in the enum; the app renders whatever
> phase string arrives. Writing the device against the sim would propagate the drift into firmware.
> F14.6 reconciles all three, and the device is written against the **spec**.

### F14.1 app_ota: inspect the image header as a pure core

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [03 §3.7](../design/03-firmware-architecture.md)

`ota_image.c` — pure C11, no ESP-IDF, no allocation: the first 288 bytes of an upload in, a verdict
plus the descriptor's strings out. The three hard checks are the decisions section's table (`0xE9`,
`chip_id == 0x0009`, app-desc magic `0xABCD5432`); `version`, `project_name` and `idf_ver` are read
out and reported. A buffer shorter than 288 bytes is **"not yet decidable"**, not "invalid" — the
caller is streaming and must be able to ask again after the next chunk rather than rejecting an
upload that has barely started.

Every offset is taken from a real image rather than from a struct definition, and the fixtures make
that checkable: `protocol/fixtures/ota/` carries the first 288 bytes of the **actual heltec-v3
build**, of `bootloader.bin`, and of `partition-table.bin`.

**Done when:** the committed app-image header parses to project `smoke_bridge` and the pinned
release version; the bootloader header and the partition-table header are each rejected with a
*distinct* reason; a buffer of 287 bytes returns "undecided" and one of 288 does not; an all-zero
and an all-`0xFF` buffer are rejected without reading past the end; a descriptor whose strings are
unterminated is asserted to yield NUL-terminated output; and the reason strings are asserted to
differ, because "invalid image" with no detail is what makes a support conversation take an hour.

### F14.2 app_ota: implement the upload session — admission, accounting, and the phase machine

- **blocked-by:** F14.1 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [10 §10.5](../design/10-repo-tooling-and-testing.md)

`ota_core.c`, still pure. **Admission** first, because it is the rule the outline calls out by name:
a session active and no `?force=1` → refuse, and the refusal is `409 session_active` with the
device's own sentence, not a bare code. A second concurrent upload → `503 ota_in_progress`. A
zero-length body → `400 invalid_body`. Then **accounting**: bytes received against the declared
content length, the phase machine over §6.3's exact five values (`receiving` → `writing` →
`verifying` → `rebooting`, or `failed` from anywhere), and a progress emitter that fires on every
phase change and every whole 5 % — **not per chunk**, because a 1.3 MB image in 4 KB reads is 320
frames and the WebSocket cap is two clients.

Failure is a state, not an exception: any error transitions to `failed` with a reason, and the
session must be resettable so a failed upload does not wedge the endpoint at `503` forever. That is
the bug this task exists to not have.

**Done when:** admission is table-tested for the four outcomes including `force=1` overriding an
active session; a 1.3 MB image in 4 KB chunks is asserted to emit exactly 21 progress events
(0 %…100 %) and to reach `rebooting`; a chunk arriving after `failed` is rejected rather than
accounted; a second `begin` while one is live returns `in_progress`; an abort returns the session to
idle so the **next** upload is admitted; and the byte count is asserted to match the image exactly,
because an off-by-one here is an image that fails SHA-256 after four minutes of upload.

### F14.3 app_ota: implement the §3.7 health gate as a pure verdict

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [03 §3.7](../design/03-firmware-architecture.md)

`ota_gate.c`: a facts struct in, one of four verdicts out — `NOT_APPLICABLE` (the running image is
not pending-verify, so there is nothing to confirm), `WAITING`, `PASS`, `FAIL` — plus a bitmask
naming *which* clause failed, because "the health gate failed" in a log with no detail is the same
useless sentence as "invalid image".

The two clauses the decisions section reinterprets are implemented as written there: the storage
clause is **`cooks` mounted and writable**, not "both partitions" (D13 makes the literal reading
unsatisfiable); and a **crash reset fails immediately** without waiting out the 120 s, while a
brownout or a power-on does not fail at all. Uptime is a parameter, not a call — the whole function
is a table test.

**Done when:** a table walks all four verdicts including every single-clause failure; an image that
is not pending-verify is asserted `NOT_APPLICABLE` **even with every clause failing**, because
confirming or rolling back an image nobody is verifying is a bug; a panic reset is asserted to fail
at 1 s rather than at 120 s; a brownout reset with all clauses met is asserted to **pass**; 119 s is
asserted `WAITING` and 120 s is not; and the failed-clause mask is asserted to name every failing
clause rather than only the first.

### F14.4 app_ota: implement the ESP-IDF glue behind an injected OTA seam

- **blocked-by:** F14.2, F14.3 · **verify:** H · **board:** no
- **design:** [03 §3.1, §3.7](../design/03-firmware-architecture.md)

The thin half, and it stays thin: `esp_ota_begin` on `esp_ota_get_next_update_partition`,
`esp_ota_write` per chunk, `esp_ota_end` (which is where the SHA-256 is actually checked),
`esp_ota_set_boot_partition`, and a **deferred** `esp_restart` on an `esp_timer` so the HTTP reply
reaches the client before the socket dies. Plus the gate half: `esp_ota_get_state_partition` to learn
whether we are pending-verify, `esp_reset_reason` for the crash clause, a 10 s periodic timer that
evaluates F14.3 until it stops returning `WAITING`, and `esp_ota_mark_app_valid_cancel_rollback` on
`PASS`.

Every one of those is an op, so the whole thing runs on the host against fakes. `esp_ota_end`
failing with `ESP_ERR_OTA_VALIDATE_FAILED` — the corrupt-image case that matters — is a fake
returning an error, not a hardware event. **No new task row**: the write runs on the httpd task, the
gate on an `esp_timer` callback.

**Done when:** the seam is driven host-side for a clean upload, a `begin` that fails (no free slot),
a `write` that fails mid-image, an `end` that fails validation (asserted to leave the boot partition
**unchanged** — this is the clause that keeps a corrupt image from being booted), and a `set_boot`
that fails; the reboot is asserted deferred rather than immediate; the gate timer is asserted to stop
polling after `PASS` or `FAIL`; a `FAIL` is asserted **not** to call any rollback-and-reboot function
(the decisions section's passive choice, asserted rather than remembered); and both images build.

### F14.5 app_api: register `POST /ota` and stream the body into it

- **blocked-by:** F14.4 · **verify:** H · **board:** no
- **design:** [06 §6.1, §6.2, §6.3](../design/06-device-api.md)

The honest 404 becomes the route. Two things make this more than registration:

**The 8 KB body cap does not apply, and must not be applied.** `common_handler` buffers every request
into a static `APP_API_MAX_BODY` array and returns `413` beyond it; a 1.3 MB image must be
intercepted **before** that and read in ≤ 4 KB chunks straight into `esp_ota_write`. Nothing is ever
materialised — the same structural rule F9 inherited, now on the request side.

**Progress frames go through the push queue, not straight to the sockets.** `ws_broadcast` is
documented as running *only* on the `ws_push` task; the OTA handler runs on the httpd task. A new
push-message kind carries `(phase, pct)` across, which is the same discipline `ws_push` and
`ble_push` already enforce and the same one whose absence crashed the M2 bench sitting inside lwip.

The bearer gate applies exactly as it does to every other API route, and the reply is §6.2's
`OtaAccepted` shape.

**Done when:** a host-driven upload of the committed header fixture plus padding returns 200 with
`accepted`, `image_size_b`, `slot` and `rebooting_in_ms`; the same upload with a session open returns
`409 session_active` and **writes nothing**, while `?force=1` proceeds; a bad header returns
`400 invalid_body` naming the reason and is asserted to abort before any write; a wrong bearer token
returns `401` before admission is even evaluated; progress frames are asserted to be enqueued rather
than broadcast from the handler; and the route is asserted to be the *only* one exempt from the 8 KB
cap.

### F14.6 protocol: make the sim answer the OTA contract the device answers

- **blocked-by:** F14.5 · **verify:** H · **board:** no
- **design:** [06 §6.2, §6.3](../design/06-device-api.md), [10 §10.3](../design/10-repo-tooling-and-testing.md)

Three implementations of one contract, and until now nothing forced them to agree because the device
half did not exist. It does now, and the sim is wrong twice: it replies `{ok, bytes, rebooting}`
where the spec says `OtaAccepted`, and it emits a `done` phase that is **not in `WsOtaFrame`'s
enum**. The app renders whatever string arrives, so nobody noticed.

The sim adopts the spec's reply shape and the spec's five phases, and — the part that actually
matters — **it validates the image header with the same rules the device uses**. A sim that accepts
`[1, 2, 3, 4]` as firmware gives the app path false confidence in exactly the case that costs a
board. Its tests move to the committed header fixture, which is what both sides now parse.

**Done when:** `dart test` in `tools/sim` passes with the reply asserted against `OtaAccepted`'s
required fields and the terminal phase asserted to be a member of the spec's enum; an upload of four
arbitrary bytes is asserted to be **refused** by the sim, as the device refuses it; the contract test
in `tools/protogen` still passes; and the app's existing OTA progress test is asserted to still pass
against the renamed phases, or updated with the change called out.

### F14.7 firmware: one version string, and it comes from the app descriptor

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [10 §10.8](../design/10-repo-tooling-and-testing.md), [06 §6.5](../design/06-device-api.md)

`CONFIG_APP_PROJECT_VER_FROM_CONFIG=y` and `CONFIG_APP_PROJECT_VER="1.0.0"` in
`sdkconfig.defaults`, and `ops_sysinfo` reads `esp_app_get_description()->version` instead of the
literal `"1.0.0"` it has carried since M2. The descriptor, `/status.fw`, the mDNS TXT record, the
WebSocket `hello` frame and the OTA reply then all say the same thing, and a release is one line to
bump.

Small, and it belongs before F14.9 rather than after: the whole point of the bench row is watching a
version change over the air, and it cannot be watched if every build reports `1.0.0` regardless of
what it is.

**Done when:** the built image's descriptor is asserted to carry `1.0.0` at offset 48 (through
F14.1's parser, against the committed fixture regenerated from this build); `/status.fw`, the `hello`
frame's `fw` and the mDNS TXT `fw=` are asserted to come from one source rather than three literals;
and both images build.

### F14.8 main: wire boot step 16 to the real gate, and report it in `/status`

- **blocked-by:** F14.4, F14.7 · **verify:** H · **board:** no
- **design:** [03 §3.4, §3.7](../design/03-firmware-architecture.md), [06 §6.2](../design/06-device-api.md)

Step 16 of the boot table has read `"OTA health gate: stub until F14"` since M0. This is F14. The
step arms the gate with the fact-suppliers main.c is uniquely placed to give it — `app_net`'s state,
`cook_store`'s mount, `app_api`'s listening flag (a new one-line accessor), `esp_reset_reason` — and
returns immediately; the verdict lands up to 120 s later, on the timer.

Then the part that makes the bench row observable without a serial cable: an additive `"ota"` object
in `GET /api/v1/status` carrying the running slot, whether it is pending-verify, the gate's verdict,
and the failed-clause names when there are any. **This is the `/status.ble` lesson applied before the
board can teach it again** — a shape-complete placeholder that outlives its milestone reports a
healthy gate on a device that never confirmed one, and [hardware-verified](../hardware-verified.md)
records what that cost the last time.

**Done when:** the boot step is asserted to arm rather than block (the sequence completes in
`boot_seq`'s own test with the gate still `WAITING`); `/status.ota` is asserted for the four verdicts
including the failed-clause list; the fixture, `openapi.yaml`'s `Status` schema and the sim all carry
the new object with the fields in the same order; a build that is not pending-verify is asserted to
report `not_applicable` rather than a cheerful `passed`; and a gate failure is asserted to raise
`system_fault` exactly once rather than on every timer tick.

### F14.9 bench: the first real OTA, and the deliberately broken image

- **blocked-by:** F14.8, T5.6 · **verify:** B · **board:** yes
- **design:** [03 §3.7](../design/03-firmware-architecture.md), [10 §10.5](../design/10-repo-tooling-and-testing.md), [hardware-verified](../hardware-verified.md)

**The row rule 8 exists for, and it runs second in the sitting — after T5.6 has put the same image on
the board over USB.** Not first. The order is the rule.

Four observations, in order. **One:** with a session deliberately active, `POST /api/v1/ota` is
refused `409` and the cook is untouched; `?force=1` then proceeds. **Two:** a good image uploads,
verifies, reboots, and comes back reporting the new version — and `/status.ota` shows
`pending_verify` for up to 120 s and then `passed`. **Three:** the health gate is failed on purpose —
the cleanest way is to OTA with the test router powered off so the STA clause cannot be met — and the
next reset is confirmed to roll back to the previous slot. **Four:** a deliberately broken image (the
merged binary, uploaded to the OTA endpoint on purpose) is refused by F14.1 before a byte is written.

A USB cable and `idf.py flash` stay within reach for the whole row. If anything goes wrong, that is
the recovery, and it is why this is a bench row and not a CI job.

**Done when:** all four observations are recorded in `docs/hardware-verified.md` with the versions
before and after, the observed gate timing, and the slot names; the rollback is confirmed by reading
`/status.ota` and the running version after the reset rather than inferred; and anything that
behaved differently from this plan is a named row rather than an omission.

---

## T5 — `tools/flash`, the merged image, and the browser installer

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** the outline's own warning is
> the one to keep — **T5 cannot copy the reference's `merge_bin` offsets.** Its partition table is a
> different table on a different flash size: it merges at `0x0 / 0x8000 / 0x10000 / 0x210000` with a
> single `factory` app and a SPIFFS blob, and ours is `0x0 / 0x8000 / 0xf000 / 0x20000` with dual
> OTA slots and an `otadata` the reference does not have at all. The root `Makefile` already carries
> a comment saying so. **Every offset is read from the build's own `flasher_args.json`**, never
> transcribed — which is the actual mitigation, because a transcribed offset is right until the day
> the partition table moves.
>
> The installer page itself *is* worth copying outright, and is MIT.

### T5.1 tools/flash: build the merged image from the build's own `flasher_args.json`

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [10 §10.8](../design/10-repo-tooling-and-testing.md), [03 §3.5](../design/03-firmware-architecture.md)

A Dart package in the existing workspace. It reads `flasher_args.json` from a build directory, places
each part at its offset in a `0xFF`-filled buffer, and writes one image flashable at `0x0` —
bootloader, partition table, `ota_data_initial`, app. Overlapping parts are an **error**, not a
last-writer-wins surprise, and a part whose offset lands beyond the declared flash size is an error
too.

The one behaviour beyond concatenation is esptool's: patch flash mode into byte 2 and
`(size << 4) | freq` into byte 3 of the image at offset 0. Implemented, and asserted to be a no-op
for a `dio / 80m / 8MB` build — the assertion is the interesting half, because the day it stops being
a no-op is the day someone changed a flash setting without changing the bootloader.

**Done when:** the merged image is asserted byte-identical to the parts at their offsets (spot-checked
at `0x0`, `0x8000`, `0xf000` and `0x20000`); its length is asserted to be `0x20000 + len(app)` with
no trailing padding; overlapping parts and out-of-range offsets each fail with a named error;
`ota_data_initial` is asserted **present**, because a merged image without it boots nowhere; and the
header patch is asserted to be a no-op against the real build's bytes and *not* a no-op against a
synthesised `qio / 40m / 4MB` header.

### T5.2 tools/flash: emit the esp-web-tools manifest and the documented esptool command

- **blocked-by:** T5.1 · **verify:** H · **board:** no
- **design:** [10 §10.8](../design/10-repo-tooling-and-testing.md)

Two outputs from the same knowledge, so neither can drift from the image. The **manifest** is
`esp-web-tools`' `manifest.json`: `chipFamily: "ESP32-S3"`, one part at offset 0 (the merged image),
`new_install_prompt_erase` set — because a board carrying a previous install has an `otadata` and a
`cooks` filesystem that a fresh flash should not inherit silently. The **command** is §10.8's
`python -m esptool ... write_flash 0x0 <image>`, generated with the real chip, the real offset and
the real filename rather than typed into a README.

Both go in the release artifact set, and both are printed by the tool so a human flashing by hand is
copying something that was computed.

**Done when:** the manifest validates against `esp-web-tools`' documented shape and names exactly one
part at offset 0; its `chipFamily` is asserted to match `flasher_args.json`'s `chip`; the emitted
esptool command is asserted to carry the merged image's actual filename and `0x0`; and a golden test
pins both outputs so a change to either is a reviewed diff.

### T5.3 tools/installer: the browser installer page

- **blocked-by:** T5.2 · **verify:** H · **board:** no
- **design:** [10 §10.8](../design/10-repo-tooling-and-testing.md), [05 §5.7](../design/05-connectivity-and-provisioning.md)

The page a user with Chrome or Edge opens, plugs the board in, and clicks Install — no Python, no
esptool, no toolchain. Copied from the reference (MIT, and the reference's is well judged), retargeted
at our manifest and our board, with **the one addition §10.8 specifies**: a first-boot step that hands
off to BLE onboarding — *"open the Smoke Bridge app and look for `SmokeBridge-XXXX`"* — because a
flashed board with no app is a board with a blinking LED and no next step.

It also carries what the reference's page does not need to: the antenna warning
([01 §1.5](../design/01-hardware.md) — powering an SX1262 with no antenna damages it), and the
honest sentence that a fresh install erases stored cooks.

**Done when:** the page loads with no build step and no bundler; a test asserts it references the
manifest T5.2 emits and nothing else that would 404 on Pages; the antenna warning and the
`SmokeBridge-XXXX` handoff string are both asserted present; and the page is asserted to name the
same version the manifest does.

### T5.4 ci: `release.yml` — the tag-driven release

- **blocked-by:** T5.3 · **verify:** H · **board:** no
- **design:** [10 §10.6, §10.8](../design/10-repo-tooling-and-testing.md)

The last of §10.6's six workflows, and the only one still missing. On a `v*` tag: build the firmware,
run T5.1/T5.2 to produce the merged image and the manifest, build the release APK, assemble the
changelog from Conventional Commits, publish a GitHub Release with all four §10.8 artifacts, and
deploy `tools/installer/` plus the firmware assets to Pages.

Two guards, because a release workflow that can publish a wrong thing is worse than no workflow.
**One:** the tag and the version must agree — `v1.0.0` against `CONFIG_APP_PROJECT_VER` and
`app/pubspec.yaml`, checked before anything is built, since §10.8 makes firmware and app share a
version. **Two:** the app-only OTA image and the merged image are published under names that cannot
be confused (`-ota.bin` vs `-heltec-v3-<version>.bin`), because F14.1 exists precisely because
someone will upload the wrong one anyway.

**Done when:** the workflow is committed and its version-agreement guard is exercised by a host test
that reads the same three files the workflow does and fails on a mismatch; the four artifact names
match §10.8 exactly; the Pages deployment is asserted to publish the manifest and the merged image at
the paths the page references; and no step assumes a private repo (Q-F).

### T5.5 repo: the flashing runbook, and the public-repo sweep

- **blocked-by:** T5.4 · **verify:** H · **board:** no
- **design:** [10 §10.7, §10.8](../design/10-repo-tooling-and-testing.md)

The README gains what a stranger needs: install from the browser, or flash by hand with the generated
command, then onboard over BLE. Short, and pointing at the installer rather than reproducing it.

Then the obligation Q-F creates. **Sweep the tree before the first release workflow can run**: a home
SSID or PSK in a fixture or a doc, an API token, a MAC address, a personal path, a `.local` hostname
that identifies a household. `docs/hardware-verified.md` is the likeliest place — it is a bench log,
written when nobody was thinking about publication. This is a task and not a hope because "we'll check
before we publish" is how credentials get published.

**Done when:** the README's flashing section names the artifacts the release actually produces; the
sweep is run and its findings are either fixed or explicitly judged harmless in one place; a test
greps the tree for the specific shapes worth failing on (a `psk`/`password` key with a non-placeholder
value, a bearer token, the test network's SSID) so the sweep is repeatable rather than a one-off
reading; and the MIT attribution [D9](../design/00-overview.md) requires is asserted present in the
files that carry upstream code.

### T5.6 bench: flash the merged image over USB, then install it from a browser

- **blocked-by:** T5.5 · **verify:** B · **board:** yes
- **design:** [10 §10.8](../design/10-repo-tooling-and-testing.md), [hardware-verified](../hardware-verified.md)

**The first row of the sitting, and rule 8's precondition for every row after it.** The merged image
goes on over USB with the generated `esptool` command — proving the offsets, the `otadata`, and that
the image T5.1 built is the image the board runs. Only then is the same board eligible for F14.9's
OTA.

Then the installer, on its own terms: open the Pages URL in Chrome, plug the board into a machine that
has never had ESP-IDF installed, click Install, and confirm it boots to the splash and advertises
`SmokeBridge-XXXX`. The point of the page is that it works for someone without a toolchain, so a
machine with one does not test it.

**Done when:** both installs are recorded in `docs/hardware-verified.md` with the image size, the
elapsed flash time and the version the board reported afterwards; the browser install is confirmed to
have been done from a toolchain-free machine or the deviation is stated; the first-boot handoff string
is confirmed to match what the board actually advertises; and stored cooks are confirmed erased or
preserved as the page claims.

---

## V3 — the 24-hour soak

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** §12.8's `F9 + F10` row said
> RAM, and said that if it is tight *"that is a design conversation, not a task"*. It was tight —
> V3a.1 measured `min_free_heap` ≈ 78.2 KB against a 150 KB target — and M3, M4 and M5 all correctly
> declined to fix it by trimming buffers at a bench. **V3 is the conversation, and the soak is what
> it argues from.**
>
> The risk is not the measurement, it is **choosing the criteria after seeing the trace.** They are
> therefore fixed in the decisions section above — a floor, a slope, a fragmentation bound and a stack
> margin — before V3.3 runs. A 24-hour trace can be made to support almost any conclusion if you pick
> the threshold afterwards.

### V3.1 app_api: expose per-task stack watermarks and heap fragmentation

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [01 §1.4](../design/01-hardware.md), [10 §10.5](../design/10-repo-tooling-and-testing.md), [standing-work](standing-work.md)

`GET /api/v1/debug/tasks`: every task's name, declared stack, high-water mark and **remaining
margin** — the margin computed on the device rather than left to the reader, since that is the number
the threshold is stated against — plus `free_heap`, `min_free_heap` and `largest_free_block`. The
emitter is pure and streamed like every other response; the FreeRTOS call sits behind an op, so the
shape is host-tested against a fake task list.

`CONFIG_FREERTOS_USE_TRACE_FACILITY=y` is what makes `uxTaskGetSystemState` available; it costs a few
bytes per TCB and buys the ability to enumerate tasks the application did not create — **the IDF's
own httpd, NimBLE host and event-loop tasks, which are exactly the ones `tasks.h` cannot account for
and §1.4 had to estimate.** The once-a-minute debug log §1.4 asks for is added beside it.

**Done when:** the endpoint's shape is asserted against a fake task list including a task at its
declared limit (margin 0) and one that the table does not know about; `largest_free_block` is asserted
present and distinct from `free_heap`, because a single number cannot express fragmentation;
`openapi.yaml` carries the path and the sim answers it, so the soak recorder can be developed against
the sim; the endpoint is asserted to be bearer-gated like every other API route; and both images
build.

### V3.2 tools/soak: the recorder, and the report that closes the heap question

- **blocked-by:** V3.1 · **verify:** H · **board:** no
- **design:** [10 §10.5](../design/10-repo-tooling-and-testing.md), [hardware-verified](../hardware-verified.md)

A Dart tool that holds a WebSocket, polls `/status` and `/debug/tasks` on a cadence, appends one
NDJSON line per sample to a file that survives the tool being killed, and — the half that matters —
**produces the report**: the four criteria from the decisions section evaluated against the trace, each
with the number that met or missed it, plus packet counters, reconnect count, WebSocket drops and
storage growth.

It computes the least-squares slope on `free_heap` rather than eyeballing endpoints, because a leak of
6 KB/day is invisible in a before-and-after pair and obvious in a regression over 2,880 samples. It is
developed against `tools/sim` and against the committed **real** 18.9-hour capture
(`protocol/fixtures/overnight-18h.smk`) rather than a synthetic one, so the dropouts and RSSI decay in
the reconnect statistics are the ones a real cook produces.

**Done when:** a synthesised trace with a known 6 KB/day leak is asserted to fail the slope criterion
and one with pure noise of the same amplitude is asserted to pass it — which is the whole reason the
slope is computed rather than differenced; a trace that dips below the floor for a single sample is
asserted to fail the floor criterion (a floor is a floor); a task at 400 B of margin fails the stack
criterion; the recorder is asserted to survive and resume across a mid-run process kill without losing
or duplicating samples; and the report renders the same four verdicts whether the source is the sim or
a file.

### V3.3 bench: run the 24-hour soak, and close the heap question

- **blocked-by:** V3.2, F14.9 · **verify:** B · **board:** yes
- **design:** [10 §10.5](../design/10-repo-tooling-and-testing.md), [hardware-verified](../hardware-verified.md)

24 hours, on the release image, with **everything running**: STA up, a phone bonded over BLE, a
WebSocket client streaming, the display awake, a session recording real LoRa traffic. Not a bench
build and not an idle bridge — the whole point is the configuration the open question was raised
against.

Then the verdict, against the four criteria fixed in advance. If they all hold, the 150 KB target in
[01 §1.4](../design/01-hardware.md) is corrected to the measured floor **and the estimate it replaces
is struck**, per [standing-work](standing-work.md)'s design-maintenance rule; NimBLE's real ≈ 90–100 KB
goes in beside it. If any fail, the plan is the design conversation with buffer counts and concurrency
caps on the table — and a 24-hour trace to argue from, which is what M3 wanted and could not have.

**Done when:** the NDJSON trace and the generated report are committed as evidence; the four criteria
are each recorded pass or fail **with the number**; the open question in `docs/hardware-verified.md` is
closed with the option chosen and the reason, or explicitly re-opened with what the trace showed; and
[01 §1.4](../design/01-hardware.md)'s estimate is updated rather than left to contradict the
measurement.

---

## V4 — the on-target release checklist

### V4.1 docs: turn §10.5's checklist into a runnable document

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [10 §10.5](../design/10-repo-tooling-and-testing.md)

[10 §10.5](../design/10-repo-tooling-and-testing.md) lists seven on-target checks *"run manually,
recorded in the release notes"*, in prose. Prose is what makes a pre-release checklist get skipped:
half the rows already have exact commands somewhere in `docs/hardware-verified.md` and the other half
have to be re-derived at the bench at 11 p.m.

This writes them out as a checklist with, for each row, the exact command or gesture, the observation
that constitutes a pass, and the earlier bench row it re-runs. Several are already proven and cite
their evidence rather than being redone — the stock-receiver check closed at V2, the power-cut resume
at the M1 exit gate — which is the difference between a checklist and a ritual.

**Done when:** all seven §10.5 rows appear with a command and a pass condition; every row that a
previous milestone already verified cites that evidence and says whether it must be re-run on the
release image; the rows that are genuinely new (OTA with a session active, rollback on a broken image,
the 24 h soak) point at F14.9 and V3.3 rather than duplicating them; and the checklist lives in
`docs/hardware-verified.md` where every other bench result lives.

### V4.2 decision: settle D13, and record it

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [06 §6.4](../design/06-device-api.md), [00 §Decisions](../design/00-overview.md), [03 §3.5](../design/03-firmware-architecture.md)

The outline is explicit that the fallback web UI is **decided in M6 and not built in M6**. The
decision and its reasoning are in the decisions section above — **no, and the partition is not
reclaimed either** — and this task is the recording of it, in the decision log rather than in a task
plan nobody reads afterwards.

It is a task and not a footnote because [standing-work](standing-work.md)'s maintenance rule says so:
*"a decision that D1–D14 didn't cover — add it to the log with its rationale, don't leave it in a PR
description."* D13 is in the log; what changes is its status, from *deferred* to *decided, with the
argument*.

**Done when:** D13's row in [00 §Decisions](../design/00-overview.md) carries the decision, the date
and the reasoning; [06 §6.4](../design/06-device-api.md) and [03 §3.5](../design/03-firmware-architecture.md)
agree with it; the `www` partition and `ops_www_available()` are asserted **unchanged** (the decision is
to change nothing, and a test that proves nothing moved is what makes that legible); and the v1.1
revisit condition is named rather than left as "someday".

### V4.3 bench: run the release checklist, and hand over for the tag

- **blocked-by:** V4.1, V4.2, V3.3 · **verify:** C · **board:** yes
- **design:** [10 §10.5, §10.8](../design/10-repo-tooling-and-testing.md), [11 §11.1](../design/11-roadmap-and-risks.md)

The last row of the sitting and the milestone's own gate. Run V4.1's checklist end to end on the
release image, with a real cook where a row needs one, and record every result.

**Then stop.** Tagging `v1.0.0` is a human's decision made with the completed checklist in front of
them, and nothing in this plan does it — the release workflow fires on the tag, publishes to a public
Pages site, and is not something to trigger on an inference that everything looked fine.

**Done when:** every row of the checklist is pass or fail by observation in
`docs/hardware-verified.md`; the artifacts the release will publish are the ones that were actually
tested (the same merged image T5.6 flashed and the same APK the checklist ran); anything failing is a
named row with a decision — ship with it, fix it, or defer it to v1.0.1; and the handover states
plainly that the tag is owed and by whom.

---

## A12 — the rider

### A12.6 app: make the firmware screen's upload real

- **blocked-by:** F14.6 · **verify:** H · **board:** no
- **design:** [08 §8.1, §8.6](../design/08-flutter-app.md), [06 §6.2](../design/06-device-api.md)

A12.5 built the screen — the `409` explanation, the deliberate force path, progress from `ota`
frames — and left `onUpload` wired to nothing, because in M4 there was no endpoint to call. There is
now. `HttpTransport.uploadFirmware()` streams the image to `POST /api/v1/ota`, carries `?force=1`
when asked, surfaces the device's own refusal sentence on a `409`, and completes on the terminal
phase; `settings_route` wires it through an optional `AppEnv.firmwareImage` seam, exactly the way
`notifications` is optional and degrades.

The file picker is **not** in scope and the decisions section says why. With no source registered the
screen states where to get an image and how to install it, which is honest; with a fake registered
the whole path runs under `flutter test`; and against `tools/sim` it runs for real.

**Done when:** the upload is driven against the sim for success, for `409 session_active` and the
force retry, and for a mid-upload disconnect; progress is asserted to come from `ota` frames rather
than from byte counting (the device is authoritative about its own phase); the screen with no image
source is asserted to render the explanation and **not** a dead enabled button; `flutter analyze` and
`dart format` stay clean; and the golden for the firmware screen is regenerated with the change called
out.

---

## What is deliberately _not_ in M6

|                                                        | Why                                                                                                                                                                                                       |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The device-served fallback web UI                      | **D13, decided in V4.2: no.** The installer, the captive page and a documented OpenAPI cover every case §6.4 argues for. The partition stays reserved — reclaiming it costs a repartition and every stored cook |
| Reclaiming the 512 KB `www` partition                  | Same decision, opposite direction. 2,432 KB is already 54 days of history; nobody is short, and the change is not free                                                                                     |
| A file picker in the app                               | SAF, a new plugin, an Android integration `flutter test` cannot run, and a manifest change — real scope, not in M6's epic table. A12.6 finishes the transport half so v1.1 adds only the picker            |
| Signed / encrypted OTA (secure boot, flash encryption) | Not in [03 §3.7](../design/03-firmware-architecture.md), and it would make a bricked board unrecoverable over USB — the exact failure rule 8 exists to prevent. A LAN-local endpoint behind a bearer token is the threat model |
| Delta / compressed OTA images                          | 2.5 MB slots and a 1.3 MB image. The problem it solves does not exist here                                                                                                                                |
| An OTA "check for updates" call to GitHub              | Cloud dependency for a device that must work with no internet ([11 §11.2](../design/11-roadmap-and-risks.md)). The app enforces a minimum firmware version and points at the release page                  |
| Automatic rollback-and-reboot on gate failure          | Decided above: three of the four clauses can fail for reasons that are not the firmware's, and forcing a reboot turns a dark router into a rollback loop that costs the cook                               |
| iOS                                                    | Deferred ([11 §11.2](../design/11-roadmap-and-risks.md))                                                                                                                                                  |
| Tagging `v1.0.0`                                       | A human's call, made with V4.3's completed checklist in hand. The workflow fires on the tag and publishes publicly; that is not a step to infer                                                            |
