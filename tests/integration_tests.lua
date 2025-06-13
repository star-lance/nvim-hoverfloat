-- tests/integration_tests.lua - Integration tests with realistic scenarios

-- Use either plenary or simple runner
local function describe(name, func)
  if _G.describe then
    _G.describe(name, func)
  else
    print("📝 " .. name)
    func()
  end
end

local function it(name, func)
  if _G.it then
    _G.it(name, func)
  else
    local ok, err = pcall(func)
    if ok then
      print("  ✅ " .. name)
    else
      print("  ❌ " .. name .. ": " .. tostring(err))
      error("Test failed: " .. name)
    end
  end
end

local function before_each(func)
  if _G.before_each then
    _G.before_each(func)
  else
    func() -- Execute immediately in simple mode
  end
end

local function after_each(func)
  if _G.after_each then
    _G.after_each(func)
  else
    -- In simple mode, we don't have cleanup hooks
    -- Tests should clean up after themselves
  end
end

-- Use either plenary assert or our simple one
local assert = _G.assert or require('luassert')

-- Test file paths
local LUA_TEST_FILE = vim.fn.expand('<sfile>:h') .. '/sample_files/test_file.lua'
local GO_TEST_FILE = vim.fn.expand('<sfile>:h') .. '/sample_files/test_file.go'

-- Enhanced vim mock for integration testing
_G.vim = {
  uv = { 
    now = function() return os.time() * 1000 end,
    new_timer = function()
      return {
        start = function() end,
        stop = function() end,
        close = function() end
      }
    end
  },
  
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function() return LUA_TEST_FILE end,
    nvim_win_get_cursor = function() return {10, 5} end,
    nvim_win_set_cursor = function() end,
    nvim_buf_is_valid = function() return true end,
    nvim_buf_is_loaded = function() return true end,
    nvim_buf_get_changedtick = function() return 1 end,
    nvim_get_option_value = function(opt)
      if opt == 'filetype' then return 'lua' end
      if opt == 'buftype' then return '' end
      return ''
    end,
    nvim_create_autocmd = function() end,
    nvim_create_augroup = function() return 1 end,
  },
  
  fn = {
    expand = function(expr)
      if expr == '<cword>' then return 'test_symbol' end
      if expr:match('<sfile>') then return '/test/path' end
      return expr
    end,
    fnamemodify = function(file, mod) 
      if mod == ':.' then
        return file:match('[^/]+$') or file
      end
      return file
    end,
    line = function(expr)
      if expr == 'w0' then return 1 end
      if expr == 'w$' then return 50 end
      return 25
    end,
    filereadable = function() return 1 end,
    mkdir = function() end,
  },
  
  lsp = {
    get_clients = function()
      return {{
        id = 1,
        name = 'lua_ls',
        server_capabilities = {
          hoverProvider = true,
          definitionProvider = true,
          referencesProvider = true,
          typeDefinitionProvider = true
        }
      }}
    end,
    buf_request = function(bufnr, method, params, callback)
      -- Simulate realistic LSP responses based on the sample files
      if method == 'textDocument/hover' then
        callback(nil, {
          contents = {
            'function M.add_numbers(x, y)',
            'Adds two numbers together using calculate_sum'
          }
        })
      elseif method == 'textDocument/definition' then
        callback(nil, {{
          uri = LUA_TEST_FILE,
          range = { start = { line = 7, character = 0 } }
        }})
      elseif method == 'textDocument/references' then
        callback(nil, {
          { uri = LUA_TEST_FILE, range = { start = { line = 7, character = 0 } } },
          { uri = LUA_TEST_FILE, range = { start = { line = 12, character = 20 } } }
        })
      else
        callback('Method not supported', nil)
      end
    end
  },
  
  json = {
    encode = function(data) return vim.fn.json_encode(data) end,
    decode = function(str) return vim.fn.json_decode(str) end
  },
  
  defer_fn = function(fn, delay) fn() end,
  wait = function(timeout, condition) return true end,
  schedule_wrap = function(fn) return fn end,
  tbl_filter = function(func, tbl)
    local result = {}
    for _, v in ipairs(tbl) do
      if func(v) then table.insert(result, v) end
    end
    return result
  end,
  
  -- Add missing vim utility functions
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

describe('Real File Integration Tests', function()
  local hoverfloat
  
  before_each(function()
    -- Clear module cache
    for name, _ in pairs(package.loaded) do
      if name:match('^hoverfloat') then
        package.loaded[name] = nil
      end
    end
    
    -- Create test files if they don't exist
    local lua_content = [[
local M = {}
function M.add_numbers(x, y)
  return x + y
end
return M
]]
    local file = io.open(LUA_TEST_FILE, 'w')
    if file then
      file:write(lua_content)
      file:close()
    end
  end)
  
  after_each(function()
    -- Cleanup
    if hoverfloat and hoverfloat.stop then
      hoverfloat.stop()
    end
    os.remove(LUA_TEST_FILE)
    os.remove(GO_TEST_FILE)
  end)

  it('should handle rapid cursor movement without crashes', function()
    local cursor_tracker = require('hoverfloat.core.cursor_tracker')
    local cache = require('hoverfloat.prefetch.cache')
    
    cursor_tracker.enable()
    cache.clear_all()
    
    -- Simulate rapid cursor movement (like scrolling)
    local positions = {
      {1, 1}, {5, 10}, {15, 5}, {20, 15}, {8, 3},
      {25, 8}, {12, 20}, {30, 2}, {18, 12}, {6, 18}
    }
    
    for _, pos in ipairs(positions) do
      vim.api.nvim_win_set_cursor(0, pos)
      cursor_tracker.force_update()
    end
    
    -- Should not crash and should maintain state
    local stats = cursor_tracker.get_stats()
    assert.is_table(stats)
    assert.is_true(stats.tracking_enabled)
    
    cursor_tracker.disable()
  end)

  it('should handle large cursor jumps efficiently', function()
    local cursor_tracker = require('hoverfloat.core.cursor_tracker')
    local performance = require('hoverfloat.core.performance')
    
    performance.reset_stats()
    cursor_tracker.enable()
    
    -- Simulate large jumps (beginning to end of file)
    local large_jumps = {
      {1, 1},      -- Beginning
      {1000, 50},  -- End of large file
      {1, 1},      -- Back to beginning
      {500, 25},   -- Middle
      {1000, 1},   -- End again
    }
    
    local start_time = vim.uv.now()
    
    for _, pos in ipairs(large_jumps) do
      vim.api.nvim_win_set_cursor(0, pos)
      cursor_tracker.force_update()
    end
    
    local elapsed = vim.uv.now() - start_time
    
    -- Should handle large jumps quickly (< 100ms total)
    assert.is_true(elapsed < 100, "Large jumps should be handled quickly")
    
    cursor_tracker.disable()
  end)

  it('should cache data effectively during normal usage', function()
    local cache = require('hoverfloat.prefetch.cache')
    local lsp_service = require('hoverfloat.core.lsp_service')
    
    cache.clear_all()
    
    -- Simulate normal editing session with repeated visits to same symbols
    local common_positions = {
      {8, 20},  -- M.add_numbers
      {9, 15},  -- Inside function
      {8, 20},  -- Back to M.add_numbers (should hit cache)
    }
    
    local cache_hits = 0
    local lsp_requests = 0
    
    for _, pos in ipairs(common_positions) do
      vim.api.nvim_win_set_cursor(0, pos)
      
      -- Check if data is cached
      local cached = cache.get_cursor_data()
      if cached then
        cache_hits = cache_hits + 1
      else
        lsp_requests = lsp_requests + 1
        
        -- Simulate LSP response and caching
        local test_data = {
          hover = {'test hover content'},
          definition = {file = LUA_TEST_FILE, line = 8, col = 20}
        }
        cache.store(1, pos[1], 'test_symbol', test_data)
      end
    end
    
    -- Should have at least one cache hit from repeated position
    assert.is_true(cache_hits > 0, "Should have cache hits for repeated positions")
    
    local stats = cache.get_stats()
    assert.is_true(stats.total_symbols_cached > 0)
  end)

  it('should handle edge cases gracefully', function()
    local buffer = require('hoverfloat.utils.buffer')
    local symbols = require('hoverfloat.utils.symbols')
    
    -- Test with empty file
    vim.api.nvim_buf_get_name = function() return '/tmp/empty.lua' end
    local empty_file = io.open('/tmp/empty.lua', 'w')
    if empty_file then
      empty_file:close()
    end
    
    assert.is_true(buffer.is_valid_buffer(1))
    
    -- Test with very long lines
    vim.api.nvim_win_set_cursor(0, {1, 1000})
    local symbol = symbols.get_word_under_cursor()
    assert.is_string(symbol)
    
    -- Test with invalid positions
    vim.api.nvim_win_set_cursor(0, {-1, -1})
    local context = require('hoverfloat.core.position').get_current_context()
    assert.is_table(context)
    
    -- Cleanup
    os.remove('/tmp/empty.lua')
  end)

  it('should handle communication failures gracefully', function()
    local socket_client = require('hoverfloat.communication.socket_client')
    
    -- Test sending data when not connected
    local test_data = {
      file = LUA_TEST_FILE,
      line = 10,
      col = 5,
      timestamp = vim.uv.now()
    }
    
    local success = socket_client.send_context_update(test_data)
    -- Should handle gracefully (return false, not crash)
    assert.is_boolean(success)
    
    local status = socket_client.get_status()
    assert.is_table(status)
    assert.is_boolean(status.connected)
  end)

  it('should maintain performance under load', function()
    local performance = require('hoverfloat.core.performance')
    local cache = require('hoverfloat.prefetch.cache')
    
    performance.reset_stats()
    cache.clear_all()
    
    -- Simulate heavy usage
    local start_time = vim.uv.now()
    
    for i = 1, 50 do
      local mock_data = {
        hover = {'content ' .. i},
        definition = {file = '/test' .. i .. '.lua', line = i, col = 1}
      }
      
      -- Store in cache
      cache.store(1, i, 'symbol_' .. i, mock_data)
      
      -- Record performance metrics
      local req_start = performance.start_request()
      performance.complete_request(req_start, i % 2 == 0, false)
    end
    
    local elapsed = vim.uv.now() - start_time
    local stats = performance.get_stats()
    
    -- Should handle 50 operations quickly
    assert.is_true(elapsed < 500, "Should handle load efficiently")
    assert.equals(50, stats.total_requests)
    assert.is_true(stats.cache_hits > 0)
    
    -- Cache should have data
    local cache_stats = cache.get_stats()
    assert.is_true(cache_stats.total_symbols_cached > 40)
  end)
end)
