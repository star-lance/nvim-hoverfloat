-- lua/hoverfloat/process/tui_manager.lua - Enhanced with better readiness and terminal support
local M = {}
local socket_client = require('hoverfloat.communication.socket_client')
local logger = require('hoverfloat.utils.logger')

-- Process state
local state = {
  process_handle = nil,
  process_running = false,
  readiness_signaled = false,
  readiness_timeout_timer = nil,
  terminal_process = nil,
}

-- Configuration
local SOCKET_PATH = "/tmp/nvim_context.sock"
local BINARY_PATH = vim.fn.expand("~/.local/bin/nvim-context-tui")
local READINESS_TIMEOUT_MS = 10000      -- 10 seconds timeout for readiness
local READINESS_CHECK_INTERVAL_MS = 100 -- Check every 100ms

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
        "--override=font_size=11",
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
        "--dimensions", tostring(width), tostring(height),
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
    name = "konsole",
    check = function() return vim.fn.executable("konsole") == 1 end,
    cmd = function(title, width, height, binary, socket)
      return {
        "konsole",
        "--title", title,
        "-e", binary, socket
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
  -- First check if user has a preference in environment
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

  -- Otherwise find first available
  for _, config in ipairs(TERMINAL_CONFIGS) do
    if config.check() then
      logger.plugin("info", "Using terminal: " .. config.name)
      return config
    end
  end

  return nil
end

-- Check for readiness using file-based signaling
local function check_readiness_file()
  local ready_file = string.format("/tmp/nvim_context_tui_%d.ready", state.terminal_process or 0)
  if vim.fn.filereadable(ready_file) == 1 then
    -- Remove the file to avoid stale signals
    vim.fn.delete(ready_file)
    return true
  end
  return false
end

-- Handle readiness signal
local function on_readiness_signaled()
  if state.readiness_signaled then
    return
  end

  state.readiness_signaled = true

  -- Cancel readiness timeout
  if state.readiness_timeout_timer then
    state.readiness_timeout_timer:close()
    state.readiness_timeout_timer = nil
  end

  logger.plugin("info", "TUI readiness signal received")

  -- Now it's safe to connect to the socket
  M.setup_socket_connection()
end

-- Poll for readiness
local function poll_for_readiness()
  local start_time = vim.uv.now()

  local function check()
    -- Check if process is still running
    if not state.process_running then
      logger.plugin("error", "TUI process died before signaling readiness")
      return
    end

    -- Check for readiness file
    if check_readiness_file() then
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

-- Start the TUI process with automatic terminal detection
function M.start()
  if state.process_handle then
    logger.plugin("warn", "TUI process already running")
    return true
  end

  -- Check if binary exists
  if vim.fn.executable(BINARY_PATH) ~= 1 then
    logger.plugin("error", "TUI binary not found. Run 'make install' to build it.")
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

  -- Build command
  local cmd = terminal_config.cmd(
    "nvim-hoverfloat-tui", -- title
    80,                    -- width
    25,                    -- height
    BINARY_PATH,
    SOCKET_PATH
  )

  logger.plugin("info", "Starting TUI with " .. terminal_config.name .. ": " .. table.concat(cmd, " "))

  local handle = vim.fn.jobstart(cmd, {
    detach = true,
    on_exit = function(job_id, exit_code, event)
      M.on_process_exit(exit_code)
    end,
  })

  if handle > 0 then
    state.process_handle = handle
    state.process_running = true
    state.terminal_process = handle -- Store for readiness file checking

    -- Start polling for readiness
    poll_for_readiness()

    logger.plugin("info", "TUI started, waiting for readiness signal...")
    return true
  else
    logger.plugin("error", "Failed to start TUI")
    vim.notify("nvim-hoverfloat: Failed to start TUI", vim.log.levels.ERROR)
    return false
  end
end

-- Setup socket connection after TUI signals readiness
function M.setup_socket_connection()
  local max_retries = 10
  local retry_count = 0

  local function try_connect()
    retry_count = retry_count + 1

    -- Check if socket file exists
    if vim.fn.filereadable(SOCKET_PATH) == 1 then
      socket_client.connect(SOCKET_PATH)

      -- Check if connection was successful after a brief delay
      vim.defer_fn(function()
        if socket_client.is_connected() then
          logger.plugin("debug", "Socket connected successfully")
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
      vim.defer_fn(try_connect, 100)
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
  -- Clean up readiness file if it exists
  if state.terminal_process then
    local ready_file = string.format("/tmp/nvim_context_tui_%d.ready", state.terminal_process)
    vim.fn.delete(ready_file)
  end

  state.process_handle = nil
  state.process_running = false
  state.readiness_signaled = false
  state.terminal_process = nil

  logger.plugin("info", "TUI exited with code: " .. exit_code)
  socket_client.disconnect()

  -- Auto-restart on unexpected exit (but not if clean shutdown)
  if exit_code ~= 0 and exit_code ~= 130 and exit_code ~= 15 then -- 130 = SIGINT, 15 = SIGTERM
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

-- No setup needed
function M.setup()
  -- Nothing to do
end

return M
