#!/bin/sh
set -eu

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH="$0"
ROOT="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"

FONT_SOURCE_DIR="$ROOT/fonts/maple-mono"
FONT_FAMILY="Maple Mono NF CN"
USER_FONT_DIR="$HOME/.local/share/fonts/nvim-offline-build"
USER_FONT_MARKER="$USER_FONT_DIR/.nvim-offline-build-managed"
USER_FONT_MANIFEST="$USER_FONT_DIR/.nvim-offline-build-files"
USER_FONT_LINK="$HOME/.fonts/nvim-offline-build"
STATE_DIR="$ROOT/state/fontconfig"
STATE_FONT_DIR="$STATE_DIR/user-font-dir"
CACHE_DIR="$ROOT/cache/fontconfig"
BUNDLE_CONFIG="$ROOT/config/fontconfig/conf.d/99-nvim-offline-build.conf"
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

Default mode is --user. Font files are copied to:
  ~/.local/share/fonts/nvim-offline-build

--system registers the bundled fonts for all users and requires root.
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

[ -d "$FONT_SOURCE_DIR" ] || fail "Bundled Maple Mono NF CN fonts not found: $FONT_SOURCE_DIR"
find "$FONT_SOURCE_DIR" -type f -name '*.ttf' -print -quit | grep -q . || fail "No TTF files found in $FONT_SOURCE_DIR"
command -v fc-cache >/dev/null 2>&1 || fail "fontconfig is required (fc-cache was not found)."
command -v fc-list >/dev/null 2>&1 || fail "fontconfig is required (fc-list was not found)."

xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g'
}

write_system_config() {
    config_path="$1"
    xml_font_dir="$(xml_escape "$FONT_SOURCE_DIR")"

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

remove_managed_symlink() {
    link_path="$1"
    expected_target="$2"

    if [ -L "$link_path" ]; then
        current_target="$(readlink -f "$link_path" 2>/dev/null || true)"
        if [ "$current_target" = "$expected_target" ]; then
            rm -f "$link_path"
            info "Removed legacy registration link: $link_path"
        fi
    fi
}

remove_legacy_state_link() {
    state_file="$1"
    expected_target="$2"

    if [ -f "$state_file" ]; then
        old_link="$(cat "$state_file")"
        [ -n "$old_link" ] && remove_managed_symlink "$old_link" "$expected_target"
        rm -f "$state_file"
    fi
}

font_is_registered() {
    expected_dir="$1"
    listed_files="$(fc-list -f '%{file}\n' 2>/dev/null || true)"
    found=0

    while IFS= read -r listed_file; do
        [ -n "$listed_file" ] || continue
        resolved_file="$(readlink -f "$listed_file" 2>/dev/null || true)"
        case "$resolved_file" in
            "$expected_dir"/*)
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
    write_system_config "$SYSTEM_CONF"
    fc-cache -f "$FONT_SOURCE_DIR"
    font_is_registered "$FONT_SOURCE_DIR" || fail "Fontconfig did not register fonts from $FONT_SOURCE_DIR."
    info "System font registration completed."
    info "Font directory: $FONT_SOURCE_DIR"
    info "Select '$FONT_FAMILY' in your terminal profile, then restart the terminal."
    exit 0
fi

[ -n "$HOME" ] || fail "HOME is not set."
[ -d "$HOME" ] || fail "HOME directory does not exist: $HOME"
[ -w "$HOME" ] || fail "HOME is not writable: $HOME"

# Remove registration links created by older versions, but only when they
# still point to this bundle. Existing user configuration is never replaced.
remove_legacy_state_link "$STATE_DIR/user-config-link" "$BUNDLE_CONFIG"
remove_legacy_state_link "$STATE_DIR/user-font-link" "$FONT_SOURCE_DIR"
remove_legacy_state_link "$STATE_DIR/user-cache-link" "$CACHE_DIR"
remove_managed_symlink "$USER_FONT_LINK" "$FONT_SOURCE_DIR"

if [ -f "$BUNDLE_CONFIG" ] && grep -q 'Managed by nvim-offline-build' "$BUNDLE_CONFIG"; then
    rm -f "$BUNDLE_CONFIG"
fi

mkdir -p "$(dirname "$USER_FONT_DIR")"

if [ -L "$USER_FONT_DIR" ]; then
    fail "Refusing to install fonts through a symlink: $USER_FONT_DIR"
fi

if [ -e "$USER_FONT_DIR" ]; then
    [ -d "$USER_FONT_DIR" ] || fail "Font destination exists and is not a directory: $USER_FONT_DIR"
    if [ -L "$USER_FONT_MARKER" ]; then
        fail "Refusing to use a symlink marker: $USER_FONT_MARKER"
    fi
    if [ -f "$USER_FONT_MARKER" ]; then
        [ "$(cat "$USER_FONT_MARKER")" = "Managed by nvim-offline-build" ] || fail "Unrecognized font directory marker: $USER_FONT_MARKER"
    elif find "$USER_FONT_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        fail "Font destination already contains files and is not managed by this installer: $USER_FONT_DIR"
    fi
else
    mkdir -p "$USER_FONT_DIR"
fi

# Remove only files listed by our previous manifest. Any unrelated files
# manually placed in this dedicated directory are preserved.
if [ -f "$USER_FONT_MANIFEST" ]; then
    while IFS= read -r old_file; do
        [ -n "$old_file" ] || continue
        case "$old_file" in
            */*|.|..) fail "Invalid entry in managed font manifest: $old_file" ;;
        esac
        rm -f "$USER_FONT_DIR/$old_file"
    done < "$USER_FONT_MANIFEST"
fi

manifest_tmp="$USER_FONT_MANIFEST.tmp.$$"
: > "$manifest_tmp"
font_count=0
for source_file in "$FONT_SOURCE_DIR"/*.ttf; do
    [ -f "$source_file" ] || continue
    font_name="$(basename "$source_file")"
    cp -f "$source_file" "$USER_FONT_DIR/$font_name"
    chmod 644 "$USER_FONT_DIR/$font_name"
    printf '%s\n' "$font_name" >> "$manifest_tmp"
    font_count=$((font_count + 1))
done

[ "$font_count" -gt 0 ] || fail "No TTF files were copied."
if [ -f "$FONT_SOURCE_DIR/OFL.txt" ]; then
    cp -f "$FONT_SOURCE_DIR/OFL.txt" "$USER_FONT_DIR/OFL.txt"
    chmod 644 "$USER_FONT_DIR/OFL.txt"
    printf '%s\n' "OFL.txt" >> "$manifest_tmp"
fi

mv -f "$manifest_tmp" "$USER_FONT_MANIFEST"
printf '%s\n' "Managed by nvim-offline-build" > "$USER_FONT_MARKER"

# Fontconfig normally scans ~/.local/share/fonts. Older CentOS 7 builds may
# only scan ~/.fonts, so create a compatibility link only when required.
fc-cache -f "$USER_FONT_DIR"
if ! font_is_registered "$USER_FONT_DIR"; then
    ensure_symlink "$USER_FONT_DIR" "$USER_FONT_LINK"
    fc-cache -f "$USER_FONT_DIR"
fi

font_is_registered "$USER_FONT_DIR" || fail "Fontconfig still cannot see fonts in $USER_FONT_DIR."

mkdir -p "$STATE_DIR"
state_tmp="$STATE_FONT_DIR.tmp.$$"
printf '%s\n' "$USER_FONT_DIR" > "$state_tmp"
mv -f "$state_tmp" "$STATE_FONT_DIR"

info "User font installation completed without root."
info "Font files: $USER_FONT_DIR"
info "Fontconfig cache: $HOME/.cache/fontconfig"
info "Select '$FONT_FAMILY' in your terminal profile, then restart the terminal."
