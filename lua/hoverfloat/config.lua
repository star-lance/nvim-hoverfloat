-- lua/hoverfloat/config.lua - Centralized configuration management
local M = {}

-- Minimal configuration - only essential options
local default_config = {
  socket_path = "/tmp/nvim_context.sock",  -- IPC socket location
  terminal_cmd = nil,                      -- Auto-detect if nil
  binary_path = nil,                       -- Auto-detect if nil
}

-- Current configuration
local current_config = {}

-- Auto-detect suitable terminal emulator
local function detect_terminal()
  local terminals = { "kitty", "alacritty", "wezterm", "gnome-terminal", "xterm" }
  
  for _, term in ipairs(terminals) do
    if vim.fn.executable(term) == 1 then
      return term
    end
  end
  
  error("No supported terminal emulator found. Please install kitty, alacritty, wezterm, gnome-terminal, or xterm.")
end

-- Auto-detect TUI binary path
local function detect_binary_path()
  local binary_name = "nvim-context-tui"
  local search_paths = {
    vim.fn.expand("~/.local/bin/" .. binary_name),
    "/usr/local/bin/" .. binary_name,
    "/usr/bin/" .. binary_name,
  }
  
  for _, path in ipairs(search_paths) do
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  
  error("TUI binary not found. Please run 'make install' to build and install the binary.")
end

-- Setup configuration with auto-detection
function M.setup(user_config)
  -- Merge with defaults
  current_config = vim.tbl_deep_extend("force", default_config, user_config or {})
  
  -- Validate socket path
  if type(current_config.socket_path) ~= "string" or current_config.socket_path == "" then
    error("socket_path must be a non-empty string")
  end
  
  -- Auto-detect terminal if not provided
  if not current_config.terminal_cmd then
    current_config.terminal_cmd = detect_terminal()
  end
  
  -- Auto-detect binary path if not provided  
  if not current_config.binary_path then
    current_config.binary_path = detect_binary_path()
  end
  
  return current_config
end

-- Get current configuration
function M.get()
  return vim.deepcopy(current_config)
end

-- Get socket path
function M.get_socket_path()
  return current_config.socket_path
end

-- Get terminal command
function M.get_terminal_cmd()
  return current_config.terminal_cmd
end

-- Get binary path
function M.get_binary_path()
  return current_config.binary_path
end

return M
