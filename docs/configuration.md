# Configuration

The entry point is `~/.config/hypr/hyprland.lua`. Machine-specific monitor rules belong in the **undistributed** file
`~/.config/hypr/monitors.local.lua`; it survives updates. The template:

```{literalinclude} ../monitors.example.lua
:language: lua
:linenos:
```

`hyprctl monitors all` lists the outputs. After changes run `hyprctl reload`, then `hyprctl configerrors`.

## Screenshots with Satty

The editor defaults live in `~/.config/hypr/satty.toml`:

```{literalinclude} ../satty.toml
:language: toml
```

## Monitor manager

`monitors.sh` manages layout, mirroring, arrangement, scale, resolution, rotation and named profiles.
{kbd}`Super + Shift + D` opens the Fuzzel menu; in a terminal:

```bash
~/.config/hypr/monitors.sh status
~/.config/hypr/monitors.sh map                  # text sketch of the layout
~/.config/hypr/monitors.sh arrange HDMI-A-1 above eDP-1 center   # relative placement
~/.config/hypr/monitors.sh extend right         # or left, above, below
~/.config/hypr/monitors.sh mirror               # all mirror the internal display
~/.config/hypr/monitors.sh only external        # or internal, <output>
~/.config/hypr/monitors.sh scale HDMI-A-1 1.5
~/.config/hypr/monitors.sh mode HDMI-A-1 1920x1080@60
~/.config/hypr/monitors.sh rotate HDMI-A-1 1
~/.config/hypr/monitors.sh profile save office  # later: profile load office
~/.config/hypr/monitors.sh reset                # back to automatic
```

### Arranging monitors

`arrange <monitor> <relation> <reference> [alignment]` places one monitor relative to another:

| Relation | Meaning |
| --- | --- |
| `right-of` / `left-of` | Next to the reference's right/left edge |
| `above` / `below` | Over/under the reference |
| alignment `start` (default) / `center` / `end` | Where the two edges line up (top/left, centred, bottom/right) |

Sizes take scale and rotation into account. `map` draws the result, for example:

```text
+------------------------------++------------------------------+
|                              ||                              |
|             eDP-1            ||           HDMI-A-1           |
|             1920x1080        ||           1920x1080          |
+------------------------------++------------------------------+
```

### Remembering layouts and setting defaults

Every time a monitor is plugged in or out, Hyprland calls `monitors.sh auto`, which chooses the layout in this order:

1. **A named profile** (`profile save office`) for exactly the connected set of outputs.
2. **The remembered layout** of that set: every change you make with the tool is stored automatically, so a setup you have arranged once comes
   back by itself the next time you dock – no explicit save needed.
3. **Your default** for setups it has never seen. Set it once:

```bash
monitors.sh default                       # show the defaults
monitors.sh default placement left        # new monitors go left of the laptop: right | left | above | below | mirror
monitors.sh default align center          # line the edges up at start | center | end
monitors.sh default internal-off on       # switch the laptop display off while an external one is connected
monitors.sh default apply                 # apply the default to the current setup right now
```

Resolution, scale and rotation are remembered **per physical display** (by its make/model/serial), so the same monitor on another port or
another day keeps its settings. The menu ({kbd}`Super + Shift + D` → “Standard für neue Monitore”) offers the same choices.
A remembered layout wins over a changed default; use `default apply` to re-lay the current setup with the new default.

### Files

The script writes `~/.config/hypr/monitors.local.lua` (git-ignored, loaded by `hyprland.lua` after the default rules) and reloads Hyprland.
It keeps the per-output state in `~/.local/state/aco/monitors.json`; profiles live in `~/.config/aco/monitor-profiles/`.
With `MONITORS_DRY_RUN=1` it only prints the Lua file without reloading.
