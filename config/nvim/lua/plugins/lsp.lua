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
        cmd = { "verible-verilog-ls" },
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
    pattern = { "tcl", "sdc", "xdc", "upf" },
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

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(event)
        local opts = { buffer = event.buf, silent = true }
        local map = vim.keymap.set

        map("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
        map("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "Go to declaration" }))
        map("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "Find references" }))
        map("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", opts, { desc = "Go to implementation" }))
        map("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
        map("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename symbol" }))
        map("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code action" }))
        map("n", "<leader>lf", vim.lsp.buf.format, vim.tbl_extend("force", opts, { desc = "Format with LSP" }))
    end,
})
