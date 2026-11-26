#!/usr/bin/env bash
# ============================================================================
# STANDARD-PROGRAMME: Dateien → Dolphin, Video → Celluloid, Musik → Amberol.
# Läuft bei jedem Hyprland-Start und setzt nur Typen, die in der eigenen
# ~/.config/mimeapps.list noch fehlen: eigene Entscheidungen (xdg-mime,
# "Öffnen mit … immer") bleiben erhalten. Systemweite Vorschläge zählen nicht,
# sonst öffnete z. B. Amberol Ordner, weil es sich dafür anmeldet.
# ============================================================================
set -euo pipefail

command -v xdg-mime >/dev/null || exit 0
user_list=${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list

chosen() { # mime-typ: steht in der eigenen Liste unter [Default Applications]
    awk -v t="$1" '/^\[/ { section = $0 } section == "[Default Applications]" && index($0, t "=") == 1 { found = 1 }
        END { exit !found }' "$user_list" 2>/dev/null
}

set_default() { # desktop-datei mime-typ...
    local app=$1 type
    shift
    [[ -f /usr/share/applications/$app ]] || return 0
    for type in "$@"; do
        chosen "$type" || xdg-mime default "$app" "$type"
    done
}

set_default org.kde.dolphin.desktop inode/directory
set_default io.github.celluloid_player.Celluloid.desktop \
    video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo video/mpeg video/ogg
set_default io.bassi.Amberol.desktop \
    audio/mpeg audio/flac audio/ogg audio/x-vorbis+ogg audio/opus audio/x-wav audio/mp4 audio/aac
