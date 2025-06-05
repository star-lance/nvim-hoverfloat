-- lua/hoverfloat/lsp_collector.lua - LSP data collection and formatting
local M = {}

-- Cache for LSP responses to avoid duplicate requests
local cache = {
  data = {},
  ttl = 30000,  -- 30 seconds TTL
}

-- Helper function to create cache key
local function make_cache_key(bufnr, line, col, request_type)
  return string.format("%d:%d:%d:%s", bufnr, line, col, request_type)
end

-- Helper function to check cache
local function get_cached_result(key)
  local entry = cache.data[key]
  if entry and (vim.uv.now() - entry.timestamp) < cache.ttl then
    return entry.result
  end
  return nil
end

-- Helper function to store in cache
local function cache_result(key, result)
  cache.data[key] = {
    result = result,
    timestamp = vim.uv.now()
  }
end

-- Clean old cache entries
local function cleanup_cache()
  local now = vim.uv.now()
  for key, entry in pairs(cache.data) do
    if (now - entry.timestamp) > cache.ttl then
      cache.data[key] = nil
    end
  end
end

-- Trim empty lines from hover content
local function trim_empty_lines(lines)
  if not lines then return {} end
  
  local trimmed = {}
  for _, line in ipairs(lines) do
    if line and line:match("%S") then
      table.insert(trimmed, line)
    end
  end
  return trimmed
end

-- Format file path to be relative to workspace
local function format_file_path(uri)
  if not uri then return "Unknown" end
  
  local file_path = vim.uri_to_fname(uri)
  local cwd = vim.fn.getcwd()
  
  -- Try to make path relative to current working directory
  if file_path:sub(1, #cwd) == cwd then
    return file_path:sub(#cwd + 2)  -- +2 to remove leading slash
  end
  
  -- Fallback to just filename if path is too long
  local filename = vim.fn.fnamemodify(file_path, ":t")
  if #file_path > 50 then
    return ".../" .. filename
  end
  
  return file_path
end

-- Get position encoding from the first available LSP client
local function get_position_encoding()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 then
    return clients[1].offset_encoding or 'utf-16'
  end
  return 'utf-16'  -- Default fallback
end

-- Request hover information
local function request_hover(params, callback, config)
  local bufnr = vim.api.nvim_get_current_buf()
  local cache_key = make_cache_key(bufnr, params.position.line, params.position.character, "hover")
  
  -- Check cache first
  local cached = get_cached_result(cache_key)
  if cached then
    callback("hover", cached)
    return
  end
  
  vim.lsp.buf_request(bufnr, 'textDocument/hover', params, function(err, result)
    local hover_data = {}
    
    if not err and result and result.contents then
      local hover_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
      hover_data = trim_empty_lines(hover_lines)
      
      -- Limit number of lines
      if #hover_data > config.max_hover_lines then
        hover_data = vim.list_slice(hover_data, 1, config.max_hover_lines)
        table.insert(hover_data, "... (truncated)")
      end
    end
    
    cache_result(cache_key, hover_data)
    callback("hover", hover_data)
  end)
end

-- Request definition information
local function request_definition(params, callback, config)
  if not config.show_definition_location then
    callback("definition", nil)
    return
  end
  
  local bufnr = vim.api.nvim_get_current_buf()
  local cache_key = make_cache_key(bufnr, params.position.line, params.position.character, "definition")
  
  -- Check cache first
  local cached = get_cached_result(cache_key)
  if cached then
    callback("definition", cached)
    return
  end
  
  vim.lsp.buf_request(bufnr, 'textDocument/definition', params, function(err, result)
    local def_data = nil
    
    if not err and result and #result > 0 then
      local def = result[1]
      if def.uri then
        def_data = {
          file = format_file_path(def.uri),
          line = def.range.start.line + 1,
          col = def.range.start.character + 1
        }
      end
    end
    
    cache_result(cache_key, def_data)
    callback("definition", def_data)
  end)
end

-- Request references information
local function request_references(params, callback, config)
  if not config.show_references_count then
    callback("references", nil)
    return
  end
  
  local bufnr = vim.api.nvim_get_current_buf()
  local cache_key = make_cache_key(bufnr, params.position.line, params.position.character, "references")
  
  -- Check cache first
  local cached = get_cached_result(cache_key)
  if cached then
    callback("references", cached)
    return
  end
  
  local ref_params = vim.tbl_extend('force', params, {
    context = { includeDeclaration = true }
  })
  
  vim.lsp.buf_request(bufnr, 'textDocument/references', ref_params, function(err, result)
    local ref_data = {
      count = 0,
      locations = {}
    }
    
    if not err and result then
      ref_data.count = #result
      
      -- Process reference locations
      for i, ref in ipairs(result) do
        if i <= config.max_references_shown and ref.uri then
          table.insert(ref_data.locations, {
            file = format_file_path(ref.uri),
            line = ref.range.start.line + 1,
            col = ref.range.start.character + 1
          })
        end
      end
      
      -- Add "and X more" indicator if there are more references
      if #result > config.max_references_shown then
        ref_data.more_count = #result - config.max_references_shown
      end
    end
    
    cache_result(cache_key, ref_data)
    callback("references", ref_data)
  end)
end

-- Request type definition information (optional)
local function request_type_definition(params, callback, config)
  if not config.show_type_info then
    callback("type_definition", nil)
    return
  end
  
  local bufnr = vim.api.nvim_get_current_buf()
  local cache_key = make_cache_key(bufnr, params.position.line, params.position.character, "type_definition")
  
  -- Check cache first
  local cached = get_cached_result(cache_key)
  if cached then
    callback("type_definition", cached)
    return
  end
  
  vim.lsp.buf_request(bufnr, 'textDocument/typeDefinition', params, function(err, result)
    local type_data = nil
    
    if not err and result and #result > 0 then
      local type_def = result[1]
      if type_def.uri then
        type_data = {
          file = format_file_path(type_def.uri),
          line = type_def.range.start.line + 1,
          col = type_def.range.start.character + 1
        }
      end
    end
    
    cache_result(cache_key, type_data)
    callback("type_definition", type_data)
  end)
end

-- Main function to gather all context information
function M.gather_context_info(completion_callback, config)
  local position_encoding = get_position_encoding()
  local params = vim.lsp.util.make_position_params(0, position_encoding)
  
  -- Current file information
  local context_data = {
    file = format_file_path(vim.uri_from_bufnr(0)),
    line = vim.fn.line('.'),
    col = vim.fn.col('.'),
    timestamp = vim.uv.now()
  }
  
  -- Track pending requests
  local pending_requests = 0
  local function start_request()
    pending_requests = pending_requests + 1
  end
  
  local function complete_request(data_type, data)
    pending_requests = pending_requests - 1
    
    -- Store the result
    if data_type == "hover" then
      context_data.hover = data
    elseif data_type == "definition" then
      context_data.definition = data
    elseif data_type == "references" then
      if data then
        context_data.references_count = data.count
        context_data.references = data.locations
        if data.more_count then
          context_data.references_more = data.more_count
        end
      end
    elseif data_type == "type_definition" then
      context_data.type_definition = data
    end
    
    -- Call completion callback when all requests are done
    if pending_requests == 0 then
      cleanup_cache()  -- Clean old cache entries
      completion_callback(context_data)
    end
  end
  
  -- Start all LSP requests
  start_request()
  request_hover(params, complete_request, config)
  
  start_request()
  request_definition(params, complete_request, config)
  
  start_request()
  request_references(params, complete_request, config)
  
  start_request()
  request_type_definition(params, complete_request, config)
  
  -- Fallback timeout in case requests hang
  vim.defer_fn(function()
    if pending_requests > 0 then
      completion_callback(context_data)
    end
  end, 5000)  -- 5 second timeout
end

-- Get symbol under cursor (simpler version for quick checks)
function M.get_symbol_at_cursor()
  local position_encoding = get_position_encoding()
  local params = vim.lsp.util.make_position_params(0, position_encoding)
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Get the word under cursor
  local word = vim.fn.expand('<cword>')
  if not word or word == '' then
    return nil
  end
  
  return {
    word = word,
    file = format_file_path(vim.uri_from_bufnr(bufnr)),
    line = params.position.line + 1,
    col = params.position.character + 1,
  }
end

-- Check if LSP is available for current buffer
function M.has_lsp_capability(capability)
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.supports_method(capability) then
      return true
    end
  end
  return false
end

-- Get available LSP capabilities for current buffer
function M.get_lsp_capabilities()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local capabilities = {
    hover = false,
    definition = false,
    references = false,
    type_definition = false,
  }
  
  for _, client in ipairs(clients) do
    if client.supports_method('textDocument/hover') then
      capabilities.hover = true
    end
    if client.supports_method('textDocument/definition') then
      capabilities.definition = true
    end
    if client.supports_method('textDocument/references') then
      capabilities.references = true
    end
    if client.supports_method('textDocument/typeDefinition') then
      capabilities.type_definition = true
    end
  end
  
  return capabilities
end

-- Clear cache (useful for debugging)
function M.clear_cache()
  cache.data = {}
end

-- Get cache statistics
function M.get_cache_stats()
  local count = 0
  for _ in pairs(cache.data) do
    count = count + 1
  end
  
  return {
    entries = count,
    ttl = cache.ttl,
  }
end

return M
