#!/usr/bin/env bash
# SUDO_ASKPASS helper: asks for the password in the desktop menu, prints it.
exec aco-menu --password --lines 0 --prompt "󰌾" --placeholder "Passwort für sudo" --width 30 </dev/null
