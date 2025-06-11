-- lua/hoverfloat/communication/socket_client.lua - Socket communication client
local M = {}
local uv = vim.uv or vim.loop
local message_handler = require('hoverfloat.communication.message_handler')
local logger = require('hoverfloat.utils.logger')

-- Connection state
local state = {
  socket_path = "/tmp/nvim_context.sock",
  socket = nil,
  connected = false,
  connecting = false,
  incoming_buffer = "",
  message_queue = nil,
  rate_limiter = nil,
}

-- Configuration
local config = {
  connection_timeout = 5000,
  max_queue_size = 100,
  max_messages_per_second = 10,
}

-- Initialize components
local function initialize_components()
  state.message_queue = message_handler.MessageQueue.new(config.max_queue_size)
  state.rate_limiter = message_handler.RateLimiter.new(config.max_messages_per_second)
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

-- Handle connection failure with retry logic
local function handle_connection_failure(reason)
  logger.socket("error", "Connection failed: " .. reason)
  cleanup_connection()
  
  -- Could implement retry logic here if needed
end

-- Process incoming messages
local function handle_incoming_data(data)
  if not data then return end
  
  -- Append to buffer and parse messages
  state.incoming_buffer = state.incoming_buffer .. data
  local messages, remaining = message_handler.parse_incoming_data(state.incoming_buffer)
  state.incoming_buffer = remaining
  
  -- Process each message
  for _, message in ipairs(messages) do
    handle_received_message(message)
  end
end

-- Handle received messages
function handle_received_message(message)
  logger.socket("debug", "Received message: " .. message.type)
  
  -- Handle specific message types
  if message.type == "pong" then
    -- Handle pong response for ping monitoring
    logger.socket("debug", "Received pong")
  elseif message.type == "error" then
    logger.socket("error", "Server error: " .. (message.data.error or "Unknown"))
  end
  
  -- Additional message handling could be added here
end

-- Send message with rate limiting and queuing
local function send_raw_message(message)
  -- Check rate limiting
  if not state.rate_limiter:check_limit() then
    logger.socket("warn", "Rate limit exceeded, queuing message")
    state.message_queue:add(message)
    return false
  end
  
  -- Check connection
  if not state.connected or not state.socket then
    state.message_queue:add(message)
    if not state.connecting then
      M.connect()
    end
    return false
  end
  
  -- Send message
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
      break -- Stop if sending fails
    end
  end
end

-- Create connection to socket
local function create_connection()
  if state.connecting or state.connected then
    return
  end
  
  state.connecting = true
  logger.socket("info", "Attempting to connect to " .. state.socket_path)
  
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
  end, config.connection_timeout)
  
  -- Attempt connection
  socket:connect(state.socket_path, function(err)
    connection_completed = true
    
    if err then
      socket:close()
      handle_connection_failure("Connection failed: " .. err)
      return
    end
    
    -- Connection successful
    state.socket = socket
    state.connected = true
    state.connecting = false
    state.incoming_buffer = ""
    
    logger.socket("info", "Connected successfully")
    
    -- Start reading data
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
    
    -- Flush any queued messages
    flush_message_queue()
  end)
end

-- Public API

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})
  
  if user_config and user_config.socket_path then
    state.socket_path = user_config.socket_path
  end
  
  initialize_components()
end

function M.connect(socket_path)
  if socket_path then
    state.socket_path = socket_path
  end
  
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

function M.send_status(status_data)
  local message = message_handler.create_status_message(status_data)
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
    socket_path = state.socket_path,
    queued_messages = state.message_queue:size(),
  }
end

function M.get_connection_health()
  local health = {
    connected = state.connected,
    connecting = state.connecting,
    socket_exists = vim.fn.filereadable(state.socket_path) == 1,
    queue_size = state.message_queue:size(),
  }
  
  if state.connected then
    health.status = "connected"
  elseif state.connecting then
    health.status = "connecting"
  else
    health.status = "disconnected"
  end
  
  return health
end

function M.force_reconnect()
  cleanup_connection()
  create_connection()
end

function M.clear_queue()
  local queue_size = state.message_queue:size()
  state.message_queue:clear()
  return queue_size
end

function M.test_connection()
  if not state.connected then
    return false, "Not connected"
  end
  
  return M.send_ping()
end

function M.cleanup()
  M.disconnect()
end

function M.reset()
  M.disconnect()
end

function M.ensure_connected()
  if not state.connected and not state.connecting then
    create_connection()
  end
end

return M
