# Nook Kiosk

The lobby kiosk for **Nook**, a community locker hub for apartment buildings. Residents borrow and return shared items (drills, tents, board games…) from lockers in the foyer by scanning the QR code from their Nook app booking.

**Try it in your browser:** https://jacob9170.github.io/nook-kiosk/

Works best on an iPad or a laptop. On an iPad, tap Share → **Add to Home Screen** to open it full screen like an app.

## Test data

Everything runs on built-in test data that resets when you reload the page.

| Booking | Use with | What happens |
|---|---|---|
| `482193` | Borrow, then Return | Cordless Drill Kit, locker 03 |
| `573046` | Borrow, then Return | Claw Hammer, locker 04 (web version only) |
| `715024` | Return | 4-Person Tent, locker 08 |
| `920457` | Return | Pressure Washer, locker 09 (overdue) |
| `306611` | Borrow | Too early: pickup window opens later |

Scan the QR codes in [`QR Test Codes`](QR%20Test%20Codes), type the number on the keypad, or tap a demo booking on the scan screen.

| Sign in | Apartment | PIN |
|---|---|---|
| Resident | `1204` | `1234` |
| Building admin | `0000` | `2468` |

## What's in this repo

- **`nook/`** + **`Resonance.xcodeproj`**: the native iPad app (SwiftUI). Open the project in Xcode and press ⌘R.
- **`docs/`**: the web version above (HTML/CSS/JavaScript), hosted with GitHub Pages.

## Hosting

The link above is served by GitHub Pages from the `docs/` folder on `main`. If it shows a 404, turn Pages back on: **Settings → Pages → Build and deployment → Source: Deploy from a branch → `main` / `/docs` → Save**. The site is live again about a minute later, and every push to `main` updates it.
