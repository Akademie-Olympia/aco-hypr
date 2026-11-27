# Hyprland Desktop Environment & Keybindings

Hyprland (`~/.config/hypr/hyprland.lua`) serves as the primary Wayland tiling compositor in the [`aco-arch-dotfiles`](https://aco-arch-dotfiles.readthedocs.io/en/latest/) ecosystem. It is engineered for **instant reaction speeds**, **maximum screen real estate**, **multi-monitor workspace agility**, and **seamless cross-monitor window recall**.

---

## Design Philosophy

- **Responsiveness**: Animations, shadows, and blur are disabled (`animations.enabled = false`, `blur.enabled = false`, `shadow.enabled = false`).
- **Screen space**: No inner or outer gaps, unrounded corners and a `1px` border.
- **Window navigation**: Return to the previous window (`Alt + Tab`), cycle windows (`Alt + Shift + Tab`), search with the menu (`Super + G`), or use cross-monitor slots.
- **TTY launch**: Log into a Linux TTY and start the session with `start-hyprland`.

---

## Personal Monitor Layout (Git-Ignored)

The shared configuration automatically detects monitors at scale `1` and places
new outputs to the right of existing monitors (`auto-right`). Explicit local rules
take precedence, so existing personal layouts are preserved. Individual
layouts belong in `~/.config/hypr/monitors.local.lua`, which is loaded after the
default monitor rules and excluded from Git. No personal monitor layout needs to
be committed, even when `~/.config/hypr` points into the dotfiles repository.

The easiest way is the monitor manager: {kbd}`Super + Shift + D` (or `~/.config/hypr/monitors.sh`) arranges, mirrors, scales and rotates monitors and
saves profiles that restore themselves when the same monitors are plugged in (see [Configuration](configuration)). To edit the file by hand instead:

```bash
# Create once; preserve an existing local configuration:
cp -n ~/.config/hypr/monitors.example.lua ~/.config/hypr/monitors.local.lua
hyprctl monitors all
$EDITOR ~/.config/hypr/monitors.local.lua
hyprctl reload
hyprctl configerrors
```

Uncomment and adapt the template's `hl.monitor({...})` rules: `output` is the
connector name, `mode` is `WIDTHxHEIGHT@HZ`, and `position` is `XxY` in logical
pixels. Local edits require `hyprctl reload`. Without the local file, automatic
placement remains active. `XDG_CONFIG_HOME` is respected when set. Back up the
local file separately: it is not part of Git and `git clean -fdx` can delete it.

---

## Application Launchers & System Controls

The primary modifier key (`SUPER`) is the **Windows / Super key**.

| Keybinding | Command / Script | Action |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Space</kbd> *(or <kbd>Alt</kbd> + <kbd>Space</kbd>, <kbd>Super</kbd> + <kbd>D</kbd> / <kbd>R</kbd> / <kbd>A</kbd>)* | `aco-menu apps` | Toggle the **rofi** launcher (apps and windows) |
| <kbd>Super</kbd> + <kbd>Return</kbd> *(or <kbd>Super</kbd> + <kbd>Q</kbd>)* | `kitty` | Open default terminal ([Kitty](https://aco-kitty.readthedocs.io/en/latest/)) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Return</kbd> | `kitty -e tmux new-session -A -s main` | Open terminal attached to persistent [tmux](https://aco-tmux.readthedocs.io/en/latest/) session `main` |
| <kbd>Super</kbd> + <kbd>B</kbd> | `firefox` | Launch web browser (**Firefox**) |
| <kbd>Super</kbd> + <kbd>E</kbd> | `aco-files` | Open the file manager (**ACO Dateien**) |
| <kbd>Super</kbd> + <kbd>Y</kbd> | `kitty -e yazi` | Open TUI file manager (**Yazi**) |
| <kbd>Super</kbd> + <kbd>L</kbd> | `hyprlock` | Lock screen immediately |
| <kbd>Super</kbd> + <kbd>Escape</kbd> | `~/.config/hypr/powermenu.sh` | Power menu (lock, log out, suspend, reboot, shut down) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd> | `killall -SIGUSR2 waybar \|\| ...` | Reload or restart **Waybar** |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd> | `~/.config/wallpaper/wallpaper.sh tui` | Open interactive multi-monitor **Wallpaper TUI** (`wallpaper`) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>E</kbd> *(or <kbd>Super</kbd> + <kbd>M</kbd>)* | `hl.dsp.exit()` | Exit Hyprland session back to TTY |

---

## Cross-Monitor Window Switching & Pinning Slots (`1–10` / `F1–F4`)

All window switching functions in `hyprland.lua` operate **globally across all connected monitors and workspaces** (including automatically revealing windows hidden in the special scratchpad workspace).

### 1. Instant Ping-Pong & Cycling

| Keybinding | Function | Action |
| :--- | :--- | :--- |
| <kbd>Alt</kbd> + <kbd>Tab</kbd> *(or <kbd>Super</kbd> + <kbd>Tab</kbd>, <kbd>Super</kbd> + <kbd>BackSpace</kbd>)* | `focus_last_window()` | **Jump immediately to the last active window** across any monitor or workspace. Pressing it again jumps right back (ping-pong switch). |
| <kbd>Alt</kbd> + <kbd>Shift</kbd> + <kbd>Tab</kbd> *(or <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Tab</kbd>)* | `cycle_all_windows(1)` | **Cycle through all open windows** across all monitors and workspaces (sorted spatially left-to-right, top-to-bottom). |
| <kbd>Super</kbd> + <kbd>^</kbd> *(or <kbd>Super</kbd> + <kbd>`</kbd>, key below Escape)* | `cycle_same_class()` | **Cycle through windows of the same application** across all monitors (e.g. all Kitty terminals or Firefox windows). |
| <kbd>Super</kbd> + <kbd>G</kbd> *(or <kbd>Super</kbd> + <kbd>#</kbd>)* | `~/.config/hypr/windowswitcher.sh` | **Interactive Window & Slot Switcher**: Lists all open windows sorted by focus history (most recent window first -> press <kbd>Enter</kbd> to jump immediately, or type to filter by app, title, monitor, or `Pos 1..9`). |

### 2. Window Pinning Slots (`1..10` and `F1..F4`)

Pin critical windows (IDE, browser, docs, terminal, chat) to persistent slots and jump to them from any monitor:

| Keybinding | Function | Action |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>1..9, 0</kbd> | `save_window_slot(1..10)` | **Pin/save active window to Slot `1..10`** (shows a desktop notification and tags the window with `slot_<n>`). |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>1..9, 0</kbd> | `jump_window_slot(1..10)` | **Jump to Slot `1..10`** across any monitor/workspace:<br>• If a window is pinned to slot `<n>`, focuses it immediately *(pressing the same chord again while already in that window jumps back to your previous window!)*.<br>• If no window was manually pinned to slot `<n>`, jumps to the `<n>`-th open window spatially. |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>F1..F4</kbd> *(or <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>F1..F4</kbd>)* | `save_window_slot(1..4)` | **Pin/save active window to Quick Slot `1..4`**. |
| <kbd>Super</kbd> + <kbd>F1..F4</kbd> | `jump_window_slot(1..4)` | **Single-chord Quick Jump to Slot `1..4`** (or back to previous window if already focused). |

---

## Multi-Monitor Controls

| Keybinding | Function | Action |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>O</kbd> *(or <kbd>Super</kbd> + <kbd>&lt;</kbd>)* | `focus_next_monitor(1)` | Focus the next / other physical monitor |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>O</kbd> *(or <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>&lt;</kbd>)* | `move_window_to_next_monitor()` | Move active window to the next physical monitor and focus it |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>O</kbd> | `workspaces.swap_with_next_monitor()` | Swap the whole workspace rows of this and the next monitor |

---

## Workspaces (one row per monitor)

Every monitor owns its own row of workspaces, shown as circles in the bar: the workspace on screen is filled
(accent colour on the focused monitor, grey on the others), circles with windows are drawn stronger than empty
ones. Every monitor owns one row (group) of ids: *k*·10+1 … *k*·10+10, at start the first monitor 1–10 and the next
one 11–20, left to right. `Super + 3` therefore means "workspace 3 of this monitor". A monitor keeps its row when
monitors are rearranged; a monitor that is plugged in gets the lowest free row and its workspaces back, and when a
monitor is unplugged its workspaces with windows appear as extra circles on the remaining one. The logic lives in
`workspaces.lua`.

**Settings > Bildschirme** switches between two modes and sets how many circles always exist
(`~/.config/aco/workspaces.conf`, applied with `hyprctl reload`):

| Setting | Values | Default |
| :--- | :--- | :--- |
| `mode` | `monitor` – keys switch only the focused monitor; `all` – `Super + N` switches every monitor to its workspace N | `monitor` |
| `persistent` | circles that exist even when empty, `0`–`10` | `5` |

| Keybinding | Action |
| :--- | :--- |
| <kbd>Super</kbd> + <kbd>1..9, 0</kbd> | Workspace `1..10` of this monitor (all monitors in mode `all`) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>1..9, 0</kbd> | Move active window to workspace `1..10` of its monitor |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>1..9, 0</kbd> | Same as <kbd>Super</kbd> + <kbd>N</kbd>, but **only if the workspace already exists** |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>←</kbd> / <kbd>→</kbd>, <kbd>Super</kbd> + <kbd>,</kbd> / <kbd>.</kbd>, <kbd>Super</kbd> + <kbd>PageUp</kbd> / <kbd>PageDown</kbd> | Previous / next workspace of this monitor; stops at the last circle instead of creating new ones |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Shift</kbd> + <kbd>←</kbd> / <kbd>→</kbd>, <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>,</kbd> / <kbd>.</kbd> | Move active window one workspace left / right |
| <kbd>Super</kbd> + <kbd>N</kbd> / <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>N</kbd> | Go to / move the window to the first empty workspace of this monitor |
| <kbd>Super</kbd> + <kbd>Mouse Wheel</kbd>, scrolling on the circles | Previous / next workspace of this monitor |
| Clicking a circle | Go to that workspace |
| `3-Finger Horizontal Swipe` *(Touchpad)* | Next / previous workspace of this monitor (one step per swipe, no live tracking) |
| <kbd>Super</kbd> + <kbd>S</kbd> | Toggle special scratchpad workspace (`special:magic`) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | Move active window into the scratchpad (`special:magic`) |

---

## Window Tiling, Floating & Resizing

| Keybinding | Action |
| :--- | :--- |
| <kbd>Super</kbd> + <kbd>C</kbd> *(or <kbd>Super</kbd> + <kbd>W</kbd>)* | Close active window |
| <kbd>Super</kbd> + <kbd>F</kbd> | Toggle true fullscreen |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>F</kbd> | Toggle maximized state (Waybar remains visible) |
| <kbd>Super</kbd> + <kbd>V</kbd> | Toggle floating mode for active window |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>C</kbd> | Center floating window on screen |
| <kbd>Super</kbd> + <kbd>T</kbd> | Toggle dwindle split direction (Horizontal / Vertical) |
| <kbd>Super</kbd> + <kbd>P</kbd> | Toggle pseudo-tiling for active window |
| <kbd>Super</kbd> + <kbd>←</kbd> / <kbd>→</kbd> / <kbd>↑</kbd> / <kbd>↓</kbd> | Move focus directionally (crosses onto adjacent monitors automatically at screen edges) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>←</kbd> / <kbd>→</kbd> / <kbd>↑</kbd> / <kbd>↓</kbd> | Move/swap active window directionally |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>←</kbd> / <kbd>→</kbd> / <kbd>↑</kbd> / <kbd>↓</kbd> | Resize active window in `40px` increments (repeatable) |
| <kbd>Super</kbd> + `Left Mouse Drag` | Move window with mouse |
| <kbd>Super</kbd> + `Right Mouse Drag` | Resize window with mouse (or drag window borders directly) |

---

## Screenshots, Audio & Brightness

| Keybinding | Command | Action |
| :--- | :--- | :--- |
| <kbd>Print</kbd> or <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>P</kbd> | `screenshot region` | Select region, save/copy, then annotate with Satty |
| <kbd>Super</kbd> + <kbd>Print</kbd> | `screenshot full` | Capture all screens, save/copy, then annotate with Satty |
| <kbd>Alt</kbd> + <kbd>Print</kbd> | `screenshot window` | Capture active window's visible screen area |
| <kbd>Shift</kbd> + <kbd>Print</kbd> | `screenshot monitor` | Capture focused monitor |
| `XF86AudioRaiseVolume` / `LowerVolume` | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+/-` | Increase / decrease volume in 5% steps (capped at 100%) |
| `XF86AudioMute` / `XF86AudioMicMute` | `wpctl set-mute ... toggle` | Toggle speaker mute / microphone mute |
| `XF86MonBrightnessUp` / `Down` | `brightnessctl -e4 -n2 set 5%+/-` | Increase / decrease screen brightness in 5% steps |

### Snipping Tool

The Hyprland package installs `grim`, `slurp`, `wl-clipboard` and `satty` as
dependencies, along with the `screenshot` command and the **Screenshot** application
entry in the launcher. No additional screenshot daemon is needed.

Press **Print**, draw a rectangle, and use Satty to add arrows, text, highlights
or blur. **Enter / Ctrl+C** copies the edited image, saves it and closes Satty;
**Ctrl+S** saves to file. Escape during selection cancels without taking a capture.
The original capture is saved and copied before the editor opens, so closing
the editor without saving retains the original.

By default files go to `~/Pictures/Bildschirmfotos/Bildschirmfoto-*.png` and to the clipboard; *Einstellungen > Bildschirmfotos* (`~/.config/aco/screenshot.conf`) chooses clipboard, folder or both, the folder, and whether Satty opens (`SCREENSHOT_DIR` overrides the folder for one call).
If Satty is not installed, capture/save/copy still work without annotation.
`screenshot` or `screenshot region` selects a region; `screenshot full` captures
all screens. `screenshot window` captures the active window's visible screen area
(not obscured content); `screenshot monitor` captures the focused monitor.

Satty opens as a centered floating editor. Its desktop-matching palette, arrow
tool and copy/save behavior are configured in `~/.config/hypr/satty.toml`.
This file is managed like other Hyprland defaults: user changes are preserved,
and conflicting updates arrive as `.pacnew`. While editing text, Enter confirms
the text first; press it again to copy/save the image.

---

## Wallpaper

Wallpaper commands and configuration are documented in the [Wallpaper guide](https://aco-docs.readthedocs.io/en/latest/wallpaper/guide/).
