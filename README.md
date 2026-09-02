# Notch Work

Notch Work is a native macOS 14+ workday companion that keeps one current task
and the next three tasks in a compact panel at the top of the display.

This repository currently contains an **MVP 0.4 development build**:

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

The script produces `dist/Notch Work.app` and `dist/Notch-Work.dmg`, applies an
ad-hoc signature for personal use, and places an Applications shortcut in the
DMG. For distribution, set `CODESIGN_IDENTITY` to a Developer ID identity and
notarize the resulting app.

### Downloadable GitHub build

The repository includes a macOS GitHub Actions workflow. Open **Actions → Build
macOS app → Run workflow**, wait for the build to finish, and download the
`Notch-Work-macOS` artifact. The artifact contains `Notch-Work.dmg`. Builds use
an ad-hoc signature for personal installation and are not Apple-notarized.

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
