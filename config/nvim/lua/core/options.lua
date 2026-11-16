vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.termguicolors = true

vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.smartindent = true

vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true

vim.opt.updatetime = 300
vim.opt.timeoutlen = 500
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.wrap = false
vim.opt.scrolloff = 6
vim.opt.sidescrolloff = 8

local state = vim.fn.stdpath("state")
vim.fn.mkdir(state .. "/undo", "p")
vim.fn.mkdir(state .. "/swap", "p")
vim.fn.mkdir(state .. "/backup", "p")

vim.opt.undofile = true
vim.opt.undodir = state .. "/undo//"
vim.opt.directory = state .. "/swap//"
vim.opt.backupdir = state .. "/backup//"
vim.opt.backup = false
vim.opt.writebackup = false

vim.diagnostic.config({
    severity_sort = true,
    underline = true,
    update_in_insert = false,
    virtual_text = {
        spacing = 2,
        source = "if_many",
    },
    float = {
        border = "rounded",
        source = "if_many",
    },
})
