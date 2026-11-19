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

### Profiles

`profile save <name>` stores the current layout together with the set of connected outputs. When Hyprland reports a monitor being plugged in or
out it calls `monitors.sh auto`: if a profile exists for exactly the connected set it is loaded, otherwise the default rules apply. So an
“office” profile saved once restores itself every time you dock.

### Files

The script writes `~/.config/hypr/monitors.local.lua` (git-ignored, loaded by `hyprland.lua` after the default rules) and reloads Hyprland.
It keeps the per-output state in `~/.local/state/aco/monitors.json`; profiles live in `~/.config/aco/monitor-profiles/`.
With `MONITORS_DRY_RUN=1` it only prints the Lua file without reloading.
