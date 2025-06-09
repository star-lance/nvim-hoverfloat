-- lua/hoverfloat/socket_client.lua - Persistent connection version with fast event fixes
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

-- Enhanced logging functions
local function log_connection_event(event, details)
  local timestamp = os.date("%H:%M:%S")
  local log_msg = string.format("[HoverFloat Socket %s] %s", timestamp, event)
  if details then
    log_msg = log_msg .. ": " .. (type(details) == "table" and vim.inspect(details) or tostring(details))
  end
  
  vim.schedule(function()
    if config.debug then
      vim.notify(log_msg, vim.log.levels.DEBUG)
    end
  end)
end

local function log_error(event, details)
  local timestamp = os.date("%H:%M:%S")
  local log_msg = string.format("[HoverFloat Socket %s] ERROR: %s", timestamp, event)
  if details then
    log_msg = log_msg .. ": " .. (type(details) == "table" and vim.inspect(details) or tostring(details))
  end
  
  vim.schedule(function()
    vim.notify(log_msg, vim.log.levels.ERROR)
  end)
end

local function log_warn(event, details)
  local timestamp = os.date("%H:%M:%S")
  local log_msg = string.format("[HoverFloat Socket %s] WARN: %s", timestamp, event)
  if details then
    log_msg = log_msg .. ": " .. (type(details) == "table" and vim.inspect(details) or tostring(details))
  end
  
  vim.schedule(function()
    vim.notify(log_msg, vim.log.levels.WARN)
  end)
end

local function log_info(event, details)
  local timestamp = os.date("%H:%M:%S")
  local log_msg = string.format("[HoverFloat Socket %s] %s", timestamp, event)
  if details then
    log_msg = log_msg .. ": " .. (type(details) == "table" and vim.inspect(details) or tostring(details))
  end
  
  vim.schedule(function()
    vim.notify(log_msg, vim.log.levels.INFO)
  end)
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

  -- Stop timers (schedule to avoid fast event context issues)
  if state.heartbeat_timer then
    local timer_to_stop = state.heartbeat_timer
    vim.schedule(function()
      if timer_to_stop then
        vim.fn.timer_stop(timer_to_stop)
      end
    end)
    state.heartbeat_timer = nil
  end

  if state.connection_check_timer then
    local timer_to_stop = state.connection_check_timer
    vim.schedule(function()
      if timer_to_stop then
        vim.fn.timer_stop(timer_to_stop)
      end
    end)
    state.connection_check_timer = nil
  end
end

-- Handle connection failure
local function handle_connection_failure(reason)
  log_error("Connection failed", {
    reason = reason,
    attempt = state.connection_attempts + 1,
    max_attempts = config.max_connection_attempts,
    socket_path = state.socket_path
  })
  cleanup_connection()

  state.connection_attempts = state.connection_attempts + 1

  if state.connection_attempts >= config.max_connection_attempts then
    log_error("Max connection attempts reached", {
      attempts = state.connection_attempts,
      giving_up = true
    })
    vim.schedule(function()
      vim.notify("HoverFloat: Max connection attempts reached. Stopping reconnection.", vim.log.levels.ERROR)
    end)
    return
  end

  schedule_reconnect()
end

-- Schedule reconnection attempt
function schedule_reconnect()
  if state.reconnect_timer then
    vim.schedule(function()
      if state.reconnect_timer then
        vim.fn.timer_stop(state.reconnect_timer)
      end
    end)
  end

  local delay = get_reconnect_delay()
  log_info("Scheduling reconnection", {
    delay_ms = delay,
    attempt = state.connection_attempts + 1,
    max_attempts = config.max_connection_attempts
  })

  vim.schedule(function()
    state.reconnect_timer = vim.fn.timer_start(delay, function()
      state.reconnect_timer = nil
      create_connection()
    end)
  end)
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

-- Handle parsed message
local function handle_message(json_str)
  local ok, message = pcall(vim.json.decode, json_str)
  if not ok then
    log_error("Message parse error", {
      error = message,
      json_preview = json_str:sub(1, 100) .. (json_str:len() > 100 and "..." or "")
    })
    return
  end

  log_connection_event("Received message", {
    type = message.type,
    timestamp = message.timestamp,
    has_data = message.data ~= nil
  })

  -- Handle different message types
  if message.type == "pong" then
    state.last_heartbeat_received = vim.uv.now()
    local latency = state.last_heartbeat_received - state.last_heartbeat_sent
    log_connection_event("Heartbeat pong received", {
      latency_ms = latency,
      client_timestamp = message.client_timestamp
    })
  elseif message.type == "error" then
    local error_msg = "Unknown error"
    if message.data and message.data.error then
      error_msg = message.data.error
    end
    log_error("TUI reported error", error_msg)
    vim.schedule(function()
      vim.notify("HoverFloat TUI Error: " .. error_msg, vim.log.levels.ERROR)
    end)
  elseif message.type == "status" then
    log_connection_event("Status update from TUI", message.data)
  else
    log_warn("Unknown message type received", message.type)
  end
end

-- Send message to TUI
local function send_raw_message(json_message)
  if not state.connected or not state.socket then
    -- Queue message for later
    if #state.message_queue < config.max_queue_size then
      table.insert(state.message_queue, json_message)
      log_connection_event("Message queued", {
        queue_size = #state.message_queue,
        max_size = config.max_queue_size,
        connected = state.connected
      })
    else
      log_warn("Message queue full, dropping message", {
        queue_size = #state.message_queue,
        max_size = config.max_queue_size
      })
    end

    -- Try to connect if not already connecting
    if not state.connecting then
      log_connection_event("Auto-connecting due to queued message")
      create_connection()
    end
    return false
  end

  -- Send immediately
  local ok = state.socket:write(json_message, function(err)
    if err then
      log_error("Socket write error", err)
      handle_connection_failure("Write failed: " .. err)
    else
      log_connection_event("Message sent successfully")
    end
  end)

  if not ok then
    log_error("Socket write failed immediately")
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

  local queue_size = #state.message_queue
  if queue_size == 0 then
    return
  end

  log_connection_event("Flushing queue", string.format("%d messages", queue_size))

  for _, queued_msg in ipairs(state.message_queue) do
    if not send_raw_message(queued_msg) then
      -- If sending fails, stop flushing
      break
    end
  end

  state.message_queue = {}
end

-- Start heartbeat mechanism
local function start_heartbeat()
  if state.heartbeat_timer then
    vim.schedule(function()
      if state.heartbeat_timer then
        vim.fn.timer_stop(state.heartbeat_timer)
      end
    end)
  end

  log_connection_event("Starting heartbeat", {
    interval_ms = config.heartbeat_interval,
    timeout_ms = config.heartbeat_timeout
  })

  -- Use vim.schedule to avoid fast event context issues
  vim.schedule(function()
    state.heartbeat_timer = vim.fn.timer_start(config.heartbeat_interval, function()
      if not state.connected then
        log_connection_event("Heartbeat skipped - not connected")
        return
      end

      -- Check if we've missed heartbeats
      local now = vim.uv.now()
      if state.last_heartbeat_received > 0 then
        local time_since_last_heartbeat = now - state.last_heartbeat_received
        if time_since_last_heartbeat > config.heartbeat_timeout then
          log_error("Heartbeat timeout detected", {
            timeout_ms = config.heartbeat_timeout,
            time_since_last_ms = time_since_last_heartbeat,
            last_sent = state.last_heartbeat_sent,
            last_received = state.last_heartbeat_received
          })
          handle_connection_failure("Heartbeat timeout")
          return
        end
      end

      -- Send ping
      local ping_msg = create_message("ping", { timestamp = now })
      if send_raw_message(ping_msg) then
        state.last_heartbeat_sent = now
        log_connection_event("Heartbeat ping sent", { timestamp = now })
      else
        log_warn("Failed to send heartbeat ping")
      end
    end, { ['repeat'] = -1 })
  end)
end

-- Stop heartbeat mechanism
local function stop_heartbeat()
  if state.heartbeat_timer then
    vim.schedule(function()
      if state.heartbeat_timer then
        vim.fn.timer_stop(state.heartbeat_timer)
        state.heartbeat_timer = nil
      end
    end)
  end
end

-- Create persistent connection
function create_connection()
  if state.connecting or state.connected then
    log_connection_event("Connection already in progress or established", {
      connecting = state.connecting,
      connected = state.connected
    })
    return
  end

  log_info("Starting connection attempt", {
    attempt = state.connection_attempts + 1,
    max_attempts = config.max_connection_attempts,
    socket_path = state.socket_path
  })
  
  state.connecting = true

  local socket = uv.new_pipe(false)
  if not socket then
    handle_connection_failure("Failed to create socket")
    return
  end

  -- Set up connection timeout using vim.schedule
  local timeout_timer
  vim.schedule(function()
    timeout_timer = vim.fn.timer_start(config.connection_timeout, function()
      log_error("Connection timeout", {
        timeout_ms = config.connection_timeout,
        attempt = state.connection_attempts + 1
      })
      if socket and not socket:is_closing() then
        socket:close()
      end
      state.connecting = false
      handle_connection_failure("Connection timeout")
    end)
  end)

  -- Attempt connection
  socket:connect(state.socket_path, function(err)
    -- Cancel timeout timer
    if timeout_timer then
      vim.schedule(function()
        vim.fn.timer_stop(timeout_timer)
      end)
    end

    if err then
      log_error("Connection failed", {
        error = err,
        socket_path = state.socket_path,
        attempt = state.connection_attempts + 1
      })
      socket:close()
      handle_connection_failure("Connection failed: " .. err)
      return
    end

    -- Connection successful!
    state.socket = socket
    state.connected = true
    state.connecting = false
    state.connection_attempts = 0 -- Reset attempts counter
    state.incoming_buffer = ""

    log_info("Socket connection established", {
      socket_path = state.socket_path,
      attempts_required = state.connection_attempts
    })

    -- Set up read handler
    socket:read_start(function(read_err, data)
      if read_err then
        log_error("Socket read error", read_err)
        handle_connection_failure("Read error: " .. read_err)
        return
      end

      if data then
        log_connection_event("Data received", {
          bytes = #data,
          preview = data:sub(1, 50) .. (data:len() > 50 and "..." or "")
        })
        handle_incoming_data(data)
      else
        -- EOF - connection closed by server
        log_warn("Connection closed by server", "EOF received")
        handle_connection_failure("Connection closed by server")
      end
    end)

    -- Start heartbeat
    start_heartbeat()

    -- Flush queued messages
    flush_message_queue()

    -- Notify user
    vim.schedule(function()
      vim.notify("HoverFloat: Connected to context window", vim.log.levels.INFO)
    end)
  end)
end

-- Public API functions

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})

  if user_config and user_config.socket_path then
    state.socket_path = user_config.socket_path
  end

  -- Enable debug logging if requested
  if user_config and user_config.debug then
    vim.g.hoverfloat_debug = true
  end

  log_connection_event("Setup", "Socket client configured")
end

function M.connect(socket_path)
  if socket_path then
    log_connection_event("Socket path updated", {
      old_path = state.socket_path,
      new_path = socket_path
    })
    state.socket_path = socket_path
  end

  log_info("Connection requested", { socket_path = state.socket_path })
  create_connection()
end

function M.disconnect()
  log_info("Disconnect requested")

  -- Cancel reconnection
  if state.reconnect_timer then
    vim.schedule(function()
      if state.reconnect_timer then
        vim.fn.timer_stop(state.reconnect_timer)
        state.reconnect_timer = nil
        log_connection_event("Reconnection timer cancelled")
      end
    end)
  end

  -- Stop heartbeat
  stop_heartbeat()

  -- Send clean disconnect message if connected
  if state.connected and state.socket then
    log_connection_event("Sending disconnect message to TUI")
    local disconnect_msg = create_message("disconnect", {})
    send_raw_message(disconnect_msg)

    -- Give it a moment to send, then close
    vim.defer_fn(function()
      cleanup_connection()
    end, 100)
  else
    cleanup_connection()
  end

  -- Clear message queue
  local queue_size = #state.message_queue
  state.message_queue = {}
  state.connection_attempts = 0

  log_info("Disconnected successfully", {
    cleared_queue_messages = queue_size,
    reset_attempts = true
  })

  vim.schedule(function()
    vim.notify("HoverFloat: Disconnected from context window", vim.log.levels.INFO)
  end)
end

function M.send_context_update(context_data)
  log_connection_event("Sending context update", {
    has_hover = context_data.hover and #context_data.hover > 0,
    has_definition = context_data.definition ~= nil,
    references_count = context_data.references_count or 0,
    connected = state.connected
  })
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
  log_connection_event("Force reconnect", "User requested")
  cleanup_connection()
  state.connection_attempts = 0 -- Reset attempts
  create_connection()
end

function M.clear_queue()
  local queue_size = #state.message_queue
  state.message_queue = {}
  log_connection_event("Queue cleared", string.format("Removed %d messages", queue_size))
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

-- Cleanup function
function M.cleanup()
  log_connection_event("Cleanup", "Shutting down socket client")
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
