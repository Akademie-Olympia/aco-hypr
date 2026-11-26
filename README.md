# Hyprland configuration

Hyprland desktop with window/slot switching, screenshots, menus, a monitor manager and multi-monitor support.

**[Full documentation and key bindings](https://aco-hypr.readthedocs.io/en/latest/)** ·
[Design & dependencies](https://aco-hypr.readthedocs.io/en/latest/design/) ·
[Installation and security](https://aco-arch-dotfiles.readthedocs.io/en/latest/arch-package/)

```bash
curl -fsSL https://raw.githubusercontent.com/Akademie-Olympia/aco-arch-dotfiles/main/install.sh | bash -s -- hypr
```

Package: `aco-arch-dotfiles-hypr`. Entry point: `~/.config/hypr/hyprland.lua`.
Machine-specific monitor rules belong in the undistributed `monitors.local.lua` (or let `monitors.sh` write it, `Super + Shift + D`).
Desktop components are installed as package dependencies; a running session is never restarted automatically.

Develop in this repository and push to `main`. After a successful registry build update with `sudo pacman -Syu`. [PACKAGING.md](PACKAGING.md).

### Screenshot / snipping tool

`grim`, `slurp`, `wl-clipboard` and Satty are installed with the Hyprland package.
The launcher offers **Screenshot (snip)**; in a terminal use `screenshot`.

| Key | Capture |
| --- | --- |
| `Print` or `Super + Shift + P` | Select a region |
| `Alt + Print` | Active window |
| `Shift + Print` | Active monitor |
| `Super + Print` | All monitors |

The PNG is saved to `~/Downloads` and copied to the clipboard immediately. Satty opens floating for annotating with arrows, text and markers.
`Enter` / `Ctrl+C` copies and saves the edited version; `Ctrl+S` saves. The editor then closes. While typing text, `Enter` first confirms the text.
`Esc` cancels the selection; in the editor the already saved original capture is kept.

The Satty defaults (theme colours, arrow tool, visible toolbars) are generated from `aco-theme/satty.toml.tpl`; change the
template in your user copy to adjust them. `SCREENSHOT_DIR` overrides the location, for example `SCREENSHOT_DIR="$HOME/Pictures/Screenshots" screenshot region`.
More modes: `screenshot window`, `screenshot monitor`, `screenshot full`. Without Satty, capturing, saving and copying still work.
Window captures show the visible part of the screen, not hidden window contents. No extra background service runs.

### Laptop keys

Volume, microphone and brightness keys run `osd.sh`, which changes the value and shows a short banner with a bar
(through aco-swaync, not kept in the notification history).

### Monitors and local rules

New monitors are placed to the right of the existing ones with their preferred resolution and scale `1` (`auto-right`). Explicit local monitor
rules take precedence; existing individual layouts are preserved.

`~/.config/hypr/monitors.local.lua` holds machine-specific monitor rules and is not packaged. The template `monitors.example.lua` shows the
format; `hyprctl monitors all` lists the outputs. Instead of editing it by hand you can use `monitors.sh` (`Super + Shift + D`): extend, mirror,
arrange monitors relative to each other, scale, rotate and save profiles that are restored automatically when the same monitors are plugged in.
Each monitor has its own row of workspaces, shown as circles in the bar (filled = on screen). `Super + 1…9` switches the
focused monitor, or every monitor at once in mode `all`; switch the mode and the number of fixed circles under
**Einstellungen > Bildschirme** (`workspaces.lua`, `~/.config/aco/workspaces.conf`).
`Super + S` shows or hides the scratchpad workspace; `Super + Shift + S` moves the active window there. After changes run `hyprctl reload` and
`hyprctl configerrors`.

Your own changes in the activated user copy survive synchronisation; new differing defaults appear as `.pacnew`.
See [update and recovery](https://aco-arch-dotfiles.readthedocs.io/en/latest/verification/).

### Theme

Colours, fonts and rounding come from [aco-theme](https://github.com/Akademie-Olympia/aco-theme): the templates in `aco-theme/` are rendered to `~/.config/aco/theme/hypr/` and included from here, so this config only holds behaviour and layout. Switch with `aco-theme mode|accent|transparency`; personal overrides go into `~/.config/aco/theme.local.conf`.

After changing bindings run `python3 scripts/check-binds.py` inside the session: it verifies that every command a binding
starts exists and that no key combination is bound twice (`make binds` in aco-dev runs it in the test VM).

`Super + I` opens the settings hub (`settings.sh`: appearance, wallpaper grid, Wi-Fi, Bluetooth with scanning and pairing, sound with mute and device choice, camera with a live preview and which app uses it, displays with the workspace mode, power profile, notifications, system and drivers, shortcuts, update; entries appear only when their tool or device is present; Esc goes back one level). Quick toggles and sliders live in the control centre (aco-swaync). All menus run through `aco-menu` (aco-rofi). `Super + Shift + T` toggles light/dark. `Super + U` opens the notification centre (aco-swaync).

[![Package safety](https://github.com/Akademie-Olympia/aco-hypr/actions/workflows/package.yml/badge.svg)](https://github.com/Akademie-Olympia/aco-hypr/actions/workflows/package.yml)

[MIT licence](LICENSE).
