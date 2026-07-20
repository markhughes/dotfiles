-- ---------- leader ----------
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ---------- options ----------
local opt = vim.opt

opt.number = true
opt.relativenumber = false
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.ignorecase = true
opt.smartcase = true
opt.termguicolors = true
opt.signcolumn = "yes"
opt.undofile = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.scrolloff = 8
opt.splitright = true
opt.splitbelow = true

-- ---------- keymaps ----------
local map = vim.keymap.set
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
