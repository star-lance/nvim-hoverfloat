-- lua/hoverfloat/init.lua - Main plugin entry point with enhanced logging
--
-- Architecture: This plugin focuses on DISPLAY and FORMATTING of LSP data.
-- LSP communication is delegated to Neovim's built-in vim.lsp.buf.* functions.
-- This ensures compatibility with all LSP servers and leverages battle-tested code.
--
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

-- Plugin state - initialize early to avoid undefined access
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

local function log_debug(message, details)
  -- Check for debug mode in multiple places to handle initialization order
  local debug_enabled = false

  if state and state.config and state.config.communication and state.config.communication.debug then
    debug_enabled = true
  elseif vim.g.hoverfloat_debug then
    debug_enabled = true
  end

  if debug_enabled then
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
    log_dir = nil,                -- Custom log directory (default: stdpath('cache')/hoverfloat)
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

-- Helper function to find TUI binary (with debug/production detection)
local function find_tui_binary()
  log_debug("Searching for TUI binary")

  if state.binary_path then
    log_debug("Using cached binary path", state.binary_path)
    return state.binary_path
  end

  local possible_paths = {
    -- Development paths (debug builds in priority)
    './build/debug/nvim-context-tui-debug',
    './build/nvim-context-tui',
    './nvim-context-tui',
    './cmd/context-tui/nvim-context-tui',

    -- Plugin installation paths
    vim.fn.stdpath('data') .. '/lazy/nvim-hoverfloat/build/debug/nvim-context-tui-debug',
    vim.fn.stdpath('data') .. '/lazy/nvim-hoverfloat/build/nvim-context-tui',
    vim.fn.stdpath('data') .. '/lazy/nvim-hoverfloat/nvim-context-tui',

    -- User installation paths (check debug first for development)
    vim.fn.expand('~/.local/bin/nvim-context-tui-debug'),
    vim.fn.expand('~/.local/bin/nvim-context-tui'),
    '/usr/local/bin/nvim-context-tui-debug',
    '/usr/local/bin/nvim-context-tui',
    '/usr/bin/nvim-context-tui',
  }

  log_debug("Checking binary paths", possible_paths)

  for _, path in ipairs(possible_paths) do
    if vim.fn.executable(path) == 1 then
      state.binary_path = path
      local is_debug = path:match("debug") ~= nil
      log_info("Found TUI binary", {
        path = path,
        type = is_debug and "debug" or "production",
        auto_detected = true
      })
      return path
    end
  end

  -- Try PATH with both variants
  for _, binary_name in ipairs({ "nvim-context-tui-debug", "nvim-context-tui" }) do
    if vim.fn.executable(binary_name) == 1 then
      state.binary_path = binary_name
      local is_debug = binary_name:match("debug") ~= nil
      log_info("Found TUI binary in PATH", {
        binary = binary_name,
        type = is_debug and "debug" or "production"
      })
      return state.binary_path
    end
  end

  log_error("TUI binary not found", {
    searched_paths = possible_paths,
    suggestion = "Run 'make prod' or 'make debug' to build and install"
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
          log_error("TUI stderr output", {
            job_id = job_id,
            error = error_msg,
            lines = data
          })
          state.last_error_time = vim.uv.now()
        end
      end,
      on_stdout = function(job_id, data, event)
        if #data > 1 or (data[1] and data[1] ~= "") then
          local stdout_msg = table.concat(data, "\n")
          log_info("TUI stdout output", {
            job_id = job_id,
            output = stdout_msg,
            lines = data
          })
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
      socket = state.config.communication.socket_path,
      log_path = logger.get_log_path()
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
      logger.cleanup() -- Close log file properly
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
      if state.config.communication.debug then
        logger.enable_debug()
        log_info("Debug mode enabled", { log_path = logger.get_log_path() })
      else
        log_info("Debug mode disabled")
        logger.disable_debug()
      end
    elseif action == 'logs' then
      -- Show log file
      logger.show_log()
    elseif action == 'log-path' then
      -- Show log file path
      local log_path = logger.get_log_path()
      if log_path then
        log_info("Current log file path", { path = log_path })
        -- Only show this in the editor for path info
        vim.notify("Log file: " .. log_path, vim.log.levels.INFO)
      else
        log_warn("No log file available", { debug_enabled = state.config.communication.debug })
      end
    elseif action == 'log-tail' then
      -- Show last 50 lines of log
      local lines = logger.tail_log(50)
      if #lines > 0 then
        -- Display in a floating window or buffer
        vim.cmd('split')
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_win_set_buf(0, buf)
        vim.bo[buf].filetype = 'log'
        vim.bo[buf].readonly = true
        vim.bo[buf].modifiable = false
      else
        log_warn("No log content available")
      end
    elseif action == 'log-clean' then
      -- Clean up old log files
      logger.cleanup_old_logs(7) -- Keep logs for 7 days
      log_info("Cleaned up old log files")
    elseif action == 'stats' then
      local uptime = math.floor((vim.uv.now() - state.startup_time) / 1000)
      log_info("HoverFloat Statistics", {
        uptime_seconds = uptime,
        total_lsp_requests = state.total_lsp_requests,
        total_updates_sent = state.total_updates_sent,
        last_error_time = state.last_error_time > 0 and os.date("%H:%M:%S", state.last_error_time / 1000) or "none",
        current_hash = state.last_sent_hash and state.last_sent_hash:sub(1, 8) .. "..." or "none",
        logger_status = logger.get_status()
      })
    elseif action == 'test-tui' then
      -- Test TUI binary manually
      local binary_path = find_tui_binary()
      if binary_path then
        log_info("Testing TUI binary", { binary = binary_path })
        local handle = vim.fn.jobstart(
          { binary_path, "--help" },
          {
            on_stdout = function(job_id, data, event)
              if #data > 1 or (data[1] and data[1] ~= "") then
                log_info("TUI help output", table.concat(data, "\n"))
              end
            end,
            on_stderr = function(job_id, data, event)
              if #data > 1 or (data[1] and data[1] ~= "") then
                log_error("TUI help error", table.concat(data, "\n"))
              end
            end,
            on_exit = function(job_id, exit_code, event)
              log_info("TUI help test completed", { exit_code = exit_code })
            end
          }
        )
      else
        log_error("Cannot test TUI - binary not found")
      end
    elseif action == 'socket-info' then
      -- Check socket file status
      local socket_path = state.config.communication.socket_path
      local socket_exists = vim.fn.filereadable(socket_path) == 1
      local socket_stat = socket_exists and vim.fn.getfperm(socket_path) or "none"
      log_info("Socket file information", {
        path = socket_path,
        exists = socket_exists,
        permissions = socket_stat,
        process_id = state.display_process,
        connected = socket_client.is_connected()
      })
    elseif action == 'test-socket' then
      -- Test raw socket connection without plugin overhead
      log_info("Testing raw socket connection", { socket_path = state.config.communication.socket_path })
      local uv = vim.uv or vim.loop
      local test_socket = uv.new_pipe(false)

      if test_socket then
        test_socket:connect(state.config.communication.socket_path, function(err)
          if err then
            log_error("Raw socket test failed", err)
          else
            log_info("Raw socket test successful")
            test_socket:close()
          end
        end)
      else
        log_error("Could not create test socket")
      end
    elseif action == 'test-lsp' then
      -- Test LSP data collection using the simplified approach
      log_info("Testing LSP data collection")
      if not has_lsp_clients() then
        log_error("No LSP clients available for testing")
        return
      end

      lsp_collector.gather_context_info(function(context_data)
        if context_data then
          log_info("LSP test successful", {
            has_hover = context_data.hover and #context_data.hover > 0,
            has_definition = context_data.definition ~= nil,
            references_count = context_data.references_count or 0,
            has_type_def = context_data.type_definition ~= nil,
            file = context_data.file,
            position = string.format("%d:%d", context_data.line, context_data.col)
          })
        else
          log_warn("LSP test returned no data")
        end
      end, state.config.features)
    elseif action == 'switch-debug' then
      -- Switch to debug binary
      local debug_path = vim.fn.expand('~/.local/bin/nvim-context-tui-debug')
      if vim.fn.executable(debug_path) == 1 then
        log_info("Switching to debug binary", { path = debug_path })
        M.set_binary_path(debug_path)
        stop_display_process()
        vim.defer_fn(start_display_process, 500)
      else
        log_error("Debug binary not found", {
          path = debug_path,
          suggestion = "Run 'make debug' to build and install debug binary"
        })
      end
    elseif action == 'switch-prod' then
      -- Switch to production binary
      local prod_path = vim.fn.expand('~/.local/bin/nvim-context-tui')
      if vim.fn.executable(prod_path) == 1 then
        log_info("Switching to production binary", { path = prod_path })
        M.set_binary_path(prod_path)
        stop_display_process()
        vim.defer_fn(start_display_process, 500)
      else
        log_error("Production binary not found", {
          path = prod_path,
          suggestion = "Run 'make prod' to build and install production binary"
        })
      end
    elseif action == 'binary-info' then
      -- Show detailed binary information
      local current_binary = find_tui_binary()
      if current_binary then
        local is_debug = current_binary:match("debug") ~= nil
        local file_info = vim.fn.getfperm(current_binary)
        local file_size = vim.fn.getfsize(current_binary)

        log_info("Current binary information", {
          path = current_binary,
          type = is_debug and "debug" or "production",
          permissions = file_info,
          size_bytes = file_size,
          size_mb = string.format("%.2f MB", file_size / 1024 / 1024),
          executable = vim.fn.executable(current_binary) == 1
        })

        -- Check for other available binaries
        local debug_path = vim.fn.expand('~/.local/bin/nvim-context-tui-debug')
        local prod_path = vim.fn.expand('~/.local/bin/nvim-context-tui')

        log_info("Available binaries", {
          debug_available = vim.fn.executable(debug_path) == 1,
          debug_path = debug_path,
          production_available = vim.fn.executable(prod_path) == 1,
          production_path = prod_path
        })
      else
        log_error("No TUI binary found", {
          suggestion = "Run 'make prod' or 'make debug' to build and install"
        })
      end
    else
      log_info(
      'Usage: ContextWindow [open|close|toggle|restart|status|connect|disconnect|reconnect|health|debug|stats|test-tui|socket-info|test-socket|test-lsp|switch-debug|switch-prod|binary-info|logs|log-path|log-tail|log-clean]')
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'open', 'close', 'toggle', 'restart', 'status', 'connect', 'disconnect', 'reconnect', 'health', 'debug',
        'stats', 'test-tui', 'socket-info', 'test-socket', 'test-lsp', 'switch-debug', 'switch-prod', 'binary-info',
        'logs', 'log-path', 'log-tail', 'log-clean' }
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
  log_info("Setting up HoverFloat plugin")

  -- Merge user configuration with defaults
  state.config = vim.tbl_deep_extend("force", default_config, opts or {})

  log_debug("Plugin configuration", state.config)

  -- Initialize file-based logger (non-disruptive)
  logger.setup({
    debug = state.config.communication.debug,
    log_dir = state.config.communication.log_dir
  })

  log_info("File-based logging initialized", {
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
    log_info("Auto-starting display process in 1 second")
    vim.defer_fn(function()
      start_display_process()
    end, 1000) -- Give Neovim time to fully load
  end

  log_info("LSP Context Window plugin loaded successfully (simplified architecture)", {
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
