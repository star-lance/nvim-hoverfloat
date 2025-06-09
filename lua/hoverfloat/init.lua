-- lua/hoverfloat/init.lua - Main plugin entry point (Persistent Connection Version)
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

  -- Communication settings (updated for persistent connections)
  communication = {
    socket_path = "/tmp/nvim_context.sock",
    reconnect_delay = 2000,       -- 2 seconds initial reconnection delay
    max_reconnect_delay = 30000,  -- 30 seconds max reconnection delay
    heartbeat_interval = 10000,   -- 10 seconds heartbeat interval
    connection_timeout = 5000,    -- 5 seconds connection timeout
    heartbeat_timeout = 30000,    -- 30 seconds before considering connection dead
    max_queue_size = 100,         -- Maximum queued messages
    max_connection_attempts = 10, -- Max connection attempts before giving up
    update_delay = 50,            -- Debounce delay for cursor updates (ms)
    debug = false,                -- Enable debug logging
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
  auto_connect = true, -- Automatically connect to TUI when available
}

-- Plugin state
local state = {
  config = {},
  update_timer = nil,
  display_process = nil,
  plugin_enabled = true,
  binary_path = nil,
  last_sent_hash = nil,
  lsp_collection_in_progress = false,
  connection_status_timer = nil,
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

-- Check if we should update context
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

      -- Send through persistent connection
      local success = socket_client.send_context_update(context_data)
      if not success and state.config.communication.debug then
        vim.notify("Failed to send context update (will be queued)", vim.log.levels.DEBUG)
      end
    end
  end, state.config.features)
end

-- Debounced update function
local function debounced_update()
  if state.update_timer then
    vim.fn.timer_stop(state.update_timer)
  end

  local delay = state.config.communication.update_delay or 50
  state.update_timer = vim.fn.timer_start(delay, function()
    update_context()
    state.update_timer = nil
  end)
end

-- Connection status monitoring
local function monitor_connection_status()
  if state.connection_status_timer then
    vim.fn.timer_stop(state.connection_status_timer)
  end

  state.connection_status_timer = vim.fn.timer_start(5000, function() -- Check every 5 seconds
    if not socket_client.is_connected() and state.display_process then
      -- TUI is running but socket is disconnected
      if state.config.auto_connect then
        socket_client.ensure_connected()
      end
    end
  end, { ['repeat'] = -1 })
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
    vim.notify("TUI binary not found. Run `make install` to build the binary.", vim.log.levels.ERROR)
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

        -- Disconnect socket when TUI exits
        socket_client.disconnect()

        -- Stop connection monitoring
        if state.connection_status_timer then
          vim.fn.timer_stop(state.connection_status_timer)
          state.connection_status_timer = nil
        end

        if exit_code ~= 0 and state.config.auto_restart_on_error then
          vim.notify("Display process exited unexpectedly, restarting...", vim.log.levels.WARN)
          vim.defer_fn(start_display_process, 2000)
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

    -- Wait for TUI to initialize, then try to connect
    vim.defer_fn(function()
      if state.config.auto_connect then
        socket_client.connect(state.config.communication.socket_path)
      end

      -- Start connection monitoring
      monitor_connection_status()

      -- Send initial update after connection is established
      vim.defer_fn(function()
        if socket_client.is_connected() then
          debounced_update()
        end
      end, 1000)
    end, 1000)

    return true
  else
    vim.notify("Failed to start display process", vim.log.levels.ERROR)
    return false
  end
end

-- Stop the display process
local function stop_display_process()
  -- Disconnect socket first
  socket_client.disconnect()

  -- Stop connection monitoring
  if state.connection_status_timer then
    vim.fn.timer_stop(state.connection_status_timer)
    state.connection_status_timer = nil
  end

  if state.display_process then
    vim.fn.jobstop(state.display_process)
    state.display_process = nil
    vim.notify("Context display window closed", vim.log.levels.INFO)
  end
end

-- Setup autocmds for cursor tracking
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("HoverFloatContext", { clear = true })

  -- Track cursor movement (only if socket is connected)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      if not state.plugin_enabled then return end
      if socket_client.is_connected() then
        debounced_update()
      end
    end,
  })

  -- Update on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if not state.plugin_enabled then return end
      if has_lsp_clients() and socket_client.is_connected() then
        vim.defer_fn(debounced_update, 100)
      end
    end,
  })

  -- Handle LSP attach/detach
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function()
      if not state.plugin_enabled then return end
      if socket_client.is_connected() then
        vim.defer_fn(debounced_update, 200)
      end
    end,
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      stop_display_process()
      socket_client.cleanup()
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
    elseif action == 'connect' then
      socket_client.connect(state.config.communication.socket_path)
    elseif action == 'disconnect' then
      socket_client.disconnect()
    elseif action == 'reconnect' then
      socket_client.force_reconnect()
    elseif action == 'health' then
      print(vim.inspect(socket_client.get_connection_health()))
    else
      vim.notify('Usage: ContextWindow [open|close|toggle|restart|status|connect|disconnect|reconnect|health]',
        vim.log.levels.INFO)
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'open', 'close', 'toggle', 'restart', 'status', 'connect', 'disconnect', 'reconnect', 'health' }
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
  vim.keymap.set('n', '<leader>cn', ':ContextWindow reconnect<CR>',
    { desc = 'Reconnect Context Window', silent = true })
  vim.keymap.set('n', '<leader>ch', ':ContextWindow health<CR>',
    { desc = 'Context Window Health', silent = true })
end

-- Main setup function
function M.setup(opts)
  -- Merge user configuration with defaults
  state.config = vim.tbl_deep_extend("force", default_config, opts or {})

  -- Initialize socket client with configuration
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

  vim.notify("LSP Context Window plugin loaded (persistent connections)", vim.log.levels.INFO)
end

-- Public API (enhanced for persistent connections)
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

M.connect = function()
  return socket_client.connect(state.config.communication.socket_path)
end

M.disconnect = function()
  return socket_client.disconnect()
end

M.reconnect = function()
  return socket_client.force_reconnect()
end

M.is_connected = function()
  return socket_client.is_connected()
end

M.get_connection_status = function()
  return socket_client.get_status()
end

M.get_connection_health = function()
  return socket_client.get_connection_health()
end

M.clear_message_queue = function()
  return socket_client.clear_queue()
end

M.get_status = function()
  local socket_status = socket_client.get_status()
  return {
    enabled = state.plugin_enabled,
    tui_running = state.display_process ~= nil,
    socket_connected = socket_status.connected,
    socket_connecting = socket_status.connecting,
    binary_path = state.binary_path,
    config = state.config,
    last_sent_hash = state.last_sent_hash,
    lsp_collection_in_progress = state.lsp_collection_in_progress,
    socket_status = socket_status,
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

-- Test and diagnostic functions
M.test_connection = function()
  return socket_client.test_connection()
end

M.force_update = function()
  update_context()
end

M.reset_connection = function()
  socket_client.reset()
end

return M
