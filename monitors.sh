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
defaults_file="$config_home/aco/monitor-defaults.json"   # placement policy for unknown setups
known_file="$state_home/aco/monitors-known.json"         # mode/scale/rotation per physical display
wallpaper="$config_home/wallpaper/wallpaper.sh"

usage() {
    cat <<'HELP'
monitors.sh [befehl]

  menu                       Fuzzel-Menü (Standard ohne Argument)
  status | list              Angeschlossene Bildschirme und Modi anzeigen
  extend [right|left|above|below]
                             Alle Bildschirme nebeneinander anordnen (intern zuerst)
  mirror [quelle]            Alle anderen Bildschirme spiegeln die Quelle (Standard: intern)
  map                        Layout als Text-Skizze zeichnen
  arrange <anschluss> <left-of|right-of|above|below> <referenz> [start|center|end]
                             Bildschirm relativ zu einem anderen platzieren
                             (Ausrichtung an Anfang, Mitte oder Ende der Kante)
  only <anschluss>|internal|external
                             Nur diesen Bildschirm aktiv lassen
  on <anschluss>             Bildschirm wieder einschalten (danach extend)
  scale <anschluss> <faktor> Skalierung, z. B. 1, 1.25, 1.5, 2 (ordnet danach nebeneinander an)
  mode <anschluss> <WxH@Hz>  Auflösung/Bildwiederholrate, z. B. 1920x1080@60
  rotate <anschluss> <0-3>   0 normal, 1 90°, 2 180°, 3 270°
  profile save|load|list|delete <name>
                             Benannte Layouts sichern und wiederherstellen
  default [placement|align|internal-off <wert>] | default apply
                             Standard für unbekannte Setups: wohin neue Monitore kommen
                             (right|left|above|below|mirror), Ausrichtung (start|center|end),
                             internen Bildschirm ausschalten sobald ein externer da ist (on|off)
  auto                       Profil laden, dessen Anschlüsse genau den angeschlossenen entsprechen
                             (läuft automatisch beim Ein-/Ausstecken; ohne Treffer bleibt die Automatik)
  reset                      Lokale Regeln entfernen (Standard: automatisch rechts daneben)
HELP
}

need() { command -v "$1" >/dev/null || { echo "monitors.sh: '$1' fehlt" >&2; exit 1; }; }
need hyprctl; need jq

# Built-in Hyprland notification: no notification daemon required.
notify() { hyprctl notify -1 2500 "rgb(89b4fa)" "$*" >/dev/null 2>&1 || true; }

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
    # Jede Änderung wird für genau dieses Setup gemerkt (auto-<set>.json) und die Display-Eigenschaften
    # (Skalierung/Modus/Drehung) pro physischem Monitor; benannte Profile haben Vorrang.
    mkdir -p "$profile_dir"
    cp "$state_file" "$profile_dir/auto-$(set_key).json"
    remember_known
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



# --- Standards und Gedächtnis ------------------------------------------------------
set_key() { names | LC_ALL=C sort | paste -sd, | md5sum | cut -c1-12; }
desc_of() { live | jq -r --arg n "$1" '.[] | select(.name == $n) | .description'; }

default_get() { # schluessel standardwert
    local v=""
    [[ -f $defaults_file ]] && v="$(jq -r --arg k "$1" '.[$k] // empty' "$defaults_file")"
    printf '%s' "${v:-$2}"
}

default_set() {
    mkdir -p "$(dirname "$defaults_file")"
    [[ -s $defaults_file ]] || echo '{}' >"$defaults_file"
    local tmp; tmp="$(jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$defaults_file")"
    printf '%s\n' "$tmp" >"$defaults_file"
}

# Merkt Auflösung, Skalierung und Drehung jedes angeschlossenen Displays (nach Beschreibung,
# nicht nach Anschluss – derselbe Monitor an einem anderen Port wird wiedererkannt).
remember_known() {
    mkdir -p "$(dirname "$known_file")"
    [[ -s $known_file ]] || echo '{}' >"$known_file"
    local n d tmp
    for n in $(names); do
        d="$(desc_of "$n")"; [[ -n $d ]] || continue
        tmp="$(jq --arg d "$d" --argjson s "$(jq --arg n "$n" '.[$n] | {mode, scale, transform}' "$state_file")" '.[$d] = $s' "$known_file")"
        printf '%s\n' "$tmp" >"$known_file"
    done
}

restore_known() {
    [[ -s $known_file ]] || return 0
    local n d k
    for n in $(names); do
        d="$(desc_of "$n")"; [[ -n $d ]] || continue
        k="$(jq -c --arg d "$d" '.[$d] // empty' "$known_file")"
        [[ -n $k ]] || continue
        set_field "$n" mode "$(jq '.mode' <<<"$k")"
        set_field "$n" scale "$(jq '.scale' <<<"$k")"
        set_field "$n" transform "$(jq '.transform' <<<"$k")"
    done
}

# Anordnung nach dem eingestellten Standard (für Setups ohne gespeichertes Profil).
layout_policy() {
    local placement align internal_off
    placement="$(default_get placement right)"
    align="$(default_get align start)"
    internal_off="$(default_get internal-off off)"
    restore_known
    local ordered=() n
    for n in $(names); do is_internal "$n" && ordered+=("$n"); done
    for n in $(names); do is_internal "$n" || ordered+=("$n"); done
    if [[ $placement == mirror ]]; then layout_mirror; return; fi
    if [[ $internal_off == on && ${#ordered[@]} -gt 1 ]] && ! is_internal "${ordered[-1]}"; then
        layout_only external; return
    fi
    local rel prev="" i
    case $placement in right) rel=right-of ;; left) rel=left-of ;; above) rel=above ;; below) rel=below ;; esac
    for i in "${!ordered[@]}"; do
        n="${ordered[$i]}"
        set_field "$n" disabled false; set_field "$n" mirror null
        if [[ -z $prev ]]; then set_field "$n" x 0; set_field "$n" y 0
        else layout_arrange "$n" "$rel" "$prev" "$align"; fi
        prev="$n"
    done
}

# --- Anordnen ---------------------------------------------------------------------
# arrange MON RELATION REF [ALIGN]: setzt Position von MON relativ zu REF.
layout_arrange() {
    local mon="${1:-}" rel="${2:-}" ref="${3:-}" align="${4:-start}"
    require_output "$mon"; require_output "$ref"
    [[ $mon != "$ref" ]] || { echo "Ein Bildschirm kann nicht relativ zu sich selbst stehen." >&2; exit 2; }
    [[ $align =~ ^(start|center|end)$ ]] || { echo "Ausrichtung: start|center|end" >&2; exit 2; }
    local w h rw rh rx ry x y
    read -r w h < <(logical_size "$mon")
    read -r rw rh < <(logical_size "$ref")
    rx="$(jq -r --arg n "$ref" '.[$n].x' "$state_file")"
    ry="$(jq -r --arg n "$ref" '.[$n].y' "$state_file")"
    set_field "$mon" disabled false; set_field "$mon" mirror null
    local off_y=0 off_x=0
    case $align in
        center) off_y=$(((rh - h) / 2)); off_x=$(((rw - w) / 2)) ;;
        end)    off_y=$((rh - h));       off_x=$((rw - w)) ;;
    esac
    case $rel in
        right-of) x=$((rx + rw)); y=$((ry + off_y)) ;;
        left-of)  x=$((rx - w));  y=$((ry + off_y)) ;;
        below)    x=$((rx + off_x)); y=$((ry + rh)) ;;
        above)    x=$((rx + off_x)); y=$((ry - h)) ;;
        *) echo "Relation: left-of|right-of|above|below" >&2; exit 2 ;;
    esac
    set_field "$mon" x "$x"; set_field "$mon" y "$y"
}

# Text-Skizze des aktuellen Layouts (aus dem gespeicherten Zustand, sonst live).
show_map() {
    local rows=""
    if [[ -s $state_file ]]; then
        local n w h
        for n in $(names); do
            [[ $(jq -r --arg n "$n" '.[$n].disabled // false' "$state_file") == true ]] && continue
            [[ $(jq -r --arg n "$n" '.[$n] // empty | .mirror // empty' "$state_file") == "" ]] || continue
            read -r w h < <(logical_size "$n")
            rows+="$n $(jq -r --arg n "$n" '"\(.[$n].x) \(.[$n].y)"' "$state_file") $w $h"$'\n'
        done
    else
        rows="$(live | jq -r '.[] | select(.disabled | not) | select((.mirrorOf // "none") == "none") |
            "\(.name) \(.x) \(.y) \((.width / .scale) | floor) \((.height / .scale) | floor)"')"$'\n'
    fi
    printf '%s' "$rows" | awk -v cols=64 '
        { name[NR]=$1; x[NR]=$2; y[NR]=$3; w[NR]=$4; h[NR]=$5; n=NR
          if (NR==1 || $2<minx) minx=$2; if (NR==1 || $3<miny) miny=$3
          if (NR==1 || $2+$4>maxx) maxx=$2+$4; if (NR==1 || $3+$5>maxy) maxy=$3+$5 }
        END {
            if (!n) { print "Keine aktiven Bildschirme."; exit }
            sx = (maxx-minx) / cols; if (sx < 1) sx = 1
            sy = sx * 2.2                      # Zeichen sind etwa doppelt so hoch wie breit
            W = int((maxx-minx)/sx) + 1; H = int((maxy-miny)/sy) + 1
            for (r=0; r<H; r++) for (c=0; c<W; c++) g[r,c]=" "
            for (i=1; i<=n; i++) {
                c0=int((x[i]-minx)/sx); r0=int((y[i]-miny)/sy)
                c1=int((x[i]+w[i]-minx)/sx)-1; r1=int((y[i]+h[i]-miny)/sy)-1
                if (c1-c0 < 3) c1=c0+3; if (r1-r0 < 2) r1=r0+2
                for (c=c0; c<=c1; c++) { g[r0,c]="-"; g[r1,c]="-" }
                for (r=r0; r<=r1; r++) { g[r,c0]="|"; g[r,c1]="|" }
                g[r0,c0]="+"; g[r0,c1]="+"; g[r1,c0]="+"; g[r1,c1]="+"
                label=name[i]; lr=int((r0+r1)/2); lc=c0+int((c1-c0-length(label))/2)+1
                for (k=1; k<=length(label) && lc+k-1<c1; k++) g[lr,lc+k-1]=substr(label,k,1)
                dims=w[i] "x" h[i]; dr=lr+1
                if (dr < r1) for (k=1; k<=length(dims) && lc+k-1<c1; k++) g[dr,lc+k-1]=substr(dims,k,1)
            }
            for (r=0; r<H+0; r++) { line=""; for (c=0; c<W+0; c++) line=line g[r,c]; sub(/ +$/, "", line); print line }
        }'
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
  Spiegeln\n  Nur interner Bildschirm\n  Nur externer Bildschirm\n  Anordnen (relativ platzieren)\n  Skalierung\n  Auflösung\n  Drehen
  Standard für neue Monitore\n  Profil laden\n  Profil speichern\n  Zurücksetzen (automatisch)\n  Status'
    local pick; pick="$(printf '%s\n' "$entries" | "${ask[@]}")" || exit 0
    case $pick in
        *"(rechts)"*) "$0" extend right ;;
        *"links"*) "$0" extend left ;;
        *"darüber"*) "$0" extend above ;;
        *"darunter"*) "$0" extend below ;;
        *Spiegeln*) "$0" mirror ;;
        *"interner"*) "$0" only internal ;;
        *"externer"*) "$0" only external ;;
        *Anordnen*) local mon rel ref al
            mon="$(choose_output)" || exit 0
            rel="$(printf 'right-of\nleft-of\nabove\nbelow\n' | "${ask[@]}" --prompt="$mon liegt … ")" || exit 0
            ref="$(names | grep -vx -- "$mon" | "${ask[@]}" --prompt="… von ")" || exit 0
            al="$(printf 'start\ncenter\nend\n' | "${ask[@]}" --prompt='Ausrichtung ')" || exit 0
            "$0" arrange "$mon" "$rel" "$ref" "$al" ;;
        *Skalierung*) local o s; o="$(choose_output)" || exit 0
            s="$(printf '1\n1.25\n1.5\n1.75\n2\n' | "${ask[@]}" --prompt="Skalierung $o ")" || exit 0
            "$0" scale "$o" "$s" ;;
        *Auflösung*) local o m; o="$(choose_output)" || exit 0
            m="$(live | jq -r --arg n "$o" '.[]|select(.name==$n)|.availableModes[]' | "${ask[@]}" --prompt="Modus $o ")" || exit 0
            "$0" mode "$o" "${m%Hz}" ;;
        *Drehen*) local o t; o="$(choose_output)" || exit 0
            t="$(printf '0 normal\n1 90°\n2 180°\n3 270°\n' | "${ask[@]}" --prompt="Drehung $o ")" || exit 0
            "$0" rotate "$o" "${t%% *}" ;;
        *Standard*) local k v
            k="$(printf 'Neue Monitore: rechts\nNeue Monitore: links\nNeue Monitore: darüber\nNeue Monitore: darunter\nNeue Monitore: spiegeln\nIntern aus, wenn extern da\nIntern immer an\nStandard jetzt anwenden\n' | "${ask[@]}" --prompt='Standard ')" || exit 0
            case $k in
                *rechts*) "$0" default placement right ;; *links*) "$0" default placement left ;;
                *darüber*) "$0" default placement above ;; *darunter*) "$0" default placement below ;;
                *spiegeln*) "$0" default placement mirror ;;
                *"aus, wenn"*) "$0" default internal-off on ;; *"immer an"*) "$0" default internal-off off ;;
                *anwenden*) "$0" default apply ;;
            esac ;;
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
    map) ensure_state; show_map ;;
    arrange) ensure_state; layout_arrange "${1:-}" "${2:-}" "${3:-}" "${4:-start}"; apply ;;
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
            list|ls) ls -1 "$profile_dir" 2>/dev/null | grep -v '^auto-' | sed 's/\.json$//' ;;
            save) [[ $name =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Profilname: Buchstaben, Ziffern, _ . -" >&2; exit 2; }
                ensure_state; cp "$state_file" "$profile_dir/$name.json"; notify "Profil gespeichert" "$name" ;;
            load) [[ -f $profile_dir/${name:-/}.json ]] || { echo "Profil '$name' nicht gefunden." >&2; exit 2; }
                ensure_state; cp "$profile_dir/$name.json" "$state_file"; apply ;;
            delete|rm) rm -f -- "$profile_dir/${name:?Profilname angeben}.json" ;;
            *) usage; exit 2 ;;
        esac ;;
    auto)
        current="$(names | LC_ALL=C sort | paste -sd,)"
        ensure_state
        # 1. benanntes Profil, 2. automatisch gemerktes Layout, 3. Standard (default placement …)
        for f in "$profile_dir"/*.json; do
            [[ -f $f && $(basename "$f") != auto-* ]] || continue
            [[ "$(jq -r 'keys | sort | join(",")' "$f")" == "$current" ]] || continue
            cp "$f" "$state_file"; apply; exit 0
        done
        remembered="$profile_dir/auto-$(set_key).json"
        if [[ -f $remembered ]]; then cp "$remembered" "$state_file"; apply; exit 0; fi
        layout_policy; apply ;;
    default)
        sub="${1:-show}"
        case $sub in
            show|"") printf 'placement:    %s\nalign:        %s\ninternal-off: %s\n' \
                "$(default_get placement right)" "$(default_get align start)" "$(default_get internal-off off)" ;;
            placement) [[ ${2:-} =~ ^(right|left|above|below|mirror)$ ]] || { echo "placement: right|left|above|below|mirror" >&2; exit 2; }
                default_set placement "$2" ;;
            align) [[ ${2:-} =~ ^(start|center|end)$ ]] || { echo "align: start|center|end" >&2; exit 2; }
                default_set align "$2" ;;
            internal-off) [[ ${2:-} =~ ^(on|off)$ ]] || { echo "internal-off: on|off" >&2; exit 2; }
                default_set internal-off "$2" ;;
            apply) ensure_state; layout_policy; apply ;;
            *) usage; exit 2 ;;
        esac ;;
    reset) rm -f -- "$lua_file" "$state_file"; [[ -n ${MONITORS_DRY_RUN:-} ]] || hyprctl reload >/dev/null; notify "Bildschirm-Regeln zurückgesetzt" ;;
    help|-h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
