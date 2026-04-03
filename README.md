# RadFlag

__Rapid Autonomy Depletion Warning App__

A macOS menu bar utility that watches your CPU load and alerts you when your MacBook is working unusually hard on battery power — before the computer warms up and the battery gauge nosedives.

RadFlag compares your recent system load against an established baseline and also watches for any process that keeps burning more than one full CPU core for five straight minutes. The goal is to catch runaway plugins, render loops, and polling storms before they ruin your remaining battery life.

## How it works

RadFlag samples the system every 20 seconds and maintains a rolling 40-minute history. It uses two battery-only tripwires:

- **Load tripwire**: compare the recent 5-minute load average against the prior 35-minute baseline
- **Process tripwire**: flag any process whose average CPU use stays above 100% for the last 5 minutes

When either rule fires while you're on battery power, RadFlag sends a macOS notification. If the process rule is responsible, the alert includes the process name and PID. It will remind you as long as the condition stays elevated.

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

RadFlag lives in your menu bar. After launch, rogue-process detection becomes meaningful after 5 minutes of samples, and the load baseline finishes warming up after 10 minutes.

The menu bar icon shows:

- **Green checkmark** — load is normal (or you're on AC power)
- **Red warning triangle** — the load and/or process tripwire is active while on battery

Click the icon to see current stats (5-minute load, baseline, ratio, trigger reason, offending process, power source) and access controls:

- **Mute** — suppress alerts for 20 minutes
- **Sample now** — take an immediate reading
- **Settings** — adjust alert threshold (1.25x–2.0x), toggle notification sound, enable launch at login

## No external dependencies

RadFlag is built with native macOS frameworks (SwiftUI, AppKit, IOKit, UserNotifications). No third-party packages in the supply-chain.

## License

License undetermined as of yet. All rights are reserved by the author. You may use the app & read the source code, but you may not redistribute it without explicit permission.

Working on features at the moment, will resolve license choice at some future date.
