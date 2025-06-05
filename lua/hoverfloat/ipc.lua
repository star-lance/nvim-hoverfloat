-- lua/hoverfloat/ipc.lua - Inter-process communication management
local M = {}

local uv = vim.uv or vim.loop
local display = require('hoverfloat.display')

local display_process = nil
local display_stdin = nil

-- Setup cleanup autocmd
function M.setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("HoverFloatCleanup", { clear = true }),
    callback = function()
      M.stop_display()
      display.cleanup()
    end,
  })
end

-- Start the display process
function M.start_display(config)
  local program_path = display.create_program()
  if not program_path then
    print("Error: Could not create display program")
    return false
  end

  -- Clean up any existing process
  M.stop_display()

  -- Create pipes for communication
  local stdin = uv.new_pipe(false)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  -- Terminal arguments
  local args = {
    "--title", config.window_title,
    "--hold",
    "-e", program_path
  }

  -- Spawn the terminal process
  display_process = uv.spawn(config.terminal_cmd, {
    args = args,
    stdio = {stdin, stdout, stderr},
  }, function(code, signal)
    display_process = nil
    display_stdin = nil
    print("Context display process exited with code:", code)
  end)

  if display_process then
    display_stdin = stdin
    
    -- Handle stdout/stderr for debugging
    stdout:read_start(function(err, data)
      if err then
        print("Display stdout error:", err)
      end
    end)
    
    stderr:read_start(function(err, data)
      if err then
        print("Display stderr error:", err)
      elseif data then
        print("Display process error:", data)
      end
    end)
    
    print("Context display process started")
    return true
  else
    print("Failed to start context display process")
    return false
  end
end

-- Stop the display process
function M.stop_display()
  if display_process then
    if display_stdin and not display_stdin:is_closing() then
      display_stdin:close()
    end
    display_process:kill("sigterm")
    display_process:close()
    display_process = nil
    display_stdin = nil
    print("Context window closed")
  end
end

-- Send data to the display process
function M.send_data(data)
  if display_stdin and not display_stdin:is_closing() then
    local json_data = vim.json.encode(data)
    display_stdin:write(json_data .. "\n")
  end
end

-- Check if display is running
function M.is_running()
  return display_process ~= nil
end

return M
