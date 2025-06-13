-- lua/hoverfloat/prefetch/cache.lua - Simplified cache management
local M = {}
local position = require('hoverfloat.core.position')
local symbols = require('hoverfloat.utils.symbols')
local performance = require('hoverfloat.core.performance')

-- Cache configuration
local CACHE_TTL_MS = 45000        -- 45 seconds
local MAX_CACHE_ENTRIES = 1000
local CLEANUP_INTERVAL_MS = 60000 -- 1 minute

local symbol_cache = {}
local cache_count = 0

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

--==============================================================================
-- CORE CACHE OPERATIONS
--==============================================================================

-- Store LSP data in cache with deduplication check
function M.store(bufnr, line, word, lsp_data)
  local buffer_version = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = get_cache_key(bufnr, line, word)

  -- Initialize buffer cache if needed
  if not symbol_cache[bufnr] then
    symbol_cache[bufnr] = {}
  end

  -- Check if this is a new entry
  local is_new_entry = symbol_cache[bufnr][cache_key] == nil
  
  -- Quick deduplication - don't cache identical data
  local existing_entry = symbol_cache[bufnr][cache_key]
  if existing_entry and existing_entry.buffer_version == buffer_version then
    -- Data likely hasn't changed, skip expensive cache update
    return
  end

  -- Store cache entry
  symbol_cache[bufnr][cache_key] = create_cache_entry(lsp_data, buffer_version)

  -- Update count if new entry
  if is_new_entry then
    cache_count = cache_count + 1
  end

  -- Update performance stats
  performance.update_prefetch_stats(cache_count)
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
    -- Remove invalid entry and update count
    buffer_cache[cache_key] = nil
    cache_count = cache_count - 1
    return nil
  end

  -- Record cache hit for performance tracking
  performance.record_cache_hit()

  return cache_entry
end

-- Check if data exists in cache
function M.has_cached_data(bufnr, line, word)
  return M.get(bufnr, line, word) ~= nil
end

--==============================================================================
-- CACHE MANAGEMENT
--==============================================================================

-- Clear cache for specific buffer
function M.clear_buffer(bufnr)
  if symbol_cache[bufnr] then
    -- Count entries being removed
    for _ in pairs(symbol_cache[bufnr]) do
      cache_count = cache_count - 1
    end
    symbol_cache[bufnr] = nil
  end
end

-- Clear entire cache
function M.clear_all()
  symbol_cache = {}
  cache_count = 0
  performance.update_prefetch_stats(0)
end

-- Clear expired entries from cache
function M.cleanup_expired()
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

  -- Update global count
  cache_count = cache_count - cleaned_count
  if cleaned_count > 0 then
    performance.update_prefetch_stats(cache_count)
  end

  return cleaned_count
end

--==============================================================================
-- CACHE STATISTICS
--==============================================================================

-- Get total number of cached symbols (O(1) operation)
function M.get_total_cached_symbols()
  return cache_count
end

-- Get cache statistics
function M.get_stats()
  local total_cached = M.get_total_cached_symbols()
  local buffers_cached = 0
  local oldest_entry = nil
  local newest_entry = nil

  for bufnr, buffer_cache in pairs(symbol_cache) do
    buffers_cached = buffers_cached + 1

    for _, cache_entry in pairs(buffer_cache) do
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

--==============================================================================
-- MEMORY MANAGEMENT
--==============================================================================

-- Prune cache to keep within memory limits
function M.prune_cache(max_entries)
  max_entries = max_entries or MAX_CACHE_ENTRIES

  if cache_count <= max_entries then
    return 0 -- No pruning needed
  end

  -- Simple pruning: remove oldest entries until under limit
  local to_remove = cache_count - max_entries
  local removed_count = 0
  local oldest_timestamp = math.huge

  -- Find oldest timestamp threshold by sampling
  for bufnr, buffer_cache in pairs(symbol_cache) do
    for _, cache_entry in pairs(buffer_cache) do
      if cache_entry.timestamp < oldest_timestamp then
        oldest_timestamp = cache_entry.timestamp
      end
    end
  end

  -- Remove entries older than threshold
  for bufnr, buffer_cache in pairs(symbol_cache) do
    for cache_key, cache_entry in pairs(buffer_cache) do
      if removed_count >= to_remove then
        break
      end
      if cache_entry.timestamp <= oldest_timestamp then
        buffer_cache[cache_key] = nil
        removed_count = removed_count + 1
      end
    end
    if removed_count >= to_remove then
      break
    end
  end

  -- Clean up empty buffer caches
  for bufnr, buffer_cache in pairs(symbol_cache) do
    if next(buffer_cache) == nil then
      symbol_cache[bufnr] = nil
    end
  end

  -- Update global count
  cache_count = cache_count - removed_count
  performance.update_prefetch_stats(cache_count)
  return removed_count
end

--==============================================================================
-- UTILITY FUNCTIONS
--==============================================================================

-- Get cached data for current cursor position
function M.get_cursor_data()
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
    return M.get(symbol_info.bufnr, symbol_info.line, symbol_info.WORD)
  end

  return nil
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

-- Setup automatic cleanup
function M.setup_auto_cleanup()
  local timer = vim.loop.new_timer() or {}
  timer:start(CLEANUP_INTERVAL_MS, CLEANUP_INTERVAL_MS, vim.schedule_wrap(function()
    M.cleanup_expired()
    M.prune_cache()
  end))

  return timer
end

return M
