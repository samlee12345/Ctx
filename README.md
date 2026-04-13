# Ctx

A macOS menu bar app for switching between saved window configurations. Instead of switching between apps, Ctx lets you switch between named sets of windows — like having a "Work" layout and a "Research" layout that you can jump between instantly.

## Download

**[Download the latest release](https://github.com/samlee12345/Ctx/releases/latest)**

1. Download `Ctx.zip` from the release page
2. Unzip and drag `Ctx.app` to your Applications folder
3. Right-click `Ctx.app` → **Open** (required once to bypass Gatekeeper on unsigned apps)
4. Ctx appears in your menu bar — follow the setup steps below

> **Why right-click to open?** Ctx is distributed outside the Mac App Store and is not notarized. macOS blocks unsigned apps from double-clicking, but right-click → Open bypasses this on first launch only.

## What it does

Ctx lets you save which windows belong to a named configuration, then raise all of those windows to the front with a single keystroke. Windows from other configurations stay open in the background — nothing is hidden or moved. Configs are saved to disk and survive restarts.

**Example:** You have VS Code, a Terminal, and a Safari window open to your project docs. Save those as "Work". You also have Safari open to Gmail and a second Terminal. Save those as "Research". Press `Option+Tab` to jump between them — the right windows come to the front each time.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Option+Tab` | Cycle to the next config |
| `Shift+Option+Tab` | Cycle to the previous config |
| `Option+`` ` | Cycle focus forward through windows in the current config |
| `Shift+Option+`` ` | Cycle focus backward |

Holding Option while pressing Tab (or Shift+Tab) repeatedly lets you skip through configs — the menu bar label updates live but windows only raise when you release Option, same feel as Cmd+Tab.

## First-time setup

**Requirements:** macOS 14 or later. Accessibility permission (macOS will prompt on first launch).

1. Launch Ctx — it appears in the menu bar
2. Open your apps and arrange your windows
3. Click the Ctx menu bar item → **Open Ctx** (or press `Cmd+,`)
4. In the sidebar, select a config (e.g. "Work")
5. Check the windows you want in that config
6. Repeat for other configs
7. Press `Option+Tab` to switch between them

## Config manager

Click the menu bar item → **Open Ctx** to open the configuration window.

- **Sidebar** — lists all configs. A filled dot marks the active one. Click to select.
- **Rename** — right-click a config in the sidebar → **Rename**
- **Add / remove config** — `+` and `-` buttons at the bottom of the sidebar
- **Refresh** — click the `↺` button if you opened new windows after the manager was already open
- **Window list** — check or uncheck any open window to add or remove it from the active config. Changes save immediately.

You can also click any config in the menu bar dropdown to switch to it, or use **Add "[window]" to [Config]** to quickly add the currently focused window without opening the manager.

## How it works

Ctx uses macOS's Accessibility API (`AXUIElement`) to raise and unminimize windows, and the private `_AXUIElementGetWindow` function to map `CGWindowID` values to AX elements. Global hotkeys are registered via `CGEventTap`. Configs are persisted to `UserDefaults` and survive restarts.

The event tap automatically re-arms after sleep/wake and after macOS disables it due to secure input or timeouts.

## Build from source

```bash
git clone https://github.com/samlee12345/Ctx.git
cd Ctx
open Ctx.xcodeproj
```

Select the Ctx scheme, choose your Mac as the destination, press `Cmd+R`.

## License

MIT
