# OLED framebuffer goldens (T22)

Each `.fb` is exactly 1024 bytes of SSD1306 page-ordered GDDRAM: page 0 holds
display rows 0-7, byte `n` of a page is column `n`.

These bytes are the test gate (`ui-render` CTest). The PNG is only for human
review:

```powershell
# regenerate intentionally after a reviewed renderer/label change
$env:SX4_UPDATE_UI_GOLDENS='1'
firmware/test/build/test_ui_render.exe
Remove-Item Env:SX4_UPDATE_UI_GOLDENS

# eyeball all states (writes firmware/test/goldens/ui/png/*.png)
python tools/ui_fb_to_png.py firmware/test/goldens/ui
```

| Golden | State |
|---|---|
| `01-probes-four` | four probes, linked app, 87% |
| `02-probes-detached` | P1 detached (`---`) |
| `03-probes-invalid` | P2 invalid-but-present (`ERR`) |
| `04-probes-unknown-battery` | battery `—`, never 0% |
| `05-connection-paired` | paired X4, six rows |
| `06-connection-unpaired` | scan instructions |
| `07-billows-detected` | detected, valid SET, P4 |
| `08-billows-not-detected` | not detected, `SET —` |
| `09-bridge` | version, battery, log, readings, uptime, memory |
| `10-passkey` | `418 302` in 12x24 |
| `11-power-off-countdown` | keep holding 2 |
| `12-storage-failure` | persistent overlay |
| `13-resetting` | app-initiated progress |
| `14-clearing-log` | app-initiated progress |
| `15-off` | OFF |
| `16-boot` | splash + antenna warning |
| `17-power-off-confirm` | release to confirm |

The labels mirror `app/lib/features/device/device_preview_screen.dart`. The app
preview remains the visual reference; T37 owns the real-panel legibility check.
