#!/usr/bin/env bash
# Settings hub: one searchable menu for appearance, display, network and more.
# Entries only appear when the tool behind them is installed.
set -euo pipefail

if pgrep -x fuzzel >/dev/null; then
    pkill -x fuzzel
    exit 0
fi

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
terminal=${TERMINAL:-kitty}
entries=()

# add LABEL COMMAND [REQUIRED_TOOL]
add() {
    if [[ -z ${3:-} ]] || command -v "$3" >/dev/null; then
        entries+=("$1"$'\t'"$2")
    fi
}

add "󰔎   Erscheinungsbild"     "aco-theme menu" aco-theme
add "󰸉   Hintergrundbild"      "$config_home/wallpaper/wallpaper.sh tui"
add "󰍹   Bildschirme"          "$config_home/hypr/monitors.sh menu"
add "󰤨   Netzwerk"             "$terminal -e nmtui" nmtui
add "󰂯   Bluetooth"            "$terminal -e bluetoothctl" bluetoothctl
add "󰕾   Ton"                  "pavucontrol" pavucontrol
add "󰌌   Tastenkürzel"         "aco keys --menu" aco
add "󰚰   System aktualisieren" "$terminal -e aco update" aco

chosen=$(printf '%s\n' "${entries[@]%%$'\t'*}" |
    fuzzel --dmenu --prompt="󰒓   " --placeholder="Einstellungen" --lines="${#entries[@]}" --width=32) || exit 0

for entry in "${entries[@]}"; do
    if [[ ${entry%%$'\t'*} == "$chosen" ]]; then
        exec bash -c "${entry#*$'\t'}"
    fi
done
