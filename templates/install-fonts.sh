#!/bin/sh
set -eu

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH="$0"
ROOT="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
FONT_DIR="$ROOT/fonts/maple-mono"
CONF_DIR="/etc/fonts/conf.d"
CONF_FILE="$CONF_DIR/99-nvim-offline-build-fonts.conf"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[ -d "$FONT_DIR" ] || fail "Bundled Maple Mono NF CN fonts not found: $FONT_DIR"
find "$FONT_DIR" -type f -name '*.ttf' -print -quit | grep -q . || fail "No TTF files found in $FONT_DIR"
[ "$(id -u)" -eq 0 ] || fail "Run with sudo to register the bundled font system-wide."
command -v fc-cache >/dev/null 2>&1 || fail "fontconfig is required (fc-cache was not found)."

[ -d "$CONF_DIR" ] || fail "Fontconfig directory not found: $CONF_DIR"

cat > "$CONF_FILE" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$FONT_DIR</dir>
</fontconfig>
EOF

fc-cache -f "$FONT_DIR"

printf '%s\n' "Maple Mono NF CN is now registered with Fontconfig."
printf '%s\n' "Font directory: $FONT_DIR"
printf '%s\n' "Select 'Maple Mono NF CN' in your terminal profile."
printf '%s\n' "Restart the terminal application after changing its font."
