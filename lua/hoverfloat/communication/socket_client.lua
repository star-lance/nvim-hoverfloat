-- lua/hoverfloat/communication/socket_client.lua - Updated with connection coordination
local M = {}
local uv = vim.uv or vim.loop
local message_handler = require('hoverfloat.communication.message_handler')
local logger = require('hoverfloat.utils.logger')

-- Hardcoded configuration
local SOCKET_PATH = "/tmp/nvim_context.sock"
local CONNECTION_TIMEOUT = 5000
local MAX_QUEUE_SIZE = 100
local MAX_MESSAGES_PER_SECOND = 10

-- Connection state
local state = {
  socket = nil,
  connected = false,
  connecting = false,
  incoming_buffer = "",
  message_queue = nil,
  rate_limiter = nil,
}

-- Initialize components with hardcoded values
local function initialize_components()
  state.message_queue = message_handler.MessageQueue.new(MAX_QUEUE_SIZE)
  state.rate_limiter = message_handler.RateLimiter.new(MAX_MESSAGES_PER_SECOND)
end

-- Clean up connection resources
local function cleanup_connection()
  if state.socket then
    if not state.socket:is_closing() then
      state.socket:close()
    end
    state.socket = nil
  end
  
  state.connected = false
  state.connecting = false
  state.incoming_buffer = ""
end

-- Handle connection failure
local function handle_connection_failure(reason)
  logger.socket("error", "Connection failed: " .. reason)
  cleanup_connection()
end

-- Process incoming messages
local function handle_incoming_data(data)
  if not data then return end
  
  state.incoming_buffer = state.incoming_buffer .. data
  local messages, remaining = message_handler.parse_incoming_data(state.incoming_buffer)
  state.incoming_buffer = remaining
  
  for _, message in ipairs(messages) do
    handle_received_message(message)
  end
end

-- Handle received messages
function handle_received_message(message)
  logger.socket("debug", "Received message: " .. message.type)
  
  if message.type == "pong" then
    logger.socket("debug", "Received pong")
  elseif message.type == "error" then
    logger.socket("error", "Server error: " .. (message.data.error or "Unknown"))
  end
end

-- Send message with rate limiting
local function send_raw_message(message)
  if not state.rate_limiter:check_limit() then
    logger.socket("warn", "Rate limit exceeded, queuing message")
    state.message_queue:add(message)
    return false
  end
  
  if not state.connected or not state.socket then
    state.message_queue:add(message)
    if not state.connecting then
      M.connect()
    end
    return false
  end
  
  local ok = state.socket:write(message, function(err)
    if err then
      handle_connection_failure("Write failed: " .. err)
    end
  end)
  
  if not ok then
    handle_connection_failure("Socket write failed")
    return false
  end
  
  return true
end

-- Flush queued messages
local function flush_message_queue()
  if not state.connected or not state.socket then
    return
  end
  
  local queued_messages = state.message_queue:get_all()
  for _, message in ipairs(queued_messages) do
    if not send_raw_message(message) then
      break
    end
  end
end

-- Create connection to hardcoded socket path
local function create_connection()
  if state.connecting or state.connected then
    return
  end
  
  state.connecting = true
  logger.socket("info", "Connecting to " .. SOCKET_PATH)
  
  local socket = uv.new_pipe(false)
  if not socket then
    handle_connection_failure("Failed to create socket")
    return
  end
  
  local connection_completed = false
  
  -- Connection timeout
  vim.defer_fn(function()
    if not connection_completed then
      connection_completed = true
      if socket and not socket:is_closing() then
        socket:close()
      end
      state.connecting = false
      handle_connection_failure("Connection timeout")
    end
  end, CONNECTION_TIMEOUT)
  
  -- Attempt connection
  socket:connect(SOCKET_PATH, function(err)
    connection_completed = true
    
    if err then
      socket:close()
      handle_connection_failure("Connection failed: " .. err)
      return
    end
    
    state.socket = socket
    state.connected = true
    state.connecting = false
    state.incoming_buffer = ""
    
    logger.socket("info", "Connected successfully")
    
    socket:read_start(function(read_err, data)
      if read_err then
        handle_connection_failure("Read error: " .. read_err)
        return
      end
      
      if data then
        handle_incoming_data(data)
      else
        handle_connection_failure("Connection closed by server")
      end
    end)
    
    flush_message_queue()
    
    -- Trigger initial context update now that we're connected
    vim.defer_fn(function()
      local ok, cursor_tracker = pcall(require, 'hoverfloat.core.cursor_tracker')
      if ok and cursor_tracker.is_tracking_enabled() then
        cursor_tracker.force_update()
      end
    end, 100)
  end)
end

-- Public API (simplified)

function M.setup(user_config)
  -- Ignore user config - we know what we want
  initialize_components()
end

function M.connect(socket_path)
  -- Ignore socket_path parameter - use hardcoded value
  create_connection()
end

function M.disconnect()
  if state.connected and state.socket then
    local disconnect_msg = message_handler.create_disconnect_message("client_disconnect")
    send_raw_message(disconnect_msg)
    vim.defer_fn(cleanup_connection, 100)
  else
    cleanup_connection()
  end
  
  state.message_queue:clear()
end

function M.send_context_update(context_data)
  local message = message_handler.create_context_update(context_data)
  return send_raw_message(message)
end

function M.send_error(error_message, details)
  local message = message_handler.create_error_message(error_message, details)
  return send_raw_message(message)
end

function M.send_ping()
  if not state.connected then
    return false
  end
  
  local ping_msg = message_handler.create_ping_message()
  return send_raw_message(ping_msg)
end

-- Status functions
function M.is_connected()
  return state.connected
end

function M.is_connecting()
  return state.connecting
end

function M.get_status()
  return {
    connected = state.connected,
    connecting = state.connecting,
    socket_path = SOCKET_PATH,
    queued_messages = state.message_queue:size(),
  }
end

function M.force_reconnect()
  cleanup_connection()
  create_connection()
end

function M.cleanup()
  M.disconnect()
end

function M.reset()
  M.disconnect()
end

return M
