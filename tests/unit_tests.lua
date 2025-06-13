-- tests/unit_tests.lua - Simplified unit tests for core functionality

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
    -- Execute immediately in simple mode
    func()
  end
end

-- Use either plenary assert or our simple one
local assert = _G.assert or require('luassert')

-- Simple vim mock - only what we actually need
_G.vim = {
  uv = { now = function() return 1234567890 end },
  api = {
    nvim_get_current_buf = function() return 1 end,
    nvim_buf_get_name = function() return '/test/file.lua' end,
    nvim_win_get_cursor = function() return {10, 5} end,
    nvim_buf_get_changedtick = function() return 1 end,
    nvim_buf_is_valid = function() return true end,
    nvim_get_option_value = function(opt) 
      if opt == 'filetype' then return 'lua' end
      if opt == 'buftype' then return '' end
      return ''
    end,
  },
  fn = {
    expand = function(expr)
      if expr == '<cword>' then return 'test_symbol' end
      return expr
    end,
    fnamemodify = function(file, mod) return 'test_file.lua' end,
    json_encode = function(data) return '{"test":"json"}' end,
    json_decode = function(str) return {test = "json"} end,
  },
  json = {
    encode = function(data) return '{"test":"json"}' end,
    decode = function(str) return {test = "json"} end,
  },
  lsp = {
    get_clients = function() return {{name = "test_lsp"}} end,
  },
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

describe('Core Position Utils', function()
  it('should get current context', function()
    local position = require('hoverfloat.core.position')
    local context = position.get_current_context()
    
    assert.is_table(context)
    assert.is_string(context.file)
    assert.is_number(context.line)
    assert.is_number(context.col)
    assert.is_number(context.timestamp)
  end)

  it('should create position identifier', function()
    local position = require('hoverfloat.core.position')
    local id = position.get_position_identifier()
    
    assert.is_string(id)
    assert.matches('test_file%.lua:%d+:%d+:', id)
  end)
end)

describe('Symbol Utilities', function()
  it('should get word under cursor', function()
    local symbols = require('hoverfloat.utils.symbols')
    local word = symbols.get_word_under_cursor()
    
    assert.equals('test_symbol', word)
  end)

  it('should validate symbol structure', function()
    local symbols = require('hoverfloat.utils.symbols')
    
    local valid_symbol = {
      name = 'test_func',
      kind = 12,
      start_line = 1,
      end_line = 5,
      start_col = 1,
      end_col = 10
    }
    
    local is_valid, error_msg = symbols.validate_symbol(valid_symbol)
    assert.is_true(is_valid)
    assert.is_nil(error_msg)
    
    -- Test invalid symbol
    local invalid_symbol = {name = 'incomplete'}
    local is_invalid, error_msg2 = symbols.validate_symbol(invalid_symbol)
    assert.is_false(is_invalid)
    assert.is_string(error_msg2)
  end)
end)

describe('Cache System', function()
  local cache
  
  before_each(function()
    cache = require('hoverfloat.prefetch.cache')
    cache.clear_all()
  end)

  it('should store and retrieve data', function()
    local test_data = {
      hover = {'Function documentation'},
      definition = {file = '/test.lua', line = 10, col = 5}
    }
    
    cache.store(1, 10, 'test_symbol', test_data)
    local retrieved = cache.get(1, 10, 'test_symbol')
    
    assert.is_table(retrieved)
    assert.same({'Function documentation'}, retrieved.hover)
    assert.same({file = '/test.lua', line = 10, col = 5}, retrieved.definition)
  end)

  it('should return nil for missing data', function()
    local result = cache.get(999, 999, 'missing')
    assert.is_nil(result)
  end)

  it('should clear cache properly', function()
    cache.store(1, 10, 'test', {hover = {'test'}})
    cache.clear_buffer(1)
    
    local result = cache.get(1, 10, 'test')
    assert.is_nil(result)
  end)
end)

describe('Message Handling', function()
  it('should create context update message', function()
    local msg_handler = require('hoverfloat.communication.message_handler')
    
    local context = {
      file = '/test.lua',
      line = 10,
      col = 5,
      hover = {'test hover'}
    }
    
    local message = msg_handler.create_context_update(context)
    assert.is_string(message)
    assert.matches('context_update', message)
    assert.matches('\n$', message) -- ends with newline
  end)

  it('should validate messages correctly', function()
    local msg_handler = require('hoverfloat.communication.message_handler')
    
    local valid_json = '{"type":"ping","timestamp":1234567890,"data":{}}'
    local is_valid, parsed = msg_handler.validate_message(valid_json)
    
    assert.is_true(is_valid)
    assert.is_table(parsed)
    assert.equals('ping', parsed.type)
    
    -- Test invalid message
    local invalid_json = 'not json'
    local is_invalid, error_msg = msg_handler.validate_message(invalid_json)
    assert.is_false(is_invalid)
    assert.is_string(error_msg)
  end)
end)

describe('Performance Tracking', function()
  local performance
  
  before_each(function()
    performance = require('hoverfloat.core.performance')
    performance.reset_stats()
  end)

  it('should track request timing', function()
    local start_time = performance.start_request()
    assert.is_number(start_time)
    
    local response_time = performance.complete_request(start_time, false, false)
    assert.is_number(response_time)
    assert.is_true(response_time >= 0)
    
    local stats = performance.get_stats()
    assert.equals(1, stats.total_requests)
  end)

  it('should record cache operations', function()
    performance.record_cache_hit()
    performance.record_lsp_request()
    
    local stats = performance.get_stats()
    assert.is_true(stats.cache_hits > 0)
    assert.is_true(stats.lsp_requests > 0)
  end)

  it('should calculate hit rates', function()
    -- Record some operations
    performance.record_cache_hit()
    performance.record_cache_hit()
    performance.record_lsp_request()
    
    local hit_rate = performance.get_cache_hit_rate()
    assert.is_number(hit_rate)
    assert.is_true(hit_rate >= 0 and hit_rate <= 1)
  end)
end)
