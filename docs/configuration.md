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
