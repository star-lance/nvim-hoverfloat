-- lua/hoverfloat/utils/symbols.lua - Symbol processing utilities and extraction
local M = {}

-- LSP Symbol kinds mapping
local symbol_kinds = {
  [1] = "File",
  [2] = "Module",
  [3] = "Namespace", 
  [4] = "Package",
  [5] = "Class",
  [6] = "Method",
  [7] = "Property",
  [8] = "Field",
  [9] = "Constructor",
  [10] = "Enum",
  [11] = "Interface",
  [12] = "Function",
  [13] = "Variable",
  [14] = "Constant",
  [15] = "String",
  [16] = "Number",
  [17] = "Boolean",
  [18] = "Array",
  [19] = "Object",
  [20] = "Key",
  [21] = "Null",
  [22] = "EnumMember",
  [23] = "Struct",
  [24] = "Event",
  [25] = "Operator",
  [26] = "TypeParameter",
}

-- Symbol extraction functions (moved from position.lua and new)

-- Get word under cursor
function M.get_word_under_cursor()
  return vim.fn.expand('<cword>') or ''
end

-- Get WORD under cursor (includes more characters)
function M.get_WORD_under_cursor()
  return vim.fn.expand('<cWORD>') or ''
end

-- Get symbol at cursor with position context
function M.get_symbol_at_cursor()
  local position = require('hoverfloat.core.position')
  local symbol = M.get_word_under_cursor()
  local pos = position.get_current_context()
  
  return {
    symbol = symbol,
    word = symbol, -- alias for compatibility
    file = pos.file,
    line = pos.line,
    col = pos.col,
    bufnr = pos.bufnr,
  }
end

-- Extract symbol at specific position
function M.extract_symbol_from_position(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  
  -- Save current position
  local current_win = vim.api.nvim_get_current_win()
  local current_pos = vim.api.nvim_win_get_cursor(current_win)
  
  -- Temporarily move cursor to target position
  vim.api.nvim_win_set_cursor(current_win, { line, col - 1 }) -- Convert to 0-based
  
  local symbol = M.get_word_under_cursor()
  
  -- Restore cursor position
  vim.api.nvim_win_set_cursor(current_win, current_pos)
  
  return symbol ~= '' and symbol or nil
end

-- Get symbol kind name
function M.get_symbol_kind_name(kind)
  return symbol_kinds[kind] or "Unknown"
end

-- Get symbol icon based on kind
function M.get_symbol_icon(kind)
  local icons = {
    [1] = "📄", -- File
    [2] = "📦", -- Module
    [3] = "🏠", -- Namespace
    [4] = "📦", -- Package
    [5] = "🏛️", -- Class
    [6] = "⚡", -- Method
    [7] = "🔧", -- Property
    [8] = "🏷️", -- Field
    [9] = "🏗️", -- Constructor
    [10] = "📋", -- Enum
    [11] = "🔌", -- Interface
    [12] = "⚡", -- Function
    [13] = "📊", -- Variable
    [14] = "🔒", -- Constant
    [15] = "📝", -- String
    [16] = "🔢", -- Number
    [17] = "✅", -- Boolean
    [18] = "📊", -- Array
    [19] = "📦", -- Object
    [20] = "🔑", -- Key
    [21] = "⭕", -- Null
    [22] = "📋", -- EnumMember
    [23] = "🏗️", -- Struct
    [24] = "📡", -- Event
    [25] = "⚙️", -- Operator
    [26] = "🏷️", -- TypeParameter
  }
  return icons[kind] or "❓"
end

-- Check if symbol should be prefetched based on its kind
function M.should_prefetch_symbol(symbol)
  -- Skip certain symbol types that are less useful for hover info
  local skip_kinds = {
    [1] = true,  -- File
    [2] = true,  -- Module  
    [3] = true,  -- Namespace
    [4] = true,  -- Package
  }
  
  return not skip_kinds[symbol.kind]
end

-- Get symbol priority for prefetching (higher = more important)
function M.get_symbol_priority(symbol)
  local priorities = {
    [12] = 10, -- Function - highest priority
    [6] = 10,  -- Method - highest priority
    [5] = 9,   -- Class
    [11] = 9,  -- Interface
    [13] = 8,  -- Variable
    [14] = 8,  -- Constant
    [7] = 7,   -- Property
    [8] = 7,   -- Field
    [9] = 6,   -- Constructor
    [10] = 5,  -- Enum
    [22] = 5,  -- EnumMember
    [23] = 5,  -- Struct
  }
  
  return priorities[symbol.kind] or 3
end

-- Check if symbol overlaps with line range
function M.symbol_overlaps_range(symbol, start_line, end_line)
  return symbol.start_line <= end_line and symbol.end_line >= start_line
end

-- Filter symbols by line range
function M.filter_symbols_by_range(symbols, start_line, end_line)
  local filtered = {}
  for _, symbol in ipairs(symbols) do
    if M.symbol_overlaps_range(symbol, start_line, end_line) then
      table.insert(filtered, symbol)
    end
  end
  return filtered
end

-- Sort symbols by priority for prefetching
function M.sort_symbols_by_priority(symbols)
  local sorted = vim.deepcopy(symbols)
  table.sort(sorted, function(a, b)
    local priority_a = M.get_symbol_priority(a)
    local priority_b = M.get_symbol_priority(b)
    
    if priority_a ~= priority_b then
      return priority_a > priority_b
    end
    
    -- Secondary sort by line number
    return a.start_line < b.start_line
  end)
  return sorted
end

-- Find symbol at specific position
function M.find_symbol_at_position(symbols, line, col)
  for _, symbol in ipairs(symbols) do
    if symbol.start_line <= line and symbol.end_line >= line then
      -- Check if column is within symbol range
      if line == symbol.start_line and col < symbol.start_col then
        goto continue
      end
      if line == symbol.end_line and col > symbol.end_col then
        goto continue
      end
      return symbol
    end
    ::continue::
  end
  return nil
end

-- Get symbols near cursor position
function M.get_symbols_near_position(symbols, line, col, radius)
  radius = radius or 5
  local near_symbols = {}
  
  for _, symbol in ipairs(symbols) do
    local distance = math.min(
      math.abs(symbol.start_line - line),
      math.abs(symbol.end_line - line)
    )
    
    if distance <= radius then
      table.insert(near_symbols, {
        symbol = symbol,
        distance = distance
      })
    end
  end
  
  -- Sort by distance
  table.sort(near_symbols, function(a, b)
    return a.distance < b.distance
  end)
  
  -- Return just the symbols
  local result = {}
  for _, item in ipairs(near_symbols) do
    table.insert(result, item.symbol)
  end
  
  return result
end

-- Group symbols by kind
function M.group_symbols_by_kind(symbols)
  local groups = {}
  
  for _, symbol in ipairs(symbols) do
    local kind_name = M.get_symbol_kind_name(symbol.kind)
    if not groups[kind_name] then
      groups[kind_name] = {}
    end
    table.insert(groups[kind_name], symbol)
  end
  
  return groups
end

-- Get symbol summary for debugging
function M.get_symbol_summary(symbols)
  local summary = {
    total = #symbols,
    by_kind = {},
    line_range = { min = math.huge, max = 0 }
  }
  
  for _, symbol in ipairs(symbols) do
    local kind_name = M.get_symbol_kind_name(symbol.kind)
    summary.by_kind[kind_name] = (summary.by_kind[kind_name] or 0) + 1
    
    summary.line_range.min = math.min(summary.line_range.min, symbol.start_line)
    summary.line_range.max = math.max(summary.line_range.max, symbol.end_line)
  end
  
  if summary.total == 0 then
    summary.line_range = { min = 0, max = 0 }
  end
  
  return summary
end

-- Validate symbol structure
function M.validate_symbol(symbol)
  local required_fields = { "name", "kind", "start_line", "end_line", "start_col", "end_col" }
  
  for _, field in ipairs(required_fields) do
    if not symbol[field] then
      return false, "Missing field: " .. field
    end
  end
  
  -- Validate ranges
  if symbol.start_line > symbol.end_line then
    return false, "Invalid line range"
  end
  
  if symbol.start_line == symbol.end_line and symbol.start_col > symbol.end_col then
    return false, "Invalid column range"
  end
  
  return true
end

-- Clean and validate symbols array
function M.clean_symbols(symbols)
  local cleaned = {}
  
  for _, symbol in ipairs(symbols) do
    local valid, error_msg = M.validate_symbol(symbol)
    if valid then
      table.insert(cleaned, symbol)
    end
  end
  
  return cleaned
end

-- Enhanced symbol detection for better extraction
function M.get_symbol_info_at_cursor()
  local symbol_data = M.get_symbol_at_cursor()
  local WORD = M.get_WORD_under_cursor()
  
  return {
    word = symbol_data.symbol,
    WORD = WORD,
    line = symbol_data.line,
    col = symbol_data.col,
    file = symbol_data.file,
    bufnr = symbol_data.bufnr,
    is_empty = symbol_data.symbol == '',
    has_dots = symbol_data.symbol:find('%.') ~= nil,
    has_special = WORD ~= symbol_data.symbol,
  }
end

-- Check if current position is on a symbol worth caching
function M.is_cacheable_symbol_position()
  local info = M.get_symbol_info_at_cursor()
  
  -- Skip empty symbols or very short ones
  if info.is_empty or #info.word < 2 then
    return false
  end
  
  -- Skip common keywords that don't have useful hover info
  local skip_keywords = {
    ['if'] = true, ['else'] = true, ['for'] = true, ['while'] = true,
    ['function'] = true, ['return'] = true, ['local'] = true,
    ['and'] = true, ['or'] = true, ['not'] = true,
    ['true'] = true, ['false'] = true, ['nil'] = true,
  }
  
  return not skip_keywords[info.word:lower()]
end

return M
