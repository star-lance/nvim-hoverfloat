-- lua/hoverfloat/process/tui_manager.lua - TUI process management
local M = {}
local config = require('hoverfloat.config')
local socket_client = require('hoverfloat.communication.socket_client')
local logger = require('hoverfloat.utils.logger')

-- Process state
local state = {
  process_handle = nil,
  process_running = false,
  restart_on_error = true,
}

-- Build terminal arguments for TUI
local function build_terminal_args()
  local socket_path = config.get_socket_path()
  local binary_path = config.get_binary_path()

  -- Default TUI window configuration since these were removed from config
  local window_title = "Neovim Context TUI"
  local window_width = "80"
  local window_height = "24"

  local args = {
    "--title=" .. window_title,
    "--override=initial_window_width=" .. window_width .. "c",
    "--override=initial_window_height=" .. window_height .. "c",
    "--override=remember_window_size=no",
    "--hold",
    "-e", binary_path, socket_path
  }

  return args
end

-- Start the TUI process
function M.start()
  if state.process_handle then
    logger.plugin("warn", "TUI process already running")
    return true
  end

  local binary_path = config.get_binary_path() or ''
  local terminal_cmd = config.get_terminal_cmd()

  -- Check if binary exists
  if vim.fn.executable(binary_path) ~= 1 then
    logger.plugin("error", "TUI binary not found: " .. binary_path)
    return false
  end

  local terminal_args = build_terminal_args()
  local cmd = { terminal_cmd }
  vim.list_extend(cmd, terminal_args)

  logger.plugin("info", "Starting TUI process: " .. table.concat(cmd, " "))

  -- Start the terminal with TUI
  local handle = vim.fn.jobstart(cmd, {
    detach = true,
    on_exit = function(job_id, exit_code, event)
      M.on_process_exit(exit_code)
    end,
  })

  if handle > 0 then
    state.process_handle = handle
    state.process_running = true

    -- Set up socket connection after a delay
    M.setup_socket_connection()

    logger.plugin("info", "TUI process started with handle: " .. handle)
    return true
  else
    logger.plugin("error", "Failed to start TUI process")
    return false
  end
end

-- Setup socket connection after TUI starts
function M.setup_socket_connection()
  local socket_path = config.get_socket_path()

  local function try_connect()
    if vim.fn.filereadable(socket_path) == 1 then
      socket_client.connect(socket_path)
      return
    end

    -- Retry after short delay if socket file doesn't exist yet
    vim.defer_fn(try_connect, 100)
  end

  -- Give TUI a moment to start, then begin checking for socket
  vim.defer_fn(try_connect, 200)
end

-- Handle process exit
function M.on_process_exit(exit_code)
  state.process_handle = nil
  state.process_running = false

  logger.plugin("info", "TUI process exited with code: " .. exit_code)

  -- Disconnect socket
  socket_client.disconnect()

  -- Restart if configured and exit was unexpected
  if state.restart_on_error and exit_code ~= 0 then
    logger.plugin("info", "Restarting TUI process in 2 seconds...")
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
    logger.plugin("info", "TUI process stopped")
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
    restart_on_error = state.restart_on_error,
  }
end

-- Enable/disable auto-restart
function M.set_auto_restart(enabled)
  state.restart_on_error = enabled
end

-- Get TUI binary info
function M.get_binary_info()
  local binary_path = config.get_binary_path() or ''

  local info = {
    path = binary_path,
    exists = vim.fn.filereadable(binary_path) == 1,
    executable = vim.fn.executable(binary_path) == 1,
  }

  if info.exists then
    -- Use vim.uv for newer Neovim versions, fallback to vim.loop for older versions
    local uv = vim.uv or vim.loop
    local stat = uv.fs_stat(binary_path)
    if stat then
      info.size = stat.size
      info.modified = stat.mtime.sec
    end
  end

  return info
end

-- Setup TUI manager
function M.setup()
  -- Removed auto_restart_on_error and auto_start config dependencies
  -- These are now handled by default behavior or can be controlled via API
  state.restart_on_error = true -- Default to enabled
end

return M
