-- lua/hoverfloat/init.lua - Main plugin entry point (simplified)
local M = {}

-- Core modules
local config = require('hoverfloat.config')
local lsp_service = require('hoverfloat.core.lsp_service')
local position = require('hoverfloat.core.position')
local performance = require('hoverfloat.core.performance')

-- Communication modules
local socket_client = require('hoverfloat.communication.socket_client')

-- Prefetch modules
local prefetcher = require('hoverfloat.prefetch.prefetcher')

-- Process management
local tui_manager = require('hoverfloat.process.tui_manager')

-- Utils
local logger = require('hoverfloat.utils.logger')

-- Plugin state
local state = {
  enabled = true,
  last_sent_position = nil,
}

-- Check if context should be updated
local function should_update_context()
  return state.enabled and position.has_lsp_clients()
end

-- Get position identifier for deduplication
local function get_position_identifier()
  return position.get_position_identifier()
end

-- Main context update function
local function update_context()
  if not should_update_context() then
    return
  end

  -- Check if we're at the same position
  local current_position = get_position_identifier()
  if current_position == state.last_sent_position then
    return
  end

  local start_time = performance.start_request()

  -- Try instant lookup from prefetcher first
  prefetcher.get_instant_context_data(function(instant_data)
    if instant_data then
      -- INSTANT RESPONSE from cache!
      local response_time = performance.complete_request(start_time, true, false)
      state.last_sent_position = current_position
      socket_client.send_context_update(instant_data)

      if response_time < 2000 then -- Less than 2ms
        logger.debug("Performance", string.format("Instant response: %.2fμs", response_time))
      end
      return
    end
  end)
end

-- Setup autocmds for cursor tracking
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("HoverFloatContext", { clear = true })

  -- Track cursor movement (only if socket is connected)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      if not state.enabled then return end
      if socket_client.is_connected() then
        update_context()
      end
    end,
  })

  -- Update on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if not state.enabled then return end
      if position.has_lsp_clients() and socket_client.is_connected() then
        update_context()
      end
    end,
  })

  -- Handle LSP attach/detach
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function()
      if not state.enabled then return end
      if socket_client.is_connected() then
        update_context()
      end
    end,
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      tui_manager.stop()
      socket_client.cleanup()
      logger.cleanup()
    end,
  })
end

-- Setup commands
local function setup_commands()
  vim.api.nvim_create_user_command('ContextWindow', function(opts)
    local action = opts.args ~= '' and opts.args or 'toggle'

    if action == 'open' or action == 'start' then
      tui_manager.start()
    elseif action == 'close' or action == 'stop' then
      tui_manager.stop()
    elseif action == 'toggle' then
      tui_manager.toggle()
    elseif action == 'restart' then
      tui_manager.restart()
    elseif action == 'status' then
      local status = M.get_status()
      logger.plugin("info", "HoverFloat Status", status)
    elseif action == 'performance' then
      local report = performance.get_performance_report()
      logger.plugin("info", "Performance Report", { report = report })
    elseif action == 'warm-cache' then
      prefetcher.force_prefetch_current_buffer()
      logger.plugin("info", "Cache warming initiated")
    elseif action == 'clear-cache' then
      prefetcher.clear_cache()
      state.last_sent_position = nil
      logger.plugin("info", "Prefetch cache cleared")
    else
      logger.plugin("info", 'Usage: ContextWindow [open|close|toggle|restart|status]')
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'open', 'close', 'toggle', 'restart', 'status', 'performance', 'warm-cache', 'clear-cache' }
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
  vim.keymap.set('n', '<leader>cp', ':ContextWindow performance<CR>',
    { desc = 'Show Performance Stats', silent = true })
  vim.keymap.set('n', '<leader>cw', ':ContextWindow warm-cache<CR>',
    { desc = 'Warm Prefetch Cache', silent = true })
end

-- Main setup function
function M.setup(opts)
  -- Setup configuration first
  local current_config = config.setup(opts or {})

  -- Setup logging
  logger.setup({
    debug = current_config.communication.debug,
    log_dir = current_config.communication.log_dir
  })

  -- Setup all modules
  lsp_service.setup()
  socket_client.setup(current_config.communication)
  tui_manager.setup()

  -- Setup prefetching if enabled
  if current_config.prefetching.enabled then
    prefetcher.setup()
    logger.info("Plugin", "Symbol prefetching enabled")
  end

  -- Setup UI components
  setup_autocmds()
  setup_commands()
  setup_keymaps()

  -- Start performance monitoring
  performance.start_monitoring()

  logger.info("Plugin", "HoverFloat initialized successfully")
end

-- Public API functions
M.start = tui_manager.start
M.stop = tui_manager.stop
M.toggle = tui_manager.toggle
M.restart = tui_manager.restart

M.enable = function() state.enabled = true end
M.disable = function() state.enabled = false end
M.is_running = tui_manager.is_running

M.connect = socket_client.connect
M.disconnect = socket_client.disconnect
M.is_connected = socket_client.is_connected

-- Status and diagnostics
function M.get_status()
  local socket_status = socket_client.get_status()
  local tui_status = tui_manager.get_status()
  local prefetch_stats = prefetcher.get_stats()
  local perf_stats = performance.get_stats()

  return {
    enabled = state.enabled,
    tui_running = tui_status.running,
    socket_connected = socket_status.connected,
    socket_connecting = socket_status.connecting,
    config = config.get(),
    socket_status = socket_status,
    tui_status = tui_status,
    prefetch_stats = prefetch_stats,
    performance_stats = perf_stats,
  }
end

M.get_config = config.get
M.force_update = update_context
M.clear_cache = prefetcher.clear_cache

-- Legacy compatibility functions
M.get_connection_status = socket_client.get_status
M.get_connection_health = socket_client.get_connection_health
M.test_connection = socket_client.test_connection
M.reset_connection = socket_client.reset

return M
