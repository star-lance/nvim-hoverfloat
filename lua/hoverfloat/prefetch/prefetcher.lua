-- lua/hoverfloat/prefetch/prefetcher.lua - Updated with symbol utilities
local M = {}
local lsp_service = require('hoverfloat.core.lsp_service')
local cache = require('hoverfloat.prefetch.cache')
local position = require('hoverfloat.core.position')
local buffer = require('hoverfloat.utils.buffer')
local symbols = require('hoverfloat.utils.symbols')
local performance = require('hoverfloat.core.performance')
local logger = require('hoverfloat.utils.logger')

-- Prefetch configuration
local MAX_CONCURRENT_REQUESTS = 2
local PREFETCH_RADIUS_LINES = 30
local SYMBOL_UPDATE_DELAY_MS = 100
local DEFAULT_FEATURE_CONFIG = {
  show_hover = true,
  show_references = true,
  show_definition = true,
  show_type_info = true,
  max_references = 8,
}

-- Prefetcher state (symbols moved to symbols.lua)
local state = {
  prefetch_queue = {},
  prefetch_in_progress = {},
}

--==============================================================================
-- SYMBOL RANGE PROCESSING
--==============================================================================

-- Get symbols in the prefetch range for a buffer
local function get_prefetchable_symbols(bufnr)
  local prefetch_range = position.get_prefetch_range(bufnr, PREFETCH_RADIUS_LINES)
  if not prefetch_range then
    return {}
  end

  -- Use symbols module to get symbols in range
  local visible_symbols = symbols.get_symbols_in_range(bufnr, prefetch_range.start_line, prefetch_range.end_line)
  
  -- Filter and sort by priority
  local filterable = vim.tbl_filter(symbols.should_prefetch_symbol, visible_symbols)
  return symbols.sort_symbols_by_priority(filterable)
end

--==============================================================================
-- PREFETCH TRACKING
--==============================================================================

-- Check if symbol is already being prefetched
local function is_prefetch_in_progress(bufnr, symbol)
  local cache_key = string.format("%s:%d:%s",
    position.get_file_path(bufnr), symbol.start_line, symbol.name)
  return state.prefetch_in_progress[cache_key] ~= nil
end

-- Mark symbol as being prefetched
local function mark_prefetch_in_progress(bufnr, symbol, in_progress)
  local cache_key = string.format("%s:%d:%s",
    position.get_file_path(bufnr), symbol.start_line, symbol.name)

  if in_progress then
    state.prefetch_in_progress[cache_key] = true
  else
    state.prefetch_in_progress[cache_key] = nil
  end
end

-- Prefetch LSP data for a specific symbol
local function prefetch_symbol_data(bufnr, symbol, callback)
  if is_prefetch_in_progress(bufnr, symbol) then
    return
  end

  if cache.has_cached_data(bufnr, symbol.start_line, symbol.name) then
    if callback then callback(true) end
    return
  end

  mark_prefetch_in_progress(bufnr, symbol, true)
  performance.record_lsp_request()

  lsp_service.gather_all_context(bufnr, symbol.start_line, symbol.start_col, DEFAULT_FEATURE_CONFIG, function(lsp_data)
    if lsp_data then
      cache.store(bufnr, symbol.start_line, symbol.name, lsp_data)
    end

    mark_prefetch_in_progress(bufnr, symbol, false)

    if callback then callback(lsp_data ~= nil) end
  end)
end

--==============================================================================
-- QUEUE MANAGEMENT
--==============================================================================

-- Process prefetch queue with concurrency control
local function process_prefetch_queue()
  local current_count = 0
  for _ in pairs(state.prefetch_in_progress) do
    current_count = current_count + 1
  end

  while current_count < MAX_CONCURRENT_REQUESTS and #state.prefetch_queue > 0 do
    local item = table.remove(state.prefetch_queue, 1)
    current_count = current_count + 1

    prefetch_symbol_data(item.bufnr, item.symbol, function(success)
      vim.schedule(function()
        process_prefetch_queue()
      end)
    end)
  end

  performance.update_prefetch_stats(
    cache.get_total_cached_symbols(),
    nil,
    #state.prefetch_queue
  )
end

-- Queue symbols for prefetching
local function queue_symbols_for_prefetch(bufnr)
  local prefetchable_symbols = get_prefetchable_symbols(bufnr)

  for _, symbol in ipairs(prefetchable_symbols) do
    if not cache.has_cached_data(bufnr, symbol.start_line, symbol.name) and
        not is_prefetch_in_progress(bufnr, symbol) then
      table.insert(state.prefetch_queue, { bufnr = bufnr, symbol = symbol })
    end
  end

  process_prefetch_queue()
end

--==============================================================================
-- BUFFER DATA MANAGEMENT  
--==============================================================================

-- Clear buffer-specific prefetch data
local function clear_buffer_data(bufnr)
  symbols.clear_buffer_symbols(bufnr)
  cache.clear_buffer(bufnr)

  local file_path = position.get_file_path(bufnr)
  for cache_key in pairs(state.prefetch_in_progress) do
    if cache_key:find("^" .. file_path .. ":") then
      state.prefetch_in_progress[cache_key] = nil
    end
  end
end

-- Update symbols and trigger prefetch
local function update_symbols_and_prefetch(bufnr)
  symbols.update_buffer_symbols(bufnr, function(success, result)
    if success then
      vim.defer_fn(function()
        queue_symbols_for_prefetch(bufnr)
      end, SYMBOL_UPDATE_DELAY_MS)
    end
  end)
end

--==============================================================================
-- EVENT HANDLING & SETUP
--==============================================================================

-- Setup prefetching system
function M.setup()
  local group = vim.api.nvim_create_augroup("SymbolPrefetcher", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if buffer.is_suitable_for_lsp(bufnr) then
        update_symbols_and_prefetch(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "WinScrolled" }, {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if buffer.is_suitable_for_lsp(bufnr) then
        queue_symbols_for_prefetch(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      clear_buffer_data(bufnr)
      update_symbols_and_prefetch(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      clear_buffer_data(bufnr)
    end,
  })

  cache.setup_auto_cleanup()
  logger.info("Prefetcher", "Symbol prefetching enabled")
end

--==============================================================================
-- PUBLIC API
--==============================================================================
function M.force_prefetch_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  update_symbols_and_prefetch(bufnr)
end

function M.clear_cache()
  cache.clear_all()
  state.prefetch_queue = {}
  state.prefetch_in_progress = {}
end

function M.get_stats()
  local cache_stats = cache.get_stats()

  return {
    total_symbols_cached = cache_stats.total_symbols_cached,
    buffers_cached = cache_stats.buffers_cached,
    queue_length = #state.prefetch_queue,
    in_progress = vim.tbl_count(state.prefetch_in_progress),
    cache_stats = cache_stats,
  }
end

--==============================================================================
-- DEBUG FUNCTIONS
--==============================================================================
function M.get_buffer_symbols(bufnr)
  return symbols.get_buffer_symbols(bufnr)
end

function M.get_symbol_summary(bufnr)
  local buffer_symbols = symbols.get_buffer_symbols(bufnr)
  return symbols.get_symbol_summary(buffer_symbols)
end

return M
