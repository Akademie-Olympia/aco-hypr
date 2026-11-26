#!/usr/bin/env bash
# Bereich auswählen, als PNG speichern/kopieren und optional mit Satty bearbeiten.
set -euo pipefail
umask 077

usage() {
    printf 'Usage: screenshot [region|window|monitor|full|menu]\n  region   Bereich auswählen (Standard)\n  window   Aktives Fenster aufnehmen\n  monitor  Aktiven Bildschirm aufnehmen\n  full     Alle Bildschirme aufnehmen\n  menu     Auswahl wie bei macOS (Bereich, Fenster, Bildschirm, alle, mit Timer)\n\nZiel, Ordner, Editor und Mitteilung: ~/.config/aco/screenshot.conf (Einstellungen > Bildschirmfotos).\nSCREENSHOT_DIR überschreibt den Ordner.\n'
}

# Auswahlmenü: die gewählte Aufnahme startet erst, wenn das Menü verschwunden ist.
if [[ "${1:-}" == menu ]]; then
    choice="$(printf '%s\n' "󰩭   Bereich auswählen" "󰖯   Aktives Fenster" "󰍹   Aktiver Bildschirm" \
        "󰍺   Alle Bildschirme" "󰔛   Bildschirm in 5 Sekunden" |
        aco-menu --prompt "󰹑" --placeholder "Bildschirmfoto" --width 28 --lines 5)" || exit 0
    sleep 0.3
    case "$choice" in
        *Bereich*) exec "$0" region ;;
        *Fenster*) exec "$0" window ;;
        *"5 Sekunden"*) sleep 5; exec "$0" monitor ;;
        *"Aktiver Bildschirm"*) exec "$0" monitor ;;
        *"Alle"*) exec "$0" full ;;
    esac
    exit 0
fi

case "${1:-region}" in
    region|window|monitor|full) mode="${1:-region}" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
if (( $# > 1 )); then
    usage >&2
    exit 2
fi

required=(grim wl-copy)
if [[ "$mode" == region ]]; then
    required+=(slurp)
elif [[ "$mode" == window || "$mode" == monitor ]]; then
    required+=(hyprctl jq)
fi
for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'Screenshot: %s fehlt (Pakete: grim slurp wl-clipboard hyprland jq).\n' "$cmd" >&2
        exit 1
    fi
done

# shellcheck source=/dev/null
source "${XDG_CONFIG_HOME:-$HOME/.config}/aco/theme/hypr/colors.sh"
: "${aco_accent:?}" "${aco_scrim:?}"

args=()
if [[ "$mode" == region ]]; then
    # Escape/Abbruch darf weder einen Screenshot noch eine leere Datei erzeugen.
    geometry="$(slurp -b "$aco_scrim" -c "${aco_accent}ff" -s 00000000 -w 2)" || exit 0
    [[ -n "$geometry" ]] || exit 0
    args=(-g "$geometry")
elif [[ "$mode" == window ]]; then
    geometry="$(hyprctl -j activewindow | jq -er '
        select(.mapped == true and .hidden != true and .size[0] > 0 and .size[1] > 0)
        | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
    ')" || { printf 'Screenshot: Kein aktives Fenster verfügbar.\n' >&2; exit 1; }
    args=(-g "$geometry")
elif [[ "$mode" == monitor ]]; then
    monitor="$(hyprctl -j monitors | jq -er '.[] | select(.focused == true) | .name | select(length > 0)')" \
        || { printf 'Screenshot: Kein aktiver Bildschirm verfügbar.\n' >&2; exit 1; }
    args=(-o "$monitor")
fi

# Where the capture goes, from ~/.config/aco/screenshot.conf (Einstellungen >
# Bildschirmfotos):
#   target = both | clipboard | folder   copy, save, or both (default both)
#   folder = ~/Bilder/Bildschirmfotos    where saved captures go
#   editor = yes | no                    open Satty to annotate (default yes)
#   notify = yes | no                    show a notification with a preview (default yes)
# SCREENSHOT_DIR overrides the folder.
conf_get() { # schluessel standardwert
    local value
    value="$(awk -F ' *= *' -v k="$1" '$1 == k { v = $2 } END { print v }' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/aco/screenshot.conf" 2>/dev/null)"
    printf '%s' "${value:-$2}"
}
pictures="$(xdg-user-dir PICTURES 2>/dev/null || true)"
[[ -n "$pictures" && "$pictures" != "$HOME" ]] || pictures="$HOME/Pictures"
target="$(conf_get target both)"
folder="$(conf_get folder "$pictures/Bildschirmfotos")"
folder="${SCREENSHOT_DIR:-${folder/#\~/$HOME}}"
editor="$(conf_get editor yes)"
notify="$(conf_get notify yes)"
case "$target" in both|clipboard|folder) ;; *) target=both ;; esac

# Clipboard only: the file is a short-lived working copy in the runtime directory.
if [[ "$target" == clipboard ]]; then
    output_dir="${XDG_RUNTIME_DIR:-/tmp}/aco-screenshot"
else
    output_dir="$folder"
fi
mkdir -p -- "$output_dir"
file="$(mktemp "$output_dir/Bildschirmfoto-$(date +%Y-%m-%d-%H%M%S)-XXXX.png")"
if ! grim "${args[@]}" "$file"; then
    rm -f -- "$file"
    printf 'Screenshot: Aufnahme fehlgeschlagen.\n' >&2
    exit 1
fi

if [[ "$target" != folder ]] && ! wl-copy --type image/png < "$file"; then
    printf 'Screenshot: Zwischenablage fehlgeschlagen (%s).\n' "$file" >&2
fi

if [[ "$notify" == yes ]] && command -v notify-send >/dev/null 2>&1; then
    case "$target" in
        clipboard) body="In der Zwischenablage" ;;
        folder) body="Gespeichert in ${output_dir/#$HOME/\~}" ;;
        *) body="Kopiert und gespeichert in ${output_dir/#$HOME/\~}" ;;
    esac
    LC_ALL=C.UTF-8 notify-send -a Bildschirmfoto -i "$file" "Bildschirmfoto" "$body" >/dev/null 2>&1 || true
fi

if [[ "$editor" == yes ]] && command -v satty >/dev/null 2>&1; then
    satty_args=()
    satty_config="${XDG_CONFIG_HOME:-$HOME/.config}/aco/theme/hypr/satty.toml"
    if [[ -f "$satty_config" ]]; then
        satty_args+=(--config "$satty_config")
    else
        satty_args+=(--copy-command 'wl-copy --type image/png' --save-after-copy \
            --early-exit all --initial-tool arrow)
    fi
    # Enter/Strg+C kopiert die bearbeitete Version und speichert sie zusätzlich.
    exec satty "${satty_args[@]}" --filename "$file" --output-filename "$file"
fi
