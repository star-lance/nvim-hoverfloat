-- tests/minimal_init.lua - Minimal Test Environment with Plenary Only

-- Disable ALL plugins first to ensure truly minimal environment
vim.g.loaded_gzip = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_spec = 1

-- Basic Neovim configuration for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = false
vim.opt.compatible = false

-- Essential settings for testing
vim.cmd([[
  filetype plugin indent on
  syntax enable
]])

-- Add our plugin to runtime path FIRST
local plugin_path = vim.fn.expand("<sfile>:h:h")
vim.opt.rtp:prepend(plugin_path)

-- Set up module loading for our plugin
package.path = package.path .. ";" .. plugin_path .. "/lua/?.lua"
package.path = package.path .. ";" .. plugin_path .. "/lua/?/init.lua"

-- Find and add plenary.nvim to runtime path
local function find_and_add_plenary()
  local data_path = vim.fn.stdpath('data')
  local possible_paths = {
    data_path .. '/lazy/plenary.nvim',                      -- lazy.nvim
    data_path .. '/site/pack/packer/start/plenary.nvim',    -- packer
    data_path .. '/site/pack/packer/opt/plenary.nvim',      -- packer optional
    data_path .. '/plugged/plenary.nvim',                   -- vim-plug
    vim.fn.expand('~/.local/share/nvim/lazy/plenary.nvim'), -- explicit lazy path
  }

  print("Searching for plenary.nvim...")
  for _, path in ipairs(possible_paths) do
    print("  Checking: " .. path)
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.rtp:prepend(path) -- ADD PLENARY TO RUNTIME PATH
      print("  ✓ Found and added plenary.nvim at: " .. path)
      return path
    end
  end

  -- Try with glob expansion for pack paths
  print("  Checking with glob expansion...")
  local glob_paths = vim.fn.glob(vim.fn.expand('~/.config/nvim/pack/*/start/plenary.nvim'), false, true)
  for _, path in ipairs(glob_paths) do
    print("  Checking glob result: " .. path)
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.rtp:prepend(path) -- ADD PLENARY TO RUNTIME PATH
      print("  ✓ Found and added plenary.nvim at: " .. path)
      return path
    end
  end

  return nil
end

-- Actually call the function to find and add plenary
local plenary_path = find_and_add_plenary()

if not plenary_path then
  error([[
❌ Plenary.nvim not found in any standard location!

Searched in:
  - ]] .. vim.fn.stdpath('data') .. [[/lazy/plenary.nvim (lazy.nvim)
  - ]] .. vim.fn.stdpath('data') .. [[/site/pack/packer/start/plenary.nvim (packer)
  - ]] .. vim.fn.stdpath('data') .. [[/plugged/plenary.nvim (vim-plug)
  - ~/.config/nvim/pack/*/start/plenary.nvim (manual)

Please ensure plenary.nvim is installed via your plugin manager.
For lazy.nvim, add: { 'nvim-lua/plenary.nvim' }

You can also check where plenary is installed with:
  find ~/.local/share/nvim ~/.config/nvim -name "plenary.nvim" -type d 2>/dev/null
  ]])
end

-- Load plenary and ensure it works
print("Loading plenary.nvim...")
local plenary_ok, plenary = pcall(require, 'plenary')
if not plenary_ok then
  error("❌ Failed to load plenary.nvim even though it was found at: " .. plenary_path .. "\nError: " .. tostring(plenary))
end

-- Load plenary's busted test framework
print("Loading plenary.busted...")
local busted_ok, busted_error = pcall(require, 'plenary.busted')
if not busted_ok then
  error("❌ Failed to load plenary.busted - plenary.nvim installation may be incomplete\nError: " ..
  tostring(busted_error))
end

-- Set up test-specific environment variables
vim.env.TMPDIR = vim.env.TMPDIR or '/tmp'
vim.env.XDG_RUNTIME_DIR = vim.env.XDG_RUNTIME_DIR or '/tmp'

-- Ensure /tmp is writable for test files
if vim.fn.filewritable('/tmp') == 0 then
  error("❌ Cannot write to /tmp directory - required for testing")
end

print("✅ Minimal test environment initialized")
print("✅ Plenary.nvim loaded from: " .. plenary_path)
print("✅ Plugin loaded from: " .. plugin_path)
print("✅ Ready to run tests!")
