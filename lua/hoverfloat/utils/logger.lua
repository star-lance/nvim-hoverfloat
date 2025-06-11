-- lua/hoverfloat/utils/logger.lua - Simplified logging utility
local M = {}

local state = {
  log_file = nil,
  log_path = nil,
  debug_enabled = false,
}

-- Setup logging
function M.setup(config)
  config = config or {}
  
  local session_id = os.date("%Y%m%d_%H%M%S") .. "_" .. math.random(1000, 9999)
  local log_dir = config.log_dir or (vim.fn.stdpath('log') .. '/hoverfloat')
  vim.fn.mkdir(log_dir, 'p')
  
  state.log_path = log_dir .. '/debug_' .. session_id .. '.log'
  state.debug_enabled = config.debug or false
  
  if state.debug_enabled then
    state.log_file = io.open(state.log_path, 'w')
    if state.log_file then
      M.info("Logger", "Debug logging enabled: " .. state.log_path)
    end
  end
end

-- Cleanup logging
function M.cleanup()
  if state.log_file then
    state.log_file:close()
    state.log_file = nil
  end
end

-- Write to log file
local function write_to_file(level, component, message, data)
  if not state.log_file then
    return
  end
  
  local timestamp = os.date("%H:%M:%S.") .. string.format("%03d", (vim.uv.now() % 1000))
  local log_line = string.format("[%s] %s [%s] %s", timestamp, level, component, message)
  
  if data then
    log_line = log_line .. ": " .. vim.inspect(data)
  end
  
  state.log_file:write(log_line .. "\n")
  state.log_file:flush()
end

-- Logging functions
function M.debug(component, message, data)
  if state.debug_enabled then
    write_to_file("DEBUG", component, message, data)
  end
end

function M.info(component, message, data)
  if state.debug_enabled then
    write_to_file("INFO", component, message, data)
  end
end

function M.warn(component, message, data)
  if state.debug_enabled then
    write_to_file("WARN", component, message, data)
  end
end

function M.error(component, message, data)
  if state.debug_enabled then
    write_to_file("ERROR", component, message, data)
  end
end

-- Component-specific loggers
function M.socket(level, message, data)
  local level_funcs = { debug = M.debug, info = M.info, warn = M.warn, error = M.error }
  local func = level_funcs[level] or M.debug
  func("Socket", message, data)
end

function M.lsp(level, message, data)
  local level_funcs = { debug = M.debug, info = M.info, warn = M.warn, error = M.error }
  local func = level_funcs[level] or M.debug
  func("LSP", message, data)
end

function M.plugin(level, message, data)
  local level_funcs = { debug = M.debug, info = M.info, warn = M.warn, error = M.error }
  local func = level_funcs[level] or M.debug
  func("Plugin", message, data)
  
  -- Also output to Neovim messages for important levels
  if level == "error" then
    vim.notify("hoverfloat: " .. message, vim.log.levels.ERROR)
  elseif level == "warn" then
    vim.notify("hoverfloat: " .. message, vim.log.levels.WARN)
  elseif level == "info" and data then
    vim.notify("hoverfloat: " .. message .. " - " .. vim.inspect(data), vim.log.levels.INFO)
  end
end

-- Get logger status
function M.get_status()
  return {
    enabled = state.debug_enabled,
    log_path = state.log_path,
    file_open = state.log_file ~= nil
  }
end

-- Get log path
function M.get_log_path()
  return state.log_path
end

return M
