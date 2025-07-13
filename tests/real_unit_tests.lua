-- tests/real_unit_tests.lua - Unit tests with real Neovim API but no LSP dependencies

-- Load unified test framework
local test_framework = require('tests.test_framework')
local describe = test_framework.describe
local it = test_framework.it
local assert_ok = test_framework.assert_ok
local assert_type = test_framework.assert_type

-- Create a temporary test file using framework utility
local temp_file = test_framework.create_temp_test_file()

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
		assert_ok(message:find('context_update'), "Message should contain context_update")
		assert_ok(message:find('\n'), "Message should end with newline")

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

		-- Test 1: LSP request flow
		local start_time1 = performance.start_request()
		local line_count = vim.api.nvim_buf_line_count(0)
		local response_time1 = performance.complete_request(start_time1, false, false) -- LSP request
		assert_type('number', response_time1)
		assert_ok(response_time1 >= 0, "Response time should be non-negative")

		-- Test 2: Cache hit flow  
		local start_time2 = performance.start_request()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local response_time2 = performance.complete_request(start_time2, true, false) -- Cache hit

		-- Test 3: Manual cache hit recording
		performance.record_cache_hit()

		local stats = performance.get_stats()
		
		-- We made 3 total requests: start_request() called 2 times + record_cache_hit() called 1 time
		assert_ok(stats.total_requests == 3, "Should have 3 total requests")
		assert_ok(stats.cache_hits == 2, "Should have 2 cache hits")
		assert_ok(stats.lsp_requests == 1, "Should have 1 LSP request")

		print("    ⚡ LSP operation: " .. response_time1 .. "ms")
		print("    💾 Cache operation: " .. response_time2 .. "ms")
		print("    📊 Performance stats: requests=" .. stats.total_requests .. 
		      ", cache_hits=" .. stats.cache_hits .. ", lsp=" .. stats.lsp_requests)
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

	it('should handle debounce delay configuration', function()
		local cursor_tracker = require('hoverfloat.core.cursor_tracker')
		
		-- Test default debounce delay
		local stats = cursor_tracker.get_stats()
		assert_ok(stats.debounce_delay == 20, "Default debounce should be 20ms")
		
		-- Test setting custom debounce delay
		cursor_tracker.set_debounce_delay(50)
		stats = cursor_tracker.get_stats()
		assert_ok(stats.debounce_delay == 50, "Custom debounce should be 50ms")
		
		-- Reset to default
		cursor_tracker.set_debounce_delay(20)
		stats = cursor_tracker.get_stats()
		assert_ok(stats.debounce_delay == 20, "Should reset to 20ms")
		
		print("    ⏱️  Debounce delay configuration working")
	end)

	it('should handle position deduplication logic', function()
		local cursor_tracker = require('hoverfloat.core.cursor_tracker')
		local position = require('hoverfloat.core.position')
		
		-- Clear any existing position cache
		cursor_tracker.clear_position_cache()
		
		-- Get current position identifier
		local pos_id = position.get_position_identifier()
		assert_type('string', pos_id)
		assert_ok(#pos_id > 0, "Position identifier should not be empty")
		
		-- Verify position identifier format (file:line:col:word)
		assert_ok(pos_id:find(":"), "Position identifier should contain colons")
		
		print("    🔍 Position identifier: " .. pos_id)
		print("    ✅ Position deduplication logic working")
	end)

	it('should track autocmd registration', function()
		local cursor_tracker = require('hoverfloat.core.cursor_tracker')
		
		-- Setup tracking (registers autocmds)
		cursor_tracker.setup_tracking()
		
		-- Check if autocmds are registered by looking for the group
		local autocmds = vim.api.nvim_get_autocmds({ group = "HoverFloatCursorTracker" })
		assert_ok(#autocmds > 0, "Should have registered autocmds")
		
		-- Check for specific events
		local events = {}
		for _, autocmd in ipairs(autocmds) do
			events[autocmd.event] = true
		end
		
		assert_ok(events["CursorMoved"], "Should register CursorMoved event")
		assert_ok(events["CursorMovedI"], "Should register CursorMovedI event")
		assert_ok(events["BufEnter"], "Should register BufEnter event")
		assert_ok(events["LspAttach"], "Should register LspAttach event")
		
		print("    📋 Registered " .. #autocmds .. " autocmds")
		print("    🎯 Autocmd registration working")
	end)

	it('should handle tracking conditions', function()
		local cursor_tracker = require('hoverfloat.core.cursor_tracker')
		local buffer = require('hoverfloat.utils.buffer')
		local socket_client = require('hoverfloat.communication.socket_client')
		
		-- Test tracking enabled state
		cursor_tracker.enable()
		local stats = cursor_tracker.get_stats()
		assert_ok(stats.tracking_enabled, "Tracking should be enabled")
		
		-- Test buffer suitability check
		local bufnr = vim.api.nvim_get_current_buf()
		local is_suitable = buffer.is_suitable_for_lsp(bufnr)
		assert_type('boolean', is_suitable)
		
		-- Test socket connection state
		local socket_status = socket_client.get_status()
		assert_type('table', socket_status)
		assert_type('boolean', socket_status.connected)
		
		print("    📡 Socket connected: " .. tostring(socket_status.connected))
		print("    📄 Buffer suitable: " .. tostring(is_suitable))
		print("    ✅ Tracking conditions evaluation working")
	end)

	it('should handle force update functionality', function()
		local cursor_tracker = require('hoverfloat.core.cursor_tracker')
		
		-- Enable tracking for force update test
		cursor_tracker.enable()
		
		-- Test force update (should not throw errors)
		local force_ok = pcall(cursor_tracker.force_update)
		assert_ok(force_ok, "Force update should not throw errors")
		
		-- Check that any pending updates are cancelled
		local stats = cursor_tracker.get_stats()
		assert_ok(not stats.has_pending_update, "Should not have pending updates after force")
		
		print("    ⚡ Force update working")
	end)

	it('should handle cleanup properly', function()
		local cursor_tracker = require('hoverfloat.core.cursor_tracker')
		
		-- Enable tracking and set some state
		cursor_tracker.enable()
		cursor_tracker.set_debounce_delay(100)
		
		-- Perform cleanup
		cursor_tracker.cleanup()
		
		-- Verify cleanup effects
		local stats = cursor_tracker.get_stats()
		assert_ok(not stats.tracking_enabled, "Tracking should be disabled after cleanup")
		assert_ok(not stats.has_pending_update, "Should not have pending updates after cleanup")
		
		print("    🧹 Cleanup working properly")
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
	test_framework.cleanup_temp_file(temp_file)
	print("🧹 Temporary test file cleaned up")
end)

print("✅ Real unit tests completed successfully!")
