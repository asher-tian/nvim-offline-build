#!/bin/sh
set -eu

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH="$0"
ROOT="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
PAYLOAD="$ROOT/payload"
RUNTIME="$ROOT/runtime"
TMP="$ROOT/cache/tmp/install-$$"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[nvim-offline] %s\n' "$*"
}

[ "$(uname -s)" = "Linux" ] || fail "This bundle targets Linux."
[ "$(uname -m)" = "x86_64" ] || fail "This bundle targets x86_64; current architecture: $(uname -m)."

command -v tar >/dev/null 2>&1 || fail "tar is required."
command -v awk >/dev/null 2>&1 || fail "awk is required."
command -v ldd >/dev/null 2>&1 || fail "ldd is required."

GLIBC_VERSION="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
if [ -z "$GLIBC_VERSION" ]; then
    GLIBC_VERSION="$(ldd --version 2>&1 | sed -n '1s/.* //p')"
fi

[ -n "$GLIBC_VERSION" ] || fail "Unable to determine glibc version."
awk -v version="$GLIBC_VERSION" 'BEGIN {
    split(version, v, ".");
    if (v[1] > 2 || (v[1] == 2 && v[2] >= 17)) exit 0;
    exit 1;
}' || fail "glibc 2.17 or newer is required; found $GLIBC_VERSION."

[ -f "$PAYLOAD/nvim-linux-x86_64.tar.gz" ] || fail "Missing Neovim payload."
[ -f "$PAYLOAD/node-v22.23.5-linux-x64-glibc-217.tar.gz" ] || fail "Missing Node.js 22.23.5 payload."
[ -f "$PAYLOAD/ripgrep-15.2.0-x86_64-unknown-linux-musl.tar.gz" ] || fail "Missing ripgrep payload."
[ -f "$PAYLOAD/shfmt_v3.11.0_linux_amd64" ] || fail "Missing shfmt payload."
[ -f "$PAYLOAD/cpython-3.11.18+20261110-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz" ] || fail "Missing bundled Python 3.11.18 payload."
[ -f "$PAYLOAD/shellcheck-v0.11.0.linux.x86_64.tar.gz" ] || fail "Missing ShellCheck payload."
[ -f "$PAYLOAD/verible-v0.0-4300-ga832669d-linux-static-x86_64.tar.gz" ] || fail "Missing Verible payload."

# Fail early on noexec filesystems. The installation directory must allow execution.
mkdir -p "$ROOT/cache/tmp"
probe="$ROOT/.nvim-exec-test-$$"
printf '#!/bin/sh\nexit 0\n' > "$probe"
chmod 700 "$probe"
if ! "$probe"; then
    rm -f "$probe"
    fail "The installation filesystem appears to be mounted noexec. Choose an executable filesystem."
fi
rm -f "$probe"

mkdir -p "$RUNTIME" "$ROOT/cache" "$ROOT/state/nvim" "$ROOT/logs"

info "Extracting Neovim 0.12.5..."
rm -rf "$RUNTIME/neovim"
mkdir -p "$RUNTIME/neovim"
tar -xzf "$PAYLOAD/nvim-linux-x86_64.tar.gz" \
    -C "$RUNTIME/neovim" --strip-components=1

info "Extracting Node.js 22.23.5 (glibc 2.17 build)..."
rm -rf "$RUNTIME/node"
mkdir -p "$RUNTIME/node"
tar -xzf "$PAYLOAD/node-v22.23.5-linux-x64-glibc-217.tar.gz" \
    -C "$RUNTIME/node" --strip-components=1

info "Extracting bundled Python 3.11.18 for Tcl tooling..."
rm -rf "$RUNTIME/python"
mkdir -p "$RUNTIME/python"
tar -xzf "$PAYLOAD/cpython-3.11.18+20261110-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz" \
    -C "$RUNTIME/python" --strip-components=1
[ -x "$RUNTIME/python/bin/python3.11" ] || fail "Bundled Python archive did not contain bin/python3.11."

info "Installing ripgrep, shfmt, ShellCheck and Verible..."
mkdir -p "$TMP/rg" "$TMP/shellcheck" "$TMP/verible" "$RUNTIME/tools/bin"
tar -xzf "$PAYLOAD/ripgrep-15.2.0-x86_64-unknown-linux-musl.tar.gz" \
    -C "$TMP/rg" --strip-components=1
[ -f "$TMP/rg/rg" ] || fail "ripgrep archive did not contain rg."
cp "$TMP/rg/rg" "$RUNTIME/tools/bin/rg"
cp "$PAYLOAD/shfmt_v3.11.0_linux_amd64" "$RUNTIME/tools/bin/shfmt"

tar -xzf "$PAYLOAD/shellcheck-v0.11.0.linux.x86_64.tar.gz" \
    -C "$TMP/shellcheck" --strip-components=1
shellcheck_source="$(find "$TMP/shellcheck" -type f -name shellcheck -print -quit)"
[ -n "$shellcheck_source" ] || fail "ShellCheck archive did not contain the shellcheck executable."
cp "$shellcheck_source" "$RUNTIME/tools/bin/shellcheck"

tar -xzf "$PAYLOAD/verible-v0.0-4300-ga832669d-linux-static-x86_64.tar.gz" \
    -C "$TMP/verible" --strip-components=1
for tool_name in verible-verilog-ls verible-verilog-lint verible-verilog-format; do
    tool_source="$(find "$TMP/verible" -type f -name "$tool_name" -print -quit)"
    [ -n "$tool_source" ] || fail "Verible archive did not contain $tool_name."
    cp "$tool_source" "$RUNTIME/tools/bin/$tool_name"
done

# Restore executable bits lost when the archive was created on Windows.
chmod 755 "$ROOT/nvim" "$ROOT/verify.sh" "$ROOT/install-fonts.sh" "$ROOT/uninstall-fonts.sh"
chmod 755 "$RUNTIME/neovim/bin/nvim"
chmod 755 "$RUNTIME/node/bin/node"
chmod 755 "$RUNTIME/tools/bin/rg" "$RUNTIME/tools/bin/shfmt" \
    "$RUNTIME/tools/bin/shellcheck" \
    "$RUNTIME/tools/bin/verible-verilog-ls" \
    "$RUNTIME/tools/bin/verible-verilog-lint" \
    "$RUNTIME/tools/bin/verible-verilog-format" \
    "$RUNTIME/python/bin/python3.11"

if [ -d "$RUNTIME/commands" ]; then
    find "$RUNTIME/commands" -type f -exec chmod 755 {} \;
fi

# Check dynamic dependencies before reporting success.
if ldd "$RUNTIME/neovim/bin/nvim" 2>&1 | grep -q "not found"; then
    ldd "$RUNTIME/neovim/bin/nvim" >&2
    fail "Neovim has unresolved shared-library dependencies."
fi
if ldd "$RUNTIME/node/bin/node" 2>&1 | grep -q "not found"; then
    ldd "$RUNTIME/node/bin/node" >&2
    fail "Node.js has unresolved shared-library dependencies."
fi
if LD_LIBRARY_PATH="$RUNTIME/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$RUNTIME/python/bin/python3.11" 2>&1 | grep -q "not found"; then
    LD_LIBRARY_PATH="$RUNTIME/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$RUNTIME/python/bin/python3.11" >&2
    fail "Bundled Python has unresolved shared-library dependencies."
fi

NODE_VERSION="$("$RUNTIME/node/bin/node" --version)"
[ "$NODE_VERSION" = "v22.23.5" ] || fail "Unexpected Node.js version: $NODE_VERSION"

PYTHON_VERSION="$(LD_LIBRARY_PATH="$RUNTIME/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$RUNTIME/python/bin/python3.11" --version 2>&1)"
[ "$PYTHON_VERSION" = "Python 3.11.18" ] || fail "Unexpected bundled Python version: $PYTHON_VERSION"
LD_LIBRARY_PATH="$RUNTIME/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" PYTHONPATH="$ROOT/runtime/python-packages" "$RUNTIME/python/bin/python3.11" -c 'import tclint, pygls' || fail "Tcl tooling Python dependencies could not be imported."

NPM_VERSION="$(PATH="$RUNTIME/node/bin:$PATH" "$RUNTIME/node/bin/npm" --version)"
[ "$NPM_VERSION" = "10.9.9" ] || fail "Unexpected npm version: $NPM_VERSION"

NVIM_VERSION="$("$RUNTIME/neovim/bin/nvim" --version | sed -n '1p')"
case "$NVIM_VERSION" in
    "NVIM v0.12.5"*) ;;
    *) fail "Unexpected Neovim version: $NVIM_VERSION" ;;
esac

mkdir -p \
    "$ROOT/config" \
    "$ROOT/data/nvim/site" \
    "$ROOT/state/nvim/undo" \
    "$ROOT/state/nvim/swap" \
    "$ROOT/state/nvim/backup" \
    "$ROOT/cache/nvim" \
    "$ROOT/cache/pyright" \
    "$ROOT/cache/npm" \
    "$ROOT/cache/tmp" \
    "$ROOT/runtime/npm-global" \
    "$ROOT/logs"

rm -rf "$TMP"

info "Installation initialized."
info "Install directory: $ROOT"
info "Neovim: $NVIM_VERSION"
info "Node.js: $NODE_VERSION"
info "npm: $NPM_VERSION"
info "Run: $ROOT/nvim"
info "No system PATH or HOME configuration was changed."
