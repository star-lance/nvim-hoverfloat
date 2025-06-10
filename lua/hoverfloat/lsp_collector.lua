-- lua/hoverfloat/lsp_collector_simple.lua - Focus on display, delegate LSP to Neovim
local M = {}

-- Import the logger
local logger = require('hoverfloat.logger')

-- Simple logging for this module (non-disruptive)
local function log_debug(msg, data)
  logger.lsp("debug", msg, data)
end

local function log_info(msg, data)
  logger.lsp("info", msg, data)
end

local function log_warn(msg, data)
  logger.lsp("warn", msg, data)
end

local function log_error(msg, data)
  logger.lsp("error", msg, data)
end

-- Helper to get current position info
local function get_current_position()
  local bufnr = vim.api.nvim_get_current_buf()
  return {
    file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":."),
    line = vim.fn.line('.'),
    col = vim.fn.col('.'),
    timestamp = vim.uv.now(),
    bufnr = bufnr
  }
end

-- Check if LSP is available for current buffer
local function has_lsp_capability(capability)
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.server_capabilities[capability] then
      return true
    end
  end
  return false
end

-- Simplified hover using direct LSP request
local function get_hover_info(callback)
  if not has_lsp_capability('hoverProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting hover using direct buf_request")
  
  -- Make direct LSP request without handler interception
  local params = vim.lsp.util.make_position_params()
  vim.lsp.buf_request(0, 'textDocument/hover', params, function(err, result, ctx, config)
    if err or not result or not result.contents then
      log_debug("Hover returned no content")
      callback(nil)
      return
    end
    
    -- Use Neovim's built-in markdown conversion
    local hover_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    
    -- Filter empty lines
    local filtered_lines = {}
    for _, line in ipairs(hover_lines) do
      if line and line:match("%S") then
        table.insert(filtered_lines, line)
      end
    end
    
    log_debug("Hover info retrieved", { lines = #filtered_lines })
    callback(#filtered_lines > 0 and filtered_lines or nil)
  end)
end

-- Simplified definition using direct LSP request
local function get_definition_info(callback)
  if not has_lsp_capability('definitionProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting definition using direct buf_request")
  
  -- Make direct LSP request without handler interception
  local params = vim.lsp.util.make_position_params()
  vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result, ctx, config)
    if err or not result then
      log_debug("Definition returned no result")
      callback(nil)
      return
    end
    
    -- Use Neovim's built-in location utilities
    local locations = vim.tbl_islist(result) and result or { result }
    if #locations > 0 then
      local items = vim.lsp.util.locations_to_items(locations, 'utf-16')
      if items and #items > 0 then
        local item = items[1]
        local def_info = {
          file = item.filename,
          line = item.lnum,
          col = item.col
        }
        log_debug("Definition info retrieved", def_info)
        callback(def_info)
        return
      end
    end
    
    log_debug("No valid definition found")
    callback(nil)
  end)
end

-- Simplified references using direct LSP request
local function get_references_info(callback, max_refs)
  if not has_lsp_capability('referencesProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting references using direct buf_request")
  
  -- Make direct LSP request without handler interception
  local params = vim.lsp.util.make_position_params()
  params.context = { includeDeclaration = true }
  vim.lsp.buf_request(0, 'textDocument/references', params, function(err, result, ctx, config)
    if err or not result then
      log_debug("References returned no result")
      callback(nil)
      return
    end
    
    -- Use Neovim's built-in location utilities
    local items = vim.lsp.util.locations_to_items(result, 'utf-16')
    
    local ref_info = {
      count = #items,
      locations = {}
    }
    
    -- Convert to our format, respecting max_refs
    local limit = math.min(#items, max_refs or 8)
    for i = 1, limit do
      local item = items[i]
      table.insert(ref_info.locations, {
        file = item.filename,
        line = item.lnum,
        col = item.col
      })
    end
    
    if #items > limit then
      ref_info.more_count = #items - limit
    end
    
    log_debug("References info retrieved", { 
      total = ref_info.count, 
      displayed = #ref_info.locations 
    })
    callback(ref_info)
  end)
end

-- Simplified type definition using direct LSP request
local function get_type_definition_info(callback)
  if not has_lsp_capability('typeDefinitionProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting type definition using direct buf_request")
  
  -- Make direct LSP request without handler interception
  local params = vim.lsp.util.make_position_params()
  vim.lsp.buf_request(0, 'textDocument/typeDefinition', params, function(err, result, ctx, config)
    if err or not result then
      log_debug("Type definition returned no result")
      callback(nil)
      return
    end
    
    local locations = vim.tbl_islist(result) and result or { result }
    if #locations > 0 then
      local items = vim.lsp.util.locations_to_items(locations, 'utf-16')
      if items and #items > 0 then
        local item = items[1]
        local type_info = {
          file = item.filename,
          line = item.lnum,
          col = item.col
        }
        log_debug("Type definition info retrieved", type_info)
        callback(type_info)
        return
      end
    end
    
    log_debug("No valid type definition found")
    callback(nil)
  end)
end

-- Main function - much simpler now!
function M.gather_context_info(completion_callback, config)
  -- Check if any LSP clients are available
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    log_debug("No LSP clients available")
    completion_callback(nil)
    return
  end
  
  log_debug("Gathering LSP context info", { 
    clients = vim.tbl_map(function(c) return c.name end, clients),
    config = config 
  })
  
  -- Get current position
  local context_data = get_current_position()
  
  -- Track pending requests
  local pending_requests = 0
  local function start_request()
    pending_requests = pending_requests + 1
  end
  
  local function complete_request(request_type, data)
    pending_requests = pending_requests - 1
    
    -- Add data to context
    if request_type == "hover" then
      context_data.hover = data
    elseif request_type == "definition" then
      context_data.definition = data
    elseif request_type == "references" then
      if data then
        context_data.references_count = data.count
        context_data.references = data.locations
        context_data.references_more = data.more_count
      end
    elseif request_type == "type_definition" then
      context_data.type_definition = data
    end
    
    -- Call completion callback when all requests done
    if pending_requests == 0 then
      log_debug("All LSP requests completed")
      completion_callback(context_data)
    end
  end
  
  -- Make requests for enabled features only
  if config.show_hover then
    start_request()
    get_hover_info(function(data) complete_request("hover", data) end)
  end
  
  if config.show_definition then
    start_request()
    get_definition_info(function(data) complete_request("definition", data) end)
  end
  
  if config.show_references then
    start_request()
    get_references_info(function(data) complete_request("references", data) end, config.max_references or 8)
  end
  
  if config.show_type_info then
    start_request()
    get_type_definition_info(function(data) complete_request("type_definition", data) end)
  end
  
  -- If no requests were made, call completion immediately
  if pending_requests == 0 then
    log_debug("No LSP requests needed")
    completion_callback(context_data)
  end
end

-- Simple symbol getter
function M.get_symbol_at_cursor()
  local word = vim.fn.expand('<cword>')
  if not word or word == '' then
    return nil
  end
  
  local pos = get_current_position()
  return {
    word = word,
    file = pos.file,
    line = pos.line,
    col = pos.col,
  }
end

return M