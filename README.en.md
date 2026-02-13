# centerWindows

English | [简体中文](./README.md)

`centerWindows` is a macOS menu bar window manager. It centers the frontmost window when launched, and supports optional auto-center detection with a configurable interval.

## Features

- Center once immediately on app launch
- Auto-center detection toggle (menu item)
- Detection interval switch (1s / 2s / 5s)
- Center inside usable screen area excluding Dock and menu bar (`screen.frame - screen.visibleFrame`)
- Auto-generated app icon and menu bar icon

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)

## Build locally

```bash
swift test
swift build -c release
./.build/release/centerWindows
```

## Package

```bash
scripts/build_app.sh
scripts/create_dmg.sh
```

Outputs:

- `dist/centerWindows.app`
- `dist/centerWindows.dmg`

The DMG includes:

- `centerWindows.app`
- `Applications` (shortcut to system Applications folder)

Install by dragging `centerWindows.app` into `Applications`.

## Sign and notarize (Developer ID)

```bash
export DEVELOPER_ID_APP="Developer ID Application: YOUR_NAME (TEAMID)"
export NOTARY_PROFILE="AC_NOTARY"
scripts/sign_and_notarize.sh
```

Recommended release flow (for GitHub Releases assets):

```bash
export DEVELOPER_ID_APP="Developer ID Application: YOUR_NAME (TEAMID)"
export NOTARY_PROFILE="AC_NOTARY"
scripts/release_build.sh
```

Note: Unsigned/unnotarized DMG files can be blocked on a new Mac and may show as “damaged”.

## Free distribution (without paid signing/notarization)

If you distribute without Developer ID notarization, include these steps in release notes:

1. Open the DMG and drag `centerWindows.app` into `Applications`.
2. In `Applications`, right-click `centerWindows.app` -> `Open` -> click `Open` again.
3. If blocked, go to `System Settings -> Privacy & Security` and click “Open Anyway”.
4. If still blocked, run:

```bash
xattr -dr com.apple.quarantine /Applications/centerWindows.app
```

This is a normal Gatekeeper flow for unnotarized apps, not a corruption of app code.

## Permissions

### Accessibility

- Path: `System Settings -> Privacy & Security -> Accessibility`
- Why required:  
  The app uses macOS Accessibility APIs to read the frontmost window's frame and set a new position for centering.
- Without it:  
  The app cannot read window geometry or move windows, so centering will not work.

### Screen Recording

- Path: `System Settings -> Privacy & Security -> Screen Recording`
- Why required:  
  The app needs full screen context to reliably compute usable display bounds and avoid Dock/menu bar while centering.
- Without it:  
  Screen-context-dependent centering can become unstable on multi-display or complex layouts.

### Permission boundary

- The app does not upload screen content and does not perform telemetry collection.
- Permissions are used only for local window geometry calculations and positioning.

## License

MIT License. See [LICENSE](./LICENSE).
