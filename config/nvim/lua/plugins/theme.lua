-- Catppuccin is loaded before the rest of the UI plugins.
-- The offline build pins the plugin commit in locks/plugins.lock.json.
require("catppuccin").setup({
    flavour = "mocha",
    background = {
        light = "latte",
        dark = "mocha",
    },
    transparent_background = false,
    term_colors = true,
    integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        telescope = true,
        which_key = true,
    },
})

vim.cmd.colorscheme("catppuccin-mocha")
