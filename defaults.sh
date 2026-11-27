#!/usr/bin/env bash
# ============================================================================
# STANDARD-PROGRAMME: die eigenen ACO-Apps (Dateien, Musik, Video, Bilder,
# PDF, Editor). Fehlt eine ACO-App (Add-on nicht installiert),
# greift die nächste installierte Alternative der Liste.
# Läuft bei jedem Hyprland-Start und setzt nur Typen, die in der eigenen
# ~/.config/mimeapps.list noch fehlen: eigene Entscheidungen (xdg-mime,
# "Öffnen mit … immer") bleiben erhalten. Systemweite Vorschläge zählen nicht,
# sonst öffnete z. B. ein Player Ordner, weil er sich dafür anmeldet.
# ============================================================================
set -euo pipefail

command -v xdg-mime >/dev/null || exit 0
user_list=${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list

chosen() { # mime-typ: steht in der eigenen Liste unter [Default Applications]
    awk -v t="$1" '/^\[/ { section = $0 } section == "[Default Applications]" && index($0, t "=") == 1 { found = 1 }
        END { exit !found }' "$user_list" 2>/dev/null
}

set_default() { # "app.desktop alternative.desktop ..." mime-typ...
    local apps=$1 app type
    shift
    for app in $apps; do
        [[ -f /usr/share/applications/$app ]] || continue
        for type in "$@"; do
            chosen "$type" || xdg-mime default "$app" "$type"
        done
        return 0
    done
}

set_default "org.aco.Files.desktop org.kde.dolphin.desktop" inode/directory
set_default "org.aco.Video.desktop io.github.celluloid_player.Celluloid.desktop" \
    video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo video/mpeg video/ogg
set_default "org.aco.Music.desktop io.bassi.Amberol.desktop" \
    audio/mpeg audio/flac audio/ogg audio/x-vorbis+ogg audio/opus audio/x-wav audio/mp4 audio/aac
set_default "org.aco.Images.desktop" \
    image/jpeg image/png image/gif image/webp image/tiff image/bmp image/avif image/heif
set_default "org.aco.Pdf.desktop" application/pdf
set_default "org.aco.Edit.desktop" text/plain text/markdown
