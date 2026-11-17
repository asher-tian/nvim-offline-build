local cache_file = vim.fn.stdpath("cache") .. "/venv-selector/venvs.json"

require("venv-selector").setup({
    cache = {
        file = cache_file,
    },
    -- Search the conventional uv project environment explicitly. The default
    -- searches also scan CWD/workspaces, but an explicit .venv search avoids
    -- depending on broad workspace discovery for the common uv layout.
    search = {
        uv_cwd = {
            command = "$FD '/bin/python        enable_default_searches = true,
        enable_cached_venvs = true,
        cached_venv_automatic_activation = true,
        activate_venv_in_terminal = true,
        set_environment_variables = true,
        require_lsp_activation = true,
        fd_binary_name = "fd",
        picker = "telescope",
        notify_user_on_venv_activation = true,
        search_timeout = 10,
    },
})

vim.keymap.set("n", "<leader>vs", "<cmd>VenvSelect<cr>", {
    desc = "Select Python environment",
})
 '$CWD/.venv' --full-path --color never -HI -a -L",
        },
        uv_workspace = {
            command = "$FD '/bin/python        enable_default_searches = true,
        enable_cached_venvs = true,
        cached_venv_automatic_activation = true,
        activate_venv_in_terminal = true,
        set_environment_variables = true,
        require_lsp_activation = true,
        fd_binary_name = "fd",
        picker = "telescope",
        notify_user_on_venv_activation = true,
        search_timeout = 10,
    },
})

vim.keymap.set("n", "<leader>vs", "<cmd>VenvSelect<cr>", {
    desc = "Select Python environment",
})
 '$WORKSPACE_PATH/.venv' --full-path --color never -HI -a -L",
        },
    },
    options = {
        enable_default_searches = true,
        enable_cached_venvs = true,
        cached_venv_automatic_activation = true,
        activate_venv_in_terminal = true,
        set_environment_variables = true,
        require_lsp_activation = true,
        fd_binary_name = "fd",
        picker = "telescope",
        notify_user_on_venv_activation = true,
        search_timeout = 10,
    },
})

vim.keymap.set("n", "<leader>vs", "<cmd>VenvSelect<cr>", {
    desc = "Select Python environment",
})
