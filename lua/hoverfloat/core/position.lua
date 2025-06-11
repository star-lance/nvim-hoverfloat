-- lua/hoverfloat/core/position.lua - Position and buffer utilities
local M = {}

-- Get normalized file path
function M.get_file_path(bufnr)
  bufnr = bufnr or 0
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
end

-- Get current cursor position
function M.get_cursor_position(win)
  win = win or 0
  return vim.api.nvim_win_get_cursor(win)
end

-- Get current position info with all context
function M.get_current_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = M.get_cursor_position()
  local line, col = cursor_pos[1], cursor_pos[2]

  return {
    file = M.get_file_path(bufnr),
    line = line,
    col = col + 1,
    timestamp = vim.uv.now(),
    bufnr = bufnr,
  }
end

-- Get symbol at cursor with position
function M.get_symbol_at_cursor()
  local symbol = vim.fn.expand('<cword>') or ''

  local pos = M.get_current_context()
  return {
    symbol = symbol,
    file = pos.file,
    line = pos.line,
    col = pos.col,
    bufnr = pos.bufnr,
  }
end

-- Create unique position identifier
function M.get_position_identifier(bufnr, line, col, symbol)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not line or not col then
    local cursor_pos = M.get_cursor_position()
    line = cursor_pos[1]
    col = cursor_pos[2] + 1
  end

  symbol = symbol or M.get_symbol_at_cursor()
  local file = M.get_file_path(bufnr)

  return string.format("%s:%d:%d:%s", file, line, col, symbol or "")
end

-- Create LSP position parameters for any position
function M.make_lsp_position_params(bufnr, line, col)
  bufnr = bufnr or 0
  local cursor_pos = (line and col) and { line, col - 1 } or M.get_cursor_position()
  return {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = {
      line = cursor_pos[1] - 1,
      character = math.max(0, cursor_pos[2])
    }
  }
end

function M.get_visible_lines(winnr)
  winnr = winnr or 0
  return {
    top     = vim.fn.line('w0', winnr),
    bottom  = vim.fn.line('w$', winnr),
  }
end

-- Expand visible range for prefetching
function M.get_prefetch_range(bufnr, win)
  local visible = M.get_visible_range(bufnr, win)
  if not visible then
    return nil
  end
  return {
    start_line = math.max(1, visible.start_line - 30),
    end_line = visible.end_line + 30,
  }
end

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
  local file_path = M.get_file_path(bufnr)
  if not file_path or file_path == '' then
    return false
  end

  return true
end

-- Check if filetype should be excluded
function M.should_exclude_filetype()
  return false
end

-- Check if buffer has LSP clients
function M.has_lsp_clients(bufnr)
  bufnr = bufnr or 0
  return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
end

function M.get_lsp_clients(bufnr)
  bufnr = bufnr or 0
  return vim.lsp.get_clients({ bufnr = bufnr })
end

function M.is_suitable_for_lsp(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  return M.is_valid_buffer(bufnr) and
      not M.should_exclude_filetype() and
      M.has_lsp_clients(bufnr)
end

-- Location info utilities
local LocationUtils = {}

-- Get shortened file path
function LocationUtils.get_short_path(file_path)
  if #file_path <= 50 then
    return file_path
  end
  return ".../" .. file_path:sub(#file_path - 54)
end

-- Check if location is valid
function LocationUtils.is_valid(location)
  return location and
      location.file and location.file ~= "" and
      location.line and location.line > 0 and
      location.col and location.col > 0
end

-- Compare two locations for equality
function LocationUtils.equals(loc1, loc2)
  if not loc1 and not loc2 then
    return true
  end
  if not loc1 or not loc2 then
    return false
  end

  return loc1.file == loc2.file and
      loc1.line == loc2.line and
      loc1.col == loc2.col
end

M.location = LocationUtils

return M
