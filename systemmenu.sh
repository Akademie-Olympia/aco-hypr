#!/usr/bin/env bash
# ============================================================================
# SYSTEMMENÜ hinter dem Arch-Logo oben links (wie das Apple-Menü):
# Systeminfo, Einstellungen, Programme, Update, Sperren, Abmelden, Ruhezustand,
# Neustart, Ausschalten. Klappt als Dropdown unter der Leiste auf (aco-menu).
# ============================================================================
set -euo pipefail

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
settings=$config_home/hypr/settings.sh

rows() {
    printf '%s\n' "󰣇   Über dieses System" "󰒓   Einstellungen …" "󰀻   Programme …"
    command -v aco >/dev/null && printf '%s\n' "󰚰   System aktualisieren …"
    printf '%s\n' "󰌾   Bildschirm sperren" "󰍃   Abmelden" "󰤄   Ruhezustand" "󰜉   Neu starten" "󰐥   Ausschalten"
}

choice=$(rows | aco-menu --dropdown left --prompt "" --lines 9) || exit 0
case $choice in
    *"Über dieses System"*) exec "$settings" system ;;
    *Einstellungen*) exec "$settings" ;;
    *Programme*) exec aco-menu apps ;;
    *aktualisieren*) exec "$settings" update ;;
    *sperren*) exec hyprlock ;;
    *Abmelden*) exec hyprctl dispatch 'hl.dsp.exit()' ;;
    *Ruhezustand*) exec systemctl suspend ;;
    *"Neu starten"*) exec systemctl reboot ;;
    *Ausschalten*) exec systemctl poweroff ;;
esac
