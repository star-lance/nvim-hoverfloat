-- lua/hoverfloat/symbol_prefetcher.lua
local M = {}
local logger = require('hoverfloat.logger')

-- Prefetcher state
local prefetch_state = {
  -- Cache: [buffer_id][symbol_key] = { hover, definition, references, type_def, timestamp, buffer_version }
  symbol_cache = {},
  -- Buffer symbols: [buffer_id] = { symbols array }
  buffer_symbols = {},
  -- Prefetch queue and tracking
  prefetch_queue = {},
  prefetch_in_progress = {},
  -- Configuration
  config = {
    max_concurrent_prefetch = 2,  -- Conservative to not overwhelm LSP
    prefetch_radius_lines = 30,   -- Lines above/below viewport
    cache_ttl_ms = 45000,        -- 45 second cache TTL
    debounce_ms = 100,           // Debounce prefetch triggers
  }
}

-- Helper to check if LSP capability exists
local function has_capability(capability)
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.server_capabilities[capability] then
      return true
    end
  end
  return false
end

-- Generate cache key for a symbol at specific position
local function get_symbol_cache_key(bufnr, line, word)
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
  return string.format("%s:%d:%s", file, line, word or "")
end

-- Get all document symbols for buffer
local function get_document_symbols(bufnr, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  
  if #clients == 0 then
    callback({})
    return
  end
  
  -- Find client with document symbol support
  local symbol_client = nil
  for _, client in ipairs(clients) do
    if client.server_capabilities.documentSymbolProvider then
      symbol_client = client
      break
    end
  end
  
  if not symbol_client then
    callback({})
    return
  end
  
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  
  vim.lsp.buf_request(bufnr, 'textDocument/documentSymbol', params, function(err, result)
    if err or not result then
      callback({})
      return
    end
    
    -- Flatten hierarchical symbols
    local symbols = {}
    local function flatten_symbols(symbol_list, parent_name)
      for _, symbol in ipairs(symbol_list) do
        local full_name = parent_name and (parent_name .. "." .. symbol.name) or symbol.name
        
        table.insert(symbols, {
          name = full_name,
          kind = symbol.kind,
          range = symbol.range,
          selection_range = symbol.selectionRange,
          start_line = symbol.range.start.line + 1,  -- Convert to 1-based
          end_line = symbol.range['end'].line + 1,
          start_col = symbol.range.start.character + 1,
          end_col = symbol.range['end'].character + 1,
        })
        
        -- Process children recursively
        if symbol.children then
          flatten_symbols(symbol.children, full_name)
        end
      end
    end
    
    flatten_symbols(result)
    callback(symbols)
  end)
end

-- Get symbols in viewport + radius
local function get_visible_symbols(bufnr)
  local symbols = prefetch_state.buffer_symbols[bufnr] or {}
  local visible_symbols = {}
  
  -- Get current window visible range
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins == 0 then
    return visible_symbols
  end
  
  local win = wins[1]
  local top_line = vim.fn.line('w0', win)
  local bottom_line = vim.fn.line('w$', win)
  
  -- Expand range for prefetching
  local prefetch_start = math.max(1, top_line - prefetch_state.config.prefetch_radius_lines)
  local prefetch_end = bottom_line + prefetch_state.config.prefetch_radius_lines
  
  for _, symbol in ipairs(symbols) do
    -- Check if symbol overlaps with prefetch range
    if symbol.start_line <= prefetch_end and symbol.end_line >= prefetch_start then
      table.insert(visible_symbols, symbol)
    end
  end
  
  return visible_symbols
end

-- Check if cached data is valid
local function is_cache_valid(cached_data, buffer_version)
  if not cached_data then
    return false
  end
  
  local now = vim.uv.now()
  local age = now - cached_data.timestamp
  
  return age <= prefetch_state.config.cache_ttl_ms and 
         cached_data.buffer_version == buffer_version
end

-- Get cached symbol data
local function get_cached_symbol_data(bufnr, line, word)
  local buffer_version = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = get_symbol_cache_key(bufnr, line, word)
  
  local buffer_cache = prefetch_state.symbol_cache[bufnr]
  if not buffer_cache then
    return nil
  end
  
  local cached_data = buffer_cache[cache_key]
  if is_cache_valid(cached_data, buffer_version) then
    return cached_data
  end
  
  return nil
end

-- Store symbol data in cache
local function store_symbol_data(bufnr, line, word, lsp_data)
  local buffer_version = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = get_symbol_cache_key(bufnr, line, word)
  
  if not prefetch_state.symbol_cache[bufnr] then
    prefetch_state.symbol_cache[bufnr] = {}
  end
  
  prefetch_state.symbol_cache[bufnr][cache_key] = {
    hover = lsp_data.hover,
    definition = lsp_data.definition,
    references = lsp_data.references,
    references_count = lsp_data.references and lsp_data.references.count or 0,
    references_more = lsp_data.references and lsp_data.references.more_count or 0,
    type_definition = lsp_data.type_definition,
    timestamp = vim.uv.now(),
    buffer_version = buffer_version,
  }
end

-- LSP request functions (from your existing code)
local function get_hover_info(callback)
  if not has_capability('hoverProvider') then
    callback(nil)
    return
  end

  local clients = vim.lsp.get_clients()
  local params = vim.lsp.util.make_position_params(0, clients[1] and clients[1].offset_encoding or 'utf-16')
  vim.lsp.buf_request(0, 'textDocument/hover', params, function(err, result)
    if err or not result or not result.contents then
      callback(nil)
      return
    end

    local hover_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    local filtered_lines = vim.tbl_filter(function(line) return line and line:match("%S") end, hover_lines)
    callback(#filtered_lines > 0 and filtered_lines or nil)
  end)
end

local function get_definition_info(callback)
  if not has_capability('definitionProvider') then
    callback(nil)
    return
  end

  local clients = vim.lsp.get_clients()
  local params = vim.lsp.util.make_position_params(0, clients[1] and clients[1].offset_encoding or 'utf-16')
  vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result)
    if err or not result then
      callback(nil)
      return
    end

    local locations = vim.islist(result) and result or { result }
    local items = vim.lsp.util.locations_to_items(locations, 'utf-16')
    if items and #items > 0 then
      local item = items[1]
      callback({ file = item.filename, line = item.lnum, col = item.col })
    else
      callback(nil)
    end
  end)
end

local function get_references_info(callback, max_refs)
  if not has_capability('referencesProvider') then
    callback(nil)
    return
  end

  local clients = vim.lsp.get_clients()
  local params = vim.lsp.util.make_position_params(0, clients[1] and clients[1].offset_encoding or 'utf-16')
  params.context = { includeDeclaration = true }
  vim.lsp.buf_request(0, 'textDocument/references', params, function(err, result)
    if err or not result then
      callback(nil)
      return
    end

    local items = vim.lsp.util.locations_to_items(result, 'utf-16')
    local limit = math.min(#items, max_refs or 8)
    local ref_info = {
      count = #items,
      locations = {},
      more_count = #items > limit and (#items - limit) or nil
    }

    for i = 1, limit do
      local item = items[i]
      table.insert(ref_info.locations, { file = item.filename, line = item.lnum, col = item.col })
    end

    callback(ref_info)
  end)
end

local function get_type_definition_info(callback)
  if not has_capability('typeDefinitionProvider') then
    callback(nil)
    return
  end

  local clients = vim.lsp.get_clients()
  local params = vim.lsp.util.make_position_params(0, clients[1] and clients[1].offset_encoding or 'utf-16')
  vim.lsp.buf_request(0, 'textDocument/typeDefinition', params, function(err, result)
    if err or not result then
      callback(nil)
      return
    end

    local locations = vim.islist(result) and result or { result }
    local items = vim.lsp.util.locations_to_items(locations, 'utf-16')
    if items and #items > 0 then
      local item = items[1]
      callback({ file = item.filename, line = item.lnum, col = item.col })
    else
      callback(nil)
    end
  end)
end

-- Prefetch LSP data for a specific symbol
local function prefetch_symbol_lsp_data(bufnr, symbol, callback)
  local cache_key = get_symbol_cache_key(bufnr, symbol.start_line, symbol.name)
  
  -- Check if already in progress
  if prefetch_state.prefetch_in_progress[cache_key] then
    return
  end
  
  -- Check if already cached
  local cached = get_cached_symbol_data(bufnr, symbol.start_line, symbol.name)
  if cached then
    if callback then callback(cached) end
    return
  end
  
  prefetch_state.prefetch_in_progress[cache_key] = true
  
  -- Temporarily move cursor to symbol position
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()
  
  -- Only prefetch if we're still in the same buffer
  if current_buf ~= bufnr then
    prefetch_state.prefetch_in_progress[cache_key] = nil
    return
  end
  
  local current_pos = vim.api.nvim_win_get_cursor(current_win)
  local target_pos = { symbol.start_line, math.max(0, symbol.start_col - 1) }
  
  -- Set cursor to symbol position
  vim.api.nvim_win_set_cursor(current_win, target_pos)
  
  -- Collect LSP data
  local lsp_data = {}
  local pending_requests = 4
  
  local function complete_request(request_type, data)
    lsp_data[request_type] = data
    pending_requests = pending_requests - 1
    
    if pending_requests == 0 then
      -- Restore cursor position
      pcall(vim.api.nvim_win_set_cursor, current_win, current_pos)
      
      -- Store in cache
      store_symbol_data(bufnr, symbol.start_line, symbol.name, lsp_data)
      
      -- Mark as complete
      prefetch_state.prefetch_in_progress[cache_key] = nil
      
      if callback then callback(lsp_data) end
    end
  end
  
  -- Make all LSP requests
  get_hover_info(function(data) complete_request("hover", data) end)
  get_definition_info(function(data) complete_request("definition", data) end)
  get_references_info(function(data) complete_request("references", data) end, 8)
  get_type_definition_info(function(data) complete_request("type_definition", data) end)
end

-- Process prefetch queue with concurrency control
local function process_prefetch_queue()
  -- Count current operations
  local current_count = 0
  for _ in pairs(prefetch_state.prefetch_in_progress) do
    current_count = current_count + 1
  end
  
  -- Process queue up to concurrency limit
  while current_count < prefetch_state.config.max_concurrent_prefetch and 
        #prefetch_state.prefetch_queue > 0 do
    
    local item = table.remove(prefetch_state.prefetch_queue, 1)
    current_count = current_count + 1
    
    prefetch_symbol_lsp_data(item.bufnr, item.symbol, function()
      -- Continue processing when complete
      vim.schedule(function()
        process_prefetch_queue()
      end)
    end)
  end
end

-- Queue visible symbols for prefetching
local function queue_visible_symbols_for_prefetch(bufnr)
  local visible_symbols = get_visible_symbols(bufnr)
  
  for _, symbol in ipairs(visible_symbols) do
    local cached = get_cached_symbol_data(bufnr, symbol.start_line, symbol.name)
    local cache_key = get_symbol_cache_key(bufnr, symbol.start_line, symbol.name)
    
    -- Only queue if not cached and not in progress
    if not cached and not prefetch_state.prefetch_in_progress[cache_key] then
      table.insert(prefetch_state.prefetch_queue, { bufnr = bufnr, symbol = symbol })
    end
  end
  
  -- Start processing queue
  process_prefetch_queue()
end

-- Main API: Get instant context data if available
function M.get_instant_context_data(callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2] + 1
  local word = vim.fn.expand('<cword>')
  
  if not word or word == "" then
    callback(nil)
    return
  end
  
  -- Try to get cached data
  local cached_data = get_cached_symbol_data(bufnr, cursor_line, word)
  if cached_data then
    -- Instant response!
    local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
    callback({
      file = file,
      line = cursor_line,
      col = cursor_col,
      timestamp = vim.uv.now(),
      hover = cached_data.hover,
      definition = cached_data.definition,
      references = cached_data.references and cached_data.references.locations or nil,
      references_count = cached_data.references_count,
      references_more = cached_data.references_more,
      type_definition = cached_data.type_definition,
      cache_hit = true,
    })
    return
  end
  
  -- Not cached
  callback(nil)
end

-- Setup prefetching system
function M.setup_prefetching()
  local group = vim.api.nvim_create_augroup("SymbolPrefetcher", { clear = true })
  
  -- Update symbols and start prefetching on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      
      -- Don't prefetch for non-file buffers
      local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
      if buftype ~= '' then
        return
      end
      
      get_document_symbols(bufnr, function(symbols)
        prefetch_state.buffer_symbols[bufnr] = symbols
        
        -- Start prefetching after a short delay
        vim.defer_fn(function()
          queue_visible_symbols_for_prefetch(bufnr)
        end, 200)
      end)
    end,
  })
  
  -- Prefetch on scroll/window movement
  local prefetch_timer = nil
  vim.api.nvim_create_autocmd({ "WinScrolled", "CursorMoved" }, {
    group = group,
    callback = function()
      -- Debounce prefetching
      if prefetch_timer then
        prefetch_timer:stop()
      end
      
      prefetch_timer = vim.defer_fn(function()
        prefetch_timer = nil
        local bufnr = vim.api.nvim_get_current_buf()
        queue_visible_symbols_for_prefetch(bufnr)
      end, prefetch_state.config.debounce_ms)
    end,
  })
  
  -- Clear cache on buffer modification
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      
      -- Clear cache for this buffer
      prefetch_state.symbol_cache[bufnr] = {}
      
      -- Clear in-progress operations
      for cache_key in pairs(prefetch_state.prefetch_in_progress) do
        if cache_key:find("^" .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.") .. ":") then
          prefetch_state.prefetch_in_progress[cache_key] = nil
        end
      end
      
      -- Refresh symbols and restart prefetching
      get_document_symbols(bufnr, function(symbols)
        prefetch_state.buffer_symbols[bufnr] = symbols
        
        vim.defer_fn(function()
          queue_visible_symbols_for_prefetch(bufnr)
        end, 300)
      end)
    end,
  })
  
  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      prefetch_state.symbol_cache[bufnr] = nil
      prefetch_state.buffer_symbols[bufnr] = nil
    end,
  })
end

-- API functions
function M.force_prefetch_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  get_document_symbols(bufnr, function(symbols)
    prefetch_state.buffer_symbols[bufnr] = symbols
    queue_visible_symbols_for_prefetch(bufnr)
  end)
end

function M.clear_cache()
  prefetch_state.symbol_cache = {}
  prefetch_state.prefetch_queue = {}
  prefetch_state.prefetch_in_progress = {}
end

function M.get_stats()
  local total_cached = 0
  local buffers_cached = 0
  
  for bufnr, buffer_cache in pairs(prefetch_state.symbol_cache) do
    buffers_cached = buffers_cached + 1
    for _ in pairs(buffer_cache) do
      total_cached = total_cached + 1
    end
  end
  
  return {
    total_symbols_cached = total_cached,
    buffers_cached = buffers_cached,
    queue_length = #prefetch_state.prefetch_queue,
    in_progress = vim.tbl_count(prefetch_state.prefetch_in_progress),
    config = prefetch_state.config,
  }
end

return M
