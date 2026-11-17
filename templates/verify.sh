#!/bin/sh
set -eu

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH="$0"
ROOT="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
export NVIM_BUNDLE_ROOT="$ROOT"
export XDG_CONFIG_HOME="$ROOT/config"
export XDG_DATA_HOME="$ROOT/data"
export XDG_STATE_HOME="$ROOT/state"
export XDG_CACHE_HOME="$ROOT/cache"
export TMPDIR="$ROOT/cache/tmp"
export NPM_CONFIG_CACHE="$ROOT/cache/npm"
export NPM_CONFIG_USERCONFIG="$ROOT/config/npmrc"
export NPM_CONFIG_PREFIX="$ROOT/runtime/npm-global"
export PATH="$ROOT/runtime/commands:$ROOT/runtime/tools/bin:$ROOT/runtime/node/bin:$ROOT/runtime/python/bin:$PATH"

fail() {
    printf 'VERIFY FAILED: %s\n' "$*" >&2
    exit 1
}

printf '%s\n' "== Executable permissions =="
for executable in \
    "$ROOT/install.sh" \
    "$ROOT/nvim" \
    "$ROOT/verify.sh" \
    "$ROOT/install-fonts.sh" \
    "$ROOT/uninstall-fonts.sh" \
    "$ROOT/runtime/neovim/bin/nvim" \
    "$ROOT/runtime/node/bin/node" \
    "$ROOT/runtime/node/bin/npm" \
    "$ROOT/runtime/python/bin/python3.11" \
    "$ROOT/runtime/python-packages/bin/ruff" \
    "$ROOT/runtime/tools/bin/rg" \
    "$ROOT/runtime/tools/bin/fd" \
    "$ROOT/runtime/tools/bin/shfmt" \
    "$ROOT/runtime/tools/bin/shellcheck" \
    "$ROOT/runtime/tools/bin/verible-verilog-ls" \
    "$ROOT/runtime/tools/bin/verible-verilog-lint" \
    "$ROOT/runtime/tools/bin/verible-verilog-format"; do
    [ -x "$executable" ] || fail "Missing executable permission: $executable"
done
for command_script in "$ROOT/runtime/commands/"*; do
    [ -f "$command_script" ] || continue
    [ -x "$command_script" ] || fail "Missing executable permission: $command_script"
done
for python_command in "$ROOT/runtime/python-packages/bin/"*; do
    [ -f "$python_command" ] || continue
    [ -x "$python_command" ] || fail "Missing executable permission: $python_command"
done
printf '%s\n' "OK executable permissions"

printf '%s\n' "== Runtime versions =="
"$ROOT/runtime/node/bin/node" --version
"$ROOT/nvim" --version | sed -n '1,3p'
"$ROOT/runtime/tools/bin/rg" --version | sed -n '1p'
"$ROOT/runtime/tools/bin/fd" --version
"$ROOT/runtime/tools/bin/shfmt" --version

printf '%s\n' "== Bundled terminal font =="
[ -d "$ROOT/fonts/maple-mono" ] || fail "Missing Maple Mono NF CN font directory."
[ -f "$ROOT/fonts/maple-mono/MapleMono-NF-CN-Regular.ttf" ] || fail "Missing MapleMono-NF-CN-Regular.ttf."
font_count="$(find "$ROOT/fonts/maple-mono" -maxdepth 1 -type f -name '*.ttf' | wc -l | tr -d ' ')"
[ "$font_count" = "1" ] || fail "Expected exactly one bundled TTF font, found $font_count."
printf '%s\n' "OK Maple Mono NF CN Regular (single TTF)"

printf '%s\n' "== Required language servers =="
for command_name in \
    pyright-langserver \
    ruff \
    bash-language-server \
    vscode-html-language-server \
    vscode-css-language-server \
    vscode-json-language-server \
    typescript-language-server \
    prettier \
    tclsp \
    tclint \
    tclfmt \
    shellcheck \
    verible-verilog-ls \
    verible-verilog-lint \
    verible-verilog-format
do
    command -v "$command_name" >/dev/null 2>&1 || fail "Missing command: $command_name"
    printf 'OK %s\n' "$command_name"
done

printf '%s\n' "== Bundled Tcl Python runtime =="
LD_LIBRARY_PATH="$ROOT/runtime/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" PYTHONPATH="$ROOT/runtime/python-packages" "$ROOT/runtime/python/bin/python3.11" -c 'import tclint, pygls; print("OK tclint + pygls")'

printf '%s\n' "== Ruff formatter and project config =="
mkdir -p "${TMPDIR:-/tmp}"
ruff_smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/ruff-smoke.XXXXXX")"
trap 'rm -rf "$ruff_smoke_dir"' EXIT HUP INT TERM
cat > "$ruff_smoke_dir/pyproject.toml" <<'RUFF_CONFIG'
[tool.ruff]
line-length = 100

[tool.ruff.format]
quote-style = "single"
RUFF_CONFIG
ruff_output="$(printf 'message="hello"\n' | ruff format --stdin-filename "$ruff_smoke_dir/sample.py" -)"
printf '%s\n' "$ruff_output" | grep -F "message = 'hello'" >/dev/null || fail "Ruff did not load pyproject.toml formatting rules."
printf '%s\n' "OK Ruff formatter reads project pyproject.toml"
rm -rf "$ruff_smoke_dir"
trap - EXIT HUP INT TERM

printf '%s\n' "== Language tool versions =="
"$ROOT/runtime/tools/bin/shellcheck" --version | sed -n '1,2p'
printf '%s\n' "module top(input logic clk); endmodule" | "$ROOT/runtime/tools/bin/verible-verilog-format" --stdin_name smoke.sv - >/dev/null
"$ROOT/runtime/commands/tclint" --version
"$ROOT/runtime/python-packages/bin/ruff" --version
"$ROOT/runtime/commands/ruff" --version
printf 'set value 1\n' | "$ROOT/runtime/commands/tclint" -
printf 'set value 1\n' | "$ROOT/runtime/commands/tclfmt" - >/dev/null
printf '#!/usr/bin/env bash\necho "$HOME"\n' | "$ROOT/runtime/tools/bin/shellcheck" -s bash -

printf '%s\n' "== Plugin/config smoke test =="
[ ! -d "$ROOT/data/nvim/site/pack/offline/start/venv-selector.nvim" ] || fail "Removed plugin venv-selector.nvim is still installed."
VIM="/usr/share/vim" \
VIMRUNTIME="/usr/share/vim/vim82" \
VIMINIT="set number" \
EXINIT="set relativenumber" \
MYVIMRC="/etc/vimrc" \
MYGVIMRC="/etc/gvimrc" \
"$ROOT/nvim" --headless \
    -c 'lua assert(vim.env.VIM == nil)' \
    -c 'lua assert(vim.env.VIMRUNTIME == nil)' \
    -c 'lua assert(vim.env.VIMINIT == nil)' \
    -c 'lua assert(vim.env.EXINIT == nil)' \
    -c 'lua assert(require("cmp"))' \
    -c 'lua assert(require("telescope"))' \
    -c 'lua assert(require("nvim-tree"))' \
    -c 'lua assert(require("conform"))' \
    -c 'lua assert(require("conform").formatters_by_ft.python[1] == "ruff_format")' \
    -c 'lua assert(require("lualine"))' \
    -c 'lua assert(require("catppuccin"))' \
    -c 'lua assert(vim.fn.exists(":PyrightSetPythonPath") == 2)' \
    -c 'lua assert(vim.fn.executable("fd") == 1)' \
    -c 'lua assert(vim.fn.maparg("gc", "n") ~= "")' \
    -c 'lua assert(vim.fn.maparg("gcc", "n") ~= "")' \
    -c 'lua assert(vim.fn.maparg("grr", "n") ~= "")' \
    -c 'lua assert(vim.fn.maparg("grn", "n") ~= "")' \
    -c 'lua assert(vim.fn.maparg("gra", "n") ~= "")' \
    -c 'lua assert(vim.fn.maparg("gri", "n") ~= "")' \
    -c 'lua assert(vim.fn.maparg("gr", "n") == "")' \
    -c 'lua assert(vim.fn.maparg(" cf", "n") ~= "")' \
    -c 'lua assert(vim.fn.maparg(" f", "n") == "")' \
    -c 'setlocal filetype=python' \
    -c 'lua assert(vim.bo.commentstring == "# %s")' \
    -c 'lua assert(vim.filetype.match({filename = "sample.icl"}) == "icl")' \
    -c 'lua assert(vim.filetype.match({filename = "sample.pdl"}) == "pdl")' \
    -c 'lua assert(vim.filetype.match({filename = "sample.sdc"}) == "tcl")' \
    -c 'lua assert(vim.filetype.match({filename = "sample.csh"}) == "csh")' \
    -c 'lua assert(vim.filetype.match({filename = "sample.sv"}) == "systemverilog")' \
    -c 'setfiletype tcl' \
    -c 'lua assert(vim.bo.filetype == "tcl")' \
    -c 'lua assert(vim.bo.commentstring == "# %s")' \
    -c 'setlocal filetype=csh' \
    -c 'lua assert(vim.bo.filetype == "csh")' \
    -c 'setlocal filetype=verilog' \
    -c 'lua assert(vim.bo.filetype == "verilog")' \
    -c 'setlocal filetype=systemverilog' \
    -c 'lua assert(vim.bo.filetype == "systemverilog")' \
    -c 'lua print("config=" .. vim.fn.stdpath("config"))' \
    -c 'lua print("data=" .. vim.fn.stdpath("data"))' \
    -c 'lua print("state=" .. vim.fn.stdpath("state"))' \
    -c 'lua print("cache=" .. vim.fn.stdpath("cache"))' \
    -c 'qa!'

printf '%s\n' "VERIFY OK"
