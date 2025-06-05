local M = {}

local ipc = require('hoverfloat.ipc')

local config = {
  update_delay = 50,
  window_title = "Neovim Context Info",
  terminal_cmd = "alacritty",
  auto_start = true,
  show_references_count = true,
  show_type_info = true,
  show_definition_location = true,
  max_references_shown = 5,
  excluded_filetypes = { "markdown", "text", "help" },
}

local last_position = { 0, 0 }
local update_timer = nil

-- Helper function to check if LSP is available
local function has_lsp_clients()
  local clients = vim.lsp.get_active_clients({ bufnr = 0 })
  return #clients > 0
end

-- Check if we should skip updating for this filetype
local function should_skip_update()
  local filetype = vim.bo.filetype
  for _, excluded in ipairs(config.excluded_filetypes) do
    if filetype == excluded then
      return true
    end
  end
  return false
end

-- Check if cursor position changed significantly
local function position_changed()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local changed = cursor[1] ~= last_position[1] or math.abs(cursor[2] - last_position[2]) >= 3
  
  if changed then
    last_position = cursor
  end
  
  return changed
end

-- Trim empty lines from array
local function trim_empty_lines(lines)
  local trimmed = {}
  for _, line in ipairs(lines) do
    if line and line:match("%S") then
      table.insert(trimmed, line)
    end
  end
  return trimmed
end

-- Get comprehensive information about symbol under cursor
local function gather_symbol_info(callback)
  local params = vim.lsp.util.make_position_params()
  local results = {
    current_file = vim.fn.expand('%:~:.'),
    cursor_line = vim.fn.line('.'),
    cursor_col = vim.fn.col('.'),
  }
  local pending_requests = 0
  
  local function check_completion()
    pending_requests = pending_requests - 1
    if pending_requests == 0 then
      callback(results)
    end
  end

  -- Get hover information
  pending_requests = pending_requests + 1
  vim.lsp.buf_request(0, 'textDocument/hover', params, function(err, result)
    if not err and result and result.contents then
      local hover_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
      results.hover = trim_empty_lines(hover_lines)
    end
    check_completion()
  end)

  -- Get references
  if config.show_references_count then
    pending_requests = pending_requests + 1
    vim.lsp.buf_request(0, 'textDocument/references', vim.tbl_extend('force', params, {
      context = { includeDeclaration = true }
    }), function(err, result)
      if not err and result then
        results.references_count = #result
        results.references = {}
        for i, ref in ipairs(result) do
          if i <= config.max_references_shown and ref.uri then
            local file_path = vim.uri_to_fname(ref.uri)
            local relative_path = vim.fn.fnamemodify(file_path, ':~:.')
            table.insert(results.references, relative_path .. ":" .. (ref.range.start.line + 1))
          end
        end
        if #result > config.max_references_shown then
          table.insert(results.references, "... and " .. (#result - config.max_references_shown) .. " more")
        end
      end
      check_completion()
    end)
  end

  -- Get definition location
  if config.show_definition_location then
    pending_requests = pending_requests + 1
    vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result)
      if not err and result and #result > 0 then
        local def = result[1]
        if def.uri then
          local file_path = vim.uri_to_fname(def.uri)
          local relative_path = vim.fn.fnamemodify(file_path, ':~:.')
          results.definition_location = {
            file = relative_path,
            line = def.range.start.line + 1,
            character = def.range.start.character + 1
          }
        end
      end
      check_completion()
    end)
  end
end

-- Update context information
local function update_context()
  if not has_lsp_clients() then
    ipc.send_data({error = "No LSP server active for this buffer"})
    return
  end

  if not position_changed() then
    return
  end

  gather_symbol_info(function(info)
    ipc.send_data(info)
  end)
end

-- Debounced update function
local function debounced_update()
  if update_timer then
    vim.fn.timer_stop(update_timer)
  end
  
  update_timer = vim.fn.timer_start(config.update_delay, function()
    update_context()
    update_timer = nil
  end)
end

-- Setup autocmds for cursor tracking
local function setup_cursor_tracking()
  local group = vim.api.nvim_create_augroup("HoverFloatCursor", { clear = true })
  
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = group,
    callback = function()
      if should_skip_update() then
        return
      end
      debounced_update()
    end,
  })
  
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if has_lsp_clients() then
        vim.defer_fn(debounced_update, 100)
      end
    end,
  })
end

-- Setup commands and keymaps
local function setup_commands()
  vim.api.nvim_create_user_command("ContextWindowOpen", function()
    ipc.start_display(config)
  end, { desc = "Open separate context window" })
  
  vim.api.nvim_create_user_command("ContextWindowClose", function()
    ipc.stop_display()
  end, { desc = "Close separate context window" })
  
  vim.keymap.set('n', '<leader>co', ':ContextWindowOpen<CR>', { desc = 'Open Context Window', silent = true })
  vim.keymap.set('n', '<leader>cc', ':ContextWindowClose<CR>', { desc = 'Close Context Window', silent = true })
end

-- Main setup function
function M.setup(opts)
  -- Merge user config with defaults
  config = vim.tbl_deep_extend("force", config, opts or {})
  
  -- Initialize IPC module
  ipc.setup()
  
  -- Setup cursor tracking
  setup_cursor_tracking()
  
  -- Setup commands and keymaps
  setup_commands()
  
  -- Auto-start if configured
  if config.auto_start then
    vim.defer_fn(function()
      ipc.start_display(config)
    end, 500)
  end
end

return M
