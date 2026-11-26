#!/usr/bin/env bash
# ============================================================================
# POWER-MENÜ (zentriert, wie der Launcher)
# ============================================================================

if pgrep -x "fuzzel" > /dev/null; then
    pkill -x "fuzzel"
    exit 0
fi

options="󰌾   Bildschirm sperren\n󰍃   Abmelden\n󰤄   Ruhezustand\n󰜉   Neu starten\n󰐥   Ausschalten"

chosen="$(printf "%b" "$options" | fuzzel --dmenu \
    --width=26 \
    --lines=5 \
    --hide-prompt)"

case "$chosen" in
    *"Ausschalten"*)
        systemctl poweroff
        ;;
    *"Neu starten"*)
        systemctl reboot
        ;;
    *"Ruhezustand"*)
        systemctl suspend
        ;;
    *"Bildschirm sperren"*)
        hyprlock
        ;;
    *"Abmelden"*)
        hyprctl dispatch 'hl.dsp.exit()'
        ;;
esac
