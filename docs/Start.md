I want to create a mono repo that will extend what the Smoke X4 meat probe wireless system can do.

I would like to use this product (ESP32 LoRa V3 Development Board + 3000mAh Battery Set, Integrated WiFi Bluetooth SX1262 CP2102 0.96-inch OLED Display) and this reference repo (docs/reference).

What kind of storage does it have, can we have it store history of a 24 hour cook?

I want to program it to receive signals from a Smoke X4 bbq probe, there's open source code to do this already, but I want to serve a Flutter mobile app and do something custom.

I would like it to have 2 modes we can select on boot up, either it can host its own wifi and give you a SSID and password to put in so your app can see API for your app, or you can put so you can connect to an existing wifi network and broadcast over that for the app on the same LAN. Would be nice if Flutter can tell the device which mode it should be in after initial bluetooth connection and hand off. I'd like to see the Flutter phone app connect to it over regular wifi or adhoc wifi its hosting and then see a temp graph for a cook up to 15 hours, current temp of probes, and any other meaningful features. Utilize the screen or programmable buttons to help make the device useful (should button switch modes? should screen show wifi info if host or what network its connected to if guest or current status otherwise?)

This will be a mono repo consisting of the Flutter app (Android first for MVP), and new code after researching the reference project so we can create the custom firware needed for the ESP32 board.

After your research and analysis, create a set of design documents at `docs/design` folder with each md file being a main category or topic. Ask any questions needed to help write the design.
