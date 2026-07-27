# Smoke X4 Smart Bridge — UI/UX Design System & Master Specification

## 1. Vision & Core Principles

The **Smoke X4 Smart Bridge App** UI/UX is built to deliver a **world-class, high-contrast, dark-first barbecue telemetry experience** that rivals or exceeds leading market solutions (Typhur, Combustion Inc, Meater, ThermoWorks Signal).

### Design Principles:
1. **Arm's Length Legibility**: A user standing 6-10 feet away from their phone in a pitch-black backyard at 3:00 AM must be able to instantly read the Pit Temperature and Primary Probe status without squinting.
2. **Thermal Visual Hierarchy**: Heat and status drive color choices. Fire and high temperatures radiate in rich amber and thermal orange; targets reached glow in vibrant emerald; alerts and lid opens pop in crimson.
3. **Dual-Tier Hardware Confidence**: The UI constantly reassures the user that the hardware bridge is logging every sample locally to flash, regardless of phone battery or Wi-Fi range.
4. **Data-Dense Yet Uncluttered**: Deep telemetry (10-minute linear regression slope, Newton cooling curves, stall detection, lid open grace windows) is presented with progressive disclosure—glanceable hero numbers up front, rich graphs and crosshairs on touch.

---

## 2. Onboarding Architecture & Hardware Provisioning Flow

As specified in `docs/design/05-connectivity-and-provisioning.md`, the **Welcome View** is a 5-step hardware onboarding & BLE provisioning flow:

```
 Welcome View (Hardware Setup)
 ├── Step 1: BLE Scan for SmokeBridge-XXXX
 ├── Step 2: 6-digit OLED Passkey Verification (LE Secure Connections)
 ├── Step 3: Silent Real-Time Clock Sync (Unix ms timestamp)
 ├── Step 4: Network Mode Choice
 │     ├── Hosted AP Mode (192.168.4.1, PSK generated from RNG, high power ~145 mA)
 │     └── Joined STA Mode (smokebridge.local, home Wi-Fi, low power modem sleep ~70 mA)
 └── Step 5: Handoff Verification & Transport State Selection
```

---

## 3. Raw Probes Dashboard & Guided Cook Setup Flow

```
 Live Dashboard (Raw Probes View)
 ├── Live Telemetry (Pit, Probe 1, Probe 2, Probe 3, Probe 4)
 ├── LTTB Decimated Chart (15m, 1h, 6h, All)
 └── [ ⚡ Setup Cook Session ] Button
       │
       ▼
  Smart Cook Setup Assistant (Modal)
  ├── Protein Category & Cut Selection (Beef, Pork, Poultry, Fish)
  ├── Doneness Level Picker (Rare 125°F to Pitmaster Shred 203°F)
  ├── Automatic Pull Rest Temperature Offset ($T_{\text{pull}} = T_{\text{target}} - \Delta T_{\text{rest}}$)
  └── Dynamic Pit Band & Alarm Activation
```

### Raw Probes Monitoring Mode
- Default view on launch after bridge connection.
- Displays probes as `Probe 1`, `Probe 2`, `Probe 3`, `Probe 4` with their raw numbers and baseline min/max alarms.

### Guided Cook Setup Assistant
- When the user taps **"Setup Cook Session"**, a modal presents protein presets and doneness levels.
- **Dynamic Alarm Engine**: Automatically assigns probe names, configures target temps, pull rest offsets, pit target ranges, and early warning alerts.

---

## 4. Color Palette & Tokens

### Base Obsidian Dark Palette
| Token Name | Hex Code | Purpose |
| :--- | :--- | :--- |
| `bg-darkest` | `#07090E` | Deepest background; outdoor night screen base |
| `bg-surface` | `#0F131D` | Container surface; device frame background |
| `bg-card` | `#161C2A` | Primary card container background |
| `bg-card-hover` | `#1E2638` | Interactive hovered/tapped state |
| `bg-card-subtle` | `#121824` | Inset backgrounds, range selectors, tabs |

### Probe & Telemetry Palette
| Probe Role | Color Name | Hex Code | Purpose |
| :--- | :--- | :--- | :--- |
| **Pit Thermometer** | Thermal Fire | `#FF6B00` | Ambient pit temperature |
| **Probe 1 (Primary Food)** | Smoked Amber | `#FF9500` | Main food cut (e.g. Brisket Flat) |
| **Probe 2 (Secondary Food)** | Electric Cyan | `#06B6D4` | Secondary food cut (e.g. Brisket Point) |
| **Probe 3 (Secondary Food)** | Deep Violet | `#A855F7` | Pork shoulder or sausage |
| **Probe 4 (Secondary Food)** | Fresh Lime | `#84CC16` | Poultry or vegetable probe |

---

## 5. Screen Navigation Suite

1. 📶 **Welcome (Hardware Setup)**: 5-step BLE provisioning wizard (Scan → OLED Passkey → Clock Sync → Hosted AP vs Joined STA Wi-Fi → Handoff).
2. ⚡ **Raw Probes Dashboard**: Raw probe telemetry readouts + **"Setup Cook Session"** assistant launcher.
3. 🍖 **Presets & Smart Pull**: Protein selector (Beef, Pork, Poultry, Fish) with doneness levels and Newton cooling rest calculations.
4. 📊 **History & Analytics**: Past session logs, cook statistics, and side-by-side comparison overlays.
5. 🔔 **Alarm Rule Engine**: Hardware-latched rules vs app-tier advisory rules with Quiet Hours setup.
6. ⚙️ **Settings**: Wi-Fi mode switcher (STA vs AP), unit switcher (°F/°C), OLED display timeout, LED controls, OTA updater.
