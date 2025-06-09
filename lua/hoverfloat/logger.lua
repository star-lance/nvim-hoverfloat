-- lua/hoverfloat/logger.lua - Non-disruptive file-based logging
local M = {}

-- Logger state
local logger_state = {
  log_file = nil,
  log_path = nil,
  debug_enabled = false,
  session_id = nil,
}

-- Initialize logger
function M.setup(config)
  config = config or {}
  
  -- Generate session ID
  logger_state.session_id = os.date("%Y%m%d_%H%M%S") .. "_" .. math.random(1000, 9999)
  
  -- Set log file path
  local log_dir = config.log_dir or (vim.fn.stdpath('cache') .. '/hoverfloat')
  vim.fn.mkdir(log_dir, 'p') -- Create directory if it doesn't exist
  
  logger_state.log_path = log_dir .. '/debug_' .. logger_state.session_id .. '.log'
  logger_state.debug_enabled = config.debug or false
  
  -- Create/open log file
  if logger_state.debug_enabled then
    logger_state.log_file = io.open(logger_state.log_path, 'w')
    if logger_state.log_file then
      logger_state.log_file:write(string.format("=== HoverFloat Debug Session Started: %s ===\n", os.date("%Y-%m-%d %H:%M:%S")))
      logger_state.log_file:write(string.format("Session ID: %s\n", logger_state.session_id))
      logger_state.log_file:write(string.format("Neovim Version: %s\n", vim.version()))
      logger_state.log_file:write(string.format("Log Path: %s\n", logger_state.log_path))
      logger_state.log_file:write("=====================================\n\n")
      logger_state.log_file:flush()
    end
  end
end

-- Close logger
function M.cleanup()
  if logger_state.log_file then
    logger_state.log_file:write(string.format("\n=== Session Ended: %s ===\n", os.date("%Y-%m-%d %H:%M:%S")))
    logger_state.log_file:close()
    logger_state.log_file = nil
  end
end

-- Write to log file only (non-disruptive)
local function write_to_file(level, component, message, data)
  if not logger_state.debug_enabled or not logger_state.log_file then
    return
  end
  
  local timestamp = os.date("%H:%M:%S.") .. string.format("%03d", (vim.uv.now() % 1000))
  local log_line = string.format("[%s] %s [%s] %s", timestamp, level, component, message)
  
  if data then
    log_line = log_line .. ": " .. vim.inspect(data)
  end
  
  logger_state.log_file:write(log_line .. "\n")
  logger_state.log_file:flush() -- Ensure immediate write
end

-- Send to TUI window for display (optional)
local function send_to_tui(level, component, message, data)
  -- Only send important messages to TUI to avoid spam
  if level == "ERROR" or level == "WARN" then
    -- This will be implemented later - send structured message to TUI
    -- for now, just write to file
  end
end

-- Logging functions (non-disruptive)
function M.debug(component, message, data)
  write_to_file("DEBUG", component, message, data)
end

function M.info(component, message, data)
  write_to_file("INFO", component, message, data)
  send_to_tui("INFO", component, message, data)
end

function M.warn(component, message, data)
  write_to_file("WARN", component, message, data)
  send_to_tui("WARN", component, message, data)
end

function M.error(component, message, data)
  write_to_file("ERROR", component, message, data)
  send_to_tui("ERROR", component, message, data)
end

-- Convenience function for socket logging
function M.socket(level, message, data)
  local level_map = {
    debug = M.debug,
    info = M.info,
    warn = M.warn,
    error = M.error
  }
  
  local log_func = level_map[level] or M.debug
  log_func("Socket", message, data)
end

-- Convenience function for LSP logging
function M.lsp(level, message, data)
  local level_map = {
    debug = M.debug,
    info = M.info,
    warn = M.warn,
    error = M.error
  }
  
  local log_func = level_map[level] or M.debug
  log_func("LSP", message, data)
end

-- Convenience function for plugin logging
function M.plugin(level, message, data)
  local level_map = {
    debug = M.debug,
    info = M.info,
    warn = M.warn,
    error = M.error
  }
  
  local log_func = level_map[level] or M.debug
  log_func("Plugin", message, data)
end

-- Get current log file path
function M.get_log_path()
  return logger_state.log_path
end

-- Get logger status
function M.get_status()
  return {
    enabled = logger_state.debug_enabled,
    log_path = logger_state.log_path,
    session_id = logger_state.session_id,
    file_open = logger_state.log_file ~= nil
  }
end

-- Enable debug logging
function M.enable_debug()
  if not logger_state.debug_enabled then
    logger_state.debug_enabled = true
    M.setup({ debug = true })
    M.info("Logger", "Debug logging enabled")
  end
end

-- Disable debug logging
function M.disable_debug()
  if logger_state.debug_enabled then
    M.info("Logger", "Debug logging disabled")
    logger_state.debug_enabled = false
    M.cleanup()
  end
end

-- Tail log file (for development)
function M.tail_log(lines)
  if not logger_state.log_path or not vim.fn.filereadable(logger_state.log_path) then
    return {}
  end
  
  lines = lines or 50
  local cmd = string.format("tail -n %d %s", lines, vim.fn.shellescape(logger_state.log_path))
  local output = vim.fn.system(cmd)
  
  return vim.split(output, '\n')
end

-- Show log in new buffer (for debugging)
function M.show_log()
  if not logger_state.log_path or not vim.fn.filereadable(logger_state.log_path) then
    print("No log file available")
    return
  end
  
  -- Open log file in new split
  vim.cmd('split ' .. vim.fn.fnameescape(logger_state.log_path))
  vim.bo.readonly = true
  vim.bo.modifiable = false
  vim.bo.filetype = 'log'
  
  -- Go to end of file
  vim.cmd('normal! G')
end

-- Archive old log files
function M.cleanup_old_logs(days)
  days = days or 7
  local log_dir = vim.fn.stdpath('cache') .. '/hoverfloat'
  
  if not vim.fn.isdirectory(log_dir) then
    return
  end
  
  local files = vim.fn.glob(log_dir .. '/debug_*.log', false, true)
  local cutoff_time = os.time() - (days * 24 * 60 * 60)
  
  for _, file in ipairs(files) do
    local stat = vim.fn.getfperm(file)
    if stat ~= "" then
      local mtime = vim.fn.getftime(file)
      if mtime < cutoff_time then
        vim.fn.delete(file)
        M.debug("Logger", "Cleaned up old log file", { file = file })
      end
    end
  end
end

return M
