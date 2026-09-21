# N0 — Foundations

**Goal:** a new Flutter app at `app/` that boots, renders a themed shell over mock
state, and has the CI/golden harness the rest of the backlog depends on.

**Design:** [`newui/index.html`](../index.html) · [`newui/styles.css`](../styles.css)
· [`newui/NOTES.md`](../NOTES.md) §8 · `app.old/pubspec.yaml` (package set, reference only).

---

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N0.1 | Scaffold: `flutter create` a fresh app in `app/` (Android-first), package name unchanged, `app.old/` remains reference-only | — | H | `app.old/pubspec.yaml` |
| N0.2 | Pin the package set (`flutter_riverpod`, `riverpod_annotation`, `freezed`, `json_serializable`, `go_router`, `fl_chart`, `shared_preferences`, `logger`, `meta`). Defer BLE/drift/notifications/share to N15 | N0.1 | H | `app.old/pubspec.yaml`, NOTES §6 |
| N0.3 | `analysis_options.yaml`: strict lints; layering guards as tests — `domain/` has zero Flutter imports, `ui/` is stateless over plain values | N0.1 | H | `components_research_notes.md` §10 |
| N0.4 | Folder layout: `lib/{app,design,domain,data,features,platform}`, `test/{domain,design,features,golden,integration}` | N0.1 | H | `app.old/lib` (layout only) |
| N0.5 | Bundle the three variable fonts (Archivo, Inter, JetBrainsMono) + OFL licences, register via `LicenseRegistry` | N0.1 | H | `styles.css` §fonts, NOTES §8 |
| N0.6 | Codegen pipeline: `build_runner` wired; a trivial `@freezed` model generates; `dart run build_runner build` documented | N0.2 | H | — |
| N0.7 | Bootstrap: `ProviderScope`, `runApp`, a `SmokeApp` widget that renders a placeholder route | N0.2, N0.4 | W | `index.html` shell |
| N0.8 | Golden harness: golden test scaffold + `--update-goldens` make target + a checked-in placeholder golden at 390×844 | N0.7 | W | `index.html` frame |
| N0.9 | CI: analyze, test, golden compare; fonts available offline | N0.8 | H | `docs/tasks/README.md` (CI posture) |
| N0.10 | Make targets / scripts: `app.run`, `app.test`, `app.golden`, `app.gen` | N0.9 | H | `Makefile` |

## Exit gate

`flutter run` opens a themed blank shell on the 390×844 frame; `flutter test`
runs the layering + placeholder golden green in CI; codegen is reproducible from
a clean checkout.

## Must-not-regress

None (no invariants yet). Do not import anything from `app.old/lib`.