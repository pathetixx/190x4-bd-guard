# 190x4 BD Guard

Keeps [BetterDiscord](https://github.com/BetterDiscord/BetterDiscord) alive across Discord updates on Windows — no more reinstalling.

A Discord update only wipes one thing: the `require("betterdiscord.asar")` line inside `discord_desktop_core/index.js`. Your plugins, themes and settings in `%AppData%\BetterDiscord` are never touched. BD Guard watches that file and puts the line back the moment the updater removes it.

Patched locations (all Discord flavors, both updater layouts):

- `%LocalAppData%\Discord*\app-<ver>\modules\discord_desktop_core-N\discord_desktop_core\index.js` (current updater)
- `%AppData%\discord*\<ver>\modules\discord_desktop_core-N\discord_desktop_core\index.js` (legacy)

## How it works

- Runs hidden at logon via Task Scheduler (no console window, ~0 resources).
- On start: checks `index.js` of every installed Discord flavor (Stable / PTB / Canary) and re-injects if needed.
- Then a `FileSystemWatcher` waits for the Discord updater to rewrite `index.js` and re-injects within a second, plus an hourly safety re-check.
- Shows a toast when a repair happened. If the update landed exactly during Discord launch, one restart (tray → Quit) may be needed — the toast will say so.

Requires BetterDiscord to be installed once the normal way (`%AppData%\BetterDiscord\data\betterdiscord.asar` must exist).

## Install

PowerShell:

```powershell
irm https://raw.githubusercontent.com/pathetixx/190x4-bd-guard/main/install.ps1 | iex
```

## Uninstall

```powershell
irm https://raw.githubusercontent.com/pathetixx/190x4-bd-guard/main/uninstall.ps1 | iex
```

## Files

| File | Purpose |
| --- | --- |
| `bd-guard.ps1` | the guard itself (logon check + watcher) |
| `install.ps1` | downloads the guard to `%LocalAppData%\BDGuard`, registers the logon task, starts it |
| `uninstall.ps1` | removes the task, the process and the files |
