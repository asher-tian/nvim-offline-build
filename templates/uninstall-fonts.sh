#!/bin/sh
set -eu

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH="$0"
ROOT="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"

FONT_DIR="$ROOT/fonts/maple-mono"
CACHE_DIR="$ROOT/cache/fontconfig"
STATE_DIR="$ROOT/state/fontconfig"
BUNDLE_CONFIG="$ROOT/config/fontconfig/conf.d/99-nvim-offline-build.conf"
SYSTEM_CONF="/etc/fonts/conf.d/99-nvim-offline-build-fonts.conf"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  bash uninstall-fonts.sh [--user|--system]

Default mode is --user and does not require root.
--system removes the system-wide Fontconfig registration and requires root.
EOF
}

MODE="user"
case "$#" in
    0) ;;
    1)
        case "$1" in
            --user) MODE="user" ;;
            --system) MODE="system" ;;
            --help|-h) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

remove_managed_symlink() {
    link_path="$1"
    expected_target="$2"

    if [ -L "$link_path" ]; then
        current_target="$(readlink -f "$link_path" 2>/dev/null || true)"
        if [ "$current_target" = "$expected_target" ]; then
            rm -f "$link_path"
            printf 'Removed symlink: %s\n' "$link_path"
        else
            printf 'Kept unrelated symlink: %s -> %s\n' "$link_path" "$(readlink "$link_path")"
        fi
    fi
}

if [ "$MODE" = "system" ]; then
    [ "$(id -u)" -eq 0 ] || fail "System font unregistration requires root. Run: sudo bash uninstall-fonts.sh --system"
    if [ -f "$SYSTEM_CONF" ]; then
        grep -q 'Managed by nvim-offline-build' "$SYSTEM_CONF" || fail "Refusing to remove an unmanaged file: $SYSTEM_CONF"
        rm -f "$SYSTEM_CONF"
        command -v fc-cache >/dev/null 2>&1 && fc-cache -f
        printf '%s\n' "Removed system Fontconfig registration. Font files remain in the Neovim directory."
    else
        printf '%s\n' "System Fontconfig registration was not present."
    fi
    exit 0
fi

if [ -f "$STATE_DIR/user-config-link" ]; then
    remove_managed_symlink "$(cat "$STATE_DIR/user-config-link")" "$BUNDLE_CONFIG"
fi
if [ -f "$STATE_DIR/user-font-link" ]; then
    remove_managed_symlink "$(cat "$STATE_DIR/user-font-link")" "$FONT_DIR"
fi
if [ -f "$STATE_DIR/user-cache-link" ]; then
    remove_managed_symlink "$(cat "$STATE_DIR/user-cache-link")" "$CACHE_DIR"
fi

if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f
fi

if [ -d "$STATE_DIR" ]; then
    rm -f "$STATE_DIR/user-config-link" "$STATE_DIR/user-font-link" "$STATE_DIR/user-cache-link"
    rmdir "$STATE_DIR" 2>/dev/null || true
fi

printf '%s\n' "User Fontconfig registration removed. Font files and Neovim cache remain in the installation directory."
