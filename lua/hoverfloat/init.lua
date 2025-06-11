-- lua/hoverfloat/init.lua - Simplified plugin entry point
local M = {}

-- Core modules
local lsp_service = require('hoverfloat.core.lsp_service')
local position = require('hoverfloat.core.position')
local performance = require('hoverfloat.core.performance')
local socket_client = require('hoverfloat.communication.socket_client')
local prefetcher = require('hoverfloat.prefetch.prefetcher')
local tui_manager = require('hoverfloat.process.tui_manager')
local logger = require('hoverfloat.utils.logger')

-- Plugin state
local state = {
  last_sent_position = nil,
}

local function should_update_context()
  return true
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

  local current_position = get_position_identifier()
  if current_position == state.last_sent_position then
    return
  end

  local start_time = performance.start_request()

  -- Try instant lookup from prefetcher first
  prefetcher.get_instant_context_data(function(instant_data)
    if instant_data then
      local response_time = performance.complete_request(start_time, true, false)
      state.last_sent_position = current_position
      socket_client.send_context_update(instant_data)

      if response_time < 2000 then
        logger.debug("Performance", string.format("Instant response: %.2fμs", response_time))
      end
      return
    end
  end)
end

-- Setup autocmds for cursor tracking
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("HoverFloatContext", { clear = true })

  -- Track cursor movement
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      if state.enabled and socket_client.is_connected() then
        update_context()
      end
    end,
  })

  -- Update on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if state.enabled and position.has_lsp_clients() and socket_client.is_connected() then
        update_context()
      end
    end,
  })

  -- Auto-start TUI when LSP attaches
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function()
      if state.enabled then
        -- Start TUI if not already running
        if not tui_manager.is_running() then
          vim.defer_fn(function()
            tui_manager.start()
          end, 1000) -- 1 second delay to let LSP settle
        elseif socket_client.is_connected() then
          update_context()
        end
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
end

-- Main setup function - ignore any user options
function M.setup(opts)
  -- Ignore opts - we know what we want

  -- Setup logging with hardcoded values
  logger.setup({
    debug = true,
    log_dir = nil -- Use default
  })

  -- Setup all modules with hardcoded configurations
  lsp_service.setup()
  socket_client.setup({}) -- Will use hardcoded values
  tui_manager.setup()
  prefetcher.setup()

  -- Setup UI components
  setup_autocmds()
  setup_commands()
  setup_keymaps()

  -- Start performance monitoring
  performance.start_monitoring()

  logger.info("Plugin", "HoverFloat initialized")
end

-- Public API functions
M.start = tui_manager.start
M.stop = tui_manager.stop
M.toggle = tui_manager.toggle
M.restart = tui_manager.restart
M.is_running = tui_manager.is_running
M.is_connected = socket_client.is_connected

-- Status function
function M.get_status()
  local socket_status = socket_client.get_status()
  local tui_status = tui_manager.get_status()
  local prefetch_stats = prefetcher.get_stats()
  local perf_stats = performance.get_stats()

  return {
    enabled = state.enabled,
    tui_running = tui_status.running,
    socket_connected = socket_status.connected,
    socket_status = socket_status,
    tui_status = tui_status,
    prefetch_stats = prefetch_stats,
    performance_stats = perf_stats,
  }
end

M.force_update = update_context
M.clear_cache = prefetcher.clear_cache

return M
