-- tests/real_unit_tests.lua - Unit tests with real Neovim API but no LSP dependencies

-- Test utilities
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
		error("Test failed: " .. name)
	end
end

-- Simple assertion helpers
local function assert_ok(condition, message)
	if not condition then
		error(message or "Assertion failed")
	end
end

local function assert_type(expected_type, value)
	if type(value) ~= expected_type then
		error("Expected " .. expected_type .. " but got " .. type(value))
	end
end

-- Create a temporary test file
local temp_file = '/tmp/test_' .. os.time() .. '.lua'
local test_content = [[
local TestModule = {}

function TestModule.hello_world()
    return "Hello, World!"
end

function TestModule.add(a, b)
    return a + b
end

local function private_function()
    return "private"
end

TestModule.CONSTANT = 42

return TestModule
]]

local file = io.open(temp_file, 'w')
file:write(test_content)
file:close()

describe('Real Neovim API Tests', function()
	it('should work with real buffers', function()
		-- Open our test file
		vim.cmd('edit ' .. temp_file)
		local bufnr = vim.api.nvim_get_current_buf()

		assert_type('number', bufnr)
		assert_ok(bufnr > 0, "Buffer number should be positive")

		-- Check buffer properties
		local buf_name = vim.api.nvim_buf_get_name(bufnr)
		assert_ok(buf_name:find(temp_file, 1, true), "Buffer name should contain temp file path")

		local line_count = vim.api.nvim_buf_line_count(bufnr)
		assert_ok(line_count > 10, "Should have multiple lines")

		print("    📄 Buffer " .. bufnr .. " has " .. line_count .. " lines")
	end)

	it('should work with real cursor positioning', function()
		-- Set cursor to a specific position
		vim.api.nvim_win_set_cursor(0, { 3, 10 }) -- Line 3, column 10
		local cursor_pos = vim.api.nvim_win_get_cursor(0)

		assert_ok(cursor_pos[1] == 3, "Cursor should be on line 3")
		assert_ok(cursor_pos[2] == 10, "Cursor should be on column 10")

		print("    🎯 Cursor at line " .. cursor_pos[1] .. ", col " .. cursor_pos[2])
	end)

	it('should handle real file operations', function()
		local position = require('hoverfloat.core.position')

		-- Test getting current context
		local context = position.get_current_context()
		assert_type('table', context)
		assert_type('string', context.file)
		assert_type('number', context.line)
		assert_type('number', context.col)
		assert_type('number', context.timestamp)

		print("    📍 Context: " .. context.file .. ":" .. context.line .. ":" .. context.col)

		-- Test position identifier
		local pos_id = position.get_position_identifier()
		assert_type('string', pos_id)
		assert_ok(pos_id:find(temp_file, 1, true), "Position ID should contain temp file path")

		print("    🔍 Position ID: " .. pos_id)
	end)

	it('should extract symbols from real buffer content', function()
		-- Position cursor on 'hello_world' function
		vim.api.nvim_win_set_cursor(0, { 3, 20 })

		local symbols = require('hoverfloat.utils.symbols')
		local word = symbols.get_word_under_cursor()

		assert_type('string', word)
		print("    🔤 Word under cursor: '" .. word .. "'")

		-- Test getting symbol info
		local symbol_info = symbols.get_symbol_info_at_cursor()
		assert_type('table', symbol_info)
		assert_type('string', symbol_info.word)
		assert_type('string', symbol_info.WORD)
		assert_type('number', symbol_info.line)
		assert_type('number', symbol_info.col)

		print("    📊 Symbol info: " .. vim.inspect(symbol_info))
	end)

	it('should validate buffer suitability', function()
		local buffer = require('hoverfloat.utils.buffer')
		local bufnr = vim.api.nvim_get_current_buf()

		-- Test buffer validation
		local is_valid = buffer.is_valid_buffer(bufnr)
		assert_ok(is_valid, "Buffer should be valid")

		-- Test filetype exclusion
		local should_exclude = buffer.should_exclude_filetype(bufnr)
		assert_ok(not should_exclude, "Lua files should not be excluded")

		-- Get buffer info
		local info = buffer.get_buffer_info(bufnr)
		assert_type('table', info)
		assert_ok(info.valid, "Buffer info should show valid")
		assert_ok(info.loaded, "Buffer should be loaded")
		assert_ok(info.buftype == '', "Should be normal file")

		print("    📋 Buffer info: " .. vim.inspect(info))
	end)

	it('should handle cache operations with real data', function()
		local cache = require('hoverfloat.prefetch.cache')
		cache.clear_all()

		local bufnr = vim.api.nvim_get_current_buf()

		-- Store some test data in cache
		local test_data = {
			hover = { "Test function", "Returns a greeting" },
			definition = { file = temp_file, line = 3, col = 9 }
		}

		cache.store(bufnr, 3, 'hello_world', test_data)

		-- Retrieve from cache
		local cached = cache.get(bufnr, 3, 'hello_world')
		assert_ok(cached ~= nil, "Should have cached data")
		assert_type('table', cached.hover)
		assert_ok(#cached.hover == 2, "Should have 2 hover lines")
		assert_ok(cached.hover[1] == "Test function", "First hover line should match")

		print("    💾 Cached data: " .. #cached.hover .. " hover lines")

		-- Test cache stats
		local stats = cache.get_stats()
		assert_type('table', stats)
		assert_ok(stats.total_symbols_cached >= 1, "Should have cached symbols")

		print("    📈 Cache stats: " .. vim.inspect(stats))
	end)

	it('should create and validate messages', function()
		local msg_handler = require('hoverfloat.communication.message_handler')

		-- Create a context update message
		local context = {
			file = temp_file,
			line = 3,
			col = 20,
			timestamp = vim.uv.now(),
			hover = { "Function documentation" }
		}

		local message = msg_handler.create_context_update(context)
		assert_type('string', message)
		assert_contains('context_update', message)
		assert_contains('\n', message) -- Should end with newline

		print("    📤 Created message length: " .. #message)

		-- Test message validation
		local test_json = '{"type":"ping","timestamp":' .. vim.uv.now() .. ',"data":{}}'
		local is_valid, parsed = msg_handler.validate_message(test_json)
		assert_ok(is_valid, "Message should be valid")
		assert_type('table', parsed)
		assert_ok(parsed.type == 'ping', "Message type should be ping")

		print("    ✅ Message validation working")
	end)

	it('should track performance with real operations', function()
		local performance = require('hoverfloat.core.performance')
		performance.reset_stats()

		-- Simulate some operations
		local start_time = performance.start_request()

		-- Do some real work (file operations)
		local line_count = vim.api.nvim_buf_line_count(0)
		local cursor_pos = vim.api.nvim_win_get_cursor(0)

		local response_time = performance.complete_request(start_time, false, false)
		assert_type('number', response_time)
		assert_ok(response_time >= 0, "Response time should be non-negative")

		print("    ⚡ Operation took: " .. response_time .. "ms")

		-- Record some cache hits and LSP requests
		performance.record_cache_hit()
		performance.record_lsp_request()

		local stats = performance.get_stats()
		assert_ok(stats.total_requests == 1, "Should have 1 total request")
		assert_ok(stats.cache_hits == 1, "Should have 1 cache hit")
		assert_ok(stats.lsp_requests == 1, "Should have 1 LSP request")

		print("    📊 Performance stats: " .. vim.inspect(stats))
	end)

	it('should handle socket client state', function()
		local socket_client = require('hoverfloat.communication.socket_client')

		-- Test client setup
		socket_client.setup()

		-- Test status without connection
		local status = socket_client.get_status()
		assert_type('table', status)
		assert_type('boolean', status.connected)
		assert_type('string', status.socket_path)

		print("    🔌 Socket status: " .. vim.inspect(status))

		-- Test sending data when not connected (should queue or fail gracefully)
		local test_context = {
			file = temp_file,
			line = 3,
			col = 20,
			timestamp = vim.uv.now()
		}

		local send_result = socket_client.send_context_update(test_context)
		assert_type('boolean', send_result)

		print("    📡 Send result (not connected): " .. tostring(send_result))
	end)

	it('should handle cursor tracking state', function()
		local cursor_tracker = require('hoverfloat.core.cursor_tracker')

		-- Test enabling/disabling tracking
		cursor_tracker.enable()
		local stats = cursor_tracker.get_stats()
		assert_ok(stats.tracking_enabled, "Tracking should be enabled")

		cursor_tracker.disable()
		stats = cursor_tracker.get_stats()
		assert_ok(not stats.tracking_enabled, "Tracking should be disabled")

		print("    👁️  Cursor tracking state management working")

		-- Test position cache
		cursor_tracker.clear_position_cache()
		stats = cursor_tracker.get_stats()
		assert_ok(stats.last_sent_position == nil, "Position cache should be cleared")

		print("    🧹 Position cache cleared")
	end)

	it('should handle real line ranges and positions', function()
		local position = require('hoverfloat.core.position')

		-- Test visible lines
		local visible = position.get_visible_lines(0)
		assert_type('table', visible)
		assert_type('number', visible.top)
		assert_type('number', visible.bottom)
		assert_ok(visible.bottom >= visible.top, "Bottom should be >= top")

		print("    👀 Visible lines: " .. visible.top .. " to " .. visible.bottom)

		-- Test prefetch range
		local prefetch_range = position.get_prefetch_range(0, 0)
		if prefetch_range then
			assert_type('table', prefetch_range)
			assert_type('number', prefetch_range.start_line)
			assert_type('number', prefetch_range.end_line)

			print("    🔮 Prefetch range: " .. prefetch_range.start_line .. " to " .. prefetch_range.end_line)
		else
			print("    ⚠️  No prefetch range (window not visible)")
		end
	end)

	-- Clean up
	vim.cmd('bdelete!')
	os.remove(temp_file)
	print("🧹 Temporary test file cleaned up")
end)

print("✅ Real unit tests completed successfully!")
