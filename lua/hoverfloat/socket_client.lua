local M = {}
local uv = vim.uv or vim.loop

-- Connection state
local state = {
  socket_path = "/tmp/nvim_context.sock",
  socket = nil,
  connected = false,
  connecting = false,
  message_queue = {},
  connection_attempts = 0,
  incoming_buffer = "",
  last_activity = 0,
  reconnect_scheduled = false,
}

-- Configuration
local config = {
  reconnect_delay = 2000,       -- 2 seconds initial delay
  max_reconnect_delay = 30000,  -- 30 seconds max delay
  connection_timeout = 5000,    -- 5 seconds
  max_queue_size = 100,         -- Maximum queued messages
  max_connection_attempts = 10, -- Max attempts before giving up
  activity_timeout = 60000,     -- 60 seconds of inactivity before considering connection stale
}

-- Message creation helper
local function create_message(msg_type, data)
  local message = {
    type = msg_type,
    timestamp = vim.uv.now(),
    data = data or {}
  }
  return vim.json.encode(message) .. '\n'
end

-- Calculate exponential backoff delay
local function get_reconnect_delay()
  local delay = math.min(
    config.reconnect_delay * math.pow(2, state.connection_attempts),
    config.max_reconnect_delay
  )
  return delay
end

local logger = require('hoverfloat.logger')

-- Event-driven reconnection with exponential backoff
local function schedule_reconnect_attempt()
  if state.reconnect_scheduled or state.connected or state.connecting then
    return
  end
  
  state.reconnect_scheduled = true
  local delay = get_reconnect_delay()
  logger.socket("info", "Scheduling reconnection", { delay_ms = delay, attempt = state.connection_attempts + 1 })
  
  vim.defer_fn(function()
    state.reconnect_scheduled = false
    if not state.connected and not state.connecting then
      create_connection()
    end
  end, delay)
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
  state.last_activity = 0
end

local function handle_connection_failure(reason)
  if reason:match("Connection timeout") and state.connected then
    return  -- Ignore spurious timeouts
  end

  logger.socket("error", "Connection failed", { reason = reason, attempt = state.connection_attempts + 1 })
  cleanup_connection()
  state.connection_attempts = state.connection_attempts + 1

  if state.connection_attempts < config.max_connection_attempts then
    schedule_reconnect_attempt()
  else
    logger.socket("error", "Max reconnection attempts reached", { max_attempts = config.max_connection_attempts })
  end
end

-- Connection health check (replaces heartbeat)
local function check_connection_health()
  if not state.connected then
    return false
  end
  
  local now = vim.uv.now()
  if state.last_activity > 0 and (now - state.last_activity) > config.activity_timeout then
    logger.socket("warn", "Connection appears stale", { last_activity_age = now - state.last_activity })
    return false
  end
  
  return true
end

local function handle_message(json_str)
  local ok, message = pcall(vim.json.decode, json_str)
  if not ok then
    logger.socket("error", "Message parse error", { error = message })
    return
  end

  -- Update activity timestamp on any message
  state.last_activity = vim.uv.now()
  
  if message.type == "error" then
    logger.socket("error", "TUI reported error", message.data and message.data.error or "Unknown error")
  elseif message.type == "pong" then
    -- Optional: handle pong if manual ping is sent
    logger.socket("debug", "Received pong")
  end
end

-- Handle incoming data from socket
local function handle_incoming_data(data)
  if not data then return end

  -- Update activity on any data received
  state.last_activity = vim.uv.now()
  
  -- Append to buffer
  state.incoming_buffer = state.incoming_buffer .. data

  -- Process complete lines (newline-delimited messages)
  while true do
    local newline_pos = state.incoming_buffer:find('\n')
    if not newline_pos then break end

    local line = state.incoming_buffer:sub(1, newline_pos - 1)
    state.incoming_buffer = state.incoming_buffer:sub(newline_pos + 1)

    if line ~= "" then
      handle_message(line)
    end
  end
end

local function send_raw_message(json_message)
  -- Check connection health before sending
  if state.connected and not check_connection_health() then
    handle_connection_failure("Connection health check failed")
  end
  
  if not state.connected or not state.socket then
    if #state.message_queue < config.max_queue_size then
      table.insert(state.message_queue, json_message)
    end
    if not state.connecting and not state.reconnect_scheduled then
      create_connection()
    end
    return false
  end

  local ok = state.socket:write(json_message, function(err)
    if err then
      handle_connection_failure("Write failed: " .. err)
    else
      -- Update activity on successful write
      state.last_activity = vim.uv.now()
    end
  end)

  if not ok then
    handle_connection_failure("Socket write failed")
    return false
  end

  return true
end

local function flush_message_queue()
  if not state.connected or not state.socket or #state.message_queue == 0 then
    return
  end

  for _, queued_msg in ipairs(state.message_queue) do
    if not send_raw_message(queued_msg) then
      break
    end
  end

  state.message_queue = {}
end

-- Manual ping function for connection testing
local function send_ping()
  if not state.connected then
    return false
  end
  
  local ping_msg = create_message("ping", { timestamp = vim.uv.now() })
  return send_raw_message(ping_msg)
end

function create_connection()
  if state.connecting or state.connected then
    return
  end

  logger.socket("info", "Starting connection attempt", { attempt = state.connection_attempts + 1 })
  state.connecting = true

  local socket = uv.new_pipe(false)
  if not socket then
    handle_connection_failure("Failed to create socket")
    return
  end

  local connection_completed = false

  -- Use vim.defer_fn for timeout instead of timer
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

  socket:connect(state.socket_path, function(err)
    connection_completed = true

    if err then
      socket:close()
      handle_connection_failure("Connection failed: " .. err)
      return
    end

    state.socket = socket
    state.connected = true
    state.connecting = false
    state.connection_attempts = 0
    state.incoming_buffer = ""
    state.last_activity = vim.uv.now()

    logger.socket("info", "Socket connection established")

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
  end)
end

-- Public API functions

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})
  
  if user_config and user_config.socket_path then
    state.socket_path = user_config.socket_path
  end
end

function M.connect(socket_path)
  if socket_path then
    state.socket_path = socket_path
  end
  create_connection()
end

function M.disconnect()
  state.reconnect_scheduled = false

  if state.connected and state.socket then
    local disconnect_msg = create_message("disconnect", {})
    send_raw_message(disconnect_msg)
    vim.defer_fn(cleanup_connection, 100)
  else
    cleanup_connection()
  end

  state.message_queue = {}
  state.connection_attempts = 0
end

function M.send_context_update(context_data)
  local message = create_message("context_update", context_data)
  return send_raw_message(message)
end

function M.send_error(error_message)
  local message = create_message("error", { error = error_message })
  return send_raw_message(message)
end

function M.send_status(status_data)
  local message = create_message("status", status_data)
  return send_raw_message(message)
end

function M.send_ping()
  return send_ping()
end

function M.send_custom(msg_type, data)
  local message = create_message(msg_type, data)
  return send_raw_message(message)
end

-- Status and diagnostic functions

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
    queued_messages = #state.message_queue,
    connection_attempts = state.connection_attempts,
    last_activity = state.last_activity,
    reconnect_scheduled = state.reconnect_scheduled,
    max_connection_attempts = config.max_connection_attempts,
    reconnect_delay = get_reconnect_delay(),
    connection_healthy = check_connection_health(),
  }
end

function M.get_socket_path()
  return state.socket_path
end

function M.force_reconnect()
  cleanup_connection()
  state.connection_attempts = 0
  state.reconnect_scheduled = false
  create_connection()
end

function M.clear_queue()
  local queue_size = #state.message_queue
  state.message_queue = {}
  return queue_size
end

-- Test and diagnostic functions

function M.test_connection()
  if not state.connected then
    return false, "Not connected"
  end

  return M.send_ping()
end

function M.get_connection_health()
  local now = vim.uv.now()
  local health = {
    status = "unknown",
    connected = state.connected,
    connecting = state.connecting,
    socket_exists = vim.fn.filereadable(state.socket_path) == 1,
    queue_size = #state.message_queue,
    connection_attempts = state.connection_attempts,
    healthy = check_connection_health(),
  }

  if state.connected then
    health.status = health.healthy and "connected" or "stale"
    
    if state.last_activity > 0 then
      health.last_activity_age = now - state.last_activity
      health.activity_healthy = health.last_activity_age < config.activity_timeout
    end
  elseif state.connecting then
    health.status = "connecting"
  elseif state.reconnect_scheduled then
    health.status = "reconnecting"
  else
    health.status = "disconnected"
  end

  return health
end

function M.cleanup()
  M.disconnect()
end

-- Manual recovery functions
function M.check_and_recover()
  if state.connected and not check_connection_health() then
    logger.socket("info", "Connection unhealthy, forcing reconnect")
    M.force_reconnect()
    return true
  end
  return false
end

function M.retry_failed_connection()
  if not state.connected and not state.connecting and not state.reconnect_scheduled then
    logger.socket("info", "Manual retry triggered")
    state.connection_attempts = math.max(0, state.connection_attempts - 1) -- Give it another chance
    schedule_reconnect_attempt()
    return true
  end
  return false
end

-- Reset function for testing
function M.reset()
  M.disconnect()
  state.connection_attempts = 0
  state.last_activity = 0
  state.reconnect_scheduled = false
end

-- Auto-connect on first use
function M.ensure_connected()
  if not state.connected and not state.connecting then
    create_connection()
  end
end

return M
