#!/bin/sh
set -eu

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH="$0"
ROOT="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"

FONT_SOURCE_DIR="$ROOT/fonts/maple-mono"
USER_FONT_DIR="$HOME/.local/share/fonts/nvim-offline-build"
USER_FONT_MARKER="$USER_FONT_DIR/.nvim-offline-build-managed"
USER_FONT_MANIFEST="$USER_FONT_DIR/.nvim-offline-build-files"
USER_FONT_LINK="$HOME/.fonts/nvim-offline-build"
STATE_DIR="$ROOT/state/fontconfig"
CACHE_DIR="$ROOT/cache/fontconfig"
BUNDLE_CONFIG="$ROOT/config/fontconfig/conf.d/99-nvim-offline-build.conf"
SYSTEM_CONF="/etc/fonts/conf.d/99-nvim-offline-build-fonts.conf"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[nvim-fonts] %s\n' "$*"
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
            info "Removed symlink: $link_path"
        else
            info "Kept unrelated symlink: $link_path -> $(readlink "$link_path")"
        fi
    fi
}

remove_legacy_state_link() {
    state_file="$1"
    expected_target="$2"

    if [ -f "$state_file" ]; then
        old_link="$(cat "$state_file")"
        [ -n "$old_link" ] && remove_managed_symlink "$old_link" "$expected_target"
        if [ -w "$STATE_DIR" ]; then
            rm -f "$state_file"
        fi
    fi
}

if [ "$MODE" = "system" ]; then
    [ "$(id -u)" -eq 0 ] || fail "System font unregistration requires root. Run: sudo bash uninstall-fonts.sh --system"
    if [ -f "$SYSTEM_CONF" ]; then
        grep -q 'Managed by nvim-offline-build' "$SYSTEM_CONF" || fail "Refusing to remove an unmanaged file: $SYSTEM_CONF"
        rm -f "$SYSTEM_CONF"
        if command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f
        fi
        printf '%s\n' "Removed system Fontconfig registration. Font files remain in the Neovim directory."
    else
        printf '%s\n' "System Fontconfig registration was not present."
    fi
    exit 0
fi

[ -n "$HOME" ] || fail "HOME is not set."

# Clean up registration links created by older versions, but never remove
# links that have been repointed by the user.
remove_legacy_state_link "$STATE_DIR/user-config-link" "$BUNDLE_CONFIG"
remove_legacy_state_link "$STATE_DIR/user-font-link" "$FONT_SOURCE_DIR"
remove_legacy_state_link "$STATE_DIR/user-cache-link" "$CACHE_DIR"
remove_managed_symlink "$USER_FONT_LINK" "$FONT_SOURCE_DIR"
remove_managed_symlink "$USER_FONT_LINK" "$USER_FONT_DIR"

if [ -f "$BUNDLE_CONFIG" ] && grep -q 'Managed by nvim-offline-build' "$BUNDLE_CONFIG" && [ -w "$(dirname "$BUNDLE_CONFIG")" ]; then
    rm -f "$BUNDLE_CONFIG"
fi

if [ -d "$USER_FONT_DIR" ] && [ ! -L "$USER_FONT_DIR" ]; then
    if [ -f "$USER_FONT_MARKER" ] && [ "$(cat "$USER_FONT_MARKER")" = "Managed by nvim-offline-build" ]; then
        if [ -f "$USER_FONT_MANIFEST" ] && [ ! -L "$USER_FONT_MANIFEST" ]; then
            while IFS= read -r managed_file; do
                [ -n "$managed_file" ] || continue
                case "$managed_file" in
                    */*|.|..) fail "Invalid entry in managed font manifest: $managed_file" ;;
                esac
                rm -f "$USER_FONT_DIR/$managed_file"
            done < "$USER_FONT_MANIFEST"
            rm -f "$USER_FONT_MANIFEST"
        fi
        rm -f "$USER_FONT_MARKER"
        if rmdir "$USER_FONT_DIR" 2>/dev/null; then
            info "Removed installed font directory: $USER_FONT_DIR"
        else
            info "Kept font directory because it contains files not managed by this installer: $USER_FONT_DIR"
        fi
    else
        info "Kept unmarked font directory: $USER_FONT_DIR"
    fi
else
    info "User font directory was not present: $USER_FONT_DIR"
fi

if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f
fi

if [ -d "$STATE_DIR" ]; then
    if [ -w "$STATE_DIR" ]; then
        rm -f "$STATE_DIR/user-config-link" "$STATE_DIR/user-font-link" "$STATE_DIR/user-cache-link"
        rmdir "$STATE_DIR" 2>/dev/null || true
    fi
fi

printf '%s\n' "User font installation removed. The Neovim bundle and unrelated user fonts were left unchanged."
