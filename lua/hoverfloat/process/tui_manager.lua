-- lua/hoverfloat/process/tui_manager.lua - Hardcoded for kitty terminal
local M = {}
local socket_client = require('hoverfloat.communication.socket_client')
local logger = require('hoverfloat.utils.logger')

-- Process state
local state = {
  process_handle = nil,
  process_running = false,
}

-- Hardcoded kitty command for TUI
local SOCKET_PATH = "/tmp/nvim_context.sock"
local BINARY_PATH = vim.fn.expand("~/.local/bin/nvim-context-tui")

-- Start the TUI process with hardcoded kitty settings
function M.start()
  if state.process_handle then
    logger.plugin("warn", "TUI process already running")
    return true
  end

  -- Check if binary exists
  if vim.fn.executable(BINARY_PATH) ~= 1 then
    logger.plugin("error", "TUI binary not found. Run 'make install' to build it.")
    return false
  end

  -- Hardcoded kitty command optimized for the context window
  local cmd = {
    "kitty",
    "--title=nvim-hoverfloat-tui",
    "--override=initial_window_width=80c",
    "--override=initial_window_height=25c",
    "--override=remember_window_size=no",
    "--override=background_opacity=0.95",
    "--override=font_size=11",
    "--hold",
    "-e", BINARY_PATH, SOCKET_PATH
  }

  logger.plugin("info", "Starting TUI: " .. table.concat(cmd, " "))

  local handle = vim.fn.jobstart(cmd, {
    detach = true,
    on_exit = function(job_id, exit_code, event)
      M.on_process_exit(exit_code)
    end,
  })

  if handle > 0 then
    state.process_handle = handle
    state.process_running = true
    M.setup_socket_connection()
    logger.plugin("info", "TUI started")
    return true
  else
    logger.plugin("error", "Failed to start TUI")
    return false
  end
end

-- Setup socket connection after TUI starts
function M.setup_socket_connection()
  local function try_connect()
    if vim.fn.filereadable(SOCKET_PATH) == 1 then
      socket_client.connect(SOCKET_PATH)

      -- Force send initial data after connection
      vim.defer_fn(function()
        if socket_client.is_connected() then
          require("hoverfloat").force_update()
        end
      end, 500)
      return
    end
    vim.defer_fn(try_connect, 100)
  end

  vim.defer_fn(try_connect, 200)
end

-- Handle process exit
function M.on_process_exit(exit_code)
  state.process_handle = nil
  state.process_running = false
  logger.plugin("info", "TUI exited with code: " .. exit_code)
  socket_client.disconnect()

  -- Auto-restart on unexpected exit
  if exit_code ~= 0 then
    logger.plugin("info", "Auto-restarting TUI in 2 seconds...")
    vim.defer_fn(M.start, 2000)
  end
end

-- Stop the TUI process
function M.stop()
  socket_client.disconnect()
  if state.process_handle then
    vim.fn.jobstop(state.process_handle)
    state.process_handle = nil
    state.process_running = false
    logger.plugin("info", "TUI stopped")
  end
end

-- Restart the TUI process
function M.restart()
  M.stop()
  vim.defer_fn(M.start, 500)
end

-- Toggle the TUI process
function M.toggle()
  if state.process_running then
    M.stop()
  else
    M.start()
  end
end

-- Check if TUI process is running
function M.is_running()
  return state.process_running
end

-- Get process status
function M.get_status()
  return {
    running = state.process_running,
    handle = state.process_handle,
  }
end

-- No setup needed - everything is hardcoded
function M.setup()
  -- Nothing to do
end

return M
