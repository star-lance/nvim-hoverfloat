local M = {}

local lsp_collector = require('hoverfloat.lsp_collector')
local socket_client = require('hoverfloat.socket_client')
local logger = require('hoverfloat.logger')

local state = {
  config = {},
  display_process = nil,
  plugin_enabled = true,
  binary_path = nil,
  last_sent_hash = nil,
  lsp_collection_in_progress = false,
  total_lsp_requests = 0,
}

-- Window manager configuration functions
local function detect_window_manager()
  if os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
    return "hyprland"
  elseif os.getenv("I3SOCK") or os.getenv("SWAYSOCK") then
    return "sway"
  elseif os.getenv("QTILE_XEPHYR") then
    return "qtile"
  end
  return nil
end

local function configure_hyprland_rules()
  local config = state.config.tui.window_manager
  if not config.auto_configure then
    return
  end

  local title = state.config.tui.window_title
  local rules = {}

  if config.floating then
    table.insert(rules, string.format('windowrule = float,title:^(%s)$', title))
  end

  if config.no_focus then
    table.insert(rules, string.format('windowrule = nofocus,title:^(%s)$', title))
  end

  if config.pin then
    table.insert(rules, string.format('windowrule = pin,title:^(%s)$', title))
  end

  if config.position then
    table.insert(rules, string.format('windowrule = move %d %d,title:^(%s)$',
      config.position.x, config.position.y, title))
  end

  if state.config.tui.window_size then
    table.insert(rules, string.format('windowrule = size %d %d,title:^(%s)$',
      state.config.tui.window_size.width * 8,   -- Convert character width to pixels (approximate)
      state.config.tui.window_size.height * 16, -- Convert character height to pixels (approximate)
      title))
  end

  -- Add custom rules
  for _, rule in ipairs(config.hyprland_rules) do
    table.insert(rules, rule)
  end

  -- Apply rules via hyprctl
  for _, rule in ipairs(rules) do
    vim.fn.system(string.format('hyprctl keyword "%s"', rule))
    logger.plugin("debug", "Applied Hyprland rule", { rule = rule })
  end
end

local function setup_window_manager()
  local wm = detect_window_manager()
  logger.plugin("info", "Detected window manager", { wm = wm or "unknown" })

  if wm == "hyprland" then
    configure_hyprland_rules()
  elseif wm then
    logger.plugin("warn", "Window manager detected but auto-configuration not implemented", { wm = wm })
  end
end

local default_config = {
  -- TUI settings
  tui = {
    binary_name = "nvim-context-tui",
    binary_path = nil, -- Auto-detect or user-specified
    window_title = "LSP Context",
    window_size = { width = 80, height = 80 },
    terminal_cmd = "kitty", -- terminal emulator to spawn TUI in

    -- Window manager settings
    window_manager = {
      auto_configure = true,           -- Automatically configure window rules
      position = { x = 100, y = 100 }, -- Fixed position for floating window
      floating = true,                 -- Make window float instead of tiling
      pin = true,                      -- Pin window to all workspaces
      no_focus = true,                 -- Don't steal focus when opening
      hyprland_rules = {},             -- Additional custom Hyprland rules
    },
  },

  -- Communication settings
  communication = {
    socket_path = "/tmp/nvim_context.sock",
    connection_timeout = 5000, -- 5 seconds connection timeout
    max_queue_size = 100,      -- Maximum queued messages
    debug = false,             -- Enable debug logging
    log_dir = nil,             -- Custom log directory (default: stdpath('cache')/hoverfloat)
  },

  -- LSP feature toggles (simplified - let Neovim handle the LSP details)
  features = {
    show_hover = true,
    show_references = true,
    show_definition = true,
    show_type_info = true,
    max_references = 8, -- Maximum references to display
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

local function find_tui_binary()
  if state.binary_path then
    return state.binary_path
  end

  local possible_paths = {
    './build/debug/nvim-context-tui-debug',
    './build/nvim-context-tui',
    vim.fn.expand('~/.local/bin/nvim-context-tui-debug'),
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

  for _, binary_name in ipairs({ "nvim-context-tui-debug", "nvim-context-tui" }) do
    if vim.fn.executable(binary_name) == 1 then
      state.binary_path = binary_name
      return state.binary_path
    end
  end

  return nil
end

local function has_lsp_clients()
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end

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

  -- stable representation excluding volatile fields
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

local function should_update_context()
  return state.plugin_enabled and has_lsp_clients() and not should_skip_update()
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
  state.total_lsp_requests = state.total_lsp_requests + 1


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
      state.last_sent_hash = new_hash
      socket_client.send_context_update(context_data)
    end
  end, state.config.features)
end

-- Start the display process
local function start_display_process()
  if state.display_process then
    return true
  end

  logger.plugin("info", "Starting display process")

  -- Find TUI binary
  local binary_path = find_tui_binary()
  if not binary_path then
    logger.plugin("error", "Cannot start: TUI binary not found. Run 'make install' to build the binary.")
    return false
  end

  -- Setup window manager rules before spawning TUI
  setup_window_manager()

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
        logger.plugin("warn", "TUI process exited", {
          job_id = job_id,
          exit_code = exit_code,
          event = event
        })

        state.display_process = nil

        -- Disconnect socket when TUI exits
        socket_client.disconnect()


        if exit_code ~= 0 and state.config.auto_restart_on_error then
          vim.defer_fn(start_display_process, 2000)
        end
      end,
      on_stderr = function(job_id, data, event)
        if #data > 1 or (data[1] and data[1] ~= "") then
          local error_msg = table.concat(data, "\n")
          logger.plugin("error", "TUI stderr output", {
            job_id = job_id,
            error = error_msg,
            lines = data
          })
        end
      end,
      on_stdout = function(job_id, data, event)
        if #data > 1 or (data[1] and data[1] ~= "") then
          local stdout_msg = table.concat(data, "\n")
        end
      end
    }
  )

  if handle > 0 then
    state.display_process = handle
    logger.plugin("info", "Context display window started", {
      pid = handle,
      binary = binary_path,
      socket = state.config.communication.socket_path,
      log_path = logger.get_log_path()
    })

    -- Wait for TUI to initialize, then try to connect
    vim.defer_fn(function()
      if state.config.auto_connect then
        socket_client.connect(state.config.communication.socket_path)
      end


      -- Send initial update after connection is established
      vim.defer_fn(function()
        if socket_client.is_connected() then
          update_context()
        end
      end, 1000)
    end, 1000)

    return true
  else
    logger.plugin("error", "Failed to start display process", {
      handle = handle,
      terminal = state.config.tui.terminal_cmd,
      binary = binary_path
    })
    return false
  end
end

-- Stop the display process
local function stop_display_process()
  logger.plugin("info", "Stopping display process")

  -- Disconnect socket first
  socket_client.disconnect()


  if state.display_process then
    vim.fn.jobstop(state.display_process)
    state.display_process = nil
    logger.plugin("info", "Context display window closed")
  else
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
        update_context()
      end
    end,
  })

  -- Update on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if not state.plugin_enabled then return end
      if has_lsp_clients() and socket_client.is_connected() then
        update_context()
      end
    end,
  })

  -- Handle LSP attach/detach
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(event)
      if not state.plugin_enabled then return end
      if socket_client.is_connected() then
        update_context()
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(event)
    end,
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      logger.plugin("info", "Neovim exiting, cleaning up HoverFloat")
      stop_display_process()
      socket_client.cleanup()
      logger.cleanup() -- Close log file properly
    end,
  })
end

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
      local status = M.get_status()
      logger.plugin("info", "HoverFloat Status", status)
    else
      logger.plugin("info", 'Usage: ContextWindow [open|close|toggle|restart|status]')
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'open', 'close', 'toggle', 'restart', 'status' }
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
  -- Development/debug shortcuts
  vim.keymap.set('n', '<leader>csd', ':ContextWindow switch-debug<CR>',
    { desc = 'Switch to Debug Build', silent = true })
  vim.keymap.set('n', '<leader>csp', ':ContextWindow switch-prod<CR>',
    { desc = 'Switch to Production Build', silent = true })
  vim.keymap.set('n', '<leader>cbi', ':ContextWindow binary-info<CR>',
    { desc = 'Show Binary Info', silent = true })
  -- Log viewing shortcuts
  vim.keymap.set('n', '<leader>cll', ':ContextWindow logs<CR>',
    { desc = 'Show Log File', silent = true })
  vim.keymap.set('n', '<leader>clt', ':ContextWindow log-tail<CR>',
    { desc = 'Show Log Tail', silent = true })
  vim.keymap.set('n', '<leader>clp', ':ContextWindow log-path<CR>',
    { desc = 'Show Log Path', silent = true })
end

-- Main setup function
function M.setup(opts)
  logger.plugin("info", "Setting up HoverFloat plugin")

  -- Merge user configuration with defaults
  state.config = vim.tbl_deep_extend("force", default_config, opts or {})


  -- Initialize file-based logger (non-disruptive)
  logger.setup({
    debug = state.config.communication.debug,
    log_dir = state.config.communication.log_dir
  })

  logger.plugin("info", "File-based logging initialized", {
    log_path = logger.get_log_path(),
    debug_enabled = state.config.communication.debug
  })

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

  logger.plugin("info", "LSP Context Window plugin loaded successfully", {
    debug_mode = state.config.communication.debug,
    auto_start = state.config.auto_start,
    socket_path = state.config.communication.socket_path,
    uses_builtin_lsp = true,
    log_path = logger.get_log_path()
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
  logger.plugin("info", "Context window plugin enabled")
end

M.disable = function()
  state.plugin_enabled = false
  logger.plugin("info", "Context window plugin disabled")
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
    logger.plugin("info", "Binary path updated", path)
    return true
  else
    logger.plugin("error", "Binary not executable", path)
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
  logger.plugin("info", "Resetting connection")
  socket_client.reset()
end

-- Window manager configuration functions
M.configure_window_manager = function()
  setup_window_manager()
end

M.get_window_manager_info = function()
  local wm = detect_window_manager()
  return {
    detected = wm,
    auto_configure = state.config.tui.window_manager.auto_configure,
    config = state.config.tui.window_manager,
  }
end

M.enable_debug = function()
  state.config.communication.debug = true
  logger.plugin("info", "Debug mode enabled")
end

M.disable_debug = function()
  state.config.communication.debug = false
  logger.plugin("info", "Debug mode disabled")
end

return M
