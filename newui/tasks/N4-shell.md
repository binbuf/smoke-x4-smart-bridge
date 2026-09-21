# N4 — Shell

**Goal:** the persistent chrome every screen lives inside, plus the overlay/sheet
framework. After this epic, screens are swappable and overlays are routable.

**Design:** [`newui/index.html`](../index.html) · [`newui/app.js`](../app.js) §5
(chrome), §7 (overlays) · `newui/NOTES.md` §2, §2.4 · `styles.css` `.phone`,
`.statusbar`, `.appbar`, `.bottom-nav`, `.scrim`, `.sheet`, `.modal-card`.

---

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N4.1 | `PhaseTrack`-prefixed phone frame: status bar (clock, battery, radio), app area, scroll host, bottom nav, overlay host, toast host | N3.1 | W | `index.html` `.phone` |
| N4.2 | Bottom nav: Live / Temps / Timeline / Graph / Settings; active state; unacked-alarm dot on Live | N4.1 | W | `app.js` renderNav |
| N4.3 | `go_router` table for the 5 destinations + `history` + `cookDetail` (nested under Settings); deep-linkable | N4.2, N0.2 | W | `app.js` go/map |
| N4.4 | App-bar variants: `live` (transport chip + alerts bell with badge), `temps/timeline/graph/settings` (title + sub + bell), `history` (back + plus + bell), `cookDetail` (back + bell) | N4.2 | W | `app.js` appbarHtml |
| N4.5 | Global alerts bell + unacked count wired to the alarm state (fill behaviour in N11) | N4.4 | W | `app.js` appbarHtml |
| N4.6 | Overlay framework: `showSheet` (grabber, head, scrollable body) and `showModalCard` (centred confirm), scrim tap-to-dismiss | N4.1 | W | `app.js` `scrim`/`sheetWrap` |
| N4.7 | Overlay router: named overlays with props (`onboarding`, `setup`, `connect`, `modes`, `modesRef`, `provisionSta`, `provisionAp`, `alarms`, `alarmDetail`, `mark`, `probe`, `adopt`, `editStart`, `confirm`, `customFood`, `firmware`, `firmwareUpdate`, `diagnostics`, `verb`); deep-linkable | N4.6 | W | `app.js` §7 map |
| N4.8 | Fullscreen graph host (mounted above everything, dismiss on scrim tap) | N4.6 | W | `app.js` fullGraph |
| N4.9 | `.toast` transient messages | N4.1 | W | `app.js` toast |
| N4.10 | Dev panel: scenario buttons, screen buttons, overlay buttons, mock-event buttons, theme/units/profile toggles — release-excluded | N2.31, N4.3 | W | `index.html` devpanel |
| N4.11 | Scroll-position reset on destination change; preserve per-overlay scroll on open/close | N4.3 | W | `app.js` go |

## Exit gate

All five destinations render placeholder screens inside the real chrome; every
overlay in the list opens and dismisses by name and by deep link; the dev panel
drives scenario + screen + event from cold boot.

## Must-not-regress

Screens receive data **only** through providers from N2; the shell owns no
business state.