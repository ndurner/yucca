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

After sign-in, Yucca calls same-origin Lucca endpoints from that authenticated
page. `Enter` creates a zero-duration time entry immediately. `Leave` updates that
entry with its elapsed duration. The app never offers a date picker or writes an
entry whose start is not today.

## Build

Open `Yucca.xcodeproj`, choose the `Yucca` scheme, select an iPhone or iPad, and
Run. This scheme is intentionally phone/tablet-only, so Xcode does not need to
download watchOS device support just to install Yucca on an iPhone.

The watch source remains available through the separate `Yucca Watch App` scheme.
Once Xcode's watchOS support is installed, add that target back to the iOS target's
**Embed Watch Content** phase and add `PhoneWatchBridge.swift` back to the Yucca
target to ship both apps in one bundle.

The default identifiers are placeholders under `com.example.yucca`; set your own
development team and bundle identifiers before installing on physical devices.

## Live verification

Lucca does not provide a public demo login, so the request/response bridge is
covered by local tests but must be exercised against the intended tenant before
distribution. A tenant can also disable or restrict API access for signed-in
users. Errors from Lucca are shown in the app without changing local clock state.
