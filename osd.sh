#!/usr/bin/env bash
# ============================================================================
# OSD: Lautstärke, Mikrofon und Helligkeit ändern und kurz anzeigen.
#   osd.sh volume up|down|mute    osd.sh mic    osd.sh brightness up|down
# Die Anzeige ist eine kurze Mitteilung mit Balken (swaync). Ein fester Tag
# ersetzt die vorige, statt sie zu stapeln; aco-swaync hält sie aus dem Verlauf.
# ============================================================================
set -euo pipefail

app="Lautstärke und Helligkeit"   # aco-swaync matches this name
step=5

# notify-send rejects non-ASCII text under a plain C locale (for example when
# started without a session locale), so force UTF-8 for this one call.
show() { # icon titel prozent
    command -v notify-send >/dev/null || return 0
    LC_ALL=C.UTF-8 notify-send -a "$app" -u low -t 1200 \
        -h string:x-canonical-private-synchronous:aco-osd \
        -h "int:value:$3" "$1   $2" "$3 %" >/dev/null 2>&1 || true
}

# Lautstärke der Standardausgabe in Prozent und ob sie stumm ist.
volume_state() { # -> "prozent muted|on"
    wpctl get-volume @DEFAULT_AUDIO_SINK@ |
        awk '{ printf "%d %s\n", $2 * 100 + 0.5, (/MUTED/ ? "muted" : "on") }'
}

volume() {
    case ${1:-} in
        up) wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "$step%+" ;;
        down) wpctl set-volume @DEFAULT_AUDIO_SINK@ "$step%-" ;;
        mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        *) echo "osd.sh: volume up|down|mute" >&2; exit 2 ;;
    esac
    local percent state icon
    read -r percent state < <(volume_state)
    if [[ $state == muted ]]; then
        show "󰝟" "Stumm" 0
        return
    fi
    if ((percent >= 66)); then icon="󰕾"; elif ((percent >= 33)); then icon="󰖀"; else icon="󰕿"; fi
    show "$icon" "Lautstärke" "$percent"
}

mic() {
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
    if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
        show "󰍭" "Mikrofon aus" 0
    else
        show "󰍬" "Mikrofon an" 100
    fi
}

brightness() {
    command -v brightnessctl >/dev/null || exit 0
    case ${1:-} in
        up) brightnessctl -q -e4 -n2 set "$step%+" ;;
        down) brightnessctl -q -e4 -n2 set "$step%-" ;;
        *) echo "osd.sh: brightness up|down" >&2; exit 2 ;;
    esac
    local percent
    percent=$(brightnessctl -m | awk -F, '{ sub("%", "", $4); print $4 }')
    show "󰃠" "Helligkeit" "$percent"
}

case ${1:-} in
    volume) volume "${2:-}" ;;
    mic) mic ;;
    brightness) brightness "${2:-}" ;;
    *) echo "usage: osd.sh volume up|down|mute | mic | brightness up|down" >&2; exit 2 ;;
esac
