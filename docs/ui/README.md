# Smoke X4 Smart Bridge — UI/UX Redesign Assets & Master Prototype

> ## Status and precedence
>
> **This directory is a design reference, not a specification.** It supplied the visual direction and
> a real set of colour tokens; it is not implementable as it stands.
>
> - **Normative:** [`docs/design/13-ux-architecture.md`](../design/13-ux-architecture.md) (behaviour)
>   and [`docs/design/14-design-system.md`](../design/14-design-system.md) (visual system).
> - **Where `docs/ui/` and `docs/design/` conflict, `docs/design/` wins.**
> - `index.html` fleshes out two screens. **History, Alarms and Settings are empty headings**
>   (`index.html:696`, `:704`, `:712`), and the provisioning wizard renders two of the five steps it
>   describes. Its 5-step tree also omits the bridge↔Smoke X pairing hop entirely — see
>   [13 §13.2.2](../design/13-ux-architecture.md).
> - Deliberate deviations from this prototype, with reasons, are tabulated in
>   [14 §14.9](../design/14-design-system.md).

This directory contains the complete **UI/UX Redesign Suite** designed to transform the **Smoke X4 Smart Bridge** app into a premium, top-tier barbecue telemetry experience that rivals market leaders like Typhur, Combustion Inc, Meater, and ThermoWorks Signal.

---

## 📁 Directory Contents

- [`index.html`](index.html): **Master Interactive Web Application Prototype**
  - **Welcome View**: Hardware onboarding & 5-step BLE provisioning wizard (Scan → OLED 6-digit Passkey Entry `849 201` → Clock Sync → Hosted AP vs Joined STA Wi-Fi Mode Selection → Verification).
  - **Raw Probes Dashboard**: Live telemetry for raw connected probes (`Probe 1`, `Probe 2`, `Probe 3`, `Probe 4`) with prominent **"⚡ Setup Cook Session"** launcher button.
  - **Smart Cook Setup Assistant**: Modal dialog to configure specific proteins (Beef Brisket, Ribeye Steak, Pork Shoulder, Turkey), doneness levels (Rare to Pitmaster Shred), pull rest offsets ($T_{\text{pull}} = T_{\text{target}} - \Delta T_{\text{rest}}$), and dynamic pit crash alarms.
  - Interactive multi-series graph with Chart.js, radial circular gauge arcs, 6 full screen views, and modal dialogs.
- [`design-system.md`](design-system.md): **UI/UX Design System Specification & State Matrix**
  - Hardware BLE provisioning flow & network handoff choreography.
  - Raw Probes Dashboard & Guided Cook Setup specifications.
  - Guidance on porting design system back to Flutter (`app/lib/`).

---

## 🚀 How to View the Master Interactive Prototype

Open [`docs/ui/index.html`](index.html) in any web browser:

```bash
# Windows PowerShell
Start-Process "docs/ui/index.html"
```

Or open directly from your file manager or IDE preview.
