-- lua/hoverfloat/config.lua - Hardcoded configuration for personal use
local M = {}

-- Hardcoded paths and settings - no more configuration hell
local SOCKET_PATH = "/tmp/nvim_context.sock"
local BINARY_PATH = vim.fn.expand("~/.local/bin/nvim-context-tui")
local TERMINAL_CMD = "kitty"

function M.setup(opts)
  -- Ignore any user config - we know what we want
  return {
    socket_path = SOCKET_PATH,
    binary_path = BINARY_PATH,
    terminal_cmd = TERMINAL_CMD,
  }
end

function M.get()
  return {
    socket_path = SOCKET_PATH,
    binary_path = BINARY_PATH,
    terminal_cmd = TERMINAL_CMD,
  }
end

function M.get_socket_path()
  return SOCKET_PATH
end

function M.get_terminal_cmd()
  return TERMINAL_CMD
end

function M.get_binary_path()
  return BINARY_PATH
end

return M
