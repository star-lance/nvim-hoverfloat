-- lua/hoverfloat/communication/message_handler.lua - Message formatting and processing
local M = {}

-- Message creation helpers
function M.create_message(msg_type, data)
  local message = {
    type = msg_type,
    timestamp = vim.uv.now(),
    data = data or {}
  }
  return vim.json.encode(message) .. '\n'
end

-- Create specific message types
function M.create_context_update(context_data)
  return M.create_message("context_update", context_data)
end

-- Fast binary cursor update for position-only changes (guide.md optimization)
function M.create_fast_cursor_update(file, line, col)
  -- For high-frequency cursor updates, use compact format
  -- Still JSON for compatibility, but minimal data
  local compact_data = {
    f = file,       -- shorter keys reduce size
    l = line,
    c = col,
    t = vim.uv.now()
  }
  return M.create_message("cursor_pos", compact_data)
end

function M.create_error_message(error_text, details)
  return M.create_message("error", {
    error = error_text,
    details = details
  })
end

function M.create_status_message(status_data)
  return M.create_message("status", status_data)
end

function M.create_ping_message()
  return M.create_message("ping", {
    timestamp = vim.uv.now()
  })
end

function M.create_disconnect_message(reason)
  return M.create_message("disconnect", {
    reason = reason or "client_disconnect",
    timestamp = vim.uv.now()
  })
end

-- Message validation
local function is_valid_message_type(msg_type)
  local valid_types = {
    "context_update",
    "cursor_pos",    -- Fast cursor position updates
    "ping",
    "pong", 
    "error",
    "status",
    "disconnect"
  }
  return vim.tbl_contains(valid_types, msg_type)
end

function M.validate_message(message_data)
  local ok, message = pcall(vim.json.decode, message_data)
  if not ok then
    return false, "Invalid JSON"
  end

  if not message.type or not is_valid_message_type(message.type) then
    return false, "Invalid message type"
  end

  if not message.timestamp or type(message.timestamp) ~= "number" then
    return false, "Missing or invalid timestamp"
  end

  return true, message
end

-- Message parsing for incoming data
function M.parse_incoming_data(data_buffer)
  local messages = {}
  local remaining = data_buffer

  while true do
    local newline_pos = remaining:find('\n')
    if not newline_pos then
      break
    end

    local line = remaining:sub(1, newline_pos - 1)
    remaining = remaining:sub(newline_pos + 1)

    if line ~= "" then
      local valid, message = M.validate_message(line)
      if valid then
        table.insert(messages, message)
      end
    end
  end

  return messages, remaining
end

-- Message queuing for outbound data
local MessageQueue = {}
MessageQueue.__index = MessageQueue

function MessageQueue.new(max_size)
  return setmetatable({
    queue = {},
    max_size = max_size or 100
  }, MessageQueue)
end

function MessageQueue:add(message)
  -- Add to queue
  table.insert(self.queue, message)

  -- Enforce size limit using more efficient approach
  if #self.queue > self.max_size then
    -- Replace old queue with trimmed version (O(n) once vs O(n²))
    local new_queue = {}
    local start_idx = #self.queue - self.max_size + 1
    for i = start_idx, #self.queue do
      table.insert(new_queue, self.queue[i])
    end
    self.queue = new_queue
  end
end

function MessageQueue:get_all()
  local messages = vim.deepcopy(self.queue)
  self.queue = {}
  return messages
end

function MessageQueue:size()
  return #self.queue
end

function MessageQueue:clear()
  self.queue = {}
end

M.MessageQueue = MessageQueue

-- Rate limiting for message sending
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(max_per_second, window_ms)
  return setmetatable({
    max_per_second = max_per_second or 10,
    window_ms = window_ms or 1000,
    timestamps = {}
  }, RateLimiter)
end

function RateLimiter:check_limit()
  local now = vim.uv.now()
  local cutoff = now - self.window_ms

  -- Remove old timestamps
  local filtered = {}
  for _, timestamp in ipairs(self.timestamps) do
    if timestamp > cutoff then
      table.insert(filtered, timestamp)
    end
  end
  self.timestamps = filtered

  -- Check if we're within limit
  if #self.timestamps >= self.max_per_second then
    return false
  end

  -- Add current timestamp
  table.insert(self.timestamps, now)
  return true
end

M.RateLimiter = RateLimiter

-- Message batching for efficiency
local MessageBatcher = {}
MessageBatcher.__index = MessageBatcher

function MessageBatcher.new(batch_size, flush_interval_ms)
  local batcher = setmetatable({
    batch_size = batch_size or 5,
    flush_interval_ms = flush_interval_ms or 100,
    pending_messages = {},
    flush_timer = nil,
    flush_callback = nil
  }, MessageBatcher)

  return batcher
end

function MessageBatcher:add_message(message, callback)
  table.insert(self.pending_messages, message)

  if not self.flush_callback then
    self.flush_callback = callback
  end

  -- Flush if batch is full
  if #self.pending_messages >= self.batch_size then
    self:flush()
    return
  end

  -- Start flush timer if not already running
  if not self.flush_timer then
    self.flush_timer = vim.defer_fn(function()
      self:flush()
    end, self.flush_interval_ms)
  end
end

function MessageBatcher:flush()
  if #self.pending_messages == 0 then
    return
  end

  local messages = self.pending_messages
  local callback = self.flush_callback

  -- Clear state
  self.pending_messages = {}
  self.flush_callback = nil
  if self.flush_timer then
    self.flush_timer = nil
  end

  -- Send batch
  if callback then
    callback(messages)
  end
end

M.MessageBatcher = MessageBatcher

return M
