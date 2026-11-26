#!/usr/bin/env bash
# ============================================================================
# EINSTELLUNGEN (Super + I): ein durchsuchbarer Hub für das ganze System.
#   settings.sh [seite]   seite = appearance | wallpaper | wifi | bluetooth |
#                         sound | displays | power | notifications | system |
#                         keys | update
# Jede Seite ist ein aco-menu; Einträge erscheinen nur, wenn ihr Werkzeug
# installiert ist. Esc auf einer Unterseite führt zurück zur Übersicht.
# ============================================================================
set -euo pipefail

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
terminal=${TERMINAL:-kitty}
self=$(readlink -f "${BASH_SOURCE[0]}")

have() { command -v "$1" >/dev/null 2>&1; }
notify() { have notify-send && notify-send -a Einstellungen "$@" >/dev/null 2>&1 || true; }

# pick PROMPT PLACEHOLDER [aco-menu options...] < "label<TAB>value" rows -> value
pick() {
    local prompt=$1 placeholder=$2 rows chosen lines
    shift 2
    rows=$(cat)
    # Show every row up to 12; options passed by the caller (e.g. --lines) win.
    lines=$(wc -l <<<"$rows")
    ((lines > 12)) && lines=12
    chosen=$(cut -f1 <<<"$rows" | aco-menu --prompt "$prompt" --placeholder "$placeholder" --lines "$lines" "$@") || return
    awk -F '\t' -v sel="$chosen" '$1 == sel { print $2; exit }' <<<"$rows"
}

row() { printf '%s\t%s\n' "$1" "$2"; }

# Zeilen-Gruppen unten nutzen "if have …; then row …; fi" statt "have … && row":
# mit pipefail würde ein fehlendes Werkzeug am Ende sonst die Auswahl verwerfen.

# back STATUS [SEITE]: Esc (Status 1) führt eine Ebene zurück, standardmäßig
# zur Übersicht; wurde das Menü von außen geschlossen (130), ist Schluss.
back() {
    if (($1 == 1)); then
        if [[ -n ${2:-} ]]; then "page_$2"; else exec "$self"; fi
    fi
    exit 0
}

# --- Übersicht -----------------------------------------------------------------
page_main() {
    local page
    page=$({
        row "󰔎   Erscheinungsbild" appearance
        row "󰸉   Hintergrundbild" wallpaper
        if have nmcli; then row "󰤨   WLAN & Netzwerk" wifi; fi
        if have bluetoothctl; then row "󰂯   Bluetooth" bluetooth; fi
        if have pactl; then row "󰕾   Ton" sound; fi
        row "󰍹   Bildschirme" displays
        if have powerprofilesctl; then row "󰂄   Energie" power; fi
        if have swaync-client; then row "󰂚   Mitteilungen" notifications; fi
        row "󰻠   System & Treiber" system
        if have aco; then row "󰌌   Tastenkürzel" keys; fi
        if have aco; then row "󰚰   System aktualisieren" update; fi
    } | pick "󰒓" "Einstellungen" --width 30) || exit 0
    "page_$page"
}

# --- Erscheinungsbild ----------------------------------------------------------
page_appearance() {
    have aco-theme || { notify "aco-theme fehlt"; exit 1; }
    local mode transparency accent theme choice
    mode=$(aco-theme get mode)
    transparency=$(aco-theme get transparency)
    accent=$(aco-theme get accent_name)
    theme=$(aco-theme get theme)
    choice=$({
        if [[ $mode == dark ]]; then row "󰖨   Hell" "mode light"; else row "󰖔   Dunkel" "mode dark"; fi
        if [[ $transparency == on ]]; then row "󰂵   Transparenz ausschalten" "transparency off"
        else row "󰂵   Transparenz einschalten" "transparency on"; fi
        row "󰏘   Akzentfarbe · $accent" accent
        row "󰉼   Theme · $theme" theme
        row "󰷈   Eigene Anpassungen bearbeiten" edit
    } | pick "󰔎" "Erscheinungsbild" --width 30) || back $?
    case $choice in
        accent) page_accent ;;
        theme)
            choice=$(aco-theme list | sed -n 's/^themes: *//p' | tr ' ' '\n' | sed '/^$/d' |
                while read -r t; do row "$t" "$t"; done | pick "󰉼" "Theme") || back $? appearance
            aco-theme use "$choice" ;;
        edit) aco-theme edit ;;
        *) read -ra args <<<"$choice"; aco-theme "${args[@]}" ;;
    esac
}

page_accent() {
    local name color choice
    choice=$(for name in blue purple pink red orange yellow green cyan graphite; do
        color=$(aco-theme get "$name")
        row "<span foreground='$color'>●</span>   $name" "$name"
    done | pick "󰏘" "Akzentfarbe" --markup --width 24) || back $? appearance
    aco-theme accent "$choice"
}

# --- Hintergrund und Bildschirme -----------------------------------------------
page_wallpaper() { exec bash "$config_home/wallpaper/wallpaper.sh" tui; }
page_displays() { exec bash "$config_home/hypr/monitors.sh" menu; }

# --- WLAN & Netzwerk -----------------------------------------------------------
signal_icon() {
    local s=$1
    if ((s >= 75)); then echo "󰤨"; elif ((s >= 50)); then echo "󰤥"; elif ((s >= 25)); then echo "󰤢"; else echo "󰤟"; fi
}

# Verbindet mit einem neuen, geschützten Netz. Das Passwort steht nie in der
# Kommandozeile (sichtbar in /proc), sondern kurz in einer 0600-Datei.
wifi_connect_new() {
    local ssid=$1 security=$2 pass secrets
    if [[ -z $security || $security == -- ]]; then
        nmcli device wifi connect "$ssid" >/dev/null
        return
    fi
    pass=$(aco-menu --password --lines 0 --prompt "󰌾" --placeholder "Passwort für $ssid" </dev/null) || return 1
    secrets=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/aco-wifi.XXXXXX")
    chmod 600 "$secrets"
    trap 'rm -f "$secrets"' RETURN
    printf '802-11-wireless-security.psk:%s\n' "$pass" >"$secrets"
    nmcli connection add type wifi con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt wpa-psk >/dev/null
    if ! nmcli connection up id "$ssid" passwd-file "$secrets" >/dev/null; then
        nmcli connection delete id "$ssid" >/dev/null 2>&1 || true
        return 1
    fi
}

page_wifi() {
    local radio status choice known
    radio=$(nmcli radio wifi)
    status=$(nmcli -t -f TYPE,STATE,CONNECTION device | awk -F: '$2 == "connected" { printf "%s%s: %s", sep, $1, $3; sep = "  ·  " }')
    choice=$({
        if [[ $radio == enabled ]]; then
            row "󰖪   WLAN ausschalten" radio-off
            nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan auto 2>/dev/null |
                awk -F: '$4 != "" && !seen[$4]++' |
                while IFS=: read -r in_use signal security ssid; do
                    local mark="" lock=""
                    [[ $in_use == "*" ]] && mark="  ✓"
                    [[ -n $security && $security != -- ]] && lock="  󰌾"
                    row "$(signal_icon "$signal")   $ssid$lock$mark" "net:$security:$ssid"
                done
        else
            row "󰤨   WLAN einschalten" radio-on
        fi
        nmcli -t -f NAME,TYPE connection show | grep -q ':802-11-wireless$' && row "󰆴   Gespeichertes Netz vergessen …" forget
        if have nmtui; then row "󰒓   Erweitert (nmtui) …" nmtui; fi
    } | pick "󰤨" "WLAN & Netzwerk" --message "${status:-Nicht verbunden}" --width 34 --lines 12) || back $?
    case $choice in
        radio-off) nmcli radio wifi off ;;
        radio-on) nmcli radio wifi on ;;
        nmtui) exec "$terminal" -e nmtui ;;
        forget)
            known=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }' |
                while read -r name; do row "󰆴   $name" "$name"; done | pick "󰆴" "Netz vergessen") || back $? wifi
            nmcli connection delete id "$known" >/dev/null && notify "WLAN" "$known vergessen" ;;
        net:*)
            local rest=${choice#net:} security ssid
            security=${rest%%:*} ssid=${rest#*:}
            if nmcli -t -f NAME connection show | grep -Fxq -- "$ssid"; then
                nmcli connection up id "$ssid" >/dev/null && notify "WLAN" "Verbunden mit $ssid" || notify -u critical "WLAN" "Verbindung mit $ssid fehlgeschlagen"
            elif wifi_connect_new "$ssid" "$security"; then
                notify "WLAN" "Verbunden mit $ssid"
            else
                notify -u critical "WLAN" "Verbindung mit $ssid fehlgeschlagen"
            fi ;;
    esac
}

# --- Bluetooth -----------------------------------------------------------------
page_bluetooth() {
    local powered choice mac
    powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }')
    choice=$({
        if [[ $powered == yes ]]; then
            row "󰂲   Bluetooth ausschalten" off
            bluetoothctl devices Paired 2>/dev/null | while read -r _ mac name; do
                if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
                    row "󰂱   $name  ✓" "disconnect $mac"
                else
                    row "󰂯   $name" "connect $mac"
                fi
            done
            row "󰐕   Neues Gerät koppeln …" pair
        else
            row "󰂯   Bluetooth einschalten" on
        fi
    } | pick "󰂯" "Bluetooth" --width 32) || back $?
    case $choice in
        on | off) bluetoothctl power "$choice" >/dev/null ;;
        pair) exec "$terminal" -e bluetoothctl ;;
        connect* | disconnect*) mac=${choice#* }; bluetoothctl "${choice%% *}" "$mac" >/dev/null ;;
    esac
}

# --- Ton -----------------------------------------------------------------------
page_sound() {
    local default_sink default_source choice
    default_sink=$(pactl get-default-sink 2>/dev/null || true)
    default_source=$(pactl get-default-source 2>/dev/null || true)
    choice=$({
        pactl -f json list sinks 2>/dev/null | jq -r --arg d "$default_sink" \
            '.[] | "󰕾   \(.description)\(if .name == $d then "  ✓" else "" end)\tsink:\(.name)"'
        pactl -f json list sources 2>/dev/null | jq -r --arg d "$default_source" \
            '.[] | select(.monitor_source == "") | "󰍬   \(.description)\(if .name == $d then "  ✓" else "" end)\tsource:\(.name)"'
        if have pavucontrol; then row "󰒓   Mixer (pavucontrol) …" mixer; fi
    } | pick "󰕾" "Ausgabe oder Eingabe wählen" --width 40) || back $?
    case $choice in
        sink:*) pactl set-default-sink "${choice#sink:}" ;;
        source:*) pactl set-default-source "${choice#source:}" ;;
        mixer) exec pavucontrol ;;
    esac
}

# --- Energie -------------------------------------------------------------------
page_power() {
    local current choice profile label
    current=$(powerprofilesctl get)
    choice=$(powerprofilesctl list | sed -n 's/^[* ] *\([a-z-]*\):$/\1/p' | while read -r profile; do
        case $profile in
            performance) label="󱐋   Leistung" ;;
            balanced) label="󰾅   Ausgewogen" ;;
            power-saver) label="󰾆   Energiesparen" ;;
            *) label="     $profile" ;;
        esac
        [[ $profile == "$current" ]] && label+="  ✓"
        row "$label" "$profile"
    done | pick "󰂄" "Energieprofil" --width 26) || back $?
    powerprofilesctl set "$choice"
}

# --- Mitteilungen --------------------------------------------------------------
page_notifications() {
    local choice
    choice=$({
        if [[ $(swaync-client -D 2>/dev/null) == true ]]; then row "󰂚   Nicht stören ausschalten" dnd
        else row "󰂛   Nicht stören einschalten" dnd; fi
        row "󰎟   Mitteilungszentrale öffnen" open
        row "󰆴   Alle Mitteilungen löschen" clear
    } | pick "󰂚" "Mitteilungen" --width 28) || back $?
    case $choice in
        dnd) swaync-client -d -sw >/dev/null ;;
        open) swaync-client -t -sw >/dev/null ;;
        clear) swaync-client -C -sw >/dev/null ;;
    esac
}

# --- System & Treiber ----------------------------------------------------------
# PCI-Geräte einer Klasse mit dem Treiber, der sie gerade bedient.
pci_rows() {
    local icon=$1 pattern=$2
    have lspci || return 0
    lspci -k | awk -v icon="$icon" -v pat="$pattern" '
        /^[0-9a-f]/ { if (dev != "") print icon "   " dev "  ·  " (drv != "" ? drv : "kein Treiber"); dev = ""; drv = "" }
        /^[0-9a-f]/ && $0 ~ pat { sub(/^[^ ]+ [^:]+: /, ""); dev = $0 }
        /Kernel driver in use:/ && dev != "" { drv = $NF }
        END { if (dev != "") print icon "   " dev "  ·  " (drv != "" ? drv : "kein Treiber") }'
}

page_system() {
    local choice
    choice=$({
        echo "󰣇   $(. /etc/os-release && echo "$PRETTY_NAME")  ·  Kernel $(uname -r)"
        echo "󰻠   $(awk -F': ' '/model name/ { print $2; exit }' /proc/cpuinfo)  ·  $(nproc) Threads"
        echo "󰍛   $(free -h | awk '/^Mem:/ { print $3 " von " $2 " belegt" }')"
        echo "󰋊   $(df -h / | awk 'NR == 2 { print $3 " von " $2 " belegt (/)" }')"
        pci_rows "󰢮" "VGA|3D|Display"
        pci_rows "󰈀" "Ethernet"
        pci_rows "󰤨" "Network controller|Wireless"
        pci_rows "󰓃" "Audio"
        if have nmcli; then nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2 != "loopback" { print "󰛳   " $1 " (" $2 ")  ·  " $3 }'; fi
        if have bluetoothctl; then bluetoothctl list 2>/dev/null | awk '{ $1 = ""; print "󰂯  " $0 }'; fi
        echo "󰅍   Bericht in die Zwischenablage kopieren"
    } | aco-menu --prompt "󰻠" --placeholder "System & Treiber" --width 56 --lines 14) || back $?
    if [[ $choice == *"Zwischenablage"* ]]; then
        { uname -a; echo; lspci -k 2>/dev/null; echo; nmcli device 2>/dev/null; } | wl-copy && notify "System" "Bericht kopiert"
    else
        printf '%s' "${choice#*   }" | wl-copy
    fi
}

# --- Tastenkürzel und Updates ----------------------------------------------------
page_keys() { exec aco keys --menu; }
page_update() { exec "$terminal" -e aco update; }

page=${1:-main}
declare -F "page_$page" >/dev/null || { echo "settings.sh: unbekannte Seite '$page'" >&2; exit 2; }
"page_$page"
