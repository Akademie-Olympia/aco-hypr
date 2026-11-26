#!/usr/bin/env python3
"""Check every key binding in hyprland.lua on the machine it runs on.

    python3 scripts/check-binds.py [path/to/hyprland.lua]

- every command started by a binding (directly or through a `local` program
  variable) must exist and be executable;
- no key combination may be bound twice to different actions.
Run it inside the session (or the test VM) after changing bindings; exit 1 on problems.
"""
import importlib.util
import os
import re
import shlex
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("gen_docs", HERE / "gen-docs.py")
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)

HOME = os.environ["HOME"]
CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME", f"{HOME}/.config")
LUA_NAMES = {"home": HOME, "config_home": CONFIG_HOME}


def lua_string(expression, variables):
    """Evaluate the small subset of Lua string expressions the config uses."""
    expression = expression.strip()
    fmt = re.fullmatch(r'string\.format\("%q",\s*(.+)\)', expression)
    if fmt:
        return shlex.quote(lua_string(fmt[1], variables))
    out = ""
    for piece in re.split(r"\s*\.\.\s*", expression):
        piece = piece.strip()
        if piece[:1] in "\"'":
            out += piece[1:-1]
        elif piece in variables:
            out += variables[piece]
        else:
            return None
    return out


def program_variables(source):
    variables = dict(LUA_NAMES)
    for name, expression in re.findall(r"^local (\w+)\s*=\s*(.+?)\s*$", source, re.M):
        value = lua_string(expression, variables)
        if value is not None:
            variables[name] = value
    return variables


def executable(command):
    """First word of a shell command (after wrappers like pkill ... ||)."""
    first = shlex.split(command)[0]
    first = first.replace("~", HOME, 1)
    if "/" in first:
        return os.access(first, os.X_OK) or (first.endswith(".sh") and os.path.isfile(first))
    return shutil.which(first) is not None


def main():
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "hyprland.lua"
    source = source_path.read_text()
    variables = program_variables(source)
    problems, seen, checked = [], {}, 0
    for number, key, action in docs.bindings(source):
        exec_arg = re.search(r"exec_cmd\((.+)\)\s*(,\s*\{.*\})?\)?$", action)
        if exec_arg:
            command = lua_string(exec_arg[1], variables)
            if command is None:
                problems.append(f"hyprland.lua:{number}: {key}: cannot resolve {exec_arg[1]}")
            else:
                checked += 1
                for part in re.split(r"\s*(?:\|\||&&|;)\s*", command):
                    if part and not executable(part):
                        problems.append(f"hyprland.lua:{number}: {key}: '{part.split()[0]}' not found")
        templated = any(token in key for token in ("…", "–"))
        if not templated:
            if key in seen and seen[key][1] != action:
                problems.append(f"hyprland.lua:{number}: {key} also bound at line {seen[key][0]}")
            seen.setdefault(key, (number, action))
    for problem in problems:
        print(problem)
    print(f"{len(seen)} key combinations, {checked} commands checked, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
