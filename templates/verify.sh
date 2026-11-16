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

printf '%s\n' "== Runtime versions =="
"$ROOT/runtime/node/bin/node" --version
"$ROOT/nvim" --version | sed -n '1,3p'
"$ROOT/runtime/tools/bin/rg" --version | sed -n '1p'
"$ROOT/runtime/tools/bin/shfmt" --version

printf '%s\n' "== Bundled terminal font =="
[ -d "$ROOT/fonts/maple-mono" ] || fail "Missing Maple Mono NF CN font directory."
find "$ROOT/fonts/maple-mono" -type f -name '*.ttf' -print -quit | grep -q . || fail "No Maple Mono NF CN TTF files found."
printf '%s\n' "OK Maple Mono NF CN"

printf '%s\n' "== Required language servers =="
for command_name in \
    pyright-langserver \
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
PYTHONPATH="$ROOT/runtime/python-packages" "$ROOT/runtime/python/bin/python3.11" -c 'import tclint, pygls; print("OK tclint + pygls")'

printf '%s\n' "== Language tool versions =="
"$ROOT/runtime/tools/bin/shellcheck" --version | sed -n '1,2p'
printf '%s\n' "module top(input logic clk); endmodule" | "$ROOT/runtime/tools/bin/verible-verilog-format" --stdin_name smoke.sv - >/dev/null
"$ROOT/runtime/commands/tclint" --version

printf '%s\n' "== Plugin/config smoke test =="
"$ROOT/nvim" --headless \
    -c 'lua assert(require("cmp"))' \
    -c 'lua assert(require("telescope"))' \
    -c 'lua assert(require("nvim-tree"))' \
    -c 'lua assert(require("conform"))' \
    -c 'lua assert(require("lualine"))' \
    -c 'lua assert(require("catppuccin"))' \
    -c 'setfiletype tcl' \
    -c 'lua assert(vim.bo.filetype == "tcl")' \
    -c 'lua assert(vim.bo.commentstring == "# %s")' \
    -c 'syntax on' \
    -c 'setlocal filetype=icl' \
    -c 'lua assert(vim.bo.filetype == "icl")' \
    -c 'lua assert(vim.b.current_syntax == "icl")' \
    -c 'lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {"Module top {"})' \
    -c 'lua assert(vim.fn.synIDattr(vim.fn.synID(1, 1, 1), "name") == "iclStructure")' \
    -c 'lua assert(vim.fn.synIDattr(vim.fn.synID(1, 8, 1), "name") == "iclDeclaredName")' \
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
