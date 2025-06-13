local assert = require('luassert')
local spy = require('luassert.spy')
local stub = require('luassert.stub')

local function setup_test_environment()
  -- if there are any loaded hoverfloat modules, clear them
  for name, _ in pairs(package.loaded) do
    if name:match('^hoverfloat') then
      package.loaded[name] = nil
    end
  end
end

local function create_mock_lsp_data()
  return {
    file = '/test/file.lua',
    line = 10,
    col = 5,
    timestamp = 1234567890,
    hover = { 'Test hover content', 'Second line' },
    definition = { file = '/test/def.lua', line = 20, col = 10 },
    references = {
      { file = '/test/ref1.lua', line = 5,  col = 2 },
      { file = '/test/ref2.lua', line = 15, col = 8 }
    },
    references_count = 2,
    type_definition = { file = '/test/typedef.lua', line = 30, col = 15 }
  }
end

-- Neovim API Mock
local function setup_comprehensive_vim_mock()
  _G.vim = {
    -- Core vim modules
    uv = {
      now = function() return 1234567890 end,
      new_timer = function()
        return {
          start = function() end,
          stop = function() end,
          close = function() end,
          is_closing = function() return false end
        }
      end,
      new_pipe = function()
        return {
          connect = function(path, callback) callback(nil) end,
          read_start = function() end,
          write = function() return true end,
          close = function() end,
          is_closing = function() return false end
        }
      end
    },

    -- API functions
    api = {
      nvim_get_current_buf = function() return 1 end,
      nvim_buf_get_name = function() return '/test/file.lua' end,
      nvim_win_get_cursor = function() return { 10, 5 } end,
      nvim_get_current_win = function() return 1 end,
      nvim_win_set_cursor = function() end,
      nvim_buf_is_valid = function() return true end,
      nvim_buf_is_loaded = function() return true end,
      nvim_get_option_value = function(opt, opts)
        if opt == 'buftype' then return '' end
        if opt == 'filetype' then return 'lua' end
        return ''
      end,
      nvim_buf_get_changedtick = function() return 1 end,
      nvim_list_bufs = function() return { 1, 2, 3 } end,
      nvim_create_augroup = function() return 1 end,
      nvim_create_autocmd = function() end,
      nvim_create_user_command = function() end,
      nvim_get_commands = function() return { ContextWindow = {} } end
    },

    -- LSP module
    lsp = {
      get_clients = function()
        return { {
          id = 1,
          name = 'test_lsp',
          server_capabilities = {
            hoverProvider = true,
            definitionProvider = true,
            referencesProvider = true,
            typeDefinitionProvider = true,
            documentSymbolProvider = true
          },
          config = { root_dir = '/test' }
        } }
      end,
      buf_request = function(bufnr, method, params, callback)
        if method == 'textDocument/hover' then
          callback(nil, { contents = { 'test hover content' } })
        elseif method == 'textDocument/definition' then
          callback(nil, { { uri = '/test/def.lua', range = { start = { line = 19, character = 9 } } } })
        elseif method == 'textDocument/references' then
          callback(nil, {
            { uri = '/test/ref1.lua', range = { start = { line = 4, character = 1 } } },
            { uri = '/test/ref2.lua', range = { start = { line = 14, character = 7 } } }
          })
        elseif method == 'textDocument/typeDefinition' then
          callback(nil, { { uri = '/test/typedef.lua', range = { start = { line = 29, character = 14 } } } })
        elseif method == 'textDocument/documentSymbol' then
          callback(nil, {
            { name = 'test_function', kind = 12, range = { start = { line = 0, character = 0 }, ['end'] = { line = 5, character = 10 } } }
          })
        else
          callback('Unknown method', nil)
        end
      end,
      util = {
        make_text_document_params = function() return { uri = 'file:///test/file.lua' } end,
        make_position_params = function()
          return {
            textDocument = { uri = 'file:///test/file.lua' },
            position = { line = 9, character = 4 }
          }
        end,
        convert_input_to_markdown_lines = function(contents)
          if type(contents) == 'table' then
            return contents
          end
          return { contents }
        end
      }
    },

    -- Utility functions
    fn = {
      expand = function(expr)
        if expr == '<cword>' then return 'test_symbol' end
        if expr == '<cWORD>' then return 'test_symbol' end
        if expr == '<sfile>:h:h' then return '/test/plugin' end
        if expr:match('^~') then return expr:gsub('^~', '/home/user') end
        return expr
      end,
      fnamemodify = function(file, modifier)
        if modifier == ':.' then return file:gsub('^.*/', '') end
        return file
      end,
      executable = function() return 1 end,
      jobstart = function() return 12345 end,
      jobstop = function() end,
      line = function(expr, winnr)
        if expr == 'w0' then return 1 end
        if expr == 'w$' then return 50 end
        return 25
      end,
      filereadable = function() return 1 end,
      mkdir = function() end,
      stdpath = function(what)
        if what == 'log' then return '/tmp/nvim' end
        return '/tmp'
      end
    },

    -- Other modules
    json = {
      encode = function(data) return '{"test":"data"}' end,
      decode = function(str) return { test = 'data' } end
    },

    keymap = {
      set = function() end,
      del = function() end
    },

    notify = function() end,

    schedule_wrap = function(fn) return fn end,
    schedule = function(fn) fn() end,
    defer_fn = function(fn, delay) fn() end,
    wait = function(timeout, condition) return true end,

    tbl_filter = function(func, tbl)
      local result = {}
      for _, v in ipairs(tbl) do
        if func(v) then table.insert(result, v) end
      end
      return result
    end,

    tbl_contains = function(tbl, val)
      for _, v in ipairs(tbl) do
        if v == val then return true end
      end
      return false
    end,

    tbl_count = function(tbl)
      local count = 0
      for _ in pairs(tbl) do count = count + 1 end
      return count
    end,

    tbl_keys = function(tbl)
      local keys = {}
      for k in pairs(tbl) do table.insert(keys, k) end
      return keys
    end,

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
      for _, tbl in ipairs({ ... }) do
        for k, v in pairs(tbl) do
          result[k] = v
        end
      end
      return result
    end,

    islist = function(tbl)
      return type(tbl) == 'table' and #tbl > 0
    end,

    uri_to_bufnr = function(uri) return 1 end,

    log = {
      levels = {
        ERROR = 1,
        WARN = 2,
        INFO = 3,
        DEBUG = 4
      }
    },

    cmd = function() end,

    loop = vim.uv, -- Alias for compatibility

    g = {},
    opt = {
      rtp = { prepend = function() end },
      swapfile = false,
      backup = false,
      undofile = false
    },

    env = {}
  }
end

-- Unit Tests

describe('hoverfloat.core.position', function()
  local position

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    position = require('hoverfloat.core.position')
  end)

  it('should get current context with correct format', function()
    local result = position.get_current_context()
    assert.is_table(result)
    assert.is_string(result.file)
    assert.is_number(result.line)
    assert.is_number(result.col)
    assert.is_number(result.timestamp)
    assert.is_number(result.bufnr)
  end)

  it('should get file path correctly', function()
    local file_path = position.get_file_path(1)
    assert.equals('file.lua', file_path)
  end)

  it('should get cursor position', function()
    local cursor_pos = position.get_cursor_position()
    assert.same({ 10, 5 }, cursor_pos)
  end)

  it('should create position identifier', function()
    local identifier = position.get_position_identifier()
    assert.is_string(identifier)
    assert.matches('file%.lua:%d+:%d+:', identifier)
  end)

  it('should make LSP position params', function()
    local params = position.make_lsp_position_params(1, 10, 6)
    assert.is_table(params)
    assert.is_table(params.textDocument)
    assert.is_table(params.position)
    assert.equals(9, params.position.line)      -- 0-based
    assert.equals(5, params.position.character) -- 0-based
  end)
end)

describe('hoverfloat.utils.buffer', function()
  local buffer

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    buffer = require('hoverfloat.utils.buffer')
  end)

  it('should validate buffer correctly', function()
    assert.is_true(buffer.is_valid_buffer(1))
  end)

  it('should check LSP clients', function()
    assert.is_true(buffer.has_lsp_clients(1))
    local clients = buffer.get_lsp_clients(1)
    assert.equals(1, #clients)
    assert.equals('test_lsp', clients[1].name)
  end)

  it('should determine if buffer is suitable for LSP', function()
    assert.is_true(buffer.is_suitable_for_lsp(1))
  end)

  it('should check filetype exclusion', function()
    vim.api.nvim_get_option_value = function(opt, opts)
      if opt == 'filetype' then return 'help' end
      return ''
    end
    assert.is_true(buffer.should_exclude_filetype(1))
  end)
end)

describe('hoverfloat.utils.symbols', function()
  local symbols

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    symbols = require('hoverfloat.utils.symbols')
  end)

  it('should get word under cursor', function()
    local word = symbols.get_word_under_cursor()
    assert.equals('test_symbol', word)
  end)

  it('should get symbol at cursor', function()
    local symbol_info = symbols.get_symbol_at_cursor()
    assert.is_table(symbol_info)
    assert.equals('test_symbol', symbol_info.symbol)
    assert.is_number(symbol_info.line)
    assert.is_number(symbol_info.col)
  end)

  it('should get symbol kind name', function()
    assert.equals('Function', symbols.get_symbol_kind_name(12))
    assert.equals('Unknown', symbols.get_symbol_kind_name(999))
  end)

  it('should validate symbol structure', function()
    local valid_symbol = {
      name = 'test',
      kind = 12,
      start_line = 1,
      end_line = 5,
      start_col = 1,
      end_col = 10
    }
    local valid, error_msg = symbols.validate_symbol(valid_symbol)
    assert.is_true(valid)
    assert.is_nil(error_msg)

    local invalid_symbol = { name = 'test' }
    local valid2, error_msg2 = symbols.validate_symbol(invalid_symbol)
    assert.is_false(valid2)
    assert.is_string(error_msg2)
  end)
end)

describe('hoverfloat.prefetch.cache', function()
  local cache

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    cache = require('hoverfloat.prefetch.cache')
  end)

  it('should store and retrieve cache data', function()
    local test_data = create_mock_lsp_data()

    cache.store(1, 10, 'test_symbol', test_data)
    local retrieved = cache.get(1, 10, 'test_symbol')

    assert.is_table(retrieved)
    assert.same(test_data.hover, retrieved.hover)
    assert.same(test_data.definition, retrieved.definition)
  end)

  it('should return nil for non-existent cache entries', function()
    local result = cache.get(999, 999, 'nonexistent')
    assert.is_nil(result)
  end)

  it('should clear cache correctly', function()
    local test_data = create_mock_lsp_data()
    cache.store(1, 10, 'test_symbol', test_data)

    cache.clear_buffer(1)
    local result = cache.get(1, 10, 'test_symbol')
    assert.is_nil(result)
  end)

  it('should get cache statistics', function()
    local stats = cache.get_stats()
    assert.is_table(stats)
    assert.is_number(stats.total_symbols_cached)
    assert.is_number(stats.buffers_cached)
  end)
end)

describe('hoverfloat.communication.message_handler', function()
  local message_handler

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    message_handler = require('hoverfloat.communication.message_handler')
  end)

  it('should create context update message', function()
    local context_data = create_mock_lsp_data()
    local message = message_handler.create_context_update(context_data)

    assert.is_string(message)
    assert.matches('context_update', message)
    assert.matches('\n$', message) -- Should end with newline
  end)

  it('should create error message', function()
    local error_msg = message_handler.create_error_message('Test error', 'Details')

    assert.is_string(error_msg)
    assert.matches('error', error_msg)
    assert.matches('Test error', error_msg)
  end)

  it('should validate messages', function()
    local valid_json = '{"type":"context_update","timestamp":1234567890,"data":{}}'
    local valid, message = message_handler.validate_message(valid_json)

    assert.is_true(valid)
    assert.is_table(message)
    assert.equals('context_update', message.type)

    local invalid_json = 'invalid json'
    local valid2, error2 = message_handler.validate_message(invalid_json)
    assert.is_false(valid2)
    assert.is_string(error2)
  end)

  it('should parse incoming data', function()
    local test_data = '{"type":"ping","timestamp":1234567890,"data":{}}\n'
    local messages, remaining = message_handler.parse_incoming_data(test_data)

    assert.equals(1, #messages)
    assert.equals('ping', messages[1].type)
    assert.equals('', remaining)
  end)
end)

describe('hoverfloat.core.lsp_service', function()
  local lsp_service

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    lsp_service = require('hoverfloat.core.lsp_service')
  end)

  it('should get hover information', function()
    local hover_result = nil
    local error_result = nil

    lsp_service.get_hover(1, 10, 5, function(result, err)
      hover_result = result
      error_result = err
    end)

    assert.is_table(hover_result)
    assert.is_nil(error_result)
    assert.equals('test hover content', hover_result[1])
  end)

  it('should get definition information', function()
    local def_result = nil
    local error_result = nil

    lsp_service.get_definition(1, 10, 5, function(result, err)
      def_result = result
      error_result = err
    end)

    assert.is_table(def_result)
    assert.is_nil(error_result)
    assert.equals('/test/def.lua', def_result.file)
    assert.equals(20, def_result.line)
  end)

  it('should get references information', function()
    local refs_result = nil
    local error_result = nil

    lsp_service.get_references(1, 10, 5, 8, function(result, err)
      refs_result = result
      error_result = err
    end)

    assert.is_table(refs_result)
    assert.is_nil(error_result)
    assert.equals(2, refs_result.count)
    assert.equals(2, #refs_result.locations)
  end)

  it('should gather all context', function()
    local context_result = nil

    lsp_service.gather_all_context(1, 10, 5, nil, function(result)
      context_result = result
    end)

    assert.is_table(context_result)
    assert.equals('/test/file.lua', context_result.file)
    assert.equals(10, context_result.line)
    assert.equals(5, context_result.col)
    assert.is_table(context_result.hover)
    assert.is_table(context_result.definition)
  end)
end)

describe('hoverfloat.core.performance', function()
  local performance

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    performance = require('hoverfloat.core.performance')
  end)

  it('should track request timing', function()
    local start_time = performance.start_request()
    assert.is_number(start_time)

    local response_time = performance.complete_request(start_time, false, false)
    assert.is_number(response_time)
    assert.is_true(response_time >= 0)
  end)

  it('should record cache hits', function()
    performance.record_cache_hit()
    local stats = performance.get_stats()
    assert.is_true(stats.cache_hits > 0)
  end)

  it('should get performance statistics', function()
    local stats = performance.get_stats()
    assert.is_table(stats)
    assert.is_number(stats.total_requests)
    assert.is_number(stats.cache_hits)
    assert.is_number(stats.average_response_time)
  end)

  it('should analyze performance', function()
    local analysis = performance.analyze_performance()
    assert.is_table(analysis)
  end)
end)

describe('MessageQueue', function()
  local MessageQueue

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    local message_handler = require('hoverfloat.communication.message_handler')
    MessageQueue = message_handler.MessageQueue
  end)

  it('should create queue with max size', function()
    local queue = MessageQueue.new(5)
    assert.is_table(queue)
    assert.equals(5, queue.max_size)
  end)

  it('should add and retrieve messages', function()
    local queue = MessageQueue.new(5)
    queue:add('test message')

    assert.equals(1, queue:size())

    local messages = queue:get_all()
    assert.equals(1, #messages)
    assert.equals('test message', messages[1])
    assert.equals(0, queue:size())
  end)

  it('should enforce size limit', function()
    local queue = MessageQueue.new(2)
    queue:add('msg1')
    queue:add('msg2')
    queue:add('msg3') -- Should evict msg1

    assert.equals(2, queue:size())
  end)
end)

describe('RateLimiter', function()
  local RateLimiter

  before_each(function()
    setup_test_environment()
    setup_comprehensive_vim_mock()
    local message_handler = require('hoverfloat.communication.message_handler')
    RateLimiter = message_handler.RateLimiter
  end)

  it('should create rate limiter', function()
    local limiter = RateLimiter.new(5, 1000)
    assert.is_table(limiter)
    assert.equals(5, limiter.max_per_second)
    assert.equals(1000, limiter.window_ms)
  end)

  it('should allow requests within limit', function()
    local limiter = RateLimiter.new(5, 1000)

    for i = 1, 5 do
      assert.is_true(limiter:check_limit())
    end
  end)

  it('should deny requests over limit', function()
    local limiter = RateLimiter.new(2, 1000)

    assert.is_true(limiter:check_limit())
    assert.is_true(limiter:check_limit())
    assert.is_false(limiter:check_limit()) -- Should be denied
  end)
end)
