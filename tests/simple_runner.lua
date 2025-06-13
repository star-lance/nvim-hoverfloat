-- tests/simple_runner.lua - Simple test runner without plenary commands

-- Get the test file from command line argument
local test_file = _G.arg and _G.arg[1]
if not test_file then
  error("Usage: nvim -l simple_runner.lua <test_file>")
end

print("🧪 Running: " .. test_file)

-- Get plugin directory (parent of tests directory)
local test_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local plugin_path = vim.fn.fnamemodify(test_dir, ":h")

-- Set up module loading paths for the plugin
package.path = package.path .. ";" .. plugin_path .. "/lua/?.lua"
package.path = package.path .. ";" .. plugin_path .. "/lua/?/init.lua"

print("📂 Plugin path: " .. plugin_path)

-- Set up minimal vim mock that our plugin modules expect
_G.vim = {
  fn = {
    expand = function(expr) 
      if expr == '<cword>' then return 'test_symbol' end
      if expr == '<cWORD>' then return 'test_symbol' end
      if expr:match("^<sfile>") then return plugin_path end
      if expr:match("^~") then return expr:gsub("^~", os.getenv("HOME")) end
      return expr
    end,
    fnamemodify = function(path, mod) 
      if mod == ':.' then
        return path:match("[^/]+$") or path
      end
      return path
    end,
    stdpath = function(what) 
      if what == 'log' then return '/tmp/nvim_test' end
      return '/tmp' 
    end,
    json_encode = function(data) return '{"mock":"data"}' end,
    json_decode = function(str) return {mock = "data"} end,
  },
  opt = {},
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function() return '/test/file.lua' end,
    nvim_win_get_cursor = function() return {10, 5} end,
    nvim_buf_get_changedtick = function() return 1 end,
    nvim_buf_is_valid = function() return true end,
    nvim_buf_is_loaded = function() return true end,
    nvim_get_option_value = function(opt) 
      if opt == 'filetype' then return 'lua' end
      if opt == 'buftype' then return '' end
      return ''
    end,
  },
  uv = { now = function() return os.time() * 1000 end },
  lsp = {
    get_clients = function() return {{name = "test_lsp"}} end,
  },
  json = {
    encode = function(data) return '{"mock":"json"}' end,
    decode = function(str) return {mock = "json"} end,
  },
  -- Add the missing functions that caused the original error
  deepcopy = function(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end,
  tbl_deep_extend = function(behavior, ...)
    local result = {}
    for _, tbl in ipairs({...}) do
      for k, v in pairs(tbl or {}) do
        if type(v) == 'table' and type(result[k]) == 'table' then
          result[k] = vim.tbl_deep_extend(behavior, result[k], v)
        else
          result[k] = v
        end
      end
    end
    return result
  end,
}

-- Try to load and run plenary
local plenary_ok = false
local test_result = false

-- Look for plenary in common locations
local plenary_paths = {
  os.getenv("HOME") .. "/.local/share/nvim/lazy/plenary.nvim/lua",
  os.getenv("HOME") .. "/.local/share/nvim/site/pack/packer/start/plenary.nvim/lua",
}

for _, path in ipairs(plenary_paths) do
  package.path = package.path .. ";" .. path .. "/?.lua"
  package.path = package.path .. ";" .. path .. "/?/init.lua"
  
  local ok, _ = pcall(require, 'plenary.busted')
  if ok then
    plenary_ok = true
    print("✅ Found plenary at: " .. path)
    break
  end
end

if not plenary_ok then
  print("❌ plenary.nvim not found - falling back to basic test runner")
  
  -- Simple test runner without plenary
  local function describe(name, func)
    print("📝 " .. name)
    func()
  end
  
  local function it(name, func)
    local ok, err = pcall(func)
    if ok then
      print("  ✅ " .. name)
    else
      print("  ❌ " .. name .. ": " .. tostring(err))
      test_result = false
    end
  end
  
  _G.describe = describe
  _G.it = it
  
  -- Mock assert
  _G.assert = {
    equals = function(expected, actual) 
      if expected ~= actual then
        error("Expected " .. tostring(expected) .. " but got " .. tostring(actual))
      end
    end,
    is_true = function(val) 
      if not val then
        error("Expected true but got " .. tostring(val))
      end
    end,
    is_false = function(val) 
      if val then
        error("Expected false but got " .. tostring(val))
      end
    end,
    is_table = function(val)
      if type(val) ~= 'table' then
        error("Expected table but got " .. type(val))
      end
    end,
    is_string = function(val)
      if type(val) ~= 'string' then
        error("Expected string but got " .. type(val))
      end
    end,
    is_number = function(val)
      if type(val) ~= 'number' then
        error("Expected number but got " .. type(val))
      end
    end,
    is_function = function(val)
      if type(val) ~= 'function' then
        error("Expected function but got " .. type(val))
      end
    end,
    is_nil = function(val)
      if val ~= nil then
        error("Expected nil but got " .. tostring(val))
      end
    end,
    same = function(expected, actual)
      -- Simple deep comparison
      if type(expected) ~= type(actual) then
        error("Types don't match")
      end
      if type(expected) == 'table' then
        for k, v in pairs(expected) do
          if actual[k] ~= v then
            error("Table values don't match at key " .. tostring(k))
          end
        end
      else
        if expected ~= actual then
          error("Values don't match")
        end
      end
    end,
    matches = function(pattern, str)
      if not string.match(str, pattern) then
        error("String '" .. str .. "' doesn't match pattern '" .. pattern .. "'")
      end
    end,
  }
  
  test_result = true
end

-- Load and run the test file
local ok, err = pcall(dofile, test_file)
if not ok then
  print("❌ Error loading test file: " .. tostring(err))
  os.exit(1)
end

if plenary_ok then
  -- Try to run with plenary
  local busted = require('plenary.busted')
  local success, result = pcall(function()
    return busted.run(test_file)
  end)
  
  if success then
    print("✅ Tests completed with plenary")
    os.exit(0)
  else
    print("❌ Plenary test failed: " .. tostring(result))
    os.exit(1)
  end
else
  -- Use simple test result
  if test_result then
    print("✅ Tests completed successfully")
    os.exit(0)
  else
    print("❌ Some tests failed")
    os.exit(1)
  end
end
