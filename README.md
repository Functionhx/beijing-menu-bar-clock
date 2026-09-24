# Beijing Menu Bar Clock

A small native macOS menu bar clock that always displays Beijing time (`Asia/Shanghai`) without changing the system time zone.

## Features

- Native AppKit menu bar item and SwiftUI settings window
- Any time zone from the macOS system time-zone database, saved between launches
- Optional system-time-zone mode that overrides and disables the manual time-zone picker
- Per-app time-zone allowlist with a native app picker and individual time zones
- Quick launch for allowlisted apps directly from the menu bar
- Live verification of whether a running allowlisted app received the requested time zone
- Optional date and weekday
- Optional seconds
- Optional flashing time separators
- Spoken time announcements every hour, half hour, or quarter hour
- Built-in alert sounds or a custom audio file
- Starts automatically at login
- No Dock icon and no network access

The clock intentionally supports digital display only. It does not include an analog clock mode.

## Requirements

- macOS 14 or later
- Apple Swift toolchain / Xcode Command Line Tools

## Build

```bash
./build.sh
```

The app is created at `build/Beijing Clock.app`.

## Install for the current user

```bash
./install.sh
```

The installer places the app in `~/Applications` and creates a per-user LaunchAgent.

On recent macOS versions, enable the app under:

`System Settings → Menu Bar → Allow in the Menu Bar → Beijing Time`

## Privacy

The app does not use Location Services or the network. It reads the Mac's system clock and formats it using the time zone selected in settings. The default is `Asia/Shanghai`. When system-time-zone mode is enabled, the current macOS time zone takes precedence over the saved manual selection.

For allowlisted apps, the clock asks macOS to launch a fresh app process with a `TZ` environment value and a local verification marker. The target app is not modified. The settings window reads the running process environment to distinguish apps launched with the requested time zone from apps opened normally. This only affects apps that honor the standard time-zone environment and only when they are launched from this clock; some apps may continue to use the system time zone or server-formatted timestamps.

## License

MIT
