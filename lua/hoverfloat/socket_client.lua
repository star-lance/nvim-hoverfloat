-- lua/hoverfloat/socket_client.lua - Unix socket communication
local M = {}

local uv = vim.uv or vim.loop

-- Module state
local state = {
  socket = nil,
  connected = false,
  socket_path = "/tmp/nvim_context.sock",
  connection_attempts = 0,
  max_connection_attempts = 5,
  retry_delay = 1000,  -- milliseconds
}

-- Configuration
local config = {
  connect_timeout = 5000,   -- 5 seconds
  write_timeout = 1000,     -- 1 second
  max_message_size = 8192,  -- 8KB
  debug = false,
}

-- Debug logging
local function debug_log(message)
  if config.debug then
    print("[SocketClient] " .. message)
  end
end

-- Create and format JSON message
local function create_message(msg_type, data)
  local message = {
    type = msg_type,
    timestamp = vim.uv.now(),
    data = data or {}
  }
  
  local json_str = vim.json.encode(message)
  
  -- Check message size
  if #json_str > config.max_message_size then
    debug_log("Warning: Message size (" .. #json_str .. ") exceeds limit")
    -- Truncate hover data if too large
    if data and data.hover and #data.hover > 5 then
      data.hover = vim.list_slice(data.hover, 1, 5)
      table.insert(data.hover, "... (truncated due to size)")
      message.data = data
      json_str = vim.json.encode(message)
    end
  end
  
  return json_str
end

-- Send raw data through socket (create new connection per message to match TUI behavior)
local function send_raw(data)
  debug_log("Creating new connection for message")
  
  -- Create new socket for this message
  local socket = uv.new_pipe(false)
  if not socket then
    debug_log("Failed to create socket")
    return false
  end
  
  local success = false
  local connected = false
  
  -- Connect to socket
  socket:connect(state.socket_path, function(err)
    if err then
      debug_log("Connection failed for send: " .. err)
      socket:close()
      return
    end
    
    connected = true
    debug_log("Connected for send, writing data")
    
    -- Write data and close immediately (matching TUI expectation)
    local write_success = pcall(function()
      socket:write(data, function(write_err)
        if write_err then
          debug_log("Write failed: " .. write_err)
        else
          debug_log("Data written successfully")
          success = true
        end
        socket:close()
      end)
    end)
    
    if not write_success then
      debug_log("Write operation failed")
      socket:close()
    end
  end)
  
  -- Wait a moment for the async operation to complete
  local timeout = vim.fn.timer_start(1000, function()
    if not connected then
      debug_log("Send timeout")
      socket:close()
    end
  end)
  
  -- Small delay to allow async operation
  vim.defer_fn(function()
    vim.fn.timer_stop(timeout)
  end, 100)
  
  return true  -- Return true since we're handling async
end

-- Handle socket connection
local function on_connect()
  state.connected = true
  state.connection_attempts = 0
  debug_log("Connected to display window")
end

-- Handle socket disconnection
local function on_disconnect()
  if state.connected then
    debug_log("Disconnected from display window")
  end
  
  state.connected = false
  
  if state.socket then
    state.socket:close()
    state.socket = nil
  end
end

-- Handle socket errors
local function on_error(err)
  debug_log("Socket error: " .. (err or "unknown"))
  on_disconnect()
  
  -- Auto-reconnect if not too many attempts
  if state.connection_attempts < state.max_connection_attempts then
    debug_log("Attempting reconnection...")
    vim.defer_fn(function()
      M.connect(state.socket_path)
    end, state.retry_delay)
  end
end

-- Connect to Unix domain socket (now just sets the path - actual connections are per-message)
function M.connect(socket_path)
  if socket_path then
    state.socket_path = socket_path
  end
  
  debug_log("Socket path set to: " .. state.socket_path)
  state.connected = true  -- We're "connected" in the sense that we have a path to connect to
  
  return true
end

-- Disconnect from socket (now just clears the path)
function M.disconnect()
  debug_log("Disconnecting...")
  state.connected = false
  state.socket_path = nil
end

-- Send context update message
function M.send_context_update(context_data)
  local message = create_message("context_update", context_data)
  local timestamp = os.date("%H:%M:%S.%03d", math.floor(vim.uv.now() / 1000))
  local word = context_data.hover and #context_data.hover > 0 and "with_hover" or "no_hover"
  
  debug_log(string.format("[%s] Sending context update (%d bytes, %s, %s:%d)", 
    timestamp, #message, word, context_data.file or "unknown", context_data.line or 0))
  
  local success = send_raw(message)
  if not success then
    debug_log("FAILED to send context update - socket error")
  end
  
  return success
end

-- Send error message
function M.send_error(error_message)
  local data = { error = error_message }
  local message = create_message("error", data)
  debug_log("Sending error: " .. error_message)
  return send_raw(message)
end

-- Send status message
function M.send_status(status_data)
  local message = create_message("status", status_data)
  debug_log("Sending status update")
  return send_raw(message)
end

-- Send ping message (for testing connection)
function M.send_ping()
  local message = create_message("ping", { timestamp = vim.uv.now() })
  debug_log("Sending ping")
  return send_raw(message)
end

-- Check if connected (now just checks if we have a socket path)
function M.is_connected()
  return state.connected and state.socket_path ~= nil
end

-- Get connection status
function M.get_status()
  return {
    connected = state.connected,
    socket_path = state.socket_path,
    connection_attempts = state.connection_attempts,
    max_attempts = state.max_connection_attempts,
  }
end

-- Setup function
function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})
  
  if user_config and user_config.socket_path then
    state.socket_path = user_config.socket_path
  end
  
  debug_log("Socket client initialized")
end

-- Auto-reconnect function
function M.auto_reconnect()
  if not state.connected then
    debug_log("Auto-reconnecting...")
    M.connect()
  end
end

-- Enable debug logging
function M.enable_debug()
  config.debug = true
  debug_log("Debug logging enabled")
end

-- Disable debug logging
function M.disable_debug()
  config.debug = false
end

-- Test connection by sending ping
function M.test_connection()
  if not state.connected then
    debug_log("Not connected, cannot test")
    return false
  end
  
  return M.send_ping()
end

-- Cleanup function (called on plugin unload)
function M.cleanup()
  debug_log("Cleaning up socket client")
  M.disconnect()
end

-- Advanced: send custom message
function M.send_custom(msg_type, data)
  local message = create_message(msg_type, data)
  debug_log("Sending custom message: " .. msg_type)
  return send_raw(message)
end

-- Advanced: get raw socket for custom operations
function M.get_socket()
  return state.socket
end

-- Reset connection state (for debugging)
function M.reset()
  debug_log("Resetting connection state")
  M.disconnect()
  state.connection_attempts = 0
end

-- Set socket path
function M.set_socket_path(path)
  state.socket_path = path
  debug_log("Socket path set to: " .. path)
end

-- Get socket path
function M.get_socket_path()
  return state.socket_path
end

return M
