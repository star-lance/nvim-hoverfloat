-- lua/hoverfloat/process/tui_manager.lua - Updated with readiness signaling
local M = {}
local socket_client = require('hoverfloat.communication.socket_client')
local logger = require('hoverfloat.utils.logger')

-- Process state
local state = {
  process_handle = nil,
  process_running = false,
  readiness_signaled = false,
  output_buffer = {''},  -- Buffer for partial lines (as recommended in markdown)
  readiness_timeout_timer = nil,
}

-- Hardcoded kitty command for TUI
local SOCKET_PATH = "/tmp/nvim_context.sock"
local BINARY_PATH = vim.fn.expand("~/.local/bin/nvim-context-tui")
local READINESS_TIMEOUT_MS = 10000  -- 10 seconds timeout for readiness

-- Handle stdout output and monitor for readiness signal
local function handle_stdout(job_id, data, event)
  if not state.process_running then
    return
  end

  -- Handle partial line assembly (critical for reliability as per markdown)
  if #data > 0 then
    -- Append first line to last buffered line
    state.output_buffer[#state.output_buffer] = state.output_buffer[#state.output_buffer] .. (data[1] or "")
    
    -- Add remaining lines
    for i = 2, #data do
      table.insert(state.output_buffer, data[i] or "")
    end
  end

  -- Check for readiness signal in all complete lines
  for i = 1, #state.output_buffer - 1 do  -- Skip last line (might be partial)
    local line = state.output_buffer[i]
    if line and line:match("TUI_READY") then
      M.on_readiness_signaled()
      break
    end
  end
  
  -- Keep only recent output (prevent memory growth)
  if #state.output_buffer > 50 then
    state.output_buffer = {table.concat(state.output_buffer, "\n")}
  end
end

-- Handle stderr output (for debugging)
local function handle_stderr(job_id, data, event)
  if data and #data > 0 then
    for _, line in ipairs(data) do
      if line and line ~= "" then
        logger.plugin("debug", "TUI stderr: " .. line)
      end
    end
  end
end

-- Called when TUI signals readiness
function M.on_readiness_signaled()
  if state.readiness_signaled then
    return  -- Already handled
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

-- Handle readiness timeout
local function on_readiness_timeout()
  if not state.readiness_signaled and state.process_running then
    logger.plugin("warn", "TUI failed to signal readiness within timeout, attempting connection anyway")
    M.setup_socket_connection()
  end
  state.readiness_timeout_timer = nil
end

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

  -- Reset state
  state.readiness_signaled = false
  state.output_buffer = {''}

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
    on_stdout = handle_stdout,   -- Monitor stdout for readiness signal
    on_stderr = handle_stderr,   -- Monitor stderr for debugging
    on_exit = function(job_id, exit_code, event)
      M.on_process_exit(exit_code)
    end,
  })

  if handle > 0 then
    state.process_handle = handle
    state.process_running = true
    
    -- Setup readiness timeout
    state.readiness_timeout_timer = vim.defer_fn(on_readiness_timeout, READINESS_TIMEOUT_MS)
    
    logger.plugin("info", "TUI started, waiting for readiness signal...")
    return true
  else
    logger.plugin("error", "Failed to start TUI")
    return false
  end
end

-- Setup socket connection after TUI signals readiness
function M.setup_socket_connection()
  local function try_connect()
    -- Check if socket file exists
    if vim.fn.filereadable(SOCKET_PATH) == 1 then
      socket_client.connect(SOCKET_PATH)

      -- Check if connection was successful after a brief delay
      vim.defer_fn(function()
        if socket_client.is_connected() then
          logger.plugin("debug", "Socket connected successfully")
          -- The socket_client will handle notifying other components
        else
          logger.plugin("warn", "Socket connection attempt failed, retrying...")
          vim.defer_fn(try_connect, 500)  -- Retry after 500ms
        end
      end, 300)  -- Reduced delay since we know TUI is ready
      return
    end
    
    -- Socket file doesn't exist yet, retry
    vim.defer_fn(try_connect, 100)
  end

  -- Small delay to let TUI finish any final setup after signaling readiness
  vim.defer_fn(try_connect, 100)
end

-- Handle process exit
function M.on_process_exit(exit_code)
  -- Clean up timers
  if state.readiness_timeout_timer then
    state.readiness_timeout_timer:close()
    state.readiness_timeout_timer = nil
  end
  
  state.process_handle = nil
  state.process_running = false
  state.readiness_signaled = false
  state.output_buffer = {''}
  
  logger.plugin("info", "TUI exited with code: " .. exit_code)
  socket_client.disconnect()

  -- Auto-restart on unexpected exit (but not if clean shutdown)
  if exit_code ~= 0 and exit_code ~= 130 then  -- 130 = SIGINT (Ctrl+C)
    logger.plugin("info", "Auto-restarting TUI in 2 seconds...")
    vim.defer_fn(M.start, 2000)
  elseif not state.readiness_signaled and exit_code ~= 0 then
    logger.plugin("warn", "TUI exited before signaling readiness")
  end
end

-- Stop the TUI process
function M.stop()
  -- Clean up timers first
  if state.readiness_timeout_timer then
    state.readiness_timeout_timer:close()
    state.readiness_timeout_timer = nil
  end
  
  socket_client.disconnect()
  
  if state.process_handle then
    vim.fn.jobstop(state.process_handle)
    state.process_handle = nil
    state.process_running = false
    state.readiness_signaled = false
    state.output_buffer = {''}
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

-- Get process status with readiness information
function M.get_status()
  return {
    running = state.process_running,
    ready = state.readiness_signaled,
    handle = state.process_handle,
    waiting_for_readiness = state.process_running and not state.readiness_signaled,
    has_timeout_timer = state.readiness_timeout_timer ~= nil,
    output_buffer_size = #state.output_buffer,
  }
end

-- Force readiness (for debugging/testing)
function M.force_readiness()
  if state.process_running and not state.readiness_signaled then
    logger.plugin("debug", "Forcing readiness signal")
    M.on_readiness_signaled()
  end
end

-- Get recent TUI output for debugging
function M.get_output_buffer()
  return vim.deepcopy(state.output_buffer)
end

-- No setup needed - everything is hardcoded
function M.setup()
  -- Nothing to do
end

return M
