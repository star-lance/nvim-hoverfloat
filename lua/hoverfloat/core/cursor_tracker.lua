-- lua/hoverfloat/core/cursor_tracker.lua - Focused ONLY on cursor tracking
local M = {}

local position = require('hoverfloat.core.position')
local performance = require('hoverfloat.core.performance')
local socket_client = require('hoverfloat.communication.socket_client')
local cache = require('hoverfloat.prefetch.cache')
local lsp_service = require('hoverfloat.core.lsp_service')
local buffer = require('hoverfloat.utils.buffer')
local logger = require('hoverfloat.utils.logger')

-- Tracker state - focused on cursor tracking only  
local state = {
  last_sent_position = nil,
  tracking_enabled = false,
  update_debounce_timer = nil,
  debounce_delay = 20, -- Optimized debounce delay (guide.md suggests 50ms, but 20ms works well for local LSP)
}

-- Check if context should be updated based on current conditions
local function should_update_context()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Skip if tracking is disabled
  if not state.tracking_enabled then
    return false
  end

  -- Skip if socket is not connected
  if not socket_client.is_connected() then
    return false
  end

  -- Skip if buffer is not suitable for LSP
  if not buffer.is_suitable_for_lsp(bufnr) then
    return false
  end

  return true
end

-- Get position identifier for deduplication
local function get_position_identifier()
  return position.get_position_identifier()
end

-- Cancel any pending debounced update
local function cancel_pending_update()
  if state.update_debounce_timer then
    if not state.update_debounce_timer:is_closing() then
      state.update_debounce_timer:stop()
      state.update_debounce_timer:close()
    end
    state.update_debounce_timer = nil
  end
end

-- Core context update function - focused responsibility
local function perform_context_update()
  if not should_update_context() then
    return
  end

  local current_position = get_position_identifier()
  if current_position == state.last_sent_position then
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
      socket_client.send_context_update(formatted_data)

      logger.debug("CursorTracker", string.format("Cache hit: %.2fμs", response_time))
      return
    end
  end

  -- Cache miss - fallback to LSP
  local bufnr = vim.api.nvim_get_current_buf()
  local context = position.get_current_context()

  lsp_service.gather_all_context(bufnr, context.line, context.col, nil, function(lsp_data)
    if lsp_data then
      local response_time = performance.complete_request(start_time, false, true)
      state.last_sent_position = current_position
      socket_client.send_context_update(lsp_data)

      logger.debug("CursorTracker", string.format("LSP response: %.2fms", response_time))
    else
      performance.complete_request(start_time, false, false)
      logger.debug("CursorTracker", "No LSP data available for position: " .. current_position)
    end
  end)
end

-- Optimized debounced update using vim.uv.new_timer for better performance (guide.md recommendation)
local function schedule_context_update()
  cancel_pending_update()

  -- Use vim.uv.new_timer for more efficient timing than vim.defer_fn
  state.update_debounce_timer = vim.uv.new_timer()
  if state.update_debounce_timer then
    state.update_debounce_timer:start(state.debounce_delay, 0, vim.schedule_wrap(function()
      if state.update_debounce_timer then
        state.update_debounce_timer:close()
        state.update_debounce_timer = nil
      end
      perform_context_update()
    end))
  end
end

-- Handle cursor movement events
local function on_cursor_moved()
  if should_update_context() then
    schedule_context_update()
  end
end

-- Handle buffer enter events
local function on_buffer_enter()
  local bufnr = vim.api.nvim_get_current_buf()
  if buffer.has_lsp_clients(bufnr) and socket_client.is_connected() then
    -- Small delay to let buffer settle
    vim.defer_fn(perform_context_update, 100)
  end
end

-- Handle LSP attach events
local function on_lsp_attach()
  if socket_client.is_connected() then
    -- Delay to let LSP settle
    vim.defer_fn(perform_context_update, 500)
  end
end

-- Setup cursor tracking autocmds
function M.setup_tracking()
  local group = vim.api.nvim_create_augroup("HoverFloatCursorTracker", { clear = true })

  -- Track cursor movement with debouncing
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = on_cursor_moved,
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

  logger.info("CursorTracker", "Cursor tracking autocmds registered")
end

-- Enable cursor tracking
function M.enable()
  state.tracking_enabled = true
  logger.info("CursorTracker", "Cursor tracking enabled")

  -- Trigger immediate update if conditions are met
  if socket_client.is_connected() then
    vim.defer_fn(perform_context_update, 100)
  end
end

-- Disable cursor tracking
function M.disable()
  state.tracking_enabled = false
  cancel_pending_update()
  logger.info("CursorTracker", "Cursor tracking disabled")
end

-- Check if tracking is enabled
function M.is_tracking_enabled()
  return state.tracking_enabled
end

-- Force immediate context update (bypassing debounce)
function M.force_update()
  cancel_pending_update()
  perform_context_update()
end

-- Clear position cache (useful when switching contexts)
function M.clear_position_cache()
  state.last_sent_position = nil
  logger.debug("CursorTracker", "Position cache cleared")
end

-- Set debounce delay for updates
function M.set_debounce_delay(delay_ms)
  state.debounce_delay = delay_ms
  logger.debug("CursorTracker", "Debounce delay set to: " .. delay_ms .. "ms")
end

-- Get tracking statistics
function M.get_stats()
  return {
    tracking_enabled = state.tracking_enabled,
    last_sent_position = state.last_sent_position,
    debounce_delay = state.debounce_delay,
    has_pending_update = state.update_debounce_timer ~= nil,
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
