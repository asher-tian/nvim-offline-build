#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
export NVIM_BUNDLE_ROOT="$ROOT"
export XDG_CONFIG_HOME="$ROOT/config"
export XDG_DATA_HOME="$ROOT/data"
export XDG_STATE_HOME="$ROOT/state"
export XDG_CACHE_HOME="$ROOT/cache"
export TMPDIR="$ROOT/cache/tmp"
export NPM_CONFIG_CACHE="$ROOT/cache/npm"
export NPM_CONFIG_USERCONFIG="$ROOT/config/npmrc"
export NPM_CONFIG_PREFIX="$ROOT/runtime/npm-global"
export PATH="$ROOT/runtime/commands:$ROOT/runtime/tools/bin:$ROOT/runtime/node/bin:$PATH"

fail() {
    printf 'VERIFY FAILED: %s\n' "$*" >&2
    exit 1
}

printf '%s\n' "== Runtime versions =="
"$ROOT/runtime/node/bin/node" --version
"$ROOT/nvim" --version | sed -n '1,3p'
"$ROOT/runtime/tools/bin/rg" --version | sed -n '1p'
"$ROOT/runtime/tools/bin/shfmt" --version

printf '%s\n' "== Required language servers =="
for command_name in \
    pyright-langserver \
    bash-language-server \
    vscode-html-language-server \
    vscode-css-language-server \
    vscode-json-language-server \
    typescript-language-server \
    prettier
do
    command -v "$command_name" >/dev/null 2>&1 || fail "Missing command: $command_name"
    printf 'OK %s\n' "$command_name"
done

printf '%s\n' "== Plugin/config smoke test =="
"$ROOT/nvim" --headless \
    -c 'lua assert(require("cmp"))' \
    -c 'lua assert(require("telescope"))' \
    -c 'lua assert(require("nvim-tree"))' \
    -c 'lua assert(require("conform"))' \
    -c 'lua assert(require("lualine"))' \
    -c 'lua print("config=" .. vim.fn.stdpath("config"))' \
    -c 'lua print("data=" .. vim.fn.stdpath("data"))' \
    -c 'lua print("state=" .. vim.fn.stdpath("state"))' \
    -c 'lua print("cache=" .. vim.fn.stdpath("cache"))' \
    -c 'qa!'

printf '%s\n' "VERIFY OK"
