-- lua/hoverfloat/utils/buffer.lua - Buffer validation and LSP client management
local M = {}
local position = require('hoverfloat.core.position')

-- Hardcoded excluded filetypes for performance
local EXCLUDED_FILETYPES = {
  help = true,
  qf = true,
  netrw = true,
  fugitive = true,
  TelescopePrompt = true,
  NvimTree = true,
  ["neo-tree"] = true,
  packer = true,
  lazy = true,
  mason = true,
  ["mason-tool-installer"] = true,
  checkhealth = true,
}

-- Check if buffer is valid for LSP operations
function M.is_valid_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if buffer exists and is loaded
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end

  -- Check buffer type
  local buftype = vim.api.nvim_get_option_value('buftype', { buf = bufnr })
  if buftype ~= '' then
    return false
  end

  -- Check if file exists
  local file_path = position.get_file_path(bufnr)
  if not file_path or file_path == '' then
    return false
  end

  return true
end

-- Check if filetype should be excluded
function M.should_exclude_filetype(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end
  
  local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  return EXCLUDED_FILETYPES[filetype] or false
end

-- Check if buffer has LSP clients
function M.has_lsp_clients(bufnr)
  bufnr = bufnr or 0
  return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
end

-- Get LSP clients for buffer
function M.get_lsp_clients(bufnr)
  bufnr = bufnr or 0
  return vim.lsp.get_clients({ bufnr = bufnr })
end

-- Check if buffer is suitable for LSP operations (combines all checks)
function M.is_suitable_for_lsp(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  return M.is_valid_buffer(bufnr) and
      not M.should_exclude_filetype(bufnr) and
      M.has_lsp_clients(bufnr)
end

-- Get buffer info for debugging
function M.get_buffer_info(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return { valid = false, reason = "Invalid buffer" }
  end
  
  local info = {
    bufnr = bufnr,
    valid = vim.api.nvim_buf_is_valid(bufnr),
    loaded = vim.api.nvim_buf_is_loaded(bufnr),
    buftype = vim.api.nvim_get_option_value('buftype', { buf = bufnr }),
    filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr }),
    file_path = position.get_file_path(bufnr),
    lsp_clients = {},
    suitable_for_lsp = false,
  }
  
  -- Get LSP client info
  local clients = M.get_lsp_clients(bufnr)
  for _, client in ipairs(clients) do
    table.insert(info.lsp_clients, {
      id = client.id,
      name = client.name,
      root_dir = client.config.root_dir,
    })
  end
  
  info.suitable_for_lsp = M.is_suitable_for_lsp(bufnr)
  
  return info
end

-- Check if buffer name matches pattern
function M.buffer_matches_pattern(bufnr, pattern)
  local file_path = position.get_file_path(bufnr)
  return file_path and file_path:match(pattern) ~= nil
end

-- Get all suitable buffers for LSP operations
function M.get_suitable_buffers()
  local suitable = {}
  
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if M.is_suitable_for_lsp(bufnr) then
      table.insert(suitable, {
        bufnr = bufnr,
        file_path = position.get_file_path(bufnr),
        lsp_client_count = #M.get_lsp_clients(bufnr)
      })
    end
  end
  
  return suitable
end

-- Check if buffer has specific LSP capability
function M.has_lsp_capability(capability, bufnr)
  bufnr = bufnr or 0
  local clients = M.get_lsp_clients(bufnr)
  
  for _, client in ipairs(clients) do
    if client.server_capabilities[capability] then
      return true
    end
  end
  
  return false
end

-- Get LSP capabilities for buffer
function M.get_lsp_capabilities(bufnr)
  bufnr = bufnr or 0
  local clients = M.get_lsp_clients(bufnr)
  local capabilities = {}
  
  for _, client in ipairs(clients) do
    capabilities[client.name] = client.server_capabilities
  end
  
  return capabilities
end

-- Wait for LSP clients to attach (useful for auto-start)
function M.wait_for_lsp_attach(bufnr, timeout_ms, callback)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  timeout_ms = timeout_ms or 5000
  
  local start_time = vim.uv.now()
  
  local function check_lsp()
    if M.has_lsp_clients(bufnr) then
      callback(true)
      return
    end
    
    if vim.uv.now() - start_time > timeout_ms then
      callback(false)
      return
    end
    
    vim.defer_fn(check_lsp, 200)
  end
  
  check_lsp()
end

-- Add excluded filetype at runtime
function M.add_excluded_filetype(filetype)
  EXCLUDED_FILETYPES[filetype] = true
end

-- Remove excluded filetype at runtime  
function M.remove_excluded_filetype(filetype)
  EXCLUDED_FILETYPES[filetype] = nil
end

-- Get list of excluded filetypes
function M.get_excluded_filetypes()
  local list = {}
  for ft in pairs(EXCLUDED_FILETYPES) do
    table.insert(list, ft)
  end
  table.sort(list)
  return list
end

return M
