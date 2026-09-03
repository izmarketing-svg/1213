# Notch Work

Notch Work is a native macOS 14+ workday companion that keeps one current task
and the next three tasks in a compact panel at the top of the display.

This repository currently contains an **MVP 0.5 development build**:

- a notch-aware, borderless AppKit panel with compact and expanded states;
- NOW controls with a single-session timer (start, pause, resume, complete);
- an ordered NEXT queue limited to three visible tasks;
- projects and project-aware task creation;
- local JSON persistence in Application Support;
- automatic timer pause when the Mac sleeps or the session resigns activity;
- a menu-bar fallback and a virtual top panel for displays without a notch.
- fast Capture with Russian date parsing and Apple Reminders creation;
- Waiting returns, Done Today, and an automatically generated tomorrow plan;
- global shortcuts and project workspace foundations.
- configurable panel blocks, display/full-screen/hover behavior, notifications,
  Reminders list selection, and project workspace resources;
- opt-in local text clipboard history (disabled by default);
- neutral Back to Work prompts for projects with configured applications;
- two-way task state refresh from Apple Reminders every 60 seconds.
- opt-in Apple Calendar agenda and opt-in Google Calendar agenda with OAuth
  tokens stored in the macOS Keychain;
- resizable, sectioned settings for behavior, panel blocks, integrations, and
  project workspaces.
- end-of-day review, morning start action, editable tomorrow queue, NEXT drag
  and drop, editable project names/icons, and custom Waiting return dates;
- configurable Pomodoro cycles and a privacy-preserving focus equalizer that
  visualizes the active session without recording system audio or microphone;
- editable Command-Shift global shortcut keys, deadline/Back to Work
  notifications, all selected Google calendars, and safe reconciliation when
  an Apple Reminder is removed externally.

## Run

Open the package in Xcode 16 or later on macOS 14+ and run the `NotchWork`
scheme, or run from Terminal:

```bash
swift run NotchWork
```

The process switches to the accessory activation policy and therefore does not
appear in the Dock. Use the menu-bar icon to toggle the panel or quit.

## Build an installable app and DMG

On a Mac with Xcode command-line tools installed:

```bash
./scripts/build-app.sh
```

Для универсального DMG, работающего и на Apple Silicon, и на Intel:

```bash
NOTCHWORK_UNIVERSAL=1 ./scripts/build-app.sh
```

The script produces `dist/Notch Work.app` and `dist/Notch-Work.dmg`, applies an
ad-hoc signature for personal use, and places an Applications shortcut in the
DMG. For distribution, set `CODESIGN_IDENTITY` to a Developer ID identity and
notarize the resulting app.

### Opening the personal build

The CI artifact is ad-hoc signed because no Apple Developer certificate is
configured. In the DMG, double-click **Установить Notch Work.command** to copy
the app to Applications, remove only its download quarantine attribute, verify
the code signature, and launch it. Alternatively, after dragging the app to
Applications, run:

```bash
xattr -dr com.apple.quarantine "/Applications/Notch Work.app"
open "/Applications/Notch Work.app"
```

This workaround is only for a build you produced from this repository. Public
distribution without that step requires Developer ID signing and notarization.

CI performs ad-hoc signing when Apple credentials are absent. For Developer ID
notarization, configure repository Actions secrets `CODESIGN_IDENTITY`,
`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `APPLE_ID`,
`APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`; the workflow imports the temporary
certificate, submits the DMG with `notarytool`, staples the ticket, and removes
the temporary keychain.

### Downloadable GitHub build

Download the current universal build directly: **[Notch-Work.dmg](https://github.com/izmarketing-svg/1213/releases/download/latest/Notch-Work.dmg)**.
GitHub Actions replaces this file after every successful build of `main`, so no
Actions log or artifact archive is needed. Builds use an ad-hoc signature until
the Apple signing secrets described above are configured; in that case use the
installer included in the DMG.

## Architecture

- `Domain` contains platform-independent entities and workflow rules.
- `WorkdayStore` owns persistence and enforces the one-active-task invariant.
- `NotchPanelController` bridges SwiftUI content into a non-activating AppKit panel.
- `NotchPanelView` provides the compact NOW/NEXT/Projects interface.

The remaining work before a public 1.0 is macOS hardware validation, editable
shortcut recording, onboarding, deletion reconciliation for Reminders,
notarization, and UI polish on every supported display shape.

## Calendars

Apple Calendar uses EventKit and asks for calendar access only after the
integration is enabled. Choose individual calendars under **Settings →
Integrations**; leaving the selection empty shows all Apple calendars.

Google Calendar is disabled by default. For a personal build, create an OAuth
client of type Desktop in Google Cloud, enable the Google Calendar API, use the
callback URI `app.notchwork.personal:/oauth/google`, paste the client ID under **Settings →
Integrations**, and press **Connect Google**. The app requests read-only calendar
access. Access and refresh tokens are saved in Keychain, never in the local JSON
snapshot. The panel refreshes enabled calendars at launch, after settings
changes, and every five minutes.

## Privacy defaults

Clipboard monitoring is off until explicitly enabled under **Settings → Panel
blocks → CLIPBOARD**. When enabled, only text is stored, duplicate entries are
collapsed, entries over 10,000 characters are ignored, and only the latest 25
items remain in the local Application Support snapshot. The app cannot reliably
identify passwords copied by another application, so clipboard history should
remain disabled when handling secrets.
