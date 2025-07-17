-- lua/hoverfloat/core/cursor_tracker.lua - Enhanced for better responsiveness
local M = {}

local position = require('hoverfloat.core.position')
local performance = require('hoverfloat.core.performance')
local socket_client = require('hoverfloat.communication.socket_client')
local cache = require('hoverfloat.prefetch.cache')
local lsp_service = require('hoverfloat.core.lsp_service')
local buffer = require('hoverfloat.utils.buffer')
local logger = require('hoverfloat.utils.logger')

-- Tracker state with optimized defaults
local state = {
  last_sent_position = nil,
  tracking_enabled = false,
  update_timer = nil,
  debounce_delay = 20, -- Reduced from 20ms for better responsiveness
  last_cursor_time = 0,
  pending_update = false,
  consecutive_moves = 0,
  adaptive_delay = 10, -- Adaptive delay based on movement patterns
}

-- Movement patterns for adaptive delay
local MOVEMENT_THRESHOLD = 3 -- Consecutive moves to trigger fast mode
local FAST_DELAY = 5         -- Ultra-responsive for continuous movement
local NORMAL_DELAY = 10      -- Standard responsiveness
local SLOW_DELAY = 50        -- For minimal movement

-- Check if context should be updated
local function should_update_context()
  local bufnr = vim.api.nvim_get_current_buf()

  if not state.tracking_enabled then
    return false
  end

  if not socket_client.is_connected() then
    return false
  end

  if not buffer.is_suitable_for_lsp(bufnr) then
    return false
  end

  return true
end

-- Get position identifier for deduplication
local function get_position_identifier()
  return position.get_position_identifier()
end

-- Cancel any pending update
local function cancel_pending_update()
  if state.update_timer then
    state.update_timer:stop()
    state.update_timer:close()
    state.update_timer = nil
    state.pending_update = false
  end
end

-- Send fast cursor position update (no LSP data)
local function send_cursor_position_update()
  local context = position.get_current_context()

  -- Send minimal cursor position update for immediate feedback
  local cursor_data = {
    file = context.file,
    line = context.line,
    col = context.col,
    timestamp = vim.uv.now(),
    cursor_only = true, -- Flag to indicate position-only update
  }

  socket_client.send_context_update(cursor_data)
end

-- Core context update function
local function perform_context_update()
  if not should_update_context() then
    state.pending_update = false
    return
  end

  local current_position = get_position_identifier()
  if current_position == state.last_sent_position then
    state.pending_update = false
    return
  end

  local start_time = performance.start_request()

  -- Try cache first for instant response
  local cached_data = cache.get_cursor_data()
  if cached_data then
    local current_pos = position.get_current_context()
    local formatted_data = cache.format_for_socket(cached_data, current_pos)

    if formatted_data then
      local response_time = performance.complete_request(start_time, true, false)
      state.last_sent_position = current_position
      state.pending_update = false
      socket_client.send_context_update(formatted_data)

      logger.debug("CursorTracker", string.format("Cache hit: %.2fμs", response_time))
      return
    end
  end

  -- Send immediate cursor position while we fetch LSP data
  send_cursor_position_update()

  -- Cache miss - fetch from LSP asynchronously
  local bufnr = vim.api.nvim_get_current_buf()
  local context = position.get_current_context()

  lsp_service.gather_all_context(bufnr, context.line, context.col, nil, function(lsp_data)
    if lsp_data then
      local response_time = performance.complete_request(start_time, false, true)
      state.last_sent_position = current_position
      state.pending_update = false
      socket_client.send_context_update(lsp_data)

      logger.debug("CursorTracker", string.format("LSP response: %.2fms", response_time))
    else
      performance.complete_request(start_time, false, false)
      state.pending_update = false
      logger.debug("CursorTracker", "No LSP data available for position: " .. current_position)
    end
  end)
end

-- Adaptive delay calculation based on movement patterns
local function calculate_adaptive_delay()
  local current_time = vim.uv.now()
  local time_since_last = current_time - state.last_cursor_time

  -- If moving rapidly, use fast delay
  if time_since_last < 100 and state.consecutive_moves > MOVEMENT_THRESHOLD then
    return FAST_DELAY
    -- If moving steadily, use normal delay
  elseif time_since_last < 500 then
    return NORMAL_DELAY
    -- If movement is sparse, use slow delay
  else
    return SLOW_DELAY
  end
end

-- Schedule context update with adaptive timing
local function schedule_context_update()
  cancel_pending_update()

  state.pending_update = true
  state.consecutive_moves = state.consecutive_moves + 1

  -- Calculate adaptive delay
  local delay = calculate_adaptive_delay()
  state.adaptive_delay = delay

  -- Use high-precision timer for better responsiveness
  state.update_timer = vim.uv.new_timer()
  if state.update_timer then
    state.update_timer:start(delay, 0, vim.schedule_wrap(function()
      if state.update_timer then
        state.update_timer:close()
        state.update_timer = nil
      end
      state.consecutive_moves = 0 -- Reset consecutive move counter
      perform_context_update()
    end))
  end

  state.last_cursor_time = vim.uv.now()
end

-- Handle cursor movement events
local function on_cursor_moved()
  if should_update_context() then
    -- Send immediate cursor position for responsiveness
    if state.consecutive_moves == 0 then
      send_cursor_position_update()
    end

    schedule_context_update()
  end
end

-- Handle cursor hold (stopped moving)
local function on_cursor_hold()
  -- If there's a pending update, execute it immediately
  if state.pending_update then
    cancel_pending_update()
    perform_context_update()
  end

  -- Reset movement tracking
  state.consecutive_moves = 0
  state.adaptive_delay = NORMAL_DELAY
end

-- Handle buffer enter events
local function on_buffer_enter()
  local bufnr = vim.api.nvim_get_current_buf()
  if buffer.has_lsp_clients(bufnr) and socket_client.is_connected() then
    -- Immediate update on buffer entry
    vim.defer_fn(perform_context_update, 50)
  end
end

-- Handle LSP attach events
local function on_lsp_attach()
  if socket_client.is_connected() then
    -- Update after LSP is ready
    vim.defer_fn(perform_context_update, 200)
  end
end

-- Handle text changes (clear cache and update)
local function on_text_changed()
  -- Clear position cache as content changed
  state.last_sent_position = nil

  -- Schedule update with slightly longer delay for text changes
  if should_update_context() then
    vim.defer_fn(perform_context_update, 100)
  end
end

-- Setup cursor tracking autocmds
function M.setup_tracking()
  local group = vim.api.nvim_create_augroup("HoverFloatCursorTracker", { clear = true })

  -- Track cursor movement with high responsiveness
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = on_cursor_moved,
  })

  -- Track when cursor stops moving
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = group,
    callback = on_cursor_hold,
  })

  -- Update on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = on_buffer_enter,
  })

  -- Update when LSP attaches
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = on_lsp_attach,
  })

  -- Handle text changes
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = on_text_changed,
  })

  -- Set shorter updatetime for better CursorHold responsiveness
  vim.opt.updatetime = 100

  logger.info("CursorTracker", "Enhanced cursor tracking enabled")
end

-- Enable cursor tracking
function M.enable()
  state.tracking_enabled = true
  state.consecutive_moves = 0
  state.adaptive_delay = NORMAL_DELAY
  logger.info("CursorTracker", "Cursor tracking enabled")

  -- Trigger immediate update if conditions are met
  if socket_client.is_connected() then
    vim.defer_fn(perform_context_update, 50)
  end
end

-- Disable cursor tracking
function M.disable()
  state.tracking_enabled = false
  cancel_pending_update()
  state.consecutive_moves = 0
  logger.info("CursorTracker", "Cursor tracking disabled")
end

-- Check if tracking is enabled
function M.is_tracking_enabled()
  return state.tracking_enabled
end

-- Force immediate context update
function M.force_update()
  cancel_pending_update()
  state.consecutive_moves = 0
  perform_context_update()
end

-- Clear position cache
function M.clear_position_cache()
  state.last_sent_position = nil
  logger.debug("CursorTracker", "Position cache cleared")
end

-- Set debounce delay
function M.set_debounce_delay(delay_ms)
  state.debounce_delay = delay_ms
  logger.debug("CursorTracker", "Base debounce delay set to: " .. delay_ms .. "ms")
end

-- Get tracking statistics
function M.get_stats()
  return {
    tracking_enabled = state.tracking_enabled,
    last_sent_position = state.last_sent_position,
    debounce_delay = state.debounce_delay,
    adaptive_delay = state.adaptive_delay,
    has_pending_update = state.pending_update,
    consecutive_moves = state.consecutive_moves,
    socket_connected = socket_client.is_connected(),
  }
end

-- Cleanup on plugin shutdown
function M.cleanup()
  M.disable()
  cancel_pending_update()
  logger.debug("CursorTracker", "Cleanup completed")
end

return M
