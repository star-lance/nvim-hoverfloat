-- tests/minimal_init.lua - Completely isolated test environment

-- Completely disable user configuration
vim.env.XDG_CONFIG_HOME = '/tmp/nvim_test_' .. os.time()
vim.env.XDG_DATA_HOME = '/tmp/nvim_test_' .. os.time()
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Disable all plugins and user configs
vim.opt.loadplugins = false

-- Basic essential settings
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = false
vim.opt.compatible = false

-- Clear runtime path and only add essentials
local original_rtp = vim.opt.rtp:get()
vim.opt.rtp = {}

-- Add only Neovim's built-in runtime
for _, path in ipairs(original_rtp) do
  if path:match('/nvim/runtime$') or path:match('/nvim/runtime/pack') then
    vim.opt.rtp:append(path)
  end
end

-- Add our plugin to runtime path
local plugin_path = vim.fn.expand("<sfile>:h:h")
vim.opt.rtp:prepend(plugin_path)

-- Find and add plenary.nvim (only if it exists)
local function find_plenary()
  local data_path = vim.fn.stdpath('data')
  local paths = {
    data_path .. '/lazy/plenary.nvim',
    data_path .. '/site/pack/packer/start/plenary.nvim',
    data_path .. '/plugged/plenary.nvim',
    vim.fn.expand('~/.local/share/nvim/lazy/plenary.nvim'),
  }

  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.rtp:prepend(path)
      return true
    end
  end
  return false
end

if not find_plenary() then
  error("plenary.nvim not found. Install it with: { 'nvim-lua/plenary.nvim' }")
end

-- Load plenary test framework and register commands
local ok, plenary = pcall(require, 'plenary.busted')
if not ok then
  error("Failed to load plenary.busted: " .. tostring(plenary))
end

-- Ensure the command is registered
vim.cmd([[command! -nargs=1 PlenaryBustedFile lua require('plenary.busted').run(<f-args>)]])

print("✅ Isolated test environment ready")
