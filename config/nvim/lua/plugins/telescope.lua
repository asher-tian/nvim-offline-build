require("telescope").setup({
    defaults = {
        prompt_prefix = "  ",
        selection_caret = "> ",
        path_display = { "smart" },
        sorting_strategy = "ascending",
        layout_config = {
            prompt_position = "top",
        },
        file_ignore_patterns = {
            "%.git/",
            "node_modules/",
            "__pycache__/",
            "%.venv/",
            "venv/",
        },
    },
})

local builtin = require("telescope.builtin")
local map = vim.keymap.set

map("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
map("n", "<leader>fg", builtin.live_grep, { desc = "Search in files" })
map("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
map("n", "<leader>fh", builtin.help_tags, { desc = "Search help" })
