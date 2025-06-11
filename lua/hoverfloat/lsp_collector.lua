local M = {}
local logger = require('hoverfloat.logger')

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

local function has_capability(capability)
  return vim.tbl_contains(vim.tbl_map(function(c)
    return c.server_capabilities[capability] and true or false
  end, vim.lsp.get_clients({ bufnr = 0 })), true)
end

local function get_hover_info(callback)
  if not has_capability('hoverProvider') then
    callback(nil)
    return
  end

  logger.lsp("debug", "Requesting hover")
  local clients = vim.lsp.get_clients()
  local params = vim.lsp.util.make_position_params(0, clients[1] and clients[1].offset_encoding or 'utf-16')
  vim.lsp.buf_request(0, 'textDocument/hover', params, function(err, result)
    if err or not result or not result.contents then
      callback(nil)
      return
    end

    local hover_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    local filtered_lines = vim.tbl_filter(function(line) return line and line:match("%S") end, hover_lines)

    logger.lsp("debug", "Hover info retrieved", { lines = #filtered_lines })
    callback(#filtered_lines > 0 and filtered_lines or nil)
  end)
end

local function get_definition_info(callback)
  if not has_capability('definitionProvider') then
    callback(nil)
    return
  end

  logger.lsp("debug", "Requesting definition")
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
      local def_info = { file = item.filename, line = item.lnum, col = item.col }
      logger.lsp("debug", "Definition info retrieved", def_info)
      callback(def_info)
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

  logger.lsp("debug", "Requesting references")
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

    logger.lsp("debug", "References info retrieved", { total = ref_info.count, displayed = #ref_info.locations })
    callback(ref_info)
  end)
end

local function get_type_definition_info(callback)
  if not has_capability('typeDefinitionProvider') then
    callback(nil)
    return
  end

  logger.lsp("debug", "Requesting type definition")
  local clients = vim.lsp.get_clients()
  local params = vim.lsp.util.make_position_params(0, clients[1] and clients[1].offset_encoding or 'utf-16')
  vim.lsp.buf_request(0, 'textDocument/typeDefinition', params, function(err, result)
    if err or not result then
      callback(nil)
      return
    end

    local locations = vim.tbl_islist(result) and result or { result }
    local items = vim.lsp.util.locations_to_items(locations, 'utf-16')
    if items and #items > 0 then
      local item = items[1]
      local type_info = { file = item.filename, line = item.lnum, col = item.col }
      logger.lsp("debug", "Type definition info retrieved", type_info)
      callback(type_info)
    else
      callback(nil)
    end
  end)
end

function M.gather_context_info(completion_callback, config)
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    completion_callback(nil)
    return
  end

  logger.lsp("debug", "Gathering LSP context info", { clients = vim.tbl_map(function(c) return c.name end, clients) })

  local context_data = get_current_position()
  local pending_requests = 0

  local function complete_request(request_type, data)
    pending_requests = pending_requests - 1
    context_data[request_type] = data

    if request_type == "references" and data then
      context_data.references_count = data.count
      context_data.references = data.locations
      context_data.references_more = data.more_count
    end

    if pending_requests == 0 then
      logger.lsp("debug", "All LSP requests completed")
      completion_callback(context_data)
    end
  end

  local requests = {
    { enabled = config.show_hover,      func = get_hover_info,                                                       type = "hover" },
    { enabled = config.show_definition, func = get_definition_info,                                                  type = "definition" },
    { enabled = config.show_references, func = function(cb) get_references_info(cb, config.max_references or 8) end, type = "references" },
    { enabled = config.show_type_info,  func = get_type_definition_info,                                             type = "type_definition" }
  }

  for _, req in ipairs(requests) do
    if req.enabled then
      pending_requests = pending_requests + 1
      req.func(function(data) complete_request(req.type, data) end)
    end
  end

  if pending_requests == 0 then
    completion_callback(context_data)
  end
end

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
