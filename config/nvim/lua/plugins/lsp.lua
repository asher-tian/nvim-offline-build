local capabilities = require("cmp_nvim_lsp").default_capabilities()

local servers = {
    pyright = {
        cmd = { "pyright-langserver", "--stdio" },
        settings = {
            python = {
                analysis = {
                    autoSearchPaths = true,
                    useLibraryCodeForTypes = true,
                    diagnosticMode = "workspace",
                },
            },
        },
    },
    bashls = {
        cmd = { "bash-language-server", "start" },
        filetypes = { "sh" },
        settings = {
            bashIde = {
                shellcheckPath = "shellcheck",
                shfmt = {
                    path = "shfmt",
                },
            },
        },
    },
    verible = {
        cmd = { "verible-verilog-ls", "--rules_config_search" },
        filetypes = { "systemverilog", "verilog" },
        root_markers = { "verible.filelist", ".git" },
    },
    html = {
        cmd = { "vscode-html-language-server", "--stdio" },
    },
    cssls = {
        cmd = { "vscode-css-language-server", "--stdio" },
    },
    jsonls = {
        cmd = { "vscode-json-language-server", "--stdio" },
    },
    ts_ls = {
        cmd = { "typescript-language-server", "--stdio" },
    },
}

for name, config in pairs(servers) do
    config.capabilities = capabilities
    vim.lsp.config(name, config)
    vim.lsp.enable(name)
end

-- tclint documents this direct LSP start pattern. It also supports EDA Tcl
-- variants such as SDC, XDC and UPF; all Python dependencies are bundled.
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl" },
    callback = function(event)
        local root_dir = vim.fs.root(event.buf, {
            "tclint.toml",
            ".tclint",
            "pyproject.toml",
            ".git",
        }) or vim.fn.getcwd()

        vim.lsp.start({
            name = "tclint",
            cmd = { "tclsp" },
            root_dir = root_dir,
        }, {
            bufnr = event.buf,
        })
    end,
})

