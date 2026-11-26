#!/usr/bin/env bash
# ============================================================================
# POWER-MENÜ (aco-menu, zentriert wie der Launcher)
# ============================================================================

options="󰌾   Bildschirm sperren\n󰍃   Abmelden\n󰤄   Ruhezustand\n󰜉   Neu starten\n󰐥   Ausschalten"

chosen="$(printf "%b" "$options" | aco-menu --prompt "󰐥" --placeholder "System" --width 26 --lines 5)" || exit 0

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
