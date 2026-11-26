#!/usr/bin/env bash
# Apply a freshly rendered theme to the running Hyprland session.
set -euo pipefail
pgrep -x Hyprland >/dev/null || exit 0
hyprctl reload >/dev/null
