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
  local tui_config = config.get_section('tui')
  local comm_config = config.get_section('communication')

  local args = {
    "--title=" .. tui_config.window_title,
    "--override=initial_window_width=" .. tui_config.window_size.width .. "c",
    "--override=initial_window_height=" .. tui_config.window_size.height .. "c",
    "--override=remember_window_size=no",
    "--hold",
    "-e", tui_config.binary_path, comm_config.socket_path
  }

  return args
end

-- Start the TUI process
function M.start()
  if state.process_handle then
    logger.plugin("warn", "TUI process already running")
    return true
  end

  local tui_config = config.get_section('tui')

  -- Check if binary exists
  if vim.fn.executable(tui_config.binary_path) ~= 1 then
    logger.plugin("error", "TUI binary not found: " .. tui_config.binary_path)
    return false
  end

  local terminal_args = build_terminal_args()
  local cmd = { tui_config.terminal_cmd }
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
  local comm_config = config.get_section('communication')
  local socket_path = comm_config.socket_path

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
  local tui_config = config.get_section('tui')
  local binary_path = tui_config.binary_path

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
  local config_data = config.get()
  state.restart_on_error = config_data.auto_restart_on_error

  -- Auto-start if configured
  if config_data.auto_start then
    vim.defer_fn(M.start, 1000)
  end
end

return M
