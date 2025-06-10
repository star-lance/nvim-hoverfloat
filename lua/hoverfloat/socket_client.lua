local M = {}
local uv = vim.uv or vim.loop

-- Connection state
local state = {
  socket_path = "/tmp/nvim_context.sock",
  socket = nil,
  connected = false,
  connecting = false,
  reconnect_timer = nil,
  heartbeat_timer = nil,
  connection_check_timer = nil,
  message_queue = {},
  last_heartbeat_sent = 0,
  last_heartbeat_received = 0,
  connection_attempts = 0,
  incoming_buffer = "",
}

-- Configuration
local config = {
  reconnect_delay = 2000,       -- 2 seconds initial delay
  max_reconnect_delay = 30000,  -- 30 seconds max delay
  heartbeat_interval = 10000,   -- 10 seconds
  connection_timeout = 5000,    -- 5 seconds
  heartbeat_timeout = 30000,    -- 30 seconds before considering connection dead
  max_queue_size = 100,         -- Maximum queued messages
  max_connection_attempts = 10, -- Max attempts before giving up
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

  if state.heartbeat_timer then
    vim.fn.timer_stop(state.heartbeat_timer)
    state.heartbeat_timer = nil
  end

  if state.connection_check_timer then
    vim.fn.timer_stop(state.connection_check_timer)
    state.connection_check_timer = nil
  end
end

local function handle_connection_failure(reason)
  if reason:match("Connection timeout") and state.connected then
    return  -- Ignore spurious timeouts
  end

  logger.socket("error", "Connection failed", { reason = reason, attempt = state.connection_attempts + 1 })
  cleanup_connection()
  state.connection_attempts = state.connection_attempts + 1

  if state.connection_attempts < config.max_connection_attempts then
    schedule_reconnect()
  end
end

function schedule_reconnect()
  if state.reconnect_timer then
    vim.fn.timer_stop(state.reconnect_timer)
  end

  local delay = get_reconnect_delay()
  logger.socket("info", "Scheduling reconnection", { delay_ms = delay })

  state.reconnect_timer = vim.fn.timer_start(delay, function()
    state.reconnect_timer = nil
    create_connection()
  end)
end

local function handle_message(json_str)
  local ok, message = pcall(vim.json.decode, json_str)
  if not ok then
    logger.socket("error", "Message parse error", { error = message })
    return
  end

  if message.type == "pong" then
    state.last_heartbeat_received = vim.uv.now()
  elseif message.type == "error" then
    logger.socket("error", "TUI reported error", message.data and message.data.error or "Unknown error")
  end
end

-- Handle incoming data from socket
local function handle_incoming_data(data)
  if not data then return end

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
  if not state.connected or not state.socket then
    if #state.message_queue < config.max_queue_size then
      table.insert(state.message_queue, json_message)
    end
    if not state.connecting then
      create_connection()
    end
    return false
  end

  local ok = state.socket:write(json_message, function(err)
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

local function start_heartbeat()
  if state.heartbeat_timer then
    vim.fn.timer_stop(state.heartbeat_timer)
  end

  state.heartbeat_timer = vim.fn.timer_start(config.heartbeat_interval, function()
    if not state.connected then
      return
    end

    local now = vim.uv.now()
    if state.last_heartbeat_received > 0 and (now - state.last_heartbeat_received) > config.heartbeat_timeout then
      handle_connection_failure("Heartbeat timeout")
      return
    end

    local ping_msg = create_message("ping", { timestamp = now })
    if send_raw_message(ping_msg) then
      state.last_heartbeat_sent = now
    end
  end, { ['repeat'] = -1 })
end

local function stop_heartbeat()
  if state.heartbeat_timer then
    vim.fn.timer_stop(state.heartbeat_timer)
    state.heartbeat_timer = nil
  end
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

  local timeout_timer = nil
  local connection_completed = false

  timeout_timer = vim.fn.timer_start(config.connection_timeout, function()
    if not connection_completed then
      connection_completed = true
      if socket and not socket:is_closing() then
        socket:close()
      end
      state.connecting = false
      handle_connection_failure("Connection timeout")
    end
  end)

  socket:connect(state.socket_path, function(err)
    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
    end
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

    start_heartbeat()
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
  if state.reconnect_timer then
    vim.fn.timer_stop(state.reconnect_timer)
    state.reconnect_timer = nil
  end

  stop_heartbeat()

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
  local message = create_message("ping", { timestamp = vim.uv.now() })
  return send_raw_message(message)
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
    last_heartbeat_sent = state.last_heartbeat_sent,
    last_heartbeat_received = state.last_heartbeat_received,
    max_connection_attempts = config.max_connection_attempts,
    reconnect_delay = get_reconnect_delay(),
  }
end

function M.get_socket_path()
  return state.socket_path
end

function M.force_reconnect()
  cleanup_connection()
  state.connection_attempts = 0
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
  }

  if state.connected then
    health.status = "connected"

    if state.last_heartbeat_received > 0 then
      health.last_heartbeat_age = now - state.last_heartbeat_received
      health.heartbeat_healthy = health.last_heartbeat_age < config.heartbeat_timeout
    end
  elseif state.connecting then
    health.status = "connecting"
  else
    health.status = "disconnected"
  end

  return health
end

function M.cleanup()
  M.disconnect()
end

-- Reset function for testing
function M.reset()
  M.disconnect()
  state.connection_attempts = 0
  state.last_heartbeat_sent = 0
  state.last_heartbeat_received = 0
end

-- Auto-connect on first use
function M.ensure_connected()
  if not state.connected and not state.connecting then
    create_connection()
  end
end

return M
