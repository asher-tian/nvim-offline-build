#!/bin/sh
set -eu

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH="$0"
ROOT="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"

FONT_DIR="$ROOT/fonts/maple-mono"
FONT_FAMILY="Maple Mono NF CN"
BUNDLE_CONFIG_DIR="$ROOT/config/fontconfig/conf.d"
BUNDLE_CONFIG="$BUNDLE_CONFIG_DIR/99-nvim-offline-build.conf"
CACHE_DIR="$ROOT/cache/fontconfig"
STATE_DIR="$ROOT/state/fontconfig"
SYSTEM_CONF_DIR="/etc/fonts/conf.d"
SYSTEM_CONF="$SYSTEM_CONF_DIR/99-nvim-offline-build-fonts.conf"

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
  bash install-fonts.sh [--user|--system]

Default mode is --user and does not require root.
--system registers the bundled font for all users and requires root.
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

[ -d "$FONT_DIR" ] || fail "Bundled Maple Mono NF CN fonts not found: $FONT_DIR"
find "$FONT_DIR" -type f -name '*.ttf' -print -quit | grep -q . || fail "No TTF files found in $FONT_DIR"
command -v fc-cache >/dev/null 2>&1 || fail "fontconfig is required (fc-cache was not found)."
command -v fc-list >/dev/null 2>&1 || fail "fontconfig is required (fc-list was not found)."

xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g'
}

write_config() {
    config_path="$1"
    include_cache="$2"
    xml_font_dir="$(xml_escape "$FONT_DIR")"
    xml_cache_dir="$(xml_escape "$CACHE_DIR")"

    mkdir -p "$(dirname "$config_path")"
    [ ! -L "$config_path" ] || fail "Refusing to replace a Fontconfig symlink: $config_path"
    if [ -e "$config_path" ] && ! grep -q 'Managed by nvim-offline-build' "$config_path"; then
        fail "Refusing to overwrite an existing Fontconfig file: $config_path"
    fi

    temp_file="$config_path.tmp.$$"
    {
        printf '%s\n' '<?xml version="1.0"?>'
        printf '%s\n' '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">'
        printf '%s\n' '<fontconfig>'
        printf '%s\n' '  <!-- Managed by nvim-offline-build. -->'
        printf '  <dir>%s</dir>\n' "$xml_font_dir"
        if [ "$include_cache" = "yes" ]; then
            printf '  <cachedir>%s</cachedir>\n' "$xml_cache_dir"
        fi
        printf '%s\n' '</fontconfig>'
    } > "$temp_file"
    mv -f "$temp_file" "$config_path"
}

SYMLINK_CREATED=0
ensure_symlink() {
    link_target="$1"
    link_path="$2"
    SYMLINK_CREATED=0

    mkdir -p "$(dirname "$link_path")"
    if [ -L "$link_path" ]; then
        current_target="$(readlink -f "$link_path" 2>/dev/null || true)"
        [ "$current_target" = "$link_target" ] || fail "A different symlink already exists: $link_path -> $(readlink "$link_path")"
        return 0
    fi

    [ ! -e "$link_path" ] || fail "Refusing to replace an existing file or directory: $link_path"
    ln -s "$link_target" "$link_path"
    SYMLINK_CREATED=1
}

font_is_registered() {
    listed_files="$(fc-list -f '%{file}\n' 2>/dev/null || true)"
    found=0
    while IFS= read -r listed_file; do
        [ -n "$listed_file" ] || continue
        resolved_file="$(readlink -f "$listed_file" 2>/dev/null || true)"
        case "$resolved_file" in
            "$FONT_DIR"/*)
                found=1
                break
                ;;
        esac
    done <<EOF
$listed_files
EOF
    [ "$found" -eq 1 ]
}

if [ "$MODE" = "system" ]; then
    [ "$(id -u)" -eq 0 ] || fail "System font registration requires root. Run: sudo bash install-fonts.sh --system"
    write_config "$SYSTEM_CONF" "no"
    fc-cache -f "$FONT_DIR"
    font_is_registered || fail "Fontconfig did not register fonts from $FONT_DIR. Check /etc/fonts/conf.d/50-user.conf and Fontconfig logs."
    info "System font registration completed."
    info "Font directory: $FONT_DIR"
    info "Select '$FONT_FAMILY' in your terminal profile, then restart the terminal."
    exit 0
fi

[ -n "${HOME:-}" ] || fail "HOME is not set."
[ -d "$HOME" ] || fail "HOME directory does not exist: $HOME"
[ -w "$ROOT" ] || fail "The Neovim installation directory is not writable: $ROOT"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
case "$CONFIG_HOME" in
    /*) ;;
    *) fail "XDG_CONFIG_HOME must be an absolute path: $CONFIG_HOME" ;;
esac
case "$CACHE_HOME" in
    /*) ;;
    *) fail "XDG_CACHE_HOME must be an absolute path: $CACHE_HOME" ;;
esac

mkdir -p "$BUNDLE_CONFIG_DIR" "$CACHE_DIR" "$STATE_DIR"
write_config "$BUNDLE_CONFIG" "yes"

USER_CONFIG_LINK="$CONFIG_HOME/fontconfig/conf.d/99-nvim-offline-build.conf"
if [ "$USER_CONFIG_LINK" != "$BUNDLE_CONFIG" ]; then
    ensure_symlink "$BUNDLE_CONFIG" "$USER_CONFIG_LINK"
    if [ "$SYMLINK_CREATED" -eq 1 ]; then
        printf '%s\n' "$USER_CONFIG_LINK" > "$STATE_DIR/user-config-link"
    fi
fi

# Redirect the Fontconfig cache only when no existing cache directory is
# present. This keeps the HOME footprint to a symlink without replacing data.
USER_CACHE_LINK="$CACHE_HOME/fontconfig"
if [ "$USER_CACHE_LINK" != "$CACHE_DIR" ]; then
    if [ -L "$USER_CACHE_LINK" ]; then
        current_cache_target="$(readlink -f "$USER_CACHE_LINK" 2>/dev/null || true)"
        if [ "$current_cache_target" = "$CACHE_DIR" ]; then
            :
        else
            info "Keeping existing Fontconfig cache symlink: $USER_CACHE_LINK"
        fi
    elif [ -e "$USER_CACHE_LINK" ]; then
        info "Keeping existing Fontconfig cache directory: $USER_CACHE_LINK"
    else
        ensure_symlink "$CACHE_DIR" "$USER_CACHE_LINK"
        if [ "$SYMLINK_CREATED" -eq 1 ]; then
            printf '%s\n' "$USER_CACHE_LINK" > "$STATE_DIR/user-cache-link"
        fi
    fi
fi

fc-cache -f "$FONT_DIR"

# Some older CentOS Fontconfig installations do not load per-user conf.d
# snippets. Fall back to the long-supported ~/.fonts directory symlink.
if ! font_is_registered; then
    USER_FONT_LINK="$HOME/.fonts/nvim-offline-build"
    ensure_symlink "$FONT_DIR" "$USER_FONT_LINK"
    if [ "$SYMLINK_CREATED" -eq 1 ]; then
        printf '%s\n' "$USER_FONT_LINK" > "$STATE_DIR/user-font-link"
    fi
    fc-cache -f "$FONT_DIR"
fi

font_is_registered || fail "Fontconfig still cannot see the bundled fonts. Check that the desktop session uses Fontconfig and that $ROOT is readable."

info "User font registration completed without root."
info "Font files: $FONT_DIR"
info "Fontconfig config: $BUNDLE_CONFIG"
info "Fontconfig cache: $CACHE_DIR"
info "No font files are copied into HOME; registration links are small, and pre-existing cache paths are left untouched."
info "Select '$FONT_FAMILY' in your terminal profile, then restart the terminal."
