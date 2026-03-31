# RadFlag

__Rapid Autonomy Depletion Warning App__

A macOS menu bar utility that watches your CPU load and alerts you when your MacBook is working unusually hard on battery power — before the computer warms up and the battery gauge nosedives.

RadFlag compares your recent system load against an established baseline and raises a flag when something is out of the ordinary, so you can investigate a runaway process before it ruins your remaining battery life.

## How it works

RadFlag samples the system's load average and maintains a rolling 2-hour history. It splits this history into two windows:

- **Baseline**: what "normal" looks like for your current session
- **Recent**: what's happening now

When the recent average exceeds the baseline by a configurable ratio (default 1.5x) _and_ you're on battery power, RadFlag sends a macOS notification. It will remind you as long as the load stays elevated.

Alerts clear automatically when you plug in, and you can mute them from the menu bar if you know why you're burning the Amperes.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (to build from source)

## Building

Open the project in Xcode:

```sh
open RadFlag.xcodeproj
```

Or build from the command line:

```sh
xcodebuild -scheme RadFlag build
```

## Running the tests

```sh
xcodebuild -scheme RadFlag -destination 'platform=macOS' test
```

## Usage

RadFlag lives in your menu bar. After launch, it needs some time to establish a baseline — you'll see a warmup indicator until then.

The menu bar icon shows:

- **Green checkmark** — load is normal (or you're on AC power)
- **Red warning triangle** — recent load is significantly above baseline while on battery

Click the icon to see current stats (load, baseline, ratio, power source) and access controls:

- **Mute** — suppress alerts for one hour
- **Sample now** — take an immediate reading
- **Settings** — adjust alert threshold (1.25x–2.0x), toggle notification sound, enable launch at login

## No external dependencies

RadFlag is built with native macOS frameworks (SwiftUI, AppKit, IOKit, UserNotifications). No third-party packages in the supply-chain.

## License

License undetermined as of yet. All rights are reserved by the author. You may use the app & read the source code, but you may not redistribute it without explicit permission.

Working on features at the moment, will resolve license choice at some future date.
