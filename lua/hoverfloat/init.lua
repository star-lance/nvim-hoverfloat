local M = {}

local lsp_collector = require('hoverfloat.lsp_collector')
local socket_client = require('hoverfloat.socket_client')
local symbol_prefetcher = require('hoverfloat.symbol_prefetcher')
local logger = require('hoverfloat.logger')

local state = {
  config = {},
  display_process = nil,
  plugin_enabled = true,
  lsp_collection_in_progress = false,
  cache_hits = 0,
  total_requests = 0,
  last_sent_position = nil,
}

local default_config = {
  -- TUI settings
  tui = {
    window_title = "nvim-hoverfloat-tui",
    window_size = { width = 80, height = 80 },
    terminal_cmd = "kitty", -- terminal emulator to spawn TUI in
  },

  communication = {
    socket_path = "/tmp/nvim_context.sock",
    debug = true,  -- Enable debug logging
    log_dir = nil, -- Custom log directory (default: stdpath('cache')/hoverfloat)
  },

  features = {
    show_hover = true,
    show_references = true,
    show_definition = true,
    show_type_info = true,
  },
  prefetching = {
    enabled = true,
    prefetch_radius_lines = 30,
    max_concurrent_requests = 2,
    cache_ttl_ms = 45000,
  },
  -- Auto-start settings
  auto_start = true,
  auto_restart_on_error = true,
}

local function has_lsp_clients()
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end
local function should_update_context()
  return state.plugin_enabled and has_lsp_clients()
end

-- Get current position identifier
local function get_position_identifier()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local word = vim.fn.expand('<cword>')
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")

  return string.format("%s:%d:%d:%s", file, cursor_pos[1], cursor_pos[2], word or "")
end

-- Ultra-fast context update with prefetching
local function update_context()
  if not should_update_context() then
    return
  end

  if state.lsp_collection_in_progress then
    return
  end

  -- Check if we're at the same position
  local current_position = get_position_identifier()
  if current_position == state.last_sent_position then
    return
  end

  local start_time = vim.uv.now()
  state.total_requests = state.total_requests + 1

  -- Try instant lookup from prefetcher first
  symbol_prefetcher.get_instant_context_data(function(instant_data)
    if instant_data then
      -- INSTANT RESPONSE! Sub-millisecond
      state.cache_hits = state.cache_hits + 1
      local response_time = vim.uv.now() - start_time

      state.last_sent_position = current_position
      socket_client.send_context_update(instant_data)

      if response_time < 2000 then -- Less than 2ms
        logger.debug("Performance", string.format("Instant response: %.2fμs", response_time))
      end

      return
    end

    -- Not in cache - fall back to normal LSP collection
    state.lsp_collection_in_progress = true

    lsp_collector.gather_context_info(function(context_data)
      state.lsp_collection_in_progress = false
      if not context_data then
        return
      end

      state.last_sent_position = current_position
      socket_client.send_context_update(context_data)
    end, state.config.features)
  end)
end
-- Start the display process
local function start_display_process()
  if state.display_process then
    return true
  end

  local binary_path = vim.fn.expand("~/.local/bin/nvim-context-tui")
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
        socket_client.disconnect()
        if exit_code ~= 0 and state.config.auto_restart_on_error then
          vim.defer_fn(start_display_process, 2000)
        end
      end,
    }
  )

  if handle > 0 then
    state.display_process = handle

    -- Wait for socket file to be created by TUI, then connect
    local socket_path = state.config.communication.socket_path
    local function try_connect()
      if vim.fn.filereadable(socket_path) == 1 then
        socket_client.connect(socket_path)
        return
      end
      -- Retry after short delay if socket file doesn't exist yet
      vim.defer_fn(try_connect, 100)
    end
    -- Give TUI a moment to start, then begin checking for socket
    vim.defer_fn(try_connect, 200)

    return true
  else
    return false
  end
end

-- Stop the display process
local function stop_display_process()
  socket_client.disconnect()
  if state.display_process then
    vim.fn.jobstop(state.display_process)
    state.display_process = nil
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
    callback = function()
      if not state.plugin_enabled then return end
      if socket_client.is_connected() then
        update_context()
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function()
    end,
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      stop_display_process()
      socket_client.cleanup()
      logger.cleanup()
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
  state.config = vim.tbl_deep_extend("force", default_config, opts or {})

  logger.setup({
    debug = state.config.communication.debug,
    log_dir = state.config.communication.log_dir
  })

  if state.config.prefetching.enabled then
    symbol_prefetcher.setup_prefetching()
    logger.info("Prefetcher", "Symbol prefetching enabled")
  end

  socket_client.setup(state.config.communication)
  setup_autocmds()
  setup_commands()
  setup_keymaps()

  if state.config.auto_start then
    vim.defer_fn(function()
      start_display_process()
    end, 1000)
  end
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
end

M.disable = function()
  state.plugin_enabled = false
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
    config = state.config,
    lsp_collection_in_progress = state.lsp_collection_in_progress,
    socket_status = socket_status,
  }
end

M.get_config = function()
  return vim.deepcopy(state.config)
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

M.enable_debug = function()
  state.config.communication.debug = true
end

M.disable_debug = function()
  state.config.communication.debug = false
end


return M
