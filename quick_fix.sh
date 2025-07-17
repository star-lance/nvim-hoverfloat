#!/bin/bash
# quick_fix.sh - Fix circular dependency issues

set -e

echo "🔧 Fixing circular dependency issues..."

# Remove problematic files
echo "   Removing problematic files..."
rm -f lua/hoverfloat/core/metrics.lua
rm -f lua/hoverfloat/core/analyzer.lua  
rm -f lua/hoverfloat/core/monitor.lua
rm -f lua/hoverfloat/constants.lua

# Create config.lua if it doesn't exist
if [[ ! -f "lua/hoverfloat/config.lua" ]]; then
    echo "   Creating config.lua..."
    cat > lua/hoverfloat/config.lua << 'CONFIG_EOF'
-- lua/hoverfloat/config.lua - Fixed configuration module
local M = {}

-- Default configuration
local DEFAULT_CONFIG = {
  -- Process settings
  process = {
    socket_path = "/tmp/nvim_context.sock",
    binary_path = vim.fn.expand("~/.local/bin/nvim-context-tui"),
    auto_install = true,
  },

  -- Terminal settings
  terminal = {
    preferred = nil, -- Auto-detect: "kitty", "alacritty", etc.
    size = { width = 80, height = 25 },
    opacity = 0.95,
    font_size = 11,
  },

  -- Performance settings
  performance = {
    debounce_base = 20,   -- Base debounce in ms
    cache_ttl_ms = 45000, -- Cache TTL
    max_cache_entries = 1000,
    update_time = 100,    -- Vim updatetime for CursorHold
  },

  -- Feature toggles
  features = {
    auto_start = true,
    show_hover = true,
    show_references = true,
    show_definition = true,
    show_type_info = true,
    max_references = 8,
  },

  -- UI settings
  ui = {
    theme = "tokyo-night",
    keymaps = {
      toggle = "<leader>ct",
      open = "<leader>co",
      close = "<leader>cc",
      restart = "<leader>cr",
      status = "<leader>cs",
    },
  },

  -- Developer settings
  dev = {
    debug = false,
    log_dir = nil,
  },
}

-- User configuration (merged with defaults)
local user_config = vim.deepcopy(DEFAULT_CONFIG)

-- Helper to deep merge tables
local function deep_merge(base, override)
  if type(override) ~= "table" then
    return override
  end

  local result = vim.deepcopy(base)

  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end

  return result
end

-- Setup configuration
function M.setup(opts)
  opts = opts or {}
  user_config = deep_merge(DEFAULT_CONFIG, opts)

  -- Apply immediate settings
  if user_config.performance.update_time then
    vim.opt.updatetime = user_config.performance.update_time
  end

  if user_config.terminal.preferred then
    vim.env.HOVERFLOAT_TERMINAL = user_config.terminal.preferred
  end

  return user_config
end

-- Get current configuration
function M.get()
  return user_config
end

-- Get specific config value with dot notation
function M.get_value(path)
  local parts = vim.split(path, ".", { plain = true })
  local current = user_config

  for _, part in ipairs(parts) do
    if type(current) ~= "table" or current[part] == nil then
      return nil
    end
    current = current[part]
  end

  return current
end

-- Convenience getters
function M.get_socket_path()
  return user_config.process.socket_path
end

function M.get_binary_path()
  return user_config.process.binary_path
end

function M.get_terminal_size()
  return user_config.terminal.size
end

function M.is_auto_start_enabled()
  return user_config.features.auto_start
end

function M.is_debug_enabled()
  return user_config.dev.debug
end

function M.get_keymaps()
  return user_config.ui.keymaps
end

function M.get_feature_config()
  return {
    show_hover = user_config.features.show_hover,
    show_references = user_config.features.show_references,
    show_definition = user_config.features.show_definition,
    show_type_info = user_config.features.show_type_info,
    max_references = user_config.features.max_references,
  }
end

-- Update configuration at runtime
function M.update(path, value)
  local parts = vim.split(path, ".", { plain = true })
  local current = user_config

  -- Navigate to parent
  for i = 1, #parts - 1 do
    local part = parts[i]
    if type(current[part]) ~= "table" then
      current[part] = {}
    end
    current = current[part]
  end

  -- Set value
  current[parts[#parts]] = value

  -- Apply certain settings immediately
  if path == "performance.update_time" then
    vim.opt.updatetime = value
  elseif path == "terminal.preferred" then
    vim.env.HOVERFLOAT_TERMINAL = value
  end
end

-- Validate configuration
function M.validate()
  local ok = true
  local issues = {}

  -- Check binary path
  local binary_path = M.get_binary_path()
  if vim.fn.executable(binary_path) ~= 1 then
    ok = false
    table.insert(issues, "TUI binary not found at: " .. binary_path)
    
    if user_config.process.auto_install then
      table.insert(issues, "Run :HoverFloatInstall or 'make install' to build the binary")
    end
  end

  -- Check socket path directory
  local socket_dir = vim.fn.fnamemodify(M.get_socket_path(), ":h")
  if vim.fn.isdirectory(socket_dir) ~= 1 then
    ok = false
    table.insert(issues, "Socket directory does not exist: " .. socket_dir)
  end

  return ok, issues
end

-- Export configuration for display
function M.export()
  return vim.inspect(user_config, { indent = "  ", depth = 4 })
end

-- Reset to defaults
function M.reset()
  user_config = vim.deepcopy(DEFAULT_CONFIG)
end

-- Get default configuration
function M.get_defaults()
  return vim.deepcopy(DEFAULT_CONFIG)
end

return M
CONFIG_EOF
fi
