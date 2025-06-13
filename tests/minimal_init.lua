-- tests/minimal_init.lua - Minimal init for testing

-- Add current directory to Lua path for testing
local test_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local project_dir = vim.fn.fnamemodify(test_dir, ":h")
local lua_dir = project_dir .. "/lua"

-- Add to runtimepath
vim.opt.runtimepath:prepend(project_dir)

-- Required for plenary
local function add_to_luapath(path)
  package.path = package.path .. ";" .. path .. "/?.lua"
  package.path = package.path .. ";" .. path .. "/?/init.lua"
end

add_to_luapath(lua_dir)

-- Mock vim.uv if needed for older Neovim versions
if not vim.uv then
  vim.uv = vim.loop
end

-- Setup minimal test environment
vim.o.loadplugins = false
vim.g.loaded_2html_plugin = 1
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_gzip = 1
vim.g.loaded_logipat = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
vim.g.loaded_netrwFileHandlers = 1
vim.g.loaded_matchit = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_spellfile_plugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1