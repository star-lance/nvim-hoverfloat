local M = {}
local uv = vim.uv or vim.loop

-- Connection state
local state = {
  socket_path = "/tmp/nvim_context.sock",
  socket = nil,
  connected = false,
  connecting = false,
  message_queue = {},
  incoming_buffer = "",
}

-- Configuration
local config = {
  connection_timeout = 5000,    -- 5 seconds
  max_queue_size = 100,         -- Maximum queued messages
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
end

local function handle_connection_failure(reason)
  logger.socket("error", "Connection failed", { reason = reason })
  cleanup_connection()
end


local function handle_message(json_str)
  local ok, message = pcall(vim.json.decode, json_str)
  if not ok then
    logger.socket("error", "Message parse error", { error = message })
    return
  end
  
  if message.type == "error" then
    logger.socket("error", "TUI reported error", message.data and message.data.error or "Unknown error")
  elseif message.type == "pong" then
    logger.socket("debug", "Received pong")
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
    -- Queue message and attempt connection
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
      -- Retry connection immediately on write failure
      if not state.connecting then
        create_connection()
      end
    end
  end)

  if not ok then
    handle_connection_failure("Socket write failed")
    -- Retry connection immediately on write failure
    if not state.connecting then
      create_connection()
    end
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


function create_connection()
  if state.connecting or state.connected then
    return
  end

  logger.socket("info", "Starting connection attempt")
  state.connecting = true

  local socket = uv.new_pipe(false)
  if not socket then
    handle_connection_failure("Failed to create socket")
    return
  end

  local connection_completed = false

  -- Use vim.defer_fn for timeout
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
    state.incoming_buffer = ""

    logger.socket("info", "Socket connection established")

    socket:read_start(function(read_err, data)
      if read_err then
        handle_connection_failure("Read error: " .. read_err)
        -- Attempt immediate reconnection on read error
        if not state.connecting then
          create_connection()
        end
        return
      end

      if data then
        handle_incoming_data(data)
      else
        handle_connection_failure("Connection closed by server")
        -- Attempt immediate reconnection when server closes
        if not state.connecting then
          create_connection()
        end
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
  if state.connected and state.socket then
    local disconnect_msg = create_message("disconnect", {})
    send_raw_message(disconnect_msg)
    vim.defer_fn(cleanup_connection, 100)
  else
    cleanup_connection()
  end

  state.message_queue = {}
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
  if not state.connected then
    return false
  end
  
  local ping_msg = create_message("ping", { timestamp = vim.uv.now() })
  return send_raw_message(ping_msg)
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
  }
end

function M.get_socket_path()
  return state.socket_path
end

function M.force_reconnect()
  cleanup_connection()
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
  local health = {
    connected = state.connected,
    connecting = state.connecting,
    socket_exists = vim.fn.filereadable(state.socket_path) == 1,
    queue_size = #state.message_queue,
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

function M.cleanup()
  M.disconnect()
end

-- Manual recovery functions
function M.check_and_recover()
  if not state.connected and not state.connecting then
    logger.socket("info", "Manual recovery triggered")
    create_connection()
    return true
  end
  return false
end

function M.retry_failed_connection()
  if not state.connected and not state.connecting then
    logger.socket("info", "Manual retry triggered")
    create_connection()
    return true
  end
  return false
end

-- Reset function for testing
function M.reset()
  M.disconnect()
end

-- Auto-connect on first use
function M.ensure_connected()
  if not state.connected and not state.connecting then
    create_connection()
  end
end

return M
