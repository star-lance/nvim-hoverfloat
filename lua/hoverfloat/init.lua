-- lua/hoverfloat/init.lua - Main plugin entry point with enhanced logging
local M = {}

local lsp_collector = require('hoverfloat.lsp_collector')
local socket_client = require('hoverfloat.socket_client')

-- Logging helper
local function log(level, message, details)
  local timestamp = os.date("%H:%M:%S")
  local log_msg = string.format("[HoverFloat %s] %s", timestamp, message)
  if details then
    log_msg = log_msg .. ": " .. vim.inspect(details)
  end
  vim.notify(log_msg, level)
end

local function log_info(message, details)
  log(vim.log.levels.INFO, message, details)
end

local function log_warn(message, details)
  log(vim.log.levels.WARN, message, details)
end

local function log_error(message, details)
  log(vim.log.levels.ERROR, message, details)
end

local function log_debug(message, details)
  if state.config and state.config.communication and state.config.communication.debug then
    log(vim.log.levels.DEBUG, message, details)
  end
end

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
  startup_time = vim.uv.now(),
  total_updates_sent = 0,
  total_lsp_requests = 0,
  last_error_time = 0,
}

-- Helper function to find TUI binary
local function find_tui_binary()
  log_debug("Searching for TUI binary")
  
  if state.binary_path then
    log_debug("Using cached binary path", state.binary_path)
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

  log_debug("Checking binary paths", possible_paths)

  for _, path in ipairs(possible_paths) do
    if vim.fn.executable(path) == 1 then
      state.binary_path = path
      log_info("Found TUI binary", path)
      return path
    end
  end

  -- Try PATH
  if vim.fn.executable(state.config.tui.binary_name) == 1 then
    state.binary_path = state.config.tui.binary_name
    log_info("Found TUI binary in PATH", state.binary_path)
    return state.binary_path
  end

  log_error("TUI binary not found", { 
    searched_paths = possible_paths,
    binary_name = state.config.tui.binary_name 
  })
  return nil
end

-- Helper function to check if LSP clients are available
local function has_lsp_clients()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local has_clients = #clients > 0
  
  if not has_clients then
    log_debug("No LSP clients attached to current buffer")
  else
    log_debug("Found LSP clients", { count = #clients, names = vim.tbl_map(function(c) return c.name end, clients) })
  end
  
  return has_clients
end

-- Check if current filetype should be excluded
local function should_skip_update()
  local filetype = vim.bo.filetype
  for _, excluded in ipairs(state.config.tracking.excluded_filetypes) do
    if filetype == excluded then
      log_debug("Skipping update for excluded filetype", filetype)
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
  if not state.plugin_enabled then 
    log_debug("Plugin disabled, skipping update")
    return false 
  end
  
  if not has_lsp_clients() then 
    log_debug("No LSP clients, skipping update")
    return false 
  end
  
  if should_skip_update() then 
    return false 
  end

  return true
end

-- Content-based context update - only prevents sending exact duplicates
local function update_context()
  if not should_update_context() then
    return
  end

  -- Prevent overlapping LSP collection calls that can cause race conditions
  if state.lsp_collection_in_progress then
    log_debug("LSP collection already in progress, skipping")
    return
  end

  state.lsp_collection_in_progress = true
  state.total_lsp_requests = state.total_lsp_requests + 1
  
  log_debug("Starting LSP context collection", { 
    request_number = state.total_lsp_requests,
    buffer = vim.api.nvim_get_current_buf(),
    cursor_pos = vim.api.nvim_win_get_cursor(0)
  })

  -- Always collect LSP context information
  lsp_collector.gather_context_info(function(context_data)
    state.lsp_collection_in_progress = false

    if not context_data then
      log_warn("LSP collection returned no data")
      return
    end

    log_debug("LSP context collection completed", {
      has_hover = context_data.hover and #context_data.hover > 0,
      has_definition = context_data.definition ~= nil,
      references_count = context_data.references_count or 0,
      has_type_def = context_data.type_definition ~= nil
    })

    -- Generate hash of the new context data
    local new_hash = hash_context_data(context_data)

    -- Only skip if this is EXACTLY the same as the last message we sent
    if new_hash ~= state.last_sent_hash then
      -- Content is different from last sent message, send update
      state.last_sent_hash = new_hash
      state.total_updates_sent = state.total_updates_sent + 1

      log_debug("Sending context update", { 
        update_number = state.total_updates_sent,
        hash = new_hash:sub(1, 8) .. "...",
        connected = socket_client.is_connected()
      })

      -- Send through persistent connection
      local success = socket_client.send_context_update(context_data)
      if not success then
        if state.config.communication.debug then
          log_warn("Failed to send context update (queued for later)")
        end
      else
        log_debug("Context update sent successfully")
      end
    else
      log_debug("Context unchanged, skipping duplicate update")
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
    local socket_status = socket_client.get_status()
    log_debug("Connection status check", {
      socket_connected = socket_status.connected,
      socket_connecting = socket_status.connecting,
      tui_running = state.display_process ~= nil,
      queue_size = socket_status.queued_messages
    })

    if not socket_client.is_connected() and state.display_process then
      -- TUI is running but socket is disconnected
      log_warn("TUI running but socket disconnected, attempting reconnection")
      if state.config.auto_connect then
        socket_client.ensure_connected()
      end
    end
  end, { ['repeat'] = -1 })
end

-- Start the display process
local function start_display_process()
  if state.display_process then
    log_warn("Display process already running", { pid = state.display_process })
    return true
  end

  log_info("Starting display process")

  -- Find TUI binary
  local binary_path = find_tui_binary()
  if not binary_path then
    log_error("Cannot start: TUI binary not found. Run 'make install' to build the binary.")
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

  log_debug("Starting terminal with TUI", {
    terminal = state.config.tui.terminal_cmd,
    binary = binary_path,
    socket = state.config.communication.socket_path,
    args = terminal_args
  })

  -- Start the terminal with TUI
  local handle = vim.fn.jobstart(
    { state.config.tui.terminal_cmd, unpack(terminal_args) },
    {
      detach = true,
      on_exit = function(job_id, exit_code, event)
        log_warn("TUI process exited", { 
          job_id = job_id, 
          exit_code = exit_code, 
          event = event,
          uptime_ms = vim.uv.now() - state.startup_time
        })
        
        state.display_process = nil

        -- Disconnect socket when TUI exits
        socket_client.disconnect()

        -- Stop connection monitoring
        if state.connection_status_timer then
          vim.fn.timer_stop(state.connection_status_timer)
          state.connection_status_timer = nil
        end

        if exit_code ~= 0 and state.config.auto_restart_on_error then
          log_info("Auto-restarting TUI process in 2 seconds")
          vim.defer_fn(start_display_process, 2000)
        end
      end,
      on_stderr = function(job_id, data, event)
        if #data > 1 or (data[1] and data[1] ~= "") then
          local error_msg = table.concat(data, "\n")
          log_error("TUI stderr output", error_msg)
          state.last_error_time = vim.uv.now()
        end
      end,
      on_stdout = function(job_id, data, event)
        if #data > 1 or (data[1] and data[1] ~= "") then
          local stdout_msg = table.concat(data, "\n")
          log_debug("TUI stdout output", stdout_msg)
        end
      end
    }
  )

  if handle > 0 then
    state.display_process = handle
    state.startup_time = vim.uv.now()
    log_info("Context display window started", { 
      pid = handle,
      binary = binary_path,
      socket = state.config.communication.socket_path
    })

    -- Wait for TUI to initialize, then try to connect
    vim.defer_fn(function()
      log_debug("Attempting initial socket connection")
      if state.config.auto_connect then
        socket_client.connect(state.config.communication.socket_path)
      end

      -- Start connection monitoring
      monitor_connection_status()

      -- Send initial update after connection is established
      vim.defer_fn(function()
        if socket_client.is_connected() then
          log_debug("Sending initial context update")
          debounced_update()
        else
          log_debug("Socket not connected yet, skipping initial update")
        end
      end, 1000)
    end, 1000)

    return true
  else
    log_error("Failed to start display process", { 
      handle = handle,
      terminal = state.config.tui.terminal_cmd,
      binary = binary_path
    })
    return false
  end
end

-- Stop the display process
local function stop_display_process()
  log_info("Stopping display process")
  
  -- Disconnect socket first
  socket_client.disconnect()

  -- Stop connection monitoring
  if state.connection_status_timer then
    vim.fn.timer_stop(state.connection_status_timer)
    state.connection_status_timer = nil
  end

  if state.display_process then
    log_debug("Killing TUI process", { pid = state.display_process })
    vim.fn.jobstop(state.display_process)
    state.display_process = nil
    log_info("Context display window closed")
  else
    log_debug("No display process to stop")
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
      log_debug("Buffer entered", { 
        buffer = vim.api.nvim_get_current_buf(),
        filetype = vim.bo.filetype,
        has_lsp = has_lsp_clients()
      })
      if has_lsp_clients() and socket_client.is_connected() then
        vim.defer_fn(debounced_update, 100)
      end
    end,
  })

  -- Handle LSP attach/detach
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(event)
      if not state.plugin_enabled then return end
      log_info("LSP attached to buffer", { 
        buffer = event.buf,
        client = vim.lsp.get_client_by_id(event.data.client_id).name
      })
      if socket_client.is_connected() then
        vim.defer_fn(debounced_update, 200)
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(event)
      log_info("LSP detached from buffer", { 
        buffer = event.buf,
        client = event.data.client_id
      })
    end,
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      log_info("Neovim exiting, cleaning up HoverFloat")
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
      log_info("Manually restarting context window")
      stop_display_process()
      vim.defer_fn(start_display_process, 500)
    elseif action == 'status' then
      local status = M.get_status()
      log_info("HoverFloat Status", status)
    elseif action == 'connect' then
      log_info("Manually connecting socket")
      socket_client.connect(state.config.communication.socket_path)
    elseif action == 'disconnect' then
      log_info("Manually disconnecting socket")
      socket_client.disconnect()
    elseif action == 'reconnect' then
      log_info("Manually reconnecting socket")
      socket_client.force_reconnect()
    elseif action == 'health' then
      local health = socket_client.get_connection_health()
      log_info("HoverFloat Health Check", health)
    elseif action == 'debug' then
      -- Toggle debug mode
      state.config.communication.debug = not state.config.communication.debug
      log_info("Debug mode " .. (state.config.communication.debug and "enabled" or "disabled"))
    elseif action == 'stats' then
      local uptime = math.floor((vim.uv.now() - state.startup_time) / 1000)
      log_info("HoverFloat Statistics", {
        uptime_seconds = uptime,
        total_lsp_requests = state.total_lsp_requests,
        total_updates_sent = state.total_updates_sent,
        last_error_time = state.last_error_time > 0 and os.date("%H:%M:%S", state.last_error_time / 1000) or "none",
        current_hash = state.last_sent_hash and state.last_sent_hash:sub(1, 8) .. "..." or "none"
      })
    else
      log_info('Usage: ContextWindow [open|close|toggle|restart|status|connect|disconnect|reconnect|health|debug|stats]')
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'open', 'close', 'toggle', 'restart', 'status', 'connect', 'disconnect', 'reconnect', 'health', 'debug', 'stats' }
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
  vim.keymap.set('n', '<leader>cd', ':ContextWindow debug<CR>',
    { desc = 'Toggle Debug Mode', silent = true })
end

-- Main setup function
function M.setup(opts)
  log_info("Setting up HoverFloat plugin")
  
  -- Merge user configuration with defaults
  state.config = vim.tbl_deep_extend("force", default_config, opts or {})

  log_debug("Plugin configuration", state.config)

  -- Initialize socket client with configuration
  socket_client.setup(state.config.communication)

  -- Setup plugin components
  setup_autocmds()
  setup_commands()
  setup_keymaps()

  -- Auto-start if configured
  if state.config.auto_start then
    log_info("Auto-starting display process in 1 second")
    vim.defer_fn(function()
      start_display_process()
    end, 1000) -- Give Neovim time to fully load
  end

  log_info("LSP Context Window plugin loaded successfully", {
    debug_mode = state.config.communication.debug,
    auto_start = state.config.auto_start,
    socket_path = state.config.communication.socket_path
  })
end

-- Enhanced Public API
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
  log_info("Context window plugin enabled")
end

M.disable = function()
  state.plugin_enabled = false
  log_info("Context window plugin disabled")
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
    last_sent_hash = state.last_sent_hash and state.last_sent_hash:sub(1, 8) .. "..." or nil,
    lsp_collection_in_progress = state.lsp_collection_in_progress,
    socket_status = socket_status,
    uptime_ms = vim.uv.now() - state.startup_time,
    total_lsp_requests = state.total_lsp_requests,
    total_updates_sent = state.total_updates_sent,
    last_error_time = state.last_error_time,
  }
end

M.get_config = function()
  return vim.deepcopy(state.config)
end

M.set_binary_path = function(path)
  if vim.fn.executable(path) == 1 then
    state.binary_path = path
    log_info("Binary path updated", path)
    return true
  else
    log_error("Binary not executable", path)
    return false
  end
end

-- Test and diagnostic functions
M.test_connection = function()
  return socket_client.test_connection()
end

M.force_update = function()
  log_debug("Forcing context update")
  update_context()
end

M.reset_connection = function()
  log_info("Resetting connection")
  socket_client.reset()
end

-- Enable/disable debug mode
M.enable_debug = function()
  state.config.communication.debug = true
  log_info("Debug mode enabled")
end

M.disable_debug = function()
  state.config.communication.debug = false
  log_info("Debug mode disabled")
end

return M
