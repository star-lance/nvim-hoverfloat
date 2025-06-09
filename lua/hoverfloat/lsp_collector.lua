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

-- Simplified hover using Neovim's built-in handler
local function get_hover_info(callback)
  if not has_lsp_capability('hoverProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting hover using vim.lsp.buf.hover")
  
  -- Capture the hover response by temporarily intercepting the handler
  local original_handler = vim.lsp.handlers['textDocument/hover']
  local timeout_timer = nil
  
  vim.lsp.handlers['textDocument/hover'] = function(err, result, ctx, config)
    -- Restore original handler immediately
    vim.lsp.handlers['textDocument/hover'] = original_handler
    
    -- Cancel timeout
    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
      timeout_timer = nil
    end
    
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
  end
  
  -- Set timeout in case hover never responds
  timeout_timer = vim.fn.timer_start(2000, function()
    vim.lsp.handlers['textDocument/hover'] = original_handler
    log_debug("Hover request timed out")
    callback(nil)
  end)
  
  -- Make the hover request without triggering popup
  local params = vim.lsp.util.make_position_params()
  vim.lsp.buf_request(0, 'textDocument/hover', params, function(err, result, ctx, config)
    if original_handler then
      original_handler(err, result, ctx, config)
    end
  end)
end

-- Simplified definition using Neovim's location handling
local function get_definition_info(callback)
  if not has_lsp_capability('definitionProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting definition using vim.lsp.buf.definition")
  
  local original_handler = vim.lsp.handlers['textDocument/definition']
  local timeout_timer = nil
  
  vim.lsp.handlers['textDocument/definition'] = function(err, result, ctx, config)
    vim.lsp.handlers['textDocument/definition'] = original_handler
    
    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
      timeout_timer = nil
    end
    
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
    
    callback(nil)
  end
  
  timeout_timer = vim.fn.timer_start(2000, function()
    vim.lsp.handlers['textDocument/definition'] = original_handler
    log_debug("Definition request timed out")
    callback(nil)
  end)
  
  -- Make the definition request without triggering navigation
  local params = vim.lsp.util.make_position_params()
  vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result, ctx, config)
    if original_handler then
      original_handler(err, result, ctx, config)
    end
  end)
end

-- Simplified references using Neovim's location handling
local function get_references_info(callback, max_refs)
  if not has_lsp_capability('referencesProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting references using vim.lsp.buf.references")
  
  local original_handler = vim.lsp.handlers['textDocument/references']
  local timeout_timer = nil
  
  vim.lsp.handlers['textDocument/references'] = function(err, result, ctx, config)
    vim.lsp.handlers['textDocument/references'] = original_handler
    
    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
      timeout_timer = nil
    end
    
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
  end
  
  timeout_timer = vim.fn.timer_start(2000, function()
    vim.lsp.handlers['textDocument/references'] = original_handler
    log_debug("References request timed out")
    callback(nil)
  end)
  
  -- Make the references request without triggering navigation
  local params = vim.lsp.util.make_position_params()
  params.context = { includeDeclaration = true }
  vim.lsp.buf_request(0, 'textDocument/references', params, function(err, result, ctx, config)
    if original_handler then
      original_handler(err, result, ctx, config)
    end
  end)
end

-- Simplified type definition
local function get_type_definition_info(callback)
  if not has_lsp_capability('typeDefinitionProvider') then
    callback(nil)
    return
  end

  log_debug("Requesting type definition using vim.lsp.buf.type_definition")
  
  local original_handler = vim.lsp.handlers['textDocument/typeDefinition']
  local timeout_timer = nil
  
  vim.lsp.handlers['textDocument/typeDefinition'] = function(err, result, ctx, config)
    vim.lsp.handlers['textDocument/typeDefinition'] = original_handler
    
    if timeout_timer then
      vim.fn.timer_stop(timeout_timer)
      timeout_timer = nil
    end
    
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
    
    callback(nil)
  end
  
  timeout_timer = vim.fn.timer_start(2000, function()
    vim.lsp.handlers['textDocument/typeDefinition'] = original_handler
    log_debug("Type definition request timed out")
    callback(nil)
  end)
  
  vim.lsp.buf.type_definition()
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
