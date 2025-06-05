-- lua/hoverfloat/init.lua - Main plugin entry point
local M = {}

local lsp_collector = require('hoverfloat.lsp_collector')
local socket_client = require('hoverfloat.socket_client')

-- Default configuration
local default_config = {
  -- TUI settings
  tui = {
    binary_name = "nvim-context-tui",
    binary_path = nil, -- Auto-detect or user-specified
    window_title = "LSP Context",
    window_size = { width = 80, height = 25 },
    terminal_cmd = "kitty", -- Terminal to spawn TUI in
  },

  -- Communication settings
  communication = {
    socket_path = "/tmp/nvim_context.sock",
    timeout = 5000,
    retry_attempts = 3,
    update_delay = 50, -- Debounce delay in milliseconds (reduced due to smart content filtering)
  },

  -- LSP feature toggles
  features = {
    show_hover = true,
    show_references = true,
    show_definition = true,
    show_type_info = true,
    max_hover_lines = 15,
    max_references = 8,
  },

  -- Cursor tracking settings
  tracking = {
    excluded_filetypes = { "help", "qf", "netrw", "fugitive", "TelescopePrompt" },
  },

  -- Auto-start settings
  auto_start = true,
  auto_restart_on_error = true,
}

-- Plugin state
local state = {
  config = {},
  last_position = { 0, 0 },
  update_timer = nil,
  display_process = nil,
  socket_connected = false,
  plugin_enabled = true,
  binary_path = nil,
  -- Only cache the last message sent to prevent duplicate sends
  last_sent_hash = nil,
  -- Prevent overlapping LSP collection calls
  lsp_collection_in_progress = false,
}

-- Helper function to find TUI binary
local function find_tui_binary()
  if state.binary_path then
    return state.binary_path
  end

  local possible_paths = {
    -- Development paths
    './nvim-context-tui',
    './build/nvim-context-tui',
    './cmd/context-tui/nvim-context-tui',

    -- Plugin installation paths
    vim.fn.stdpath('data') .. '/lazy/nvim-hoverfloat/nvim-context-tui',
    vim.fn.stdpath('data') .. '/lazy/nvim-hoverfloat/build/nvim-context-tui',

    -- User installation paths
    vim.fn.expand('~/.local/bin/nvim-context-tui'),
    '/usr/local/bin/nvim-context-tui',
    '/usr/bin/nvim-context-tui',
  }

  for _, path in ipairs(possible_paths) do
    if vim.fn.executable(path) == 1 then
      state.binary_path = path
      return path
    end
  end

  -- Try PATH
  if vim.fn.executable(state.config.tui.binary_name) == 1 then
    state.binary_path = state.config.tui.binary_name
    return state.binary_path
  end

  return nil
end

-- Health check function
function M.health()
  local health = vim.health or require('health')

  health.start('nvim-hoverfloat')

  -- Check if TUI binary exists
  local binary_path = find_tui_binary()
  if binary_path then
    health.ok('TUI binary found: ' .. binary_path)
  else
    health.error('TUI binary not found', {
      'Run `make build` in the plugin directory',
      'Or install with `make install`',
      'Or ensure nvim-context-tui is in your PATH'
    })
  end

  -- Check LSP availability
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 then
    health.ok(string.format('LSP clients available (%d active)', #clients))
    for _, client in ipairs(clients) do
      health.info('  • ' .. (client.name or 'unnamed'))
    end
  else
    health.warn('No LSP clients attached to current buffer')
  end

  -- Check terminal
  if vim.fn.executable(state.config.tui.terminal_cmd) == 1 then
    health.ok('Terminal executable found: ' .. state.config.tui.terminal_cmd)
  else
    health.error('Terminal not found: ' .. state.config.tui.terminal_cmd, {
      'Install kitty or update config.tui.terminal_cmd'
    })
  end

  -- Check socket permissions
  local socket_dir = vim.fn.fnamemodify(state.config.communication.socket_path, ':h')
  if vim.fn.isdirectory(socket_dir) == 1 then
    health.ok('Socket directory accessible: ' .. socket_dir)
  else
    health.warn('Socket directory not accessible: ' .. socket_dir)
  end

  -- Plugin status
  if state.plugin_enabled then
    health.ok('Plugin enabled')
  else
    health.warn('Plugin disabled')
  end

  if state.display_process then
    health.ok('TUI process running')
  else
    health.info('TUI process not running')
  end

  if state.socket_connected then
    health.ok('Socket connected')
  else
    health.info('Socket not connected')
  end
end

-- Helper function to check if LSP clients are available
local function has_lsp_clients()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  return #clients > 0
end

-- Check if current filetype should be excluded
local function should_skip_update()
  local filetype = vim.bo.filetype
  for _, excluded in ipairs(state.config.tracking.excluded_filetypes) do
    if filetype == excluded then
      return true
    end
  end
  return false
end

-- Generate content hash for LSP context data (excluding timestamp)
local function hash_context_data(context_data)
  if not context_data then return nil end
  
  -- Create stable representation excluding volatile fields like timestamp
  local stable_data = {
    file = context_data.file,
    hover = context_data.hover,
    definition = context_data.definition,
    references_count = context_data.references_count,
    references = context_data.references,
    references_more = context_data.references_more,
    type_definition = context_data.type_definition,
  }
  
  return vim.fn.sha256(vim.json.encode(stable_data))
end

-- Check if we should update context - now much simpler, just basic checks
local function should_update_context()
  if not state.plugin_enabled then return false end
  if not has_lsp_clients() then return false end
  if should_skip_update() then return false end
  
  return true
end

-- Content-based context update - only prevents sending exact duplicates
local function update_context()
  if not should_update_context() then
    return
  end

  -- Prevent overlapping LSP collection calls that can cause race conditions
  if state.lsp_collection_in_progress then
    return
  end

  state.lsp_collection_in_progress = true

  -- Always collect LSP context information 
  lsp_collector.gather_context_info(function(context_data)
    state.lsp_collection_in_progress = false
    
    if not context_data then
      return
    end
    
    -- Generate hash of the new context data
    local new_hash = hash_context_data(context_data)
    
    -- Only skip if this is EXACTLY the same as the last message we sent
    if new_hash ~= state.last_sent_hash then
      -- Content is different from last sent message, send update
      state.last_sent_hash = new_hash
      socket_client.send_context_update(context_data)
    end
  end, state.config.features)
end

-- Debounced update function (much shorter delay since we now do smart content filtering)
local function debounced_update()
  if state.update_timer then
    vim.fn.timer_stop(state.update_timer)
  end

  -- Use shorter delay (50ms) since we now have intelligent content filtering
  local delay = math.min(state.config.communication.update_delay, 50)
  state.update_timer = vim.fn.timer_start(delay, function()
    update_context()
    state.update_timer = nil
  end)
end

-- Start the display process
local function start_display_process()
  if state.display_process then
    vim.notify("Display process already running", vim.log.levels.WARN)
    return true
  end

  -- Find TUI binary
  local binary_path = find_tui_binary()
  if not binary_path then
    vim.notify("TUI binary not found. Run :checkhealth nvim-hoverfloat for help.", vim.log.levels.ERROR)
    return false
  end

  -- Build terminal command
  local terminal_args = {
    "--title=" .. state.config.tui.window_title,
    "--override=initial_window_width=" .. state.config.tui.window_size.width .. "c",
    "--override=initial_window_height=" .. state.config.tui.window_size.height .. "c",
    "--override=remember_window_size=no",
    "--hold",
    "-e", binary_path, state.config.communication.socket_path
  }

  -- Start the terminal with TUI
  local handle = vim.fn.jobstart(
    { state.config.tui.terminal_cmd, unpack(terminal_args) },
    {
      detach = true,
      on_exit = function(job_id, exit_code, event)
        state.display_process = nil
        state.socket_connected = false

        if exit_code ~= 0 and state.config.auto_restart_on_error then
          vim.notify("Display process exited unexpectedly, restarting...", vim.log.levels.WARN)
          vim.defer_fn(start_display_process, 1000)
        end
      end,
      on_stderr = function(job_id, data, event)
        if #data > 1 or (data[1] and data[1] ~= "") then
          vim.notify("TUI error: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
        end
      end
    }
  )

  if handle > 0 then
    state.display_process = handle
    vim.notify("Context display window started", vim.log.levels.INFO)

    -- Wait a moment for the display to initialize, then connect socket
    vim.defer_fn(function()
      socket_client.connect(state.config.communication.socket_path)
      -- Send initial update
      vim.defer_fn(debounced_update, 500)
    end, 1000)

    return true
  else
    vim.notify("Failed to start display process", vim.log.levels.ERROR)
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
    vim.notify("Context display window closed", vim.log.levels.INFO)
  end
end

-- Setup autocmds for cursor tracking
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("HoverFloatContext", { clear = true })

  -- Track cursor movement
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
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
  vim.api.nvim_create_user_command('ContextWindow', function(opts)
    local action = opts.args ~= '' and opts.args or 'toggle'

    if action == 'open' or action == 'start' then
      start_display_process()
    elseif action == 'close' or action == 'stop' then
      stop_display_process()
    elseif action == 'toggle' then
      if state.display_process then
        stop_display_process()
      else
        start_display_process()
      end
    elseif action == 'restart' then
      stop_display_process()
      vim.defer_fn(start_display_process, 500)
    elseif action == 'status' then
      print(vim.inspect(M.get_status()))
    elseif action == 'health' then
      M.health()
    elseif action == 'debug' then
      -- Force trigger LSP collection for debugging
      vim.notify("Debug: Forcing LSP data collection...", vim.log.levels.INFO)
      vim.notify("Debug: Last sent hash: " .. (state.last_sent_hash or "none"), vim.log.levels.INFO)
      -- Enable socket debug temporarily for this command
      socket_client.enable_debug()
      -- Force update by clearing cache
      state.last_sent_hash = nil
      update_context()
      -- Disable debug after brief delay
      vim.defer_fn(function()
        socket_client.disable_debug()
      end, 2000)
    else
      vim.notify('Usage: ContextWindow [open|close|toggle|restart|status|health|debug]', vim.log.levels.INFO)
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'open', 'close', 'toggle', 'restart', 'status', 'health', 'debug' }
    end,
    desc = 'Manage LSP context window'
  })

  -- Legacy commands for backwards compatibility
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
end

-- Setup keymaps
local function setup_keymaps()
  vim.keymap.set('n', '<leader>co', ':ContextWindow open<CR>',
    { desc = 'Open Context Window', silent = true })
  vim.keymap.set('n', '<leader>cc', ':ContextWindow close<CR>',
    { desc = 'Close Context Window', silent = true })
  vim.keymap.set('n', '<leader>ct', ':ContextWindow toggle<CR>',
    { desc = 'Toggle Context Window', silent = true })
  vim.keymap.set('n', '<leader>cr', ':ContextWindow restart<CR>',
    { desc = 'Restart Context Window', silent = true })
  vim.keymap.set('n', '<leader>cs', ':ContextWindow status<CR>',
    { desc = 'Context Window Status', silent = true })
end

-- Main setup function
function M.setup(opts)
  -- Merge user configuration with defaults
  state.config = vim.tbl_deep_extend("force", default_config, opts or {})

  -- Initialize socket client
  socket_client.setup(state.config.communication)

  -- Setup plugin components
  setup_autocmds()
  setup_commands()
  setup_keymaps()

  -- Auto-start if configured
  if state.config.auto_start then
    vim.defer_fn(function()
      start_display_process()
    end, 1000) -- Give Neovim time to fully load
  end

  vim.notify("LSP Context Window plugin loaded", vim.log.levels.INFO)
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
  vim.notify("Context window plugin enabled", vim.log.levels.INFO)
end

M.disable = function()
  state.plugin_enabled = false
  vim.notify("Context window plugin disabled", vim.log.levels.INFO)
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
    binary_path = state.binary_path,
    config = state.config,
    -- Only track last sent message hash
    last_sent_hash = state.last_sent_hash,
    lsp_collection_in_progress = state.lsp_collection_in_progress,
    lsp_cache_stats = lsp_collector.get_cache_stats(),
  }
end

M.get_config = function()
  return vim.deepcopy(state.config)
end

M.set_binary_path = function(path)
  if vim.fn.executable(path) == 1 then
    state.binary_path = path
    return true
  else
    vim.notify("Binary not executable: " .. path, vim.log.levels.ERROR)
    return false
  end
end

-- Clear content cache (useful for debugging or forcing updates)
M.clear_content_cache = function()
  state.last_sent_hash = nil
  state.lsp_collection_in_progress = false
  lsp_collector.clear_cache()
  vim.notify("Content cache cleared", vim.log.levels.INFO)
end

return M
