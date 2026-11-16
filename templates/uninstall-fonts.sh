#!/bin/sh
set -eu

CONF_FILE="/etc/fonts/conf.d/99-nvim-offline-build-fonts.conf"

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: Run with sudo to unregister the bundled font." >&2
    exit 1
fi

if [ -f "$CONF_FILE" ]; then
    rm -f "$CONF_FILE"
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f
    fi
    printf '%s\n' "Removed Maple Mono NF CN Fontconfig registration."
else
    printf '%s\n' "Maple Mono NF CN Fontconfig registration was not present."
fi

printf '%s\n' "Font files remain in the Neovim bundle."
