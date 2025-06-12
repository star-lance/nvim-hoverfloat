-- lua/hoverfloat/prefetch/cache.lua - Updated with symbol utilities
local M = {}
local position = require('hoverfloat.core.position')
local symbols = require('hoverfloat.utils.symbols')
local performance = require('hoverfloat.core.performance')

-- Cache storage: [buffer_id][symbol_key] = cache_entry
local symbol_cache = {}

-- Cache entry structure
local function create_cache_entry(lsp_data, buffer_version)
  return {
    hover = lsp_data.hover,
    definition = lsp_data.definition,
    references = lsp_data.references,
    references_count = lsp_data.references_count or 0,
    references_more = lsp_data.references_more or 0,
    type_definition = lsp_data.type_definition,
    timestamp = vim.uv.now(),
    buffer_version = buffer_version,
  }
end

-- Generate cache key for a symbol at specific position
local function get_cache_key(bufnr, line, word)
  local file = position.get_file_path(bufnr)
  return string.format("%s:%d:%s", file, line, word or "")
end

-- Check if cached data is still valid
local function is_cache_valid(cache_entry, buffer_version, ttl_ms)
  if not cache_entry then
    return false
  end

  -- Check buffer version (invalidate if buffer changed)
  if cache_entry.buffer_version ~= buffer_version then
    return false
  end

  -- Check age
  local age = vim.uv.now() - cache_entry.timestamp
  return age <= ttl_ms
end

-- Hardcoded cache settings
local CACHE_TTL_MS = 45000 -- 45 seconds

-- Store LSP data in cache
function M.store(bufnr, line, word, lsp_data)
  local buffer_version = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = get_cache_key(bufnr, line, word)

  -- Initialize buffer cache if needed
  if not symbol_cache[bufnr] then
    symbol_cache[bufnr] = {}
  end

  -- Store cache entry
  symbol_cache[bufnr][cache_key] = create_cache_entry(lsp_data, buffer_version)

  -- Update performance stats
  performance.update_prefetch_stats(M.get_total_cached_symbols())
end

-- Retrieve LSP data from cache
function M.get(bufnr, line, word)
  local buffer_version = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = get_cache_key(bufnr, line, word)

  local buffer_cache = symbol_cache[bufnr]
  if not buffer_cache then
    return nil
  end

  local cache_entry = buffer_cache[cache_key]
  if not is_cache_valid(cache_entry, buffer_version, CACHE_TTL_MS) then
    -- Remove invalid entry
    buffer_cache[cache_key] = nil
    return nil
  end

  -- Record cache hit for performance tracking
  performance.record_cache_hit()

  return cache_entry
end

-- Get cached data for current cursor position
function M.get_current_cursor_data()
  local symbol_info = symbols.get_symbol_at_cursor()
  if not symbol_info then
    return nil
  end

  return M.get(symbol_info.bufnr, symbol_info.line, symbol_info.word)
end

-- Check if data exists in cache
function M.has_cached_data(bufnr, line, word)
  return M.get(bufnr, line, word) ~= nil
end

-- Check if current cursor position has cached data
function M.has_cached_data_at_cursor()
  if not symbols.is_cacheable_symbol_position() then
    return false
  end
  
  local symbol_info = symbols.get_symbol_at_cursor()
  if not symbol_info then
    return false
  end
  
  return M.has_cached_data(symbol_info.bufnr, symbol_info.line, symbol_info.word)
end

-- Clear cache for specific buffer
function M.clear_buffer(bufnr)
  symbol_cache[bufnr] = nil
end

-- Clear entire cache
function M.clear_all()
  symbol_cache = {}
  performance.update_prefetch_stats(0) -- Reset cached symbols count
end

-- Clear expired entries from cache
function M.cleanup_expired()
  local now = vim.uv.now()
  local cleaned_count = 0

  for bufnr, buffer_cache in pairs(symbol_cache) do
    local buffer_version = vim.api.nvim_buf_get_changedtick(bufnr)

    for cache_key, cache_entry in pairs(buffer_cache) do
      if not is_cache_valid(cache_entry, buffer_version, CACHE_TTL_MS) then
        buffer_cache[cache_key] = nil
        cleaned_count = cleaned_count + 1
      end
    end

    -- Remove empty buffer caches
    if next(buffer_cache) == nil then
      symbol_cache[bufnr] = nil
    end
  end

  if cleaned_count > 0 then
    performance.update_prefetch_stats(M.get_total_cached_symbols())
  end

  return cleaned_count
end

-- Get cache statistics
function M.get_stats()
  local total_cached = 0
  local buffers_cached = 0
  local oldest_entry = nil
  local newest_entry = nil

  for bufnr, buffer_cache in pairs(symbol_cache) do
    local buffer_count = 0
    buffers_cached = buffers_cached + 1

    for _, cache_entry in pairs(buffer_cache) do
      buffer_count = buffer_count + 1
      total_cached = total_cached + 1

      if not oldest_entry or cache_entry.timestamp < oldest_entry then
        oldest_entry = cache_entry.timestamp
      end
      if not newest_entry or cache_entry.timestamp > newest_entry then
        newest_entry = cache_entry.timestamp
      end
    end
  end

  return {
    total_symbols_cached = total_cached,
    buffers_cached = buffers_cached,
    oldest_entry_age = oldest_entry and (vim.uv.now() - oldest_entry) or 0,
    newest_entry_age = newest_entry and (vim.uv.now() - newest_entry) or 0,
  }
end

-- Get total number of cached symbols
function M.get_total_cached_symbols()
  local total = 0
  for _, buffer_cache in pairs(symbol_cache) do
    for _ in pairs(buffer_cache) do
      total = total + 1
    end
  end
  return total
end

-- Get cache entries for a specific buffer
function M.get_buffer_entries(bufnr)
  return symbol_cache[bufnr] or {}
end

-- Prune cache to keep within memory limits
function M.prune_cache(max_entries)
  max_entries = max_entries or 1000

  local current_total = M.get_total_cached_symbols()
  if current_total <= max_entries then
    return 0 -- No pruning needed
  end

  -- Collect all entries with timestamps
  local all_entries = {}
  for bufnr, buffer_cache in pairs(symbol_cache) do
    for cache_key, cache_entry in pairs(buffer_cache) do
      table.insert(all_entries, {
        bufnr = bufnr,
        cache_key = cache_key,
        timestamp = cache_entry.timestamp,
      })
    end
  end

  -- Sort by timestamp (oldest first)
  table.sort(all_entries, function(a, b)
    return a.timestamp < b.timestamp
  end)

  -- Remove oldest entries
  local to_remove = current_total - max_entries
  local removed_count = 0

  for i = 1, math.min(to_remove, #all_entries) do
    local entry = all_entries[i]
    if symbol_cache[entry.bufnr] and symbol_cache[entry.bufnr][entry.cache_key] then
      symbol_cache[entry.bufnr][entry.cache_key] = nil
      removed_count = removed_count + 1
    end
  end

  -- Clean up empty buffer caches
  for bufnr, buffer_cache in pairs(symbol_cache) do
    if next(buffer_cache) == nil then
      symbol_cache[bufnr] = nil
    end
  end

  performance.update_prefetch_stats(M.get_total_cached_symbols())
  return removed_count
end

-- Convert cached data to format expected by socket client
function M.format_for_socket(cached_data, current_position)
  if not cached_data or not current_position then
    return nil
  end

  return {
    file = current_position.file,
    line = current_position.line,
    col = current_position.col,
    timestamp = vim.uv.now(),
    hover = cached_data.hover,
    definition = cached_data.definition,
    references = cached_data.references,
    references_count = cached_data.references_count,
    references_more = cached_data.references_more,
    type_definition = cached_data.type_definition,
    cache_hit = true,
  }
end

-- Smart cache lookup for current cursor position
function M.get_smart_cursor_data()
  -- Only attempt cache lookup if position is cacheable
  if not symbols.is_cacheable_symbol_position() then
    return nil
  end
  
  local symbol_info = symbols.get_symbol_info_at_cursor()
  if not symbol_info or symbol_info.is_empty then
    return nil
  end
  
  -- Try exact word match first
  local cached_data = M.get(symbol_info.bufnr, symbol_info.line, symbol_info.word)
  if cached_data then
    return cached_data
  end
  
  -- If word has special characters, try WORD as fallback
  if symbol_info.has_special and symbol_info.WORD ~= symbol_info.word then
    cached_data = M.get(symbol_info.bufnr, symbol_info.line, symbol_info.WORD)
    if cached_data then
      return cached_data
    end
  end
  
  return nil
end

-- Setup automatic cleanup
function M.setup_auto_cleanup(cleanup_interval_ms, ttl_ms)
  cleanup_interval_ms = cleanup_interval_ms or 60000 -- 1 minute
  ttl_ms = ttl_ms or 45000                           -- 45 seconds

  local timer = vim.loop.new_timer()
  timer:start(cleanup_interval_ms, cleanup_interval_ms, vim.schedule_wrap(function()
    M.cleanup_expired(ttl_ms)
    M.prune_cache(1000) -- Keep max 1000 entries
  end))

  return timer
end

return M
