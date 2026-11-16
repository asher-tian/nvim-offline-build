-- Native package directories are kept inside this bundle. Add them before
-- requiring plugin modules so this config is independent of startup load order.
local plugin_root = vim.fn.stdpath("data") .. "/site/pack/offline/start"
for _, plugin_path in ipairs(vim.fn.glob(plugin_root .. "/*", false, true)) do
    vim.opt.runtimepath:prepend(plugin_path)
end

require("core.options")
require("core.filetypes")
require("core.keymaps")

require("plugins")
