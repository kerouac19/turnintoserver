# turnintoserver

> Integrated development version for Apple Silicon and macOS 13+. Includes external display control, cleaning mode, and a power recovery guard. See [integration status](docs/INTEGRATION_STATUS.md), [build and release instructions](RELEASING.md), and [installation instructions](INSTALL.md).

[中文](README.md) · [Product page](https://qianyushi.github.io/turnintoserver/)

<p>
  <img src="https://qianyushi.github.io/turnintoserver/icon.png" alt="turnintoserver app icon" width="96" height="96">
</p>

Close the lid.  
Keep the Mac running.  
Turn the built-in display to zero brightness.

`turnintoserver` is a small macOS menu bar utility.

Plug in your MacBook, turn on Server Mode, and close the lid. SSH, remote desktop, development servers, and local network services can keep running. At the same time, it tries to set only the built-in MacBook display to zero brightness, so the screen hidden behind the lid no longer emits light.

I built it because I wanted to use a MacBook as a small temporary server. Most keep-awake apps handle the sleep part, but not the closed-lid display part.

## Main Features

- Controls external displays while protecting the last usable display.
- Offers black or transparent cleaning overlays, with five consecutive Esc presses or an Unlock button to exit.
- Keeps the Mac running after the lid is closed.
- Sets the built-in display to zero brightness when the lid closes.
- Does not intentionally turn off external monitors.
- Runs on power, pauses automatically on battery.
- Resumes automatically when power is connected again.
- Can run Server Mode for a chosen duration, then automatically restore normal macOS power behavior.
- Can optionally keep running on battery.
- Can send low battery alerts through iMessage or Bark while running on battery.
- Supports custom global keyboard shortcuts.
- Can put the Mac to sleep from the menu or a global shortcut, then restore the previous Server Mode intent after wake.
- Supports launch at login.
- Can independently route user-maintained internal CIDRs using two configurable access points; both services, their detection signatures, and the CIDRs are editable, with only a few generic examples shown on first launch.
- Can mute audio while Server Mode is active, then restore the previous mute state.

## Good For

- SSH into a closed-lid Mac.
- Run development servers on your local network.
- Connect to a MacBook with remote desktop.
- Keep sync, download, or media services running.
- Use a MacBook as a small desktop server for a while.

## Install

Use the ZIP supplied by this integration's distributor. Upstream packages do not contain these additional features. Builders can follow [RELEASING.md](RELEASING.md); local packages are generated in `dist/`.

Unzip the package, move `turnintoserver.app` to Applications, then open the menu bar app. Follow the first-use prompts for Accessibility, the background power guard, and administrator permission. See [INSTALL.md](INSTALL.md) for installation, update, and signing status details.

## Use

The app lives only in the menu bar.

The main controls are:

- `Start Server Mode`: keeps the Mac running while connected to power.
- `Start for a Duration`: choose 30 minutes, 1 hour, 2 hours, and more; when the timer ends, Server Mode turns off automatically. Clicking the selected duration again clears the timer, while clicking another duration restarts it.
- `Allow Server Mode on Battery`: keeps running after power is unplugged. Off by default.
- `Low Battery Alerts`: sends alerts below 50% and 20% through the configured channels while running on battery; use the right-side Set Up button for iMessage / Bark.
- `Enable Shortcuts`: turns global shortcuts on or off; use the right-side Set Up button to record shortcuts for Server Mode, battery mode, and Sleep.
- `Open at Login`: opens the app after login.
- `Enable Automatic Routing`: independently watches two configurable macOS network services. When the app detects both as online, the current internal CIDR list uses the first Internal Route Egress while all other traffic keeps following the macOS default route. It is independent of Server Mode. The right-side Settings button lets users select both services and provide an optional per-service substring from the `ipconfig` summary (such as a DNS address or IP); an empty signature checks link status only. The same window maintains one IPv4 CIDR per line with `/8`, `/16`, `/24`, or `/32`. A first install shows only Wi-Fi, Ethernet, and three generic CIDR examples. An overwrite install keeps reading access points, signatures, and CIDRs already saved under the same bundle identifier instead of replacing them with examples. Saving cleans managed routes from a retired egress and immediately reconciles the new configuration. Hover shows the actual configured service names and app-detected states, current route coverage, and default egress.
- `Mute When Enabled`: mutes audio while Server Mode is actually active, then restores the previous mute state when Server Mode stops or this option is disabled.
- `Sleep`: temporarily releases Server Mode assertions and immediately puts the Mac to sleep; after wake, the previous Server Mode intent is restored.
- `About turnintoserver`: shows the version, developer, and GitHub URL. Upstream updates are disabled in this integration.
- `Quit`: restores the default sleep behavior before quitting.

For normal use, turn on Server Mode and close the lid.

If you only need it for a while, choose Start for a Duration from the menu. When the timer ends, the app turns off Server Mode and restores the normal macOS sleep and power-management behavior. A regular start with no duration selected still runs indefinitely.

If battery mode is off, unplugging power pauses Server Mode. Plugging power back in resumes it automatically.

Low battery alerts need an iMessage or Bark channel from the Set Up button beside Low Battery Alerts, and the configured channels must test successfully before the switch can be enabled. Configure one channel to send through that channel, or configure both to send through both. The first iMessage send may ask macOS for permission to let `turnintoserver` control Messages; allow it. Bark accepts a push URL such as `https://api.day.app/your-key`.

Upstream automatic updates are disabled in this integration. Install updates manually from a new integration ZIP. Before replacing the app, turn Server Mode off, wait for recovery to finish, then quit.

## About The Display

`turnintoserver` is not only about preventing sleep.

It also cares about the built-in display after the lid is closed. When the lid closes, it tries to set only the MacBook display to zero brightness, instead of turning off every display. External monitors are not intentionally blanked, and the hidden built-in screen no longer emits light.

## Safety

Do not keep a closed MacBook running inside a bag, drawer, or any poorly ventilated space.

Use it plugged in, on a desk, with normal airflow. Setting the built-in display to zero brightness reduces unnecessary light, heat, and screen wear from that panel, but it is not a replacement for cooling.

## Requirements

- Apple Silicon Mac: macOS 13 Ventura or later.
- This development integration builds arm64 only.
- Plugged-in use is recommended.

## Note

`turnintoserver` is not a Mac App Store app and does not use App Sandbox.
