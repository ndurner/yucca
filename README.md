# Yucca

Yucca is a small SwiftUI companion for Lucca Timesheet. It has one purpose: add an
arrival or departure to **today's** attendance sheet and show today's and this
week's worked time.

## Targets

- iPhone and iPad (`Yucca`)
- Apple Watch (`Yucca Watch App`), relaying requests through the paired iPhone
- Unit tests for date, duration, and entry-state calculations

## Sign-in and privacy

The user enters their Lucca tenant (for example `company.ilucca.net`) and signs in
inside Lucca's own page, including company SSO. The app keeps Lucca's persistent
web session in the system WebKit data store. It does not collect or store a
password, and no customer domain is compiled into the app.

After sign-in, Yucca reads the same current Timesheet service used by Lucca's web
interface and uses Lucca's per-entry API for non-destructive writes from that
authenticated page. `Enter` creates a one-minute placeholder in Lucca, persists its identifier
and start time in the iPhone app container, and immediately switches the UI into
its running state. `Leave` updates that same Lucca entry to the true elapsed
duration. The placeholder is necessary because Lucca accepts zero-duration
entries but does not return them as active timesheet rows. Yucca refuses to clock
out over another overlapping Lucca entry instead of creating duplicate time.
It refreshes the current Lucca timesheet while open and whenever it returns to
the foreground. If its running row is edited, completed, or deleted in the web
app, Yucca adopts that change instead of maintaining a conflicting local state.
When Yucca is clocked out, one unique one-minute entry created in Lucca's web
app is also adopted as the running sentinel; its entry identifier is then
persisted normally. A sentinel that Yucca has just completed is temporarily
ignored so a one-minute session cannot immediately restart itself.
The app never offers a date picker or writes an entry whose start is not today.

## Build

Open `Yucca.xcodeproj`, choose the `Yucca` scheme, select a paired iPhone and
Apple Watch, and Run. The iOS target embeds `Yucca Watch App`, which is also
available as a separate scheme for watch-only development. Install the matching
watchOS platform support in Xcode before building the combined scheme.

## Live verification

Lucca does not provide a public demo login, so the request/response bridge is
covered by local tests but must be exercised against the intended tenant before
distribution. A tenant can also disable or restrict API access for signed-in
users. Errors from Lucca are shown in the app without changing local clock state.
