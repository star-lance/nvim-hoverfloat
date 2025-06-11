-- lua/hoverfloat/core/lsp_service.lua - Fixed URI handling
local M = {}
local position = require('hoverfloat.core.position')
local logger = require('hoverfloat.utils.logger')

-- Cache for capability checks to avoid repeated queries
local capability_cache = {}

-- Clear capability cache when LSP clients change
local function clear_capability_cache()
  capability_cache = {}
end

-- Check if LSP capability exists for buffer with caching
local function has_capability(capability, bufnr)
  bufnr = bufnr or 0
  local cache_key = string.format("%s:%d", capability, bufnr)

  -- Check cache first
  if capability_cache[cache_key] ~= nil then
    return capability_cache[cache_key]
  end

  -- Query LSP clients
  local clients = position.get_lsp_clients(bufnr)
  local has_cap = false

  for _, client in ipairs(clients) do
    if client.server_capabilities[capability] then
      has_cap = true
      break
    end
  end

  -- Cache result
  capability_cache[cache_key] = has_cap
  return has_cap
end

-- Generic LSP request wrapper with error handling
local function make_lsp_request(bufnr, method, params, callback)
  local clients = position.get_lsp_clients(bufnr)
  if #clients == 0 then
    callback(nil, "No LSP clients attached")
    return
  end

  vim.lsp.buf_request(bufnr, method, params, function(err, result)
    if err then
      logger.lsp("warn", string.format("%s request failed: %s", method, err))
      callback(nil, err)
      return
    end
    callback(result, nil)
  end)
end

-- Helper function to safely get file path from LSP location
local function get_file_from_location(location)
  -- Handle different location formats
  local uri = location.uri or location.targetUri
  if not uri then
    return nil
  end

  -- Check if it's already a proper URI with scheme
  if uri:match("^%w+://") then
    -- It's a proper URI, convert to buffer number then to file path
    local bufnr = vim.uri_to_bufnr(uri)
    return position.get_file_path(bufnr)
  else
    -- It's a plain file path, return as-is
    return uri
  end
end

-- Helper function to safely process locations from LSP
local function process_lsp_locations(locations)
  if not locations then
    return {}
  end

  -- Ensure locations is a list
  local location_list = vim.islist(locations) and locations or { locations }
  local processed = {}

  for _, location in ipairs(location_list) do
    local file_path = get_file_from_location(location)
    if file_path then
      local range = location.range or location.targetRange
      if range then
        table.insert(processed, {
          file = file_path,
          line = range.start.line + 1, -- Convert to 1-based
          col = range.start.character + 1
        })
      end
    end
  end

  return processed
end

-- Hover information
function M.get_hover(bufnr, line, col, callback)
  bufnr = bufnr or 0

  if not has_capability('hoverProvider', bufnr) then
    callback(nil, "Hover not supported")
    return
  end

  local params = position.make_lsp_position_params(bufnr, line, col)
  make_lsp_request(bufnr, 'textDocument/hover', params, function(result, err)
    if err or not result or not result.contents then
      callback(nil, err or "No hover content")
      return
    end

    local hover_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    local filtered_lines = vim.tbl_filter(function(line)
      return line and line:match("%S")
    end, hover_lines)

    callback(#filtered_lines > 0 and filtered_lines or nil)
  end)
end

-- Definition information
function M.get_definition(bufnr, line, col, callback)
  bufnr = bufnr or 0

  if not has_capability('definitionProvider', bufnr) then
    callback(nil, "Definition not supported")
    return
  end

  local params = position.make_lsp_position_params(bufnr, line, col)
  make_lsp_request(bufnr, 'textDocument/definition', params, function(result, err)
    if err or not result then
      callback(nil, err or "No definition found")
      return
    end

    local processed_locations = process_lsp_locations(result)
    if #processed_locations > 0 then
      callback(processed_locations[1]) -- Return first definition
    else
      callback(nil, "No definition locations found")
    end
  end)
end

-- References information
function M.get_references(bufnr, line, col, max_refs, callback)
  bufnr = bufnr or 0
  max_refs = max_refs or 8

  if not has_capability('referencesProvider', bufnr) then
    callback(nil, "References not supported")
    return
  end

  local params = position.make_lsp_position_params(bufnr, line, col)
  params.context = { includeDeclaration = true }

  make_lsp_request(bufnr, 'textDocument/references', params, function(result, err)
    if err or not result then
      callback(nil, err or "No references found")
      return
    end

    local processed_locations = process_lsp_locations(result)
    local limit = math.min(#processed_locations, max_refs)

    local ref_info = {
      count = #processed_locations,
      locations = {},
      more_count = #processed_locations > limit and (#processed_locations - limit) or nil
    }

    for i = 1, limit do
      table.insert(ref_info.locations, processed_locations[i])
    end

    callback(ref_info)
  end)
end

-- Type definition information
function M.get_type_definition(bufnr, line, col, callback)
  bufnr = bufnr or 0

  if not has_capability('typeDefinitionProvider', bufnr) then
    callback(nil, "Type definition not supported")
    return
  end

  local params = position.make_lsp_position_params(bufnr, line, col)
  make_lsp_request(bufnr, 'textDocument/typeDefinition', params, function(result, err)
    if err or not result then
      callback(nil, err or "No type definition found")
      return
    end

    local processed_locations = process_lsp_locations(result)
    if #processed_locations > 0 then
      callback(processed_locations[1]) -- Return first type definition
    else
      callback(nil, "No type definition locations found")
    end
  end)
end

-- Document symbols
function M.get_document_symbols(bufnr, callback)
  bufnr = bufnr or 0

  local clients = position.get_lsp_clients(bufnr)
  if #clients == 0 then
    callback({}, "No LSP clients")
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
    callback({}, "Document symbols not supported")
    return
  end

  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

  make_lsp_request(bufnr, 'textDocument/documentSymbol', params, function(result, err)
    if err or not result then
      callback({}, err or "No symbols found")
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
          start_line = symbol.range.start.line + 1, -- Convert to 1-based
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
    callback(symbols, nil)
  end)
end

-- Aggregate context gathering (replaces gather_context_info)
function M.gather_all_context(bufnr, line, col, feature_config, callback)
  bufnr = bufnr or 0
  feature_config = feature_config or {
    show_hover = true,
    show_references = true,
    show_definition = true,
    show_type_info = true,
    max_references = 8,
  }

  if not position.is_suitable_for_lsp(bufnr) then
    callback(nil)
    return
  end

  -- Get position info
  local pos_info = position.get_current_position()
  if line and col then
    pos_info.line = line
    pos_info.col = col
  end

  local context_data = {
    file = pos_info.file,
    line = pos_info.line,
    col = pos_info.col,
    timestamp = pos_info.timestamp,
    bufnr = pos_info.bufnr
  }

  local pending_requests = 0
  local function complete_request(request_type, data)
    pending_requests = pending_requests - 1
    context_data[request_type] = data

    -- Handle references specially
    if request_type == "references" and data then
      context_data.references_count = data.count
      context_data.references = data.locations
      context_data.references_more = data.more_count
    end

    if pending_requests == 0 then
      callback(context_data)
    end
  end

  -- Queue enabled requests
  local requests = {
    {
      enabled = feature_config.show_hover ~= false,
      func = function(cb) M.get_hover(bufnr, pos_info.line, pos_info.col, cb) end,
      type = "hover"
    },
    {
      enabled = feature_config.show_definition ~= false,
      func = function(cb) M.get_definition(bufnr, pos_info.line, pos_info.col, cb) end,
      type = "definition"
    },
    {
      enabled = feature_config.show_references ~= false,
      func = function(cb) M.get_references(bufnr, pos_info.line, pos_info.col, feature_config.max_references, cb) end,
      type = "references"
    },
    {
      enabled = feature_config.show_type_info ~= false,
      func = function(cb) M.get_type_definition(bufnr, pos_info.line, pos_info.col, cb) end,
      type = "type_definition"
    }
  }

  -- Execute enabled requests
  for _, req in ipairs(requests) do
    if req.enabled then
      pending_requests = pending_requests + 1
      req.func(function(data, err)
        if err then
          logger.lsp("debug", string.format("%s request failed: %s", req.type, err))
        end
        complete_request(req.type, data)
      end)
    end
  end

  -- If no requests enabled, return immediately
  if pending_requests == 0 then
    callback(context_data)
  end
end

-- Setup LSP service and register events
function M.setup()
  -- Clear capability cache when LSP clients change
  local group = vim.api.nvim_create_augroup("LSPServiceCache", { clear = true })

  vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    group = group,
    callback = clear_capability_cache,
  })
end

-- Clear capability cache manually
function M.clear_capability_cache()
  clear_capability_cache()
end

-- Check if buffer has any LSP clients (convenience function)
function M.has_lsp_clients(bufnr)
  return position.has_lsp_clients(bufnr)
end

return M
