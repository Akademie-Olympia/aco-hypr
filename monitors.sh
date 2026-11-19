#!/usr/bin/env bash
# ============================================================================
# BILDSCHIRM-VERWALTUNG (Layout, Spiegeln, Skalierung, Auflösung, Profile)
# Tastenkombination: SUPER + SHIFT + D (Menü); im Terminal: monitors.sh <befehl>
#
# Das Skript schreibt ~/.config/hypr/monitors.local.lua (von hyprland.lua nach den
# Standardregeln geladen, Git-ignoriert) und lädt Hyprland neu. Der Zustand pro
# Anschluss liegt in ~/.local/state/aco/monitors.json; Profile unter
# ~/.config/aco/monitor-profiles/. "reset" entfernt alle lokalen Regeln.
# MONITORS_DRY_RUN=1 schreibt nur die Lua-Datei und gibt sie aus (kein Reload, für Tests).
# ============================================================================
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
lua_file="$config_home/hypr/monitors.local.lua"
state_file="$state_home/aco/monitors.json"
profile_dir="$config_home/aco/monitor-profiles"
wallpaper="$config_home/wallpaper/wallpaper.sh"

usage() {
    cat <<'HELP'
monitors.sh [befehl]

  menu                       Fuzzel-Menü (Standard ohne Argument)
  status | list              Angeschlossene Bildschirme und Modi anzeigen
  extend [right|left|above|below]
                             Alle Bildschirme nebeneinander anordnen (intern zuerst)
  mirror [quelle]            Alle anderen Bildschirme spiegeln die Quelle (Standard: intern)
  only <anschluss>|internal|external
                             Nur diesen Bildschirm aktiv lassen
  on <anschluss>             Bildschirm wieder einschalten (danach extend)
  scale <anschluss> <faktor> Skalierung, z. B. 1, 1.25, 1.5, 2 (ordnet danach nebeneinander an)
  mode <anschluss> <WxH@Hz>  Auflösung/Bildwiederholrate, z. B. 1920x1080@60
  rotate <anschluss> <0-3>   0 normal, 1 90°, 2 180°, 3 270°
  profile save|load|list|delete <name>
                             Benannte Layouts sichern und wiederherstellen
  auto                       Profil laden, dessen Anschlüsse genau den angeschlossenen entsprechen
                             (läuft automatisch beim Ein-/Ausstecken; ohne Treffer bleibt die Automatik)
  reset                      Lokale Regeln entfernen (Standard: automatisch rechts daneben)
HELP
}

need() { command -v "$1" >/dev/null || { echo "monitors.sh: '$1' fehlt" >&2; exit 1; }; }
need hyprctl; need jq

notify() { command -v notify-send >/dev/null && notify-send -a Bildschirme "$@" || true; }

live() { hyprctl monitors all -j; }

is_internal() { [[ $1 == eDP* || $1 == LVDS* || $1 == DSI* ]]; }

# --- Zustand -----------------------------------------------------------------
# Pro Anschluss: mode, scale, transform, disabled, mirror, x, y
ensure_state() {
    mkdir -p "$(dirname "$state_file")"
    if [[ ! -s $state_file ]]; then
        live | jq '
            reduce .[] as $m ({}; .[$m.name] = {
                mode: "\($m.width)x\($m.height)@\(($m.refreshRate * 100 | round) / 100)",
                scale: $m.scale, transform: $m.transform, disabled: ($m.disabled // false),
                mirror: null, x: $m.x, y: $m.y })' >"$state_file"
    fi
    # Neu angeschlossene Bildschirme ergänzen
    local merged
    merged="$(jq --argjson live "$(live)" '
        . as $s | reduce $live[] as $m ($s;
            if has($m.name) then . else .[$m.name] = {
                mode: "\($m.width)x\($m.height)@\(($m.refreshRate * 100 | round) / 100)",
                scale: $m.scale, transform: $m.transform, disabled: false,
                mirror: null, x: $m.x, y: $m.y } end)' "$state_file")"
    printf '%s\n' "$merged" >"$state_file"
}

names() { live | jq -r '.[].name'; }

set_field() { # anschluss feld json-wert
    local tmp
    tmp="$(jq --arg n "$1" --arg f "$2" --argjson v "$3" '.[$n][$f] = $v' "$state_file")"
    printf '%s\n' "$tmp" >"$state_file"
}

require_output() {
    names | grep -qx -- "${1:-}" || { echo "Unbekannter Anschluss: ${1:-}. Verfügbar: $(names | paste -sd' ')" >&2; exit 2; }
}

# --- Lua erzeugen und anwenden ---------------------------------------------------
write_lua() {
    mkdir -p "$(dirname "$lua_file")"
    {
        echo "-- Von monitors.sh erzeugt (nicht von Hand bearbeiten; 'monitors.sh reset' entfernt die Datei)."
        jq -r --argjson live "$(live | jq '[.[].name]')" '
            to_entries[] | select(.key as $k | $live | index($k)) | .key as $n | .value as $v |
            "hl.monitor({ output = \"\($n)\", " +
            (if $v.disabled then "disabled = true })"
             else "mode = \"\($v.mode)\", position = \"\($v.x)x\($v.y)\", scale = \($v.scale), transform = \($v.transform)" +
                  (if $v.mirror then ", mirror = \"\($v.mirror)\"" else "" end) + " })" end)' "$state_file"
    } >"$lua_file"
}

apply() {
    write_lua
    if [[ -n ${MONITORS_DRY_RUN:-} ]]; then cat "$lua_file"; return; fi
    hyprctl reload >/dev/null
    if [[ -x $wallpaper ]]; then ( sleep 0.8; "$wallpaper" apply --quiet ) >/dev/null 2>&1 & disown || true; fi
    notify "Bildschirm-Layout angewendet" "$(names | paste -sd' ')"
}

# --- Layout -----------------------------------------------------------------------
logical_size() { # anschluss -> "breite hoehe" (gedreht und skaliert)
    live | jq -r --arg n "$1" --argjson s "$(cat "$state_file")" '
        .[] | select(.name == $n) | ($s[$n]) as $c |
        ($c.mode | capture("(?<w>[0-9]+)x(?<h>[0-9]+)")) as $r |
        (if ($c.transform % 2) == 1 then [$r.h, $r.w] else [$r.w, $r.h] end) as $d |
        "\(($d[0] | tonumber) / $c.scale | floor) \(($d[1] | tonumber) / $c.scale | floor)"'
}

layout_extend() {
    local dir="${1:-right}" ordered=() n
    for n in $(names); do is_internal "$n" && ordered+=("$n"); done
    for n in $(names); do is_internal "$n" || ordered+=("$n"); done
    local offset=0 w h
    for n in "${ordered[@]}"; do
        if [[ $(jq -r --arg n "$n" '.[$n].disabled' "$state_file") == true ]]; then
            set_field "$n" disabled false
        fi
        set_field "$n" mirror null
        read -r w h < <(logical_size "$n")
        case $dir in
            right) set_field "$n" x "$offset"; set_field "$n" y 0; offset=$((offset + w)) ;;
            left)  ;;
            below) set_field "$n" x 0; set_field "$n" y "$offset"; offset=$((offset + h)) ;;
            above) ;;
            *) echo "Richtung: right|left|above|below" >&2; exit 2 ;;
        esac
    done
    # left/above: externe Bildschirme vor dem internen platzieren
    if [[ $dir == left || $dir == above ]]; then
        local total=0 size
        for n in $(printf '%s\n' "${ordered[@]}" | tac); do
            read -r w h < <(logical_size "$n")
            if [[ $dir == left ]]; then set_field "$n" x "$total"; set_field "$n" y 0; size=$w
            else set_field "$n" x 0; set_field "$n" y "$total"; size=$h; fi
            total=$((total + size))
        done
    fi
}

layout_mirror() {
    local source="${1:-}" n
    if [[ -z $source ]]; then
        for n in $(names); do is_internal "$n" && source=$n && break; done
        [[ -n $source ]] || source="$(names | head -1)"
    fi
    require_output "$source"
    set_field "$source" disabled false; set_field "$source" mirror null
    set_field "$source" x 0; set_field "$source" y 0
    for n in $(names); do
        [[ $n == "$source" ]] && continue
        set_field "$n" disabled false; set_field "$n" mirror "\"$source\""
    done
}

layout_only() {
    local want="${1:-}" n keep=""
    case $want in
        internal) for n in $(names); do is_internal "$n" && keep=$n && break; done ;;
        external) for n in $(names); do is_internal "$n" || { keep=$n; break; }; done ;;
        *) require_output "$want"; keep=$want ;;
    esac
    [[ -n $keep ]] || { echo "Kein passender Bildschirm für '$want'." >&2; exit 2; }
    for n in $(names); do
        set_field "$n" mirror null
        if [[ $n == "$keep" ]]; then set_field "$n" disabled false; set_field "$n" x 0; set_field "$n" y 0
        else set_field "$n" disabled true; fi
    done
}

# --- Anzeige ------------------------------------------------------------------------
show_status() {
    live | jq -r '.[] |
        "\(.name)\t\(if .disabled then "aus" else "\(.width)x\(.height)@\(.refreshRate * 100 | round / 100)" end)\t\(.x),\(.y)\tx\(.scale)\t\(.description)" +
        (if .mirrorOf and .mirrorOf != "none" then "  [spiegelt \(.mirrorOf)]" else "" end)' | column -t -s $'\t'
}

menu() {
    need fuzzel
    local ask=(fuzzel --dmenu --width=40 --lines=12 --prompt='Bildschirme ')
    choose_output() {
        local list; list="$(names)"
        [[ $(wc -l <<<"$list") -eq 1 ]] && { echo "$list"; return; }
        printf '%s\n' "$list" | "${ask[@]}" --prompt='Anschluss '
    }
    local entries=$'  Erweitern: nebeneinander (rechts)\n  Erweitern: links\n  Erweitern: darüber\n  Erweitern: darunter
  Spiegeln\n  Nur interner Bildschirm\n  Nur externer Bildschirm\n  Skalierung\n  Auflösung\n  Drehen
  Profil laden\n  Profil speichern\n  Zurücksetzen (automatisch)\n  Status'
    local pick; pick="$(printf '%s\n' "$entries" | "${ask[@]}")" || exit 0
    case $pick in
        *"(rechts)"*) "$0" extend right ;;
        *"links"*) "$0" extend left ;;
        *"darüber"*) "$0" extend above ;;
        *"darunter"*) "$0" extend below ;;
        *Spiegeln*) "$0" mirror ;;
        *"interner"*) "$0" only internal ;;
        *"externer"*) "$0" only external ;;
        *Skalierung*) local o s; o="$(choose_output)" || exit 0
            s="$(printf '1\n1.25\n1.5\n1.75\n2\n' | "${ask[@]}" --prompt="Skalierung $o ")" || exit 0
            "$0" scale "$o" "$s" ;;
        *Auflösung*) local o m; o="$(choose_output)" || exit 0
            m="$(live | jq -r --arg n "$o" '.[]|select(.name==$n)|.availableModes[]' | "${ask[@]}" --prompt="Modus $o ")" || exit 0
            "$0" mode "$o" "${m%Hz}" ;;
        *Drehen*) local o t; o="$(choose_output)" || exit 0
            t="$(printf '0 normal\n1 90°\n2 180°\n3 270°\n' | "${ask[@]}" --prompt="Drehung $o ")" || exit 0
            "$0" rotate "$o" "${t%% *}" ;;
        *"Profil laden"*) local p; p="$("$0" profile list | "${ask[@]}" --prompt='Profil ')" || exit 0
            "$0" profile load "$p" ;;
        *"Profil speichern"*) local p; p="$(printf '' | "${ask[@]}" --lines=0 --prompt='Profilname ')" || exit 0
            [[ -n $p ]] && "$0" profile save "$p" ;;
        *Zurücksetzen*) "$0" reset ;;
        *Status*) notify "Bildschirme" "$(show_status)" ;;
    esac
}

# --- Befehle --------------------------------------------------------------------------
cmd="${1:-menu}"; shift || true
case $cmd in
    menu) ensure_state; menu ;;
    status|list|ls) show_status ;;
    extend) ensure_state; layout_extend "${1:-right}"; apply ;;
    mirror) ensure_state; layout_mirror "${1:-}"; apply ;;
    only) ensure_state; layout_only "${1:?Anschluss|internal|external angeben}"; apply ;;
    on) ensure_state; require_output "${1:-}"; set_field "$1" disabled false; layout_extend right; apply ;;
    scale) ensure_state; require_output "${1:-}"
        [[ ${2:-} =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "Skalierung als Zahl, z. B. 1.25" >&2; exit 2; }
        set_field "$1" scale "$2"; layout_extend right; apply ;;
    mode) ensure_state; require_output "${1:-}"
        [[ ${2:-} =~ ^[0-9]+x[0-9]+(@[0-9.]+)?$ ]] || { echo "Modus als WxH@Hz, z. B. 1920x1080@60" >&2; exit 2; }
        set_field "$1" mode "\"$2\""; layout_extend right; apply ;;
    rotate) ensure_state; require_output "${1:-}"
        [[ ${2:-} =~ ^[0-3]$ ]] || { echo "Drehung 0-3" >&2; exit 2; }
        set_field "$1" transform "$2"; layout_extend right; apply ;;
    profile)
        mkdir -p "$profile_dir"
        sub="${1:-list}"; name="${2:-}"
        case $sub in
            list|ls) ls -1 "$profile_dir" 2>/dev/null | sed 's/\.json$//' ;;
            save) [[ $name =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Profilname: Buchstaben, Ziffern, _ . -" >&2; exit 2; }
                ensure_state; cp "$state_file" "$profile_dir/$name.json"; notify "Profil gespeichert" "$name" ;;
            load) [[ -f $profile_dir/${name:-/}.json ]] || { echo "Profil '$name' nicht gefunden." >&2; exit 2; }
                ensure_state; cp "$profile_dir/$name.json" "$state_file"; apply ;;
            delete|rm) rm -f -- "$profile_dir/${name:?Profilname angeben}.json" ;;
            *) usage; exit 2 ;;
        esac ;;
    auto)
        current="$(names | LC_ALL=C sort | paste -sd,)"
        for f in "$profile_dir"/*.json; do
            [[ -f $f ]] || continue
            [[ "$(jq -r 'keys | sort | join(",")' "$f")" == "$current" ]] || continue
            ensure_state; cp "$f" "$state_file"; apply; exit 0
        done
        # Kein passendes Profil: lokale Regeln eines anderen Setups entfernen
        if [[ -f $lua_file ]]; then rm -f -- "$lua_file" "$state_file"; [[ -n ${MONITORS_DRY_RUN:-} ]] || hyprctl reload >/dev/null; fi ;;
    reset) rm -f -- "$lua_file" "$state_file"; [[ -n ${MONITORS_DRY_RUN:-} ]] || hyprctl reload >/dev/null; notify "Bildschirm-Regeln zurückgesetzt" ;;
    help|-h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
