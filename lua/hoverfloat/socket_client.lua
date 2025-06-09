-- lua/hoverfloat/socket_client.lua - Unix socket communication
local M = {}
local uv = vim.uv or vim.loop

local state = {
  socket_path = "/tmp/nvim_context.sock",
  connection_attempts = 0,
  max_connection_attempts = 5,
  retry_delay = 1000,
}

local config = {
  connect_timeout = 5000, -- 5 seconds
  write_timeout = 1000,   -- 1 second
}

local function create_message(msg_type, data)
  local message = {
    type = msg_type,
    timestamp = vim.uv.now(),
    data = data or {}
  }
  local json_str = vim.json.encode(message)
  return json_str
end

local function send_raw(msg_type, data, callback)
  callback = callback or function() end

  local json_message = create_message(msg_type, data)

  local socket = uv.new_pipe(false)
  if not socket then
    callback(false, "Failed to create socket")
    return false
  end

  -- Set up timeout that gets cancelled on success
  local timeout_timer = vim.fn.timer_start(5000, function()
    socket:close()
    callback(false, "Connection timeout")
  end)

  socket:connect(state.socket_path, function(err)
    if err then
      vim.schedule(function()
        vim.fn.timer_stop(timeout_timer)
      end)
      socket:close()
      callback(false, "Connection failed: " .. err)
      return
    end

    socket:write(json_message, function(write_err)
      vim.schedule(function()
        vim.fn.timer_stop(timeout_timer)
      end)
      if write_err then
        socket:close()
        callback(false, "Write failed: " .. write_err)
      else
        socket:close()
        callback(true, "Success")
      end
    end)
  end)
  return true
end

function M.set_socket_path(socket_path)
  if socket_path then
    state.socket_path = socket_path
  end
  return true
end

function M.clear_socket_path()
  state.socket_path = nil
end

function M.send_context_update(context_data)
  return send_raw("context_update", context_data)
end

function M.send_error(error_message)
  local data = { error = error_message }
  return send_raw("error", data)
end

function M.send_status(status_data)
  return send_raw("status", status_data)
end

function M.send_ping()
  local data = { timestamp = vim.uv.now() }
  return send_raw("ping", data)
end

function M.send_custom(msg_type, data)
  return send_raw(msg_type, data)
end

function M.is_ready()
  return state.socket_path ~= nil
end

function M.get_status()
  return {
    socket_path = state.socket_path,
    ready = state.socket_path ~= nil,
    connection_attempts = state.connection_attempts,
    max_attempts = state.max_connection_attempts,
  }
end

function M.get_socket_path()
  return state.socket_path
end

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})
  if user_config and user_config.socket_path then
    state.socket_path = user_config.socket_path
  end
end

function M.test_connection()
  if not state.socket_path then
    return false
  end
  return M.send_ping()
end

function M.cleanup()
  M.clear_socket_path()
end

function M.reset()
  M.clear_socket_path()
  state.connection_attempts = 0
end

return M