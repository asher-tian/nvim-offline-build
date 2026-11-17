vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

require("nvim-tree").setup({
    view = {
        width = 32,
        side = "left",
    },
    renderer = {
        group_empty = true,
        highlight_git = true,
        icons = {
            show = {
                file = true,
                folder = true,
                folder_arrow = true,
                git = true,
            },
        },
    },
    filters = {
        dotfiles = false,
    },
    git = {
        enable = vim.fn.executable("git") == 1,
    },
})

require("lualine").setup({
    options = {
        globalstatus = true,
        icons_enabled = true,
        section_separators = "",
        component_separators = "|",
    },
})

require("which-key").setup({
    delay = 400,
})

require("nvim-autopairs").setup({})
require("nvim-surround").setup({})

if vim.fn.executable("git") == 1 then
    require("gitsigns").setup({})
end
