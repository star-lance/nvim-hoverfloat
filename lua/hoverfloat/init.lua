-- lua/hoverfloat/init.lua - Simplified plugin entry point focused on coordination
local M = {}

-- Core modules
local lsp_service = require('hoverfloat.core.lsp_service')
local cursor_tracker = require('hoverfloat.core.cursor_tracker')
local performance = require('hoverfloat.core.performance')
local socket_client = require('hoverfloat.communication.socket_client')
local prefetcher = require('hoverfloat.prefetch.prefetcher')
local tui_manager = require('hoverfloat.process.tui_manager')
local logger = require('hoverfloat.utils.logger')

-- Plugin coordination state (minimal)
local state = {
  initialized = false,
}

-- UI module for commands and keymaps
local ui_setup = require('hoverfloat.ui.setup')

-- Setup cleanup on exit
local function setup_cleanup()
  local group = vim.api.nvim_create_augroup("HoverFloatCleanup", { clear = true })
  
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      cursor_tracker.cleanup()
      tui_manager.stop()
      socket_client.cleanup()
      logger.cleanup()
    end,
  })
end

-- Setup auto-start functionality
local function setup_auto_start()
  local group = vim.api.nvim_create_augroup("HoverFloatAutoStart", { clear = true })
  
  -- Auto-start TUI when LSP attaches
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function()
      if not tui_manager.is_running() then
        vim.defer_fn(function()
          tui_manager.start()
          cursor_tracker.enable()
        end, 1000) -- 1 second delay to let LSP settle
      end
    end,
  })
end

-- Main setup function - focused on coordination only
function M.setup(opts)
  -- Prevent double initialization
  if state.initialized then
    logger.plugin("warn", "Plugin already initialized")
    return
  end

  -- Ignore opts - we know what we want (hardcoded configuration)
  
  -- Setup logging with hardcoded values
  logger.setup({
    debug = true,
    log_dir = nil -- Use default
  })

  -- Initialize all core modules with hardcoded configurations
  lsp_service.setup()
  socket_client.setup({}) -- Will use hardcoded values
  tui_manager.setup()
  prefetcher.setup()
  
  -- Setup cursor tracking system
  cursor_tracker.setup_tracking()

  -- Setup UI components via dedicated module
  ui_setup.setup_all()
  setup_cleanup()
  setup_auto_start()

  -- Start performance monitoring
  performance.start_monitoring()

  state.initialized = true
  logger.info("Plugin", "HoverFloat initialized successfully")
end

-- Public API functions (delegation to appropriate modules)
M.start = tui_manager.start
M.stop = tui_manager.stop
M.toggle = tui_manager.toggle
M.restart = tui_manager.restart
M.is_running = tui_manager.is_running
M.is_connected = socket_client.is_connected

-- Cursor tracking API
M.enable_tracking = cursor_tracker.enable
M.disable_tracking = cursor_tracker.disable
M.is_tracking = cursor_tracker.is_tracking_enabled
M.force_update = cursor_tracker.force_update

-- UI customization API
M.setup_custom_keymaps = ui_setup.setup_custom_keymaps
M.remove_default_keymaps = ui_setup.remove_default_keymaps

-- Cache management
M.clear_cache = function()
  cursor_tracker.clear_position_cache()
  prefetcher.clear_cache()
end

-- Status aggregation function (core coordination responsibility)
function M.get_status()
  local socket_status = socket_client.get_status()
  local tui_status = tui_manager.get_status()
  local prefetch_stats = prefetcher.get_stats()
  local perf_stats = performance.get_stats()
  local tracker_stats = cursor_tracker.get_stats()
  local ui_status = ui_setup.get_status()

  return {
    initialized = state.initialized,
    tui_running = tui_status.running,
    socket_connected = socket_status.connected,
    tracking_enabled = tracker_stats.tracking_enabled,
    socket_status = socket_status,
    tui_status = tui_status,
    tracker_stats = tracker_stats,
    ui_status = ui_status,
    prefetch_stats = prefetch_stats,
    performance_stats = perf_stats,
  }
end

-- Health check function (coordination responsibility)
function M.health()
  local status = M.get_status()
  
  return {
    ok = status.initialized and status.socket_connected and status.ui_status.commands_registered,
    issues = {
      not status.initialized and "Plugin not initialized" or nil,
      not status.socket_connected and "Socket not connected" or nil,
      not status.tui_running and "TUI not running" or nil,
      not status.tracking_enabled and "Cursor tracking disabled" or nil,
      not status.ui_status.commands_registered and "Commands not registered" or nil,
    }
  }
end

return M
