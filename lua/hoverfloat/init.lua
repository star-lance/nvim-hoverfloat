-- lua/hoverfloat/init.lua - Main plugin entry point
local M = {}

local lsp_collector = require('hoverfloat.lsp_collector')
local socket_client = require('hoverfloat.socket_client')

-- Plugin configuration
local config = {
  -- Display settings
  socket_path = "/tmp/nvim_context.sock",
  update_delay = 150,     -- Debounce delay in milliseconds
  window_title = "LSP Context",
  
  -- Kitty terminal settings
  terminal_cmd = "kitty",
  terminal_args = {
    "--title=LSP Context",
    "--override=font_size=11",
    "--override=remember_window_size=no",
    "--override=initial_window_width=80c",
    "--override=initial_window_height=25c",
    "--hold",
    "-e", "python3"
  },
  
  -- LSP feature toggles
  show_references_count = true,
  show_type_info = true,
  show_definition_location = true,
  max_references_shown = 8,
  max_hover_lines = 8,
  
  -- Cursor tracking settings
  excluded_filetypes = { "help", "qf", "netrw", "fugitive" },
  min_cursor_movement = 3,  -- Minimum column movement to trigger update
  
  -- Auto-start settings
  auto_start = true,
  auto_restart_on_error = true,
}

-- State tracking
local state = {
  last_position = { 0, 0 },
  update_timer = nil,
  display_process = nil,
  socket_connected = false,
  plugin_enabled = true,
}

-- Helper function to check if LSP clients are available
local function has_lsp_clients()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  return #clients > 0
end

-- Check if current filetype should be excluded
local function should_skip_update()
  local filetype = vim.bo.filetype
  for _, excluded in ipairs(config.excluded_filetypes) do
    if filetype == excluded then
      return true
    end
  end
  return false
end

-- Check if cursor moved significantly
local function cursor_moved_significantly()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local moved = cursor[1] ~= state.last_position[1] or 
                math.abs(cursor[2] - state.last_position[2]) >= config.min_cursor_movement
  
  if moved then
    state.last_position = cursor
  end
  
  return moved
end

-- Update context information and send to display window
local function update_context()
  if not state.plugin_enabled then return end
  if not has_lsp_clients() then
    socket_client.send_error("No LSP server active for this buffer")
    return
  end
  
  if should_skip_update() then return end
  if not cursor_moved_significantly() then return end
  
  -- Collect LSP information
  lsp_collector.gather_context_info(function(context_data)
    if context_data then
      socket_client.send_context_update(context_data)
    end
  end, config)
end

-- Debounced update function
local function debounced_update()
  if state.update_timer then
    vim.fn.timer_stop(state.update_timer)
  end
  
  state.update_timer = vim.fn.timer_start(config.update_delay, function()
    update_context()
    state.update_timer = nil
  end)
end

-- Start the display process
local function start_display_process()
  if state.display_process then
    print("Display process already running")
    return true
  end
  
  -- Create the display script path
  local script_path = debug.getinfo(1).source:match("@?(.*/)")
  local display_script = script_path .. "../../scripts/context_display.py"
  
  -- Build command arguments
  local cmd_args = vim.deepcopy(config.terminal_args)
  table.insert(cmd_args, display_script)
  table.insert(cmd_args, config.socket_path)
  
  -- Start the terminal with display script
  local handle = vim.fn.jobstart(
    { config.terminal_cmd, unpack(cmd_args) },
    {
      detach = true,
      on_exit = function(job_id, exit_code, event)
        state.display_process = nil
        state.socket_connected = false
        
        if exit_code ~= 0 and config.auto_restart_on_error then
          print("Display process exited unexpectedly, restarting...")
          vim.defer_fn(start_display_process, 1000)
        end
      end
    }
  )
  
  if handle > 0 then
    state.display_process = handle
    print("Context display window started")
    
    -- Wait a moment for the display to initialize, then connect socket
    vim.defer_fn(function()
      socket_client.connect(config.socket_path)
      -- Send initial update
      vim.defer_fn(debounced_update, 500)
    end, 1000)
    
    return true
  else
    print("Failed to start display process")
    return false
  end
end

-- Stop the display process
local function stop_display_process()
  socket_client.disconnect()
  
  if state.display_process then
    vim.fn.jobstop(state.display_process)
    state.display_process = nil
    state.socket_connected = false
    print("Context display window closed")
  end
end

-- Setup autocmds for cursor tracking
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("HoverFloatContext", { clear = true })
  
  -- Track cursor movement
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = group,
    callback = function()
      if not state.plugin_enabled then return end
      debounced_update()
    end,
  })
  
  -- Update on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if not state.plugin_enabled then return end
      if has_lsp_clients() then
        vim.defer_fn(debounced_update, 100)
      end
    end,
  })
  
  -- Handle LSP attach/detach
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function()
      if not state.plugin_enabled then return end
      vim.defer_fn(debounced_update, 200)
    end,
  })
  
  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      stop_display_process()
    end,
  })
end

-- Setup user commands
local function setup_commands()
  vim.api.nvim_create_user_command("ContextWindowOpen", function()
    start_display_process()
  end, { desc = "Open LSP context display window" })
  
  vim.api.nvim_create_user_command("ContextWindowClose", function()
    stop_display_process()
  end, { desc = "Close LSP context display window" })
  
  vim.api.nvim_create_user_command("ContextWindowToggle", function()
    if state.display_process then
      stop_display_process()
    else
      start_display_process()
    end
  end, { desc = "Toggle LSP context display window" })
  
  vim.api.nvim_create_user_command("ContextWindowRestart", function()
    stop_display_process()
    vim.defer_fn(start_display_process, 500)
  end, { desc = "Restart LSP context display window" })
  
  vim.api.nvim_create_user_command("ContextWindowEnable", function()
    state.plugin_enabled = true
    print("Context window plugin enabled")
  end, { desc = "Enable context window updates" })
  
  vim.api.nvim_create_user_command("ContextWindowDisable", function()
    state.plugin_enabled = false
    print("Context window plugin disabled")
  end, { desc = "Disable context window updates" })
end

-- Setup keymaps
local function setup_keymaps()
  vim.keymap.set('n', '<leader>co', ':ContextWindowOpen<CR>', 
    { desc = 'Open Context Window', silent = true })
  vim.keymap.set('n', '<leader>cc', ':ContextWindowClose<CR>', 
    { desc = 'Close Context Window', silent = true })
  vim.keymap.set('n', '<leader>ct', ':ContextWindowToggle<CR>', 
    { desc = 'Toggle Context Window', silent = true })
  vim.keymap.set('n', '<leader>cr', ':ContextWindowRestart<CR>', 
    { desc = 'Restart Context Window', silent = true })
end

-- Main setup function
function M.setup(opts)
  -- Merge user configuration
  config = vim.tbl_deep_extend("force", config, opts or {})
  
  -- Initialize socket client
  socket_client.setup(config)
  
  -- Setup plugin components
  setup_autocmds()
  setup_commands()
  setup_keymaps()
  
  -- Auto-start if configured
  if config.auto_start then
    vim.defer_fn(function()
      start_display_process()
    end, 1000)  -- Give Neovim time to fully load
  end
  
  print("LSP Context Window plugin loaded")
end

-- Public API
M.start = start_display_process
M.stop = stop_display_process
M.toggle = function()
  if state.display_process then
    stop_display_process()
  else
    start_display_process()
  end
end

M.enable = function()
  state.plugin_enabled = true
end

M.disable = function()
  state.plugin_enabled = false
end

M.is_running = function()
  return state.display_process ~= nil
end

M.get_status = function()
  return {
    enabled = state.plugin_enabled,
    running = state.display_process ~= nil,
    connected = state.socket_connected,
    last_position = state.last_position,
  }
end

return M
