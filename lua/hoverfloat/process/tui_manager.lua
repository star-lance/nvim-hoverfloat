-- lua/hoverfloat/process/tui_manager.lua - Simplified and fixed TUI manager
local M = {}
local logger = require('hoverfloat.utils.logger')

-- Get configuration
local function get_config()
  local config = require('hoverfloat.config')
  return {
    socket_path = config.get_socket_path(),
    binary_path = config.get_binary_path(),
    terminal_size = config.get_terminal_size(),
  }
end

-- Process state
local state = {
  process_handle = nil,
  process_running = false,
  readiness_signaled = false,
  terminal_process = nil,
}

-- Configuration
local READINESS_TIMEOUT_MS = 10000
local READINESS_CHECK_INTERVAL_MS = 200

-- Terminal configurations (ordered by preference)
local TERMINAL_CONFIGS = {
  {
    name = "kitty",
    check = function() return vim.fn.executable("kitty") == 1 end,
    cmd = function(title, width, height, binary, socket)
      return {
        "kitty",
        "--title=" .. title,
        "--override=initial_window_width=" .. width .. "c",
        "--override=initial_window_height=" .. height .. "c",
        "--override=remember_window_size=no",
        "--override=background_opacity=0.95",
        "--hold",
        "-e", binary, socket
      }
    end
  },
  {
    name = "alacritty",
    check = function() return vim.fn.executable("alacritty") == 1 end,
    cmd = function(title, width, height, binary, socket)
      return {
        "alacritty",
        "--title", title,
        "--option", "window.dimensions.columns=" .. width,
        "--option", "window.dimensions.lines=" .. height,
        "-e", binary, socket
      }
    end
  },
  {
    name = "wezterm",
    check = function() return vim.fn.executable("wezterm") == 1 end,
    cmd = function(title, width, height, binary, socket)
      return {
        "wezterm", "start",
        "--title", title,
        "--", binary, socket
      }
    end
  },
  {
    name = "foot",
    check = function() return vim.fn.executable("foot") == 1 end,
    cmd = function(title, width, height, binary, socket)
      return {
        "foot",
        "--title=" .. title,
        "--window-size-chars=" .. width .. "x" .. height,
        binary, socket
      }
    end
  },
  {
    name = "gnome-terminal",
    check = function() return vim.fn.executable("gnome-terminal") == 1 end,
    cmd = function(title, width, height, binary, socket)
      return {
        "gnome-terminal",
        "--title=" .. title,
        "--geometry=" .. width .. "x" .. height,
        "--",
        binary, socket
      }
    end
  },
  {
    name = "xterm",
    check = function() return vim.fn.executable("xterm") == 1 end,
    cmd = function(title, width, height, binary, socket)
      return {
        "xterm",
        "-title", title,
        "-geometry", width .. "x" .. height,
        "-e", binary, socket
      }
    end
  }
}

-- Get the best available terminal
local function get_terminal_config()
  -- Check user preference
  local preferred = vim.env.HOVERFLOAT_TERMINAL
  if preferred then
    for _, config in ipairs(TERMINAL_CONFIGS) do
      if config.name == preferred and config.check() then
        logger.plugin("info", "Using preferred terminal: " .. config.name)
        return config
      end
    end
    logger.plugin("warn", "Preferred terminal '" .. preferred .. "' not available")
  end

  -- Find first available
  for _, config in ipairs(TERMINAL_CONFIGS) do
    if config.check() then
      logger.plugin("info", "Using terminal: " .. config.name)
      return config
    end
  end

  return nil
end

-- Simplified readiness detection - check for socket file
local function check_readiness()
  local cfg = get_config()
  return vim.fn.filereadable(cfg.socket_path) == 1
end

-- Handle readiness signal
local function on_readiness_signaled()
  if state.readiness_signaled then
    return
  end

  state.readiness_signaled = true
  logger.plugin("info", "TUI is ready")

  -- Set up socket connection
  M.setup_socket_connection()
end

-- Poll for readiness
local function poll_for_readiness()
  local start_time = vim.uv.now()

  local function check()
    -- Check if process is still running
    if not state.process_running then
      logger.plugin("error", "TUI process died before becoming ready")
      return
    end

    -- Check for socket file existence
    if check_readiness() then
      on_readiness_signaled()
      return
    end

    -- Check timeout
    if vim.uv.now() - start_time > READINESS_TIMEOUT_MS then
      logger.plugin("warn", "TUI readiness timeout, attempting connection anyway")
      on_readiness_signaled()
      return
    end

    -- Continue polling
    vim.defer_fn(check, READINESS_CHECK_INTERVAL_MS)
  end

  check()
end

-- Start the TUI process
function M.start()
  if state.process_handle then
    logger.plugin("warn", "TUI process already running")
    return true
  end

  local cfg = get_config()

  -- Check if binary exists
  if vim.fn.executable(cfg.binary_path) ~= 1 then
    logger.plugin("error", "TUI binary not found at: " .. cfg.binary_path)
    vim.notify("nvim-hoverfloat: TUI binary not found. Run 'make install' to build it.", vim.log.levels.ERROR)
    return false
  end

  -- Get terminal configuration
  local terminal_config = get_terminal_config()
  if not terminal_config then
    logger.plugin("error", "No supported terminal found")
    vim.notify("nvim-hoverfloat: No supported terminal found. Install kitty, alacritty, or another supported terminal.",
      vim.log.levels.ERROR)
    return false
  end

  -- Reset state
  state.readiness_signaled = false

  -- Remove old socket file if it exists
  if vim.fn.filereadable(cfg.socket_path) == 1 then
    vim.fn.delete(cfg.socket_path)
  end

  -- Build command
  local size = cfg.terminal_size
  local cmd = terminal_config.cmd(
    "LSP Context",
    size.width,
    size.height,
    cfg.binary_path,
    cfg.socket_path
  )

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
    state.terminal_process = handle

    -- Start polling for readiness
    poll_for_readiness()

    logger.plugin("info", "TUI started successfully")
    return true
  else
    logger.plugin("error", "Failed to start TUI")
    vim.notify("nvim-hoverfloat: Failed to start TUI", vim.log.levels.ERROR)
    return false
  end
end

-- Setup socket connection after TUI signals readiness
function M.setup_socket_connection()
  local cfg = get_config()
  local max_retries = 10
  local retry_count = 0

  local function try_connect()
    retry_count = retry_count + 1

    -- Check if socket file exists
    if vim.fn.filereadable(cfg.socket_path) == 1 then
      local socket_client = require('hoverfloat.communication.socket_client')
      socket_client.connect(cfg.socket_path)

      -- Check if connection was successful after a brief delay
      vim.defer_fn(function()
        if socket_client.is_connected() then
          logger.plugin("info", "Socket connected successfully")

          -- Trigger initial context update
          vim.defer_fn(function()
            local ok, cursor_tracker = pcall(require, 'hoverfloat.core.cursor_tracker')
            if ok and cursor_tracker.is_tracking_enabled() then
              cursor_tracker.force_update()
            end
          end, 100)
        else
          if retry_count < max_retries then
            logger.plugin("warn", "Socket connection attempt " .. retry_count .. " failed, retrying...")
            vim.defer_fn(try_connect, 500)
          else
            logger.plugin("error", "Failed to connect after " .. max_retries .. " attempts")
            vim.notify("nvim-hoverfloat: Failed to connect to TUI", vim.log.levels.ERROR)
          end
        end
      end, 200)
      return
    end

    -- Socket file doesn't exist yet, retry if under limit
    if retry_count < max_retries then
      vim.defer_fn(try_connect, 200)
    else
      logger.plugin("error", "Socket file never appeared")
      vim.notify("nvim-hoverfloat: TUI socket connection failed", vim.log.levels.ERROR)
    end
  end

  -- Start connection attempts
  vim.defer_fn(try_connect, 100)
end

-- Handle process exit
function M.on_process_exit(exit_code)
  state.process_handle = nil
  state.process_running = false
  state.readiness_signaled = false
  state.terminal_process = nil

  logger.plugin("info", "TUI exited with code: " .. exit_code)

  -- Disconnect socket
  local socket_client = require('hoverfloat.communication.socket_client')
  socket_client.disconnect()

  -- Auto-restart on unexpected exit (but not if clean shutdown)
  if exit_code ~= 0 and exit_code ~= 130 and exit_code ~= 15 then -- 130 = SIGINT, 15 = SIGTERM
    logger.plugin("info", "Auto-restarting TUI in 2 seconds...")
    vim.defer_fn(M.start, 2000)
  end
end

-- Stop the TUI process
function M.stop()
  local socket_client = require('hoverfloat.communication.socket_client')
  socket_client.disconnect()

  if state.process_handle then
    vim.fn.jobstop(state.process_handle)
    state.process_handle = nil
    state.process_running = false
    state.readiness_signaled = false
    state.terminal_process = nil
    logger.plugin("info", "TUI stopped")
  end
end

-- Restart the TUI process
function M.restart()
  logger.plugin("info", "Restarting TUI...")
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

-- Check if TUI has signaled readiness
function M.is_ready()
  return state.readiness_signaled
end

-- Get process status
function M.get_status()
  local terminal_config = get_terminal_config()

  return {
    running = state.process_running,
    ready = state.readiness_signaled,
    handle = state.process_handle,
    waiting_for_readiness = state.process_running and not state.readiness_signaled,
    terminal = terminal_config and terminal_config.name or "none",
    terminals_available = vim.tbl_map(function(config)
      return config.name
    end, vim.tbl_filter(function(config)
      return config.check()
    end, TERMINAL_CONFIGS))
  }
end

-- Set preferred terminal
function M.set_preferred_terminal(terminal_name)
  vim.env.HOVERFLOAT_TERMINAL = terminal_name
  logger.plugin("info", "Set preferred terminal to: " .. terminal_name)
end

-- Setup function (placeholder for API compatibility)
function M.setup()
  -- Configuration is handled by the config module
end

return M
