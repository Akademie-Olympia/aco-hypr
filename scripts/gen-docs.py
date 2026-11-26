#!/usr/bin/env python3
"""Generate docs/keybindings.md from hyprland.lua.

    python3 scripts/gen-docs.py          # rewrite the page
    python3 scripts/gen-docs.py --check  # exit 1 if the page is out of date

Every ``hl.bind(...)`` line is read, its key expression evaluated and its
action described. Bindings the table below does not know are listed under
"Other" with the raw action, and ``--check`` fails so a new binding is
never silently undocumented.
"""
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "hyprland.lua"
TARGET = ROOT / "docs" / "keybindings.md"

# (pattern on the action text, group, description) – first match wins.
RULES = [
    (r"exec_cmd\(terminal\)", "Programs", "Open terminal"),
    (r'exec_cmd\("kitty -e tmux', "Programs", "Terminal with tmux session `main`"),
    (r"exec_cmd\(menu\)", "Programs", "Application launcher (rofi, `aco-menu apps`)"),
    (r"exec_cmd\(settings\)", "System", "Settings (appearance, wallpaper, Wi-Fi, sound, displays, drivers …)"),
    (r'panel \.\. " notifications"', "System", "Notification centre"),
    (r'panel \.\. " control"', "System", "Control centre (toggles, sliders, media)"),
    (r"exec_cmd\(screenshot .. \" menu\"\)", "Screenshots", "Screenshot menu (region, window, monitor, all, timer)"),
    (r"aco-theme mode toggle", "System", "Toggle light/dark"),
    (r"exec_cmd\(browser\)", "Programs", "Open browser"),
    (r"exec_cmd\(fileManager\)", "Programs", "File manager (Dolphin)"),
    (r"exec_cmd\(tuiFiles\)", "Programs", "Terminal file manager (Yazi)"),
    (r"exec_cmd\(lock\)", "System", "Lock screen"),
    (r"exec_cmd\(powermenu\)", "System", "Power menu"),
    (r"exec_cmd\(systemmenu\)", "System", "System menu (the Arch logo at the top left)"),
    (r"waybar", "System", "Restart Waybar"),
    (r"wallpaper .. \" tui\"", "System", "Wallpaper picker"),
    (r"hl\.dsp\.exit", "System", "Exit Hyprland"),
    (r"exec_cmd\(monitors", "System", "Monitor manager (layout, mirror, scale, profiles)"),
    (r"aco keys", "System", "Searchable list of all shortcuts"),
    (r"exec_cmd\(windowswitcher\)", "Windows", "Window switcher"),
    (r"exec_cmd\(screenshot .. \" region\"\)", "Screenshots", "Capture a region"),
    (r"exec_cmd\(screenshot .. \" full\"\)", "Screenshots", "Capture all monitors"),
    (r"exec_cmd\(screenshot .. \" window\"\)", "Screenshots", "Capture the active window"),
    (r"exec_cmd\(screenshot .. \" monitor\"\)", "Screenshots", "Capture the active monitor"),
    (r"window\.close", "Windows", "Close window"),
    (r'mode = "fullscreen"', "Windows", "Toggle fullscreen"),
    (r'mode = "maximized"', "Windows", "Toggle maximise"),
    (r"window\.float", "Windows", "Toggle floating"),
    (r"window\.center", "Windows", "Center window"),
    (r"window\.pseudo", "Windows", "Toggle pseudo-tiling"),
    (r"togglesplit", "Windows", "Toggle split direction"),
    (r"focus_last_window", "Windows", "Switch to the last active window"),
    (r"cycle_all_windows", "Windows", "Cycle through all windows"),
    (r"cycle_same_class", "Windows", "Cycle between windows of the same application"),
    (r"jump_window_slot", "Windows", "Jump to a saved window slot"),
    (r"save_window_slot", "Windows", "Save the current window in a slot"),
    (r"window\.drag", "Windows", "Move window with the mouse"),
    (r"window\.resize\(\), \{ mouse", "Windows", "Resize window with the mouse"),
    (r"window\.resize\(\{ x =", "Windows", "Resize window"),
    (r"window\.move\(\{ direction", "Windows", "Move window"),
    (r"hl\.dsp\.focus\(\{ direction", "Focus", "Move focus"),
    (r"focus_next_monitor", "Monitors", "Focus the next monitor"),
    (r"move_window_to_next_monitor", "Monitors", "Move window to the next monitor"),
    (r"workspaces\.swap_with_next_monitor", "Monitors", "Swap the workspace rows of this and the next monitor"),
    (r'workspace\.toggle_special', "Scratchpad", "Show/hide scratchpad"),
    (r'window\.move\(\{ workspace = "special', "Scratchpad", "Move window to the scratchpad"),
    (r"workspaces\.move_step\(1\)", "Workspaces", "Move window to the next workspace"),
    (r"workspaces\.move_step\(-1\)", "Workspaces", "Move window to the previous workspace"),
    (r"workspaces\.move_empty", "Workspaces", "Move window to an empty workspace"),
    (r"workspaces\.move\(i\)", "Workspaces", "Move window to workspace N of this monitor"),
    (r"workspaces\.step\(1\)", "Workspaces", "Next workspace of this monitor"),
    (r"workspaces\.step\(-1\)", "Workspaces", "Previous workspace of this monitor"),
    (r"workspaces\.go_empty", "Workspaces", "Open an empty workspace"),
    (r"workspaces\.go_existing", "Workspaces", "Go to workspace N, if it exists"),
    (r"workspaces\.go\(i\)", "Workspaces", "Switch to workspace N (this monitor, or all in mode \"all\")"),
    (r'osd \.\. " volume up"', "Media", "Volume up"),
    (r'osd \.\. " volume down"', "Media", "Volume down"),
    (r'osd \.\. " volume mute"', "Media", "Mute"),
    (r'osd \.\. " mic"', "Media", "Mute microphone"),
    (r'osd \.\. " brightness up"', "Media", "Brighter"),
    (r'osd \.\. " brightness down"', "Media", "Dimmer"),
]
GROUPS = ["Programs", "System", "Windows", "Focus", "Workspaces", "Monitors", "Scratchpad",
          "Screenshots", "Media", "Other"]
NAMES = {"SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl", "ALT": "Alt", "Return": "Enter",
         "space": "Space", "Escape": "Esc", "BackSpace": "Backspace", "Tab": "Tab",
         "left": "←", "right": "→", "up": "↑", "down": "↓", "period": ".", "comma": ",",
         "Next": "PageDown", "Prior": "PageUp", "mouse_down": "Wheel↓", "mouse_up": "Wheel↑",
         "mouse:272": "Left mouse button", "mouse:273": "Right mouse button", "Print": "Print",
         "dead_circumflex": "^", "grave": "`", "numbersign": "#", "less": "<",
         "XF86AudioRaiseVolume": "Volume-up key", "XF86AudioLowerVolume": "Volume-down key",
         "XF86AudioMute": "Mute key", "XF86AudioMicMute": "Mic key",
         "XF86MonBrightnessUp": "Brightness-up key", "XF86MonBrightnessDown": "Brightness-down key"}
SYMBOLS = {"mainMod": "SUPER", "key": "1…0", "slot": "1–4"}


def split_call(text):
    """Split 'a, b, {c}' at top-level commas."""
    parts, depth, current, quote = [], 0, "", None
    for char in text:
        if quote:
            current += char
            if char == quote:
                quote = None
            continue
        if char in "\"'":
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    parts.append(current.strip())
    return parts


def evaluate(expression):
    out = ""
    for piece in re.split(r"\s*\.\.\s*", expression.strip()):
        piece = piece.strip()
        if piece[:1] in "\"'":
            out += piece[1:-1]
        else:
            out += SYMBOLS.get(piece, piece)
    return out


def keys(expression):
    combo = [token.strip() for token in evaluate(expression).split("+") if token.strip()]
    return " + ".join(NAMES.get(token, token) for token in combo)


def bindings(source):
    lines = source.splitlines()
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped.startswith("hl.bind("):
            continue
        inner = stripped[len("hl.bind("):].rstrip()
        inner = inner[:-1] if inner.endswith(")") else inner
        parts = split_call(inner)
        if len(parts) < 2:
            continue
        action = ", ".join(parts[1:])
        if action.rstrip().endswith("function()") or action.rstrip() == "function(":
            action += " " + lines[number].strip()  # body of a multi-line handler
        yield number, keys(parts[0]), action


DIRECTIONS = {"left": "left", "right": "right", "up": "up", "down": "down"}


def describe(action):
    for pattern, group, text in RULES:
        if re.search(pattern, action):
            direction = re.search(r'direction = "(\w+)"', action)
            if direction:
                text += " " + DIRECTIONS[direction[1]]
            size = re.search(r"x = (-?\d+),\s*y = (-?\d+)", action)
            if size:
                x, y = int(size[1]), int(size[2])
                text = {(-1, 0): "Narrower window", (1, 0): "Wider window",
                        (0, -1): "Shorter window", (0, 1): "Taller window"}[
                    ((x > 0) - (x < 0), (y > 0) - (y < 0))] + " (repeatable)"
            return group, text
    return "Other", None


def render():
    rows = {group: [] for group in GROUPS}
    unknown = []
    seen = set()
    for number, key, action in bindings(SOURCE.read_text()):
        group, text = describe(action)
        if text is None:
            unknown.append(f"hyprland.lua:{number}: {key} -> {action}")
            text = f"`{action}`"
        item = (key, text)
        if item in seen:
            continue
        seen.add(item)
        rows[group].append(item)
    out = ["<!-- GENERATED by scripts/gen-docs.py from hyprland.lua – do not edit by hand. -->", "",
           "# Key bindings", "",
           "`Super` is the Windows key. This page is generated from `hyprland.lua`, so it is",
           "always as current as the configuration. Your own changes in `~/.config/hypr/hyprland.lua`",
           "do not appear here – they only apply locally.", ""]
    for group in GROUPS:
        if not rows[group]:
            continue
        out += [f"## {group}", "", "| Key | Action |", "| --- | --- |"]
        for key, text in rows[group]:
            cells = " ".join("{kbd}`" + part.strip() + "`" if part.strip() else "" for part in [key])
            out.append(f"| {cells} | {text} |")
        out.append("")
    return "\n".join(out), unknown


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text, unknown = render()
    for item in unknown:
        print("undocumented binding:", item, file=sys.stderr)
    if args.check:
        current = TARGET.read_text() if TARGET.exists() else ""
        if current != text or unknown:
            print("docs/keybindings.md is out of date; run scripts/gen-docs.py", file=sys.stderr)
            return 1
        return 0
    TARGET.write_text(text)
    print(f"wrote {TARGET.relative_to(ROOT)} ({text.count(chr(10))} lines)")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
