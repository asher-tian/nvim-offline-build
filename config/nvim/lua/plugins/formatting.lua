require("conform").setup({
    formatters = {
        tclfmt = {
            command = "tclfmt",
            args = { "-" },
        },
    },
    formatters_by_ft = {
        javascript = { "prettier" },
        javascriptreact = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        json = { "prettier" },
        jsonc = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        bash = { "shfmt" },
        sh = { "shfmt" },
        tcl = { "tclfmt" },
        sdc = { "tclfmt" },
        xdc = { "tclfmt" },
        upf = { "tclfmt" },
        verilog = { "verible" },
        systemverilog = { "verible" },
    },
    format_on_save = {
        timeout_ms = 1500,
        lsp_format = "fallback",
    },
})
