#!/usr/bin/env python3
"""Generate docs/keybindings.md from hyprland.lua.

    python3 scripts/gen-docs.py          # rewrite the page
    python3 scripts/gen-docs.py --check  # exit 1 if the page is out of date

Every ``hl.bind(...)`` line is read, its key expression evaluated and its
action described. Bindings the table below does not know are listed under
"Sonstiges" with the raw action, and ``--check`` fails so a new binding is
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
    (r"exec_cmd\(terminal\)", "Programme", "Terminal öffnen"),
    (r'exec_cmd\("kitty -e tmux', "Programme", "Terminal mit tmux-Sitzung `main`"),
    (r"exec_cmd\(menu\)", "Programme", "Anwendungsstarter (Fuzzel)"),
    (r"exec_cmd\(browser\)", "Programme", "Browser öffnen"),
    (r"exec_cmd\(fileManager\)", "Programme", "Dateimanager (PCManFM)"),
    (r"exec_cmd\(tuiFiles\)", "Programme", "Dateimanager im Terminal (Yazi)"),
    (r"exec_cmd\(lock\)", "System", "Bildschirm sperren"),
    (r"exec_cmd\(powermenu\)", "System", "Powermenü"),
    (r"waybar", "System", "Waybar neu starten"),
    (r"wallpaper .. \" tui\"", "System", "Wallpaper-Auswahl"),
    (r"hl\.dsp\.exit", "System", "Hyprland beenden"),
    (r"exec_cmd\(windowswitcher\)", "Fenster", "Fensterwechsler"),
    (r"exec_cmd\(screenshot .. \" region\"\)", "Screenshots", "Bereich aufnehmen"),
    (r"exec_cmd\(screenshot .. \" full\"\)", "Screenshots", "Alle Monitore aufnehmen"),
    (r"exec_cmd\(screenshot .. \" window\"\)", "Screenshots", "Aktives Fenster aufnehmen"),
    (r"exec_cmd\(screenshot .. \" monitor\"\)", "Screenshots", "Aktiven Monitor aufnehmen"),
    (r"window\.close", "Fenster", "Fenster schließen"),
    (r'mode = "fullscreen"', "Fenster", "Vollbild umschalten"),
    (r'mode = "maximized"', "Fenster", "Maximieren umschalten"),
    (r"window\.float", "Fenster", "Schwebend umschalten"),
    (r"window\.center", "Fenster", "Fenster zentrieren"),
    (r"window\.pseudo", "Fenster", "Pseudo-Tiling umschalten"),
    (r"togglesplit", "Fenster", "Teilungsrichtung wechseln"),
    (r"focus_last_window", "Fenster", "Zum zuletzt aktiven Fenster wechseln"),
    (r"cycle_all_windows", "Fenster", "Durch alle Fenster schalten"),
    (r"cycle_same_class", "Fenster", "Zwischen Fenstern derselben Anwendung wechseln"),
    (r"jump_window_slot", "Fenster", "Zu gespeichertem Fenster-Slot springen"),
    (r"save_window_slot", "Fenster", "Aktuelles Fenster im Slot speichern"),
    (r"window\.drag", "Fenster", "Fenster mit der Maus verschieben"),
    (r"window\.resize\(\), \{ mouse", "Fenster", "Fenstergröße mit der Maus ändern"),
    (r"window\.resize\(\{ x =", "Fenster", "Fenstergröße ändern"),
    (r"window\.move\(\{ direction", "Fenster", "Fenster verschieben"),
    (r"hl\.dsp\.focus\(\{ direction", "Fokus", "Fokus verschieben"),
    (r"focus_next_monitor", "Monitore", "Fokus auf nächsten Monitor"),
    (r"move_window_to_next_monitor", "Monitore", "Fenster auf nächsten Monitor"),
    (r"swap_monitors_workspaces", "Monitore", "Workspaces der Monitore tauschen"),
    (r'workspace\.toggle_special', "Scratchpad", "Scratchpad ein-/ausblenden"),
    (r'window\.move\(\{ workspace = "special', "Scratchpad", "Fenster in den Scratchpad"),
    (r'window\.move\(\{ workspace = "r\+1"', "Workspaces", "Fenster zum nächsten Workspace"),
    (r'window\.move\(\{ workspace = "r-1"', "Workspaces", "Fenster zum vorigen Workspace"),
    (r'window\.move\(\{ workspace = "empty"', "Workspaces", "Fenster auf freien Workspace"),
    (r'window\.move\(\{ workspace = i', "Workspaces", "Fenster auf Workspace N verschieben"),
    (r'focus\(\{ workspace = "r\+1"', "Workspaces", "Nächster Workspace"),
    (r'focus\(\{ workspace = "r-1"', "Workspaces", "Voriger Workspace"),
    (r'focus\(\{ workspace = "empty"', "Workspaces", "Freien Workspace öffnen"),
    (r"focus\(\{ workspace = i", "Workspaces", "Zu Workspace N wechseln"),
    (r"focus_existing_screen", "Workspaces", "Zu Bildschirm/Workspace N, falls vorhanden"),
    (r"AudioRaise|wpctl set-volume -l", "Medien", "Lauter"),
    (r"wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", "Medien", "Leiser"),
    (r"set-mute @DEFAULT_AUDIO_SINK@", "Medien", "Stumm schalten"),
    (r"set-mute @DEFAULT_AUDIO_SOURCE@", "Medien", "Mikrofon stumm schalten"),
    (r"brightnessctl.*5%\+", "Medien", "Heller"),
    (r"brightnessctl.*5%-", "Medien", "Dunkler"),
]
GROUPS = ["Programme", "System", "Fenster", "Fokus", "Workspaces", "Monitore", "Scratchpad",
          "Screenshots", "Medien", "Sonstiges"]
NAMES = {"SUPER": "Super", "SHIFT": "Shift", "CTRL": "Strg", "ALT": "Alt", "Return": "Enter",
         "space": "Leertaste", "Escape": "Esc", "BackSpace": "←Backspace", "Tab": "Tab",
         "left": "←", "right": "→", "up": "↑", "down": "↓", "period": ".", "comma": ",",
         "Next": "Bild↓", "Prior": "Bild↑", "mouse_down": "Mausrad↓", "mouse_up": "Mausrad↑",
         "mouse:272": "Linke Maustaste", "mouse:273": "Rechte Maustaste", "Print": "Druck",
         "dead_circumflex": "^", "grave": "`", "numbersign": "#", "less": "<",
         "XF86AudioRaiseVolume": "Lauter-Taste", "XF86AudioLowerVolume": "Leiser-Taste",
         "XF86AudioMute": "Stumm-Taste", "XF86AudioMicMute": "Mikrofon-Taste",
         "XF86MonBrightnessUp": "Heller-Taste", "XF86MonBrightnessDown": "Dunkler-Taste"}
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


DIRECTIONS = {"left": "links", "right": "rechts", "up": "oben", "down": "unten"}


def describe(action):
    for pattern, group, text in RULES:
        if re.search(pattern, action):
            direction = re.search(r'direction = "(\w+)"', action)
            if direction:
                text += " nach " + DIRECTIONS[direction[1]]
            size = re.search(r"x = (-?\d+),\s*y = (-?\d+)", action)
            if size:
                x, y = int(size[1]), int(size[2])
                text = {(-1, 0): "Fenster schmaler", (1, 0): "Fenster breiter",
                        (0, -1): "Fenster niedriger", (0, 1): "Fenster höher"}[
                    ((x > 0) - (x < 0), (y > 0) - (y < 0))] + " (wiederholbar)"
            return group, text
    return "Sonstiges", None


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
           "# Tastenkombinationen", "",
           "`Super` ist die Windows-Taste. Diese Seite wird aus `hyprland.lua` erzeugt und ist daher",
           "immer so aktuell wie die Konfiguration. Eigene Änderungen in `~/.config/hypr/hyprland.lua`",
           "erscheinen hier nicht – sie gelten nur lokal.", ""]
    for group in GROUPS:
        if not rows[group]:
            continue
        out += [f"## {group}", "", "| Taste | Aktion |", "| --- | --- |"]
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
