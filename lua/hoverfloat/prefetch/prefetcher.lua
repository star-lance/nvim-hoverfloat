-- lua/hoverfloat/prefetch/prefetcher.lua - Background LSP prefetching
local M = {}
local lsp_service = require('hoverfloat.core.lsp_service')
local cache = require('hoverfloat.prefetch.cache')
local position = require('hoverfloat.core.position')
local config = require('hoverfloat.config')
local performance = require('hoverfloat.core.performance')
local logger = require('hoverfloat.utils.logger')

-- Prefetcher state
local state = {
  buffer_symbols = {}, -- [bufnr] = symbols_array
  prefetch_queue = {},
  prefetch_in_progress = {},
  config = {
    max_concurrent_requests = 2,
    prefetch_radius_lines = 30,
  }
}

-- Update prefetcher configuration
local function update_config()
  local prefetch_config = config.get_section('prefetching')
  state.config.max_concurrent_requests = prefetch_config.max_concurrent_requests or 2
  state.config.prefetch_radius_lines = prefetch_config.prefetch_radius_lines or 30
end

-- Get symbols in the prefetch range for a buffer
local function get_prefetchable_symbols(bufnr)
  local symbols = state.buffer_symbols[bufnr] or {}
  local prefetch_range = position.get_prefetch_range(bufnr, state.config.prefetch_radius_lines)

  if not prefetch_range then
    return {}
  end

  local visible_symbols = {}
  for _, symbol in ipairs(symbols) do
    -- Check if symbol overlaps with prefetch range
    if symbol.start_line <= prefetch_range.end_line and
        symbol.end_line >= prefetch_range.start_line then
      table.insert(visible_symbols, symbol)
    end
  end

  return visible_symbols
end

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
  -- Check if already in progress
  if is_prefetch_in_progress(bufnr, symbol) then
    return
  end

  -- Check if already cached
  if cache.has_cached_data(bufnr, symbol.start_line, symbol.name) then
    if callback then callback(true) end
    return
  end

  mark_prefetch_in_progress(bufnr, symbol, true)
  performance.record_lsp_request()

  -- Use consolidated LSP service for all data
  local feature_config = config.get_section('features')

  lsp_service.gather_all_context(bufnr, symbol.start_line, symbol.start_col, feature_config, function(lsp_data)
    -- Store in cache
    if lsp_data then
      cache.store(bufnr, symbol.start_line, symbol.name, lsp_data)
    end

    -- Mark as complete
    mark_prefetch_in_progress(bufnr, symbol, false)

    if callback then callback(lsp_data ~= nil) end
  end)
end

-- Process prefetch queue with concurrency control
local function process_prefetch_queue()
  -- Count current operations
  local current_count = 0
  for _ in pairs(state.prefetch_in_progress) do
    current_count = current_count + 1
  end

  -- Process queue up to concurrency limit
  while current_count < state.config.max_concurrent_requests and
    #state.prefetch_queue > 0 do
    local item = table.remove(state.prefetch_queue, 1)
    current_count = current_count + 1

    prefetch_symbol_data(item.bufnr, item.symbol, function(success)
      -- Continue processing when complete
      vim.schedule(function()
        process_prefetch_queue()
      end)
    end)
  end

  -- Update performance stats
  performance.update_prefetch_stats(
    cache.get_total_cached_symbols(),
    nil, -- prefetch_requests (will be calculated)
    #state.prefetch_queue
  )
end

-- Queue symbols for prefetching
local function queue_symbols_for_prefetch(bufnr)
  local symbols = get_prefetchable_symbols(bufnr)

  for _, symbol in ipairs(symbols) do
    -- Only queue if not cached and not in progress
    if not cache.has_cached_data(bufnr, symbol.start_line, symbol.name) and
        not is_prefetch_in_progress(bufnr, symbol) then
      table.insert(state.prefetch_queue, { bufnr = bufnr, symbol = symbol })
    end
  end

  -- Start processing queue
  process_prefetch_queue()
end

-- Get instant context data if available in cache
function M.get_instant_context_data(callback)
  local symbol = position.get_symbol_at_cursor()
  if not symbol then
    callback(nil)
    return
  end

  -- Try cache first
  local cached_data = cache.get(symbol.bufnr, symbol.line, symbol.word)

  if cached_data then
    -- Format for socket client
    local current_pos = position.get_current_position()
    local formatted_data = cache.format_for_socket(cached_data, current_pos)
    callback(formatted_data)
    return
  end

  -- Not cached
  callback(nil)
end

-- Update document symbols for buffer
local function update_buffer_symbols(bufnr)
  if not position.is_suitable_for_lsp(bufnr) then
    return
  end

  lsp_service.get_document_symbols(bufnr, function(symbols, err)
    if not err and symbols then
      state.buffer_symbols[bufnr] = symbols

      -- Start prefetching after a short delay
      vim.defer_fn(function()
        queue_symbols_for_prefetch(bufnr)
      end, 100)
    end
  end)
end

-- Clear buffer-specific data
local function clear_buffer_data(bufnr)
  state.buffer_symbols[bufnr] = nil
  cache.clear_buffer(bufnr)

  -- Clear in-progress operations for this buffer
  local file_path = position.get_file_path(bufnr)
  for cache_key in pairs(state.prefetch_in_progress) do
    if cache_key:find("^" .. file_path .. ":") then
      state.prefetch_in_progress[cache_key] = nil
    end
  end
end

-- Setup prefetching system
function M.setup()
  update_config()

  local group = vim.api.nvim_create_augroup("SymbolPrefetcher", { clear = true })

  -- Update symbols and start prefetching on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()

      if position.is_suitable_for_lsp(bufnr) then
        update_buffer_symbols(bufnr)
      end
    end,
  })

  -- Prefetch on scroll/window movement
  vim.api.nvim_create_autocmd({ "WinScrolled" }, {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()

      if position.is_suitable_for_lsp(bufnr) then
        queue_symbols_for_prefetch(bufnr)
      end
    end,
  })

  -- Clear cache on buffer modification
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()

      -- Clear cache and restart prefetching
      clear_buffer_data(bufnr)
      update_buffer_symbols(bufnr)
    end,
  })

  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      clear_buffer_data(bufnr)
    end,
  })

  -- Setup automatic cache cleanup
  cache.setup_auto_cleanup()

  logger.info("Prefetcher", "Symbol prefetching enabled")
end

-- API functions
function M.force_prefetch_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  update_buffer_symbols(bufnr)
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
    config = state.config,
    cache_stats = cache_stats,
  }
end

-- Update configuration at runtime
function M.update_config()
  update_config()
end

return M
