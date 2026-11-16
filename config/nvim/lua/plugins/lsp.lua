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
