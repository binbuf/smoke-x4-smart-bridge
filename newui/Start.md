Deeply review newui\components_research_notes.md. Create an HTML mock up in the style of a Flutter app (focus more on UI/UX then mimicing Flutter) of what you think is the best possible UI/UX experience for this kind of app. 

Top features in my mind:

* Easily connect, disconnect, re-sync with ESP32 unit
* Flexible UI, allow the user to setup a cook before hand, review temperatures and log without setting anything up, or setup a cook that has already started and hook into data already collected (e.g. grill fired up, esp32 and smoke x4 turned on, but later app is synced to start cook but it can pull from existing data esp32 has already collected). 
* Show the temperature in default F (e.g. 72.4° F) but have an option to allow for Celsius
* Show grate and cook temperatures as a graph and timeline
* Have a catalog of all popular bbq items organized by category to make it easy to start a new cook. Assume best recommended done temp for that type of cook. Assume default medium rare for red meat but allow users to choose their preference. Have place holders for food items we'll replace later with real images. 
* Have the timers front and center. Smoke X4 allows for 3  meat timers and 1 grate timer. Assume probe 4 will be grate temp by default but allow user to choose. 
* Have an onboarding wizard to make it easy to connect via bluetooth and sync up
* Control the unit in its 3 modes (simple bluetooth connection / sync delta by default, it broadcasts its own wifi on esp32 as the next option, and allow esp32 to connect user's wifi if it allows to see devices on network). 
* Ensure user knows how to use each mode and it's trivial to switch between them in the app using bluetooth. 
* Add comments in the code about business logic so later LLM can consider that when translating into a real app. 
* Ensure every type of cook has an expected timeline in the app internal database. For example pulled pork will have a stall, need to be wrapped, etc. We need that for every kind of cook so one of the tabs can be timeline and we can add everything on the grill and when it was added, the app can calculate everything so we know expected time to do everything. We should consider whether to wrap, spritz, turn over, etc and add that to a database. 

* We need a history area so we can look up past cooks

* On the home/dashboard we need a section at the top for when alarms appear. Ideally the service can check in the background and detect if it can talk to esp32 and if an alarm is happening on the smoke x4 we can bubble it up to the app. Also we should have separate alarm system in the app based on our own timeline and real data we get. We can just sync any manual alarms from the smoke x4 and we can also have a setting to allow the user to prefer their own manual alarm over the built in alarms. 

* Show a stopwatch since when the cook started, allow the user to change when it started or pause it.

* Show timers based on ETA and current projects for when expected to be pulled off the grill


You may use what's in project root to help you build this new app experience but do not copy entire systems or files. The goal is to write something new not take substantial components of what already exists. 

Write static html at newui\ . Give mock objects so we can iterate through all the views and perfect the UI/UX before having it translated back into Flutter.

Create any notes needed to help with that later Flutter task at newui\NOTES.md