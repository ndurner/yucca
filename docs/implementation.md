# Implementation notes

Yucca reads the current Timesheet service used by Lucca's web interface and
makes per-entry API requests from the authenticated WebKit page. No customer
domain is compiled into the app.

## Entry lifecycle

- `Enter` creates a one-minute placeholder, saves its identifier and start time
  in the iPhone app container, and switches the UI into its running state.
- The placeholder is necessary because Lucca accepts zero-duration entries but
  does not return them as active timesheet rows.
- `Leave` updates the same entry to the elapsed duration. Yucca refuses to clock
  out over another overlapping entry instead of creating duplicate time.
- If the running row is edited, completed, or deleted in the web app, Yucca
  adopts that change when it refreshes.
- While clocked out, Yucca also adopts one unique one-minute entry created in
  the web app as its running placeholder, then persists its identifier. This
  means an ordinary one-minute entry can be interpreted as a running session.
- A placeholder that Yucca has just completed is temporarily ignored so a
  one-minute session cannot immediately restart itself.
- Yucca does not offer a date picker or write an entry whose start is not today.

## Refresh and Watch communication

The iOS dashboard refreshes every minute while open and on return to the
foreground. The Watch sends actions to the paired iPhone using WatchConnectivity
and caches the latest dashboard snapshot. It does not authenticate to Lucca or
queue offline clock actions itself.

## Verification

`Tests/TimesheetMathTests.swift` covers duration conversion, tenant-shaped date
strings, active-entry totals, previous-day entries, and exclusion of future
planned entries. Live sign-in, the WebKit request bridge, tenant permissions,
and API writes require separate verification against an authorized tenant.
