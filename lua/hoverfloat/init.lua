-- lua/hoverfloat/init.lua - Enhanced plugin entry point with better UX
local M = {}

-- Core modules
local config = require('hoverfloat.config')
local lsp_service = require('hoverfloat.core.lsp_service')
local cursor_tracker = require('hoverfloat.core.cursor_tracker')
local performance = require('hoverfloat.core.performance')
local socket_client = require('hoverfloat.communication.socket_client')
local prefetcher = require('hoverfloat.prefetch.prefetcher')
local tui_manager = require('hoverfloat.process.tui_manager')
local logger = require('hoverfloat.utils.logger')

-- Plugin state
local state = {
  initialized = false,
  health_issues = {},
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
  if not config.is_auto_start_enabled() then
    return
  end

  local group = vim.api.nvim_create_augroup("HoverFloatAutoStart", { clear = true })

  -- Auto-start TUI when LSP attaches
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function()
      if not tui_manager.is_running() then
        vim.defer_fn(function()
          local ok, err = pcall(tui_manager.start)
          if ok then
            cursor_tracker.enable()
          else
            vim.notify("hoverfloat: Failed to auto-start - " .. tostring(err), vim.log.levels.WARN)
          end
        end, 1000) -- 1 second delay to let LSP settle
      end
    end,
  })
end

-- Check and auto-install binary if needed
local function check_binary_installation()
  local binary_path = config.get_binary_path()
  if vim.fn.executable(binary_path) == 1 then
    return true
  end

  if config.get_value("process.auto_install") then
    vim.notify("hoverfloat: TUI binary not found. Run :HoverFloatInstall to build it.", vim.log.levels.INFO)

    -- Add command for easy installation
    vim.api.nvim_create_user_command('HoverFloatInstall', function()
      M.install_binary()
    end, { desc = 'Install HoverFloat TUI binary' })
  end

  return false
end

-- Install binary command
function M.install_binary()
  vim.notify("hoverfloat: Building TUI binary...", vim.log.levels.INFO)

  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
  local make_cmd = string.format("cd %s && make install", vim.fn.shellescape(plugin_dir))

  vim.fn.jobstart(make_cmd, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.notify("hoverfloat: TUI binary installed successfully!", vim.log.levels.INFO)
        -- Try to start if auto-start is enabled
        if config.is_auto_start_enabled() and not tui_manager.is_running() then
          tui_manager.start()
          cursor_tracker.enable()
        end
      else
        vim.notify("hoverfloat: Failed to build TUI binary. Check the output of 'make install'", vim.log.levels.ERROR)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("hoverfloat build: " .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
  })
end

-- Main setup function
function M.setup(opts)
  -- Prevent double initialization
  if state.initialized then
    logger.plugin("warn", "Plugin already initialized")
    return
  end

  -- Setup configuration
  local cfg = config.setup(opts)

  -- Setup logging
  logger.setup({
    debug = cfg.dev.debug,
    log_dir = cfg.dev.log_dir,
  })

  -- Check binary installation
  check_binary_installation()

  -- Initialize all core modules
  lsp_service.setup()
  socket_client.setup({
    socket_path = cfg.process.socket_path,
  })
  tui_manager.setup()
  prefetcher.setup()

  -- Setup cursor tracking with configured settings
  cursor_tracker.setup_tracking()
  cursor_tracker.set_debounce_delay(cfg.performance.debounce_base)

  -- Setup UI components
  ui_setup.setup_all()
  M.setup_custom_commands()
  setup_cleanup()
  setup_auto_start()

  -- Start performance monitoring if debug enabled
  if cfg.dev.debug then
    performance.start_monitoring()
  end

  state.initialized = true
  logger.info("Plugin", "HoverFloat initialized successfully")

  -- Show welcome message on first setup
  if opts and opts.show_welcome ~= false then
    vim.defer_fn(function()
      vim.notify("hoverfloat: Ready! Use " .. cfg.ui.keymaps.toggle .. " to toggle the context window",
        vim.log.levels.INFO)
    end, 100)
  end
end

-- Setup custom commands
function M.setup_custom_commands()
  local keymaps = config.get_keymaps()

  -- Create commands with better descriptions
  vim.api.nvim_create_user_command('HoverFloat', function(opts)
    local args = vim.split(opts.args, " ")
    local cmd = args[1] or "status"

    if cmd == "config" then
      M.show_config()
    elseif cmd == "health" then
      M.check_health()
    elseif cmd == "perf" or cmd == "performance" then
      M.show_performance()
    elseif cmd == "set" and args[2] and args[3] then
      M.set_config(args[2], args[3])
    else
      vim.notify("Usage: :HoverFloat [config|health|perf|set <key> <value>]", vim.log.levels.INFO)
    end
  end, {
    nargs = '*',
    complete = function(arg_lead, cmd_line, cursor_pos)
      local args = vim.split(cmd_line, " ")
      if #args == 2 then
        return vim.tbl_filter(function(item)
          return vim.startswith(item, arg_lead)
        end, { "config", "health", "performance", "set" })
      elseif #args == 3 and args[2] == "set" then
        return vim.tbl_filter(function(item)
          return vim.startswith(item, arg_lead)
        end, {
          "terminal.preferred",
          "performance.debounce_base",
          "features.auto_start",
          "dev.debug",
        })
      end
      return {}
    end,
    desc = 'HoverFloat management commands'
  })

  -- Terminal selection command
  vim.api.nvim_create_user_command('HoverFloatTerminal', function(opts)
    if opts.args == "" then
      local status = tui_manager.get_status()
      vim.notify("Current terminal: " .. (status.terminal or "auto-detect"), vim.log.levels.INFO)
      vim.notify("Available: " .. table.concat(status.terminals_available, ", "), vim.log.levels.INFO)
    else
      tui_manager.set_preferred_terminal(opts.args)
      config.update("terminal.preferred", opts.args)
      vim.notify("Set preferred terminal to: " .. opts.args, vim.log.levels.INFO)

      -- Restart if running
      if tui_manager.is_running() then
        vim.notify("Restarting with new terminal...", vim.log.levels.INFO)
        tui_manager.restart()
      end
    end
  end, {
    nargs = '?',
    complete = function(arg_lead)
      local status = tui_manager.get_status()
      return vim.tbl_filter(function(item)
        return vim.startswith(item, arg_lead)
      end, status.terminals_available or {})
    end,
    desc = 'Set preferred terminal for HoverFloat'
  })
end

-- Show current configuration
function M.show_config()
  local cfg_text = config.export()

  -- Create a new buffer to show config
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'lua')
  vim.api.nvim_buf_set_name(buf, 'HoverFloat Configuration')

  local lines = vim.split(cfg_text, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Open in a new window
  vim.cmd('split')
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

-- Check plugin health
function M.check_health()
  local ok, issues = config.validate()
  local health_report = { "HoverFloat Health Check", "" }

  if ok then
    table.insert(health_report, "✅ All checks passed!")
  else
    table.insert(health_report, "❌ Issues found:")
    for _, issue in ipairs(issues) do
      table.insert(health_report, "  • " .. issue)
    end
  end

  -- Add status information
  table.insert(health_report, "")
  table.insert(health_report, "Status:")
  table.insert(health_report, "  • Initialized: " .. tostring(state.initialized))
  table.insert(health_report, "  • TUI Running: " .. tostring(tui_manager.is_running()))
  table.insert(health_report, "  • Socket Connected: " .. tostring(socket_client.is_connected()))
  table.insert(health_report, "  • Tracking Enabled: " .. tostring(cursor_tracker.is_tracking_enabled()))

  local status = tui_manager.get_status()
  table.insert(health_report, "  • Terminal: " .. (status.terminal or "not detected"))

  -- Show in floating window
  local width = 60
  local height = #health_report + 2
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, health_report)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' HoverFloat Health ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Close on any key
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
end

-- Show performance stats
function M.show_performance()
  local report = performance.get_performance_report()

  -- Show in floating window
  local lines = vim.split(report, '\n')
  local width = 50
  local height = #lines + 2
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' Performance Report ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Close on any key
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
end

-- Set configuration value
function M.set_config(key, value)
  -- Try to parse value
  if value == "true" then
    value = true
  elseif value == "false" then
    value = false
  elseif tonumber(value) then
    value = tonumber(value)
  end

  config.update(key, value)
  vim.notify("Set " .. key .. " = " .. tostring(value), vim.log.levels.INFO)

  -- Apply certain changes immediately
  if key:match("^performance%.") then
    cursor_tracker.set_debounce_delay(config.get_value("performance.debounce_base"))
  elseif key:match("^terminal%.") and tui_manager.is_running() then
    vim.notify("Restart TUI to apply terminal changes", vim.log.levels.INFO)
  end
end

-- Public API functions
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

-- Get comprehensive status
function M.get_status()
  local socket_status = socket_client.get_status()
  local tui_status = tui_manager.get_status()
  local prefetch_stats = prefetcher.get_stats()
  local perf_stats = performance.get_stats()
  local tracker_stats = cursor_tracker.get_stats()
  local ui_status = ui_setup.get_status()

  return {
    initialized = state.initialized,
    config = config.get(),
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

-- Health check function
function M.health()
  local status = M.get_status()
  local ok, issues = config.validate()

  return {
    ok = ok and status.initialized and status.ui_status.commands_registered,
    issues = issues,
    status = status,
  }
end

return M
