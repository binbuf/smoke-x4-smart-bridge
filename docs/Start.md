We are making an RF Bridge for the ThermoWorks Smoke X4, supporting Billows with an ESP32 LoRa V3 Development Board.

Your job is to create the design documents at `docs/design/*.md` and tasks at `docs/tasks/*.md` to get us to MVP.

In `legacy/` we have some semi working app and firmware. We can use it as reference or example but don't take code from it whole sale. Do not use any of its UI/UX or any substantial code other than communication code you may take.

We are looking for thinnest vertical slice we can deploy end to end to test out and use core features below.

We need to rebuild both the Flutter app and the ESP32 firmware. Ensuring it's custom and only has the feature below and doesn't knowingly inherit any of the tech debt from previous iterations.

If the previous code had features, logic, or UI/UX for other stuff that isn't mentioned below, we probably don't want it for our new MVP but you may confirm what we're leaving behind as you conduct your audit.

## Features

### ESP32

- Hold PRG to turn off/on
- Tap PRG to cycle through any information windows or dialog selection
- Automatically enter bluetooth discovery mode and try to find a device to connect any time it's on and not actively connected to a device.
  - When connecting show a pairing code on the screen that you enter on your phone to connect
- Allow as many functions as possible to be controlled by the app since buttons/controls are limited on device.
  - Forget device
  - Factory reset
- As soon as powered on, if synced with Smoke X4, and Smoke X4 is on and sending data, then collect it for use later in the app. All connected probe temps (e.g. 99.9F) should be collected.
- Support ThermoWorks Billows
  - Set target temp
  - Be able to tell its connected, status, etc
- Collect temperatures periodically from all 4 probes (or whatever is connected)
- Ensure data structure is highly efficient to be able to store as much data as possible on esp32.

### Flutter app

- Handle all bluetooth discovery and connection to device
  - Health checks, status updates, syncing, disconnections, lost connection, etc
- Handle all settings device can't do on its own (Settings tab)
- Show the 4 probe temps if they're available. Probe 4 is typically the grate probe temp sensor but it can be adjusted
- Show a graph of all 4 probes (dont show anything if no probe data for that time)
  - Device should just be collecting data any time its on and Smoke X4 is on so this graph will just show whatever data it's collected. It shouldn't matter if the Flutter app is connected. As long as the ESP32 is on, it collects from the Smoke X4 and acts as a Bridge; every time the app connects or syncs during an active connection, the data is relayed to the app.
  - Rotate old data out as the esp32 memory fills up. Don't delete from Flutter app though let the user choose when to delete old data.

