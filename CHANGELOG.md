# Changelog

## 1.0.0

Initial public release of RadFlag.

### Highlights

- Adds a macOS menu bar app focused on catching battery-draining CPU activity early.
- Monitors the built-in 5-minute system load average against the prior 35-minute baseline.
- Detects rogue processes that sustain high CPU usage over a rolling 5-minute window.
- Shows the top process name, PID, and average CPU usage directly in the menu bar dropdown.
- Sends local macOS notifications with repeat suppression and a menu bar mute control.
- Includes settings for the load-ratio threshold, process CPU threshold, sound, and launch at login.

### Notes

- RadFlag only raises alerts while the Mac is on battery power.
- The app needs a short warm-up period after launch before load and process comparisons become meaningful.

### If macOS blocks the app

If a downloaded build is quarantined by macOS, remove the quarantine attribute with:

```sh
xattr -dr com.apple.quarantine /Applications/RadFlag.app
```
