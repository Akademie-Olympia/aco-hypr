# Konfiguration

Einstieg ist `~/.config/hypr/hyprland.lua`. Rechnerabhängige Monitorregeln gehören in
die **nicht verteilte** Datei `~/.config/hypr/monitors.local.lua`; sie überlebt Updates.
Die Vorlage:

```{literalinclude} ../monitors.example.lua
:language: lua
:linenos:
```

Anschlüsse zeigt `hyprctl monitors all`. Nach Änderungen `hyprctl reload`, danach
`hyprctl configerrors`.

## Screenshots mit Satty

Die Vorgaben für den Editor stehen in `~/.config/hypr/satty.toml`:

```{literalinclude} ../satty.toml
:language: toml
```

## Bildschirm-Verwaltung

`monitors.sh` verwaltet Layout, Spiegelung, Skalierung, Auflösung, Drehung und benannte Profile.
{kbd}`Super + Shift + D` öffnet das Fuzzel-Menü; im Terminal:

```bash
~/.config/hypr/monitors.sh status
~/.config/hypr/monitors.sh extend right      # oder left, above, below
~/.config/hypr/monitors.sh mirror            # alle spiegeln den internen Bildschirm
~/.config/hypr/monitors.sh only external     # oder internal, <Anschluss>
~/.config/hypr/monitors.sh scale HDMI-A-1 1.5
~/.config/hypr/monitors.sh mode HDMI-A-1 1920x1080@60
~/.config/hypr/monitors.sh rotate HDMI-A-1 1
~/.config/hypr/monitors.sh profile save buero   # später: profile load buero
~/.config/hypr/monitors.sh reset                # zurück zur Automatik
```

Das Skript schreibt `~/.config/hypr/monitors.local.lua` (Git-ignoriert, von `hyprland.lua` nach den
Standardregeln geladen) und lädt Hyprland neu. Den Zustand pro Anschluss hält es in
`~/.local/state/aco/monitors.json`, Profile liegen in `~/.config/aco/monitor-profiles/`.
Mit `MONITORS_DRY_RUN=1` wird nur die Lua-Datei ausgegeben, ohne Neuladen.
