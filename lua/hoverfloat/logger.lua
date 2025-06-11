local M = {}

local state = {
  log_file = nil,
  debug_enabled = false,
}

function M.setup(config)
  config = config or {}
  local session_id = os.date("%Y%m%d_%H%M%S") .. "_" .. math.random(1000, 9999)
  local log_dir = (vim.fn.stdpath('log') .. '/hoverfloat')
  vim.fn.mkdir(log_dir, 'p')
  local log_path = log_dir .. '/debug_' .. session_id .. '.log'
  state.debug_enabled = config.debug or false

  if state.debug_enabled then
    state.log_file = io.open(log_path, 'w')
  end

  initialize_logging_functions()
end

function M.cleanup()
  if state.log_file then
    state.log_file:close()
    state.log_file = nil
  end
end

local function noop() end

M.debug = noop
M.info = noop
M.warn = noop
M.error = noop
M.socket = noop
M.lsp = noop
M.plugin = noop

local function write_to_file(level, component, message, data)
  local timestamp = os.date("%H:%M:%S.") .. string.format("%03d", (vim.uv.now() % 1000))
  local log_line = string.format("[%s] %s [%s] %s", timestamp, level, component, message)
  if data then
    log_line = log_line .. ": " .. vim.inspect(data)
  end
  state.log_file:write(log_line .. "\n")
  state.log_file:flush()
end

function initialize_logging_functions()
  if state.debug_enabled and state.log_file then
    M.debug = function(component, message, data)
      write_to_file("DEBUG", component, message, data)
    end
    M.info = function(component, message, data)
      write_to_file("INFO", component, message, data)
    end
    M.warn = function(component, message, data)
      write_to_file("WARN", component, message, data)
    end
    M.error = function(component, message, data)
      write_to_file("ERROR", component, message, data)
    end

    local level_funcs = { debug = M.debug, info = M.info, warn = M.warn, error = M.error }
    M.socket = function(level, message, data)
      (level_funcs[level] or M.debug)("Socket", message, data)
    end
    M.lsp = function(level, message, data)
      (level_funcs[level] or M.debug)("LSP", message, data)
    end
    M.plugin = function(level, message, data)
      (level_funcs[level] or M.debug)("Plugin", message, data)
    end
  else
    M.debug = noop
    M.info = noop
    M.warn = noop
    M.error = noop
    M.socket = noop
    M.lsp = noop
    M.plugin = noop
  end
end

function M.get_status()
  return {
    enabled = state.debug_enabled,
    file_open = state.log_file ~= nil
  }
end

function M.initialize_log_decorators(module_table)
  return module_table or {}
end

return M
