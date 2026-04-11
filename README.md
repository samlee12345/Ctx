# Ctx

A macOS menu bar app for switching between saved window configurations. Instead of switching between apps, Ctx lets you switch between named sets of windows — like having a "Work" layout and a "Research" layout that you can jump between instantly.

## What it does

Ctx lets you save which windows belong to a named configuration, then raise all of those windows to the front with a single keystroke. Windows from other configurations stay open in the background — nothing is hidden or moved.

**Example:** You have VS Code, a Terminal, and a Safari window open to your project docs. You save those as "Work". You also have Safari open to Gmail and a second Terminal. You save those as "Research". Press `Option+Tab` to switch between them — the right windows come to the front each time.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Option+Tab` | Cycle to the next config |
| `Option+~` | Cycle focus through windows within the current config |

## Setup

**Requirements:** macOS 14 or later, Xcode 15+

**Permissions:** Ctx requires Accessibility access to raise and focus windows. On first launch, macOS will prompt you. If it doesn't, go to System Settings → Privacy & Security → Accessibility and add Ctx manually.

**Distribution:** Ctx is distributed outside the Mac App Store and must be built from source.

### Build and run

```bash
git clone https://github.com/samlee12345/Ctx.git
cd Ctx
open Ctx.xcodeproj
```

Then in Xcode: select the Ctx scheme, choose your Mac as the destination, and press `Cmd+R`.

### First-time setup

1. Launch Ctx — it appears in the menu bar
2. Open your apps and arrange your windows for the first configuration
3. Click the menu bar item → **Open Ctx** (or press `Cmd+,`)
4. In the sidebar, select a config (e.g. "Work")
5. Check the windows you want in that config
6. Repeat for other configs
7. Press `Option+Tab` to switch between them

## Config manager

Click the menu bar item → **Open Ctx** to open the configuration window.

- **Sidebar** — lists all configs. A filled dot marks the currently active one. Click a config to edit it.
- **Rename** — edit the name field at the top of the detail panel
- **Add config** — click `+` at the bottom of the sidebar
- **Remove config** — select a config and click `-`
- **Window list** — check or uncheck any open window to add or remove it from the config. Changes save immediately.

You can also click any config name directly in the menu bar dropdown to switch to it.

## How it works

Ctx uses macOS's Accessibility API (`AXUIElement`) to raise windows and the private `_AXUIElementGetWindow` function to map `CGWindowID` values directly to AX elements. Window configs are stored in memory for the session — since the app is designed for use with long-running windows that are never closed, this is sufficient. Configs are lost when Ctx quits.

Global hotkeys are registered via `CGEventTap` at the session level.

## Limitations

- Configs are session-only and reset when Ctx quits
- Windows that are minimized or on a different Space will not be raised
- Some apps with restricted accessibility support may not respond to raise actions

## License

MIT
