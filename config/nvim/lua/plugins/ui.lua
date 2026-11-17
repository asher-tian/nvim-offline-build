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
    sections = {
        lualine_x = {
            function()
                local ok, selector = pcall(require, "venv-selector")
                if not ok then
                    return ""
                end

                local venv_path = selector.venv()
                if not venv_path or venv_path == "" then
                    return ""
                end

                return "Py " .. vim.fn.fnamemodify(venv_path, ":t")
            end,
            "encoding",
            "fileformat",
            "filetype",
        },
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
