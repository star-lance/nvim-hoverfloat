-- tests/real_integration_tests.lua - Integration tests with real LSP and no mocks

local test_env = require('tests.test_env')

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

-- Real assertions for actual data
local function assert_has_hover_data(data)
	if not data or not data.hover or #data.hover == 0 then
		error("Expected hover data but got none")
	end
end

local function assert_has_definition(data)
	if not data or not data.definition then
		error("Expected definition but got none")
	end
	if not data.definition.file or not data.definition.line then
		error("Definition missing file or line information")
	end
end

local function assert_has_references(data)
	if not data or not data.references or #data.references == 0 then
		error("Expected references but got none")
	end
end

describe('Real LSP Integration Tests', function()
	local env

	-- Setup real test environment
	env = test_env.setup()

	it('should get real hover information from Lua LSP', function()
		if not env.lsp_available.lua then
			print("    ⏭️  Skipping: lua_ls not available")
			return
		end

		-- Open test Lua file and position cursor on a function
		local bufnr = test_env.open_test_file(env.files.lua_file, { 8, 20 }) -- On 'add_numbers'

		-- Get real LSP data using our plugin's LSP service
		local lsp_service = require('hoverfloat.core.lsp_service')
		local context_received = false
		local actual_context = nil

		lsp_service.gather_all_context(bufnr, 8, 20, nil, function(context_data)
			actual_context = context_data
			context_received = true
		end)

		-- Wait for real LSP response
		local timeout = 5000
		local start_time = vim.uv.now()
		while not context_received and (vim.uv.now() - start_time) < timeout do
			vim.wait(100)
		end

		if not context_received then
			error("LSP did not respond within timeout")
		end

		-- Verify we got real data from LSP
		assert_has_hover_data(actual_context)
		print("    📋 Received hover: " .. table.concat(actual_context.hover, " | "))

		-- Check that hover contains function information
		local hover_text = table.concat(actual_context.hover, "\n")
		if not hover_text:match("add_numbers") then
			error("Hover should mention the function name")
		end
	end)

	it('should get real definition data from Lua LSP', function()
		if not env.lsp_available.lua then
			print("    ⏭️  Skipping: lua_ls not available")
			return
		end

		local bufnr = test_env.open_test_file(env.files.lua_file, { 21, 30 }) -- On 'add_numbers' call

		local lsp_service = require('hoverfloat.core.lsp_service')
		local def_received = false
		local actual_definition = nil

		lsp_service.get_definition(bufnr, 21, 30, function(def_data)
			actual_definition = def_data
			def_received = true
		end)

		-- Wait for real LSP response
		local timeout = 5000
		local start_time = vim.uv.now()
		while not def_received and (vim.uv.now() - start_time) < timeout do
			vim.wait(100)
		end

		if not def_received then
			error("LSP definition request did not respond within timeout")
		end

		if actual_definition then
			print("    📍 Definition found at: " .. actual_definition.file .. ":" .. actual_definition.line)

			-- Verify definition points to the actual function
			if actual_definition.line < 7 or actual_definition.line > 12 then
				error("Definition should point to the function declaration area")
			end
		else
			print("    ⚠️  No definition found (may be expected for some symbols)")
		end
	end)

	it('should cache real LSP data correctly', function()
		if not env.lsp_available.lua then
			print("    ⏭️  Skipping: lua_ls not available")
			return
		end

		local cache = require('hoverfloat.prefetch.cache')
		cache.clear_all()

		local bufnr = test_env.open_test_file(env.files.lua_file, { 8, 20 })

		-- First request - should hit LSP
		local lsp_service = require('hoverfloat.core.lsp_service')
		local first_response = nil
		local first_received = false

		lsp_service.gather_all_context(bufnr, 8, 20, nil, function(context_data)
			if context_data and context_data.hover then
				-- Store in cache
				cache.store(bufnr, 8, 'add_numbers', context_data)
				first_response = context_data
			end
			first_received = true
		end)

		-- Wait for response
		local start_time = vim.uv.now()
		while not first_received and (vim.uv.now() - start_time) < 5000 do
			vim.wait(100)
		end

		if not first_response then
			error("Failed to get initial LSP response")
		end

		-- Second request - should hit cache
		local cached_data = cache.get(bufnr, 8, 'add_numbers')
		if not cached_data then
			error("Data should be cached after first request")
		end

		-- Verify cached data matches original
		if not cached_data.hover or #cached_data.hover == 0 then
			error("Cached data should contain hover information")
		end

		print("    💾 Cache working: " .. #cached_data.hover .. " hover lines cached")
	end)

	it('should track real cursor movement', function()
		if not env.lsp_available.lua then
			print("    ⏭️  Skipping: lua_ls not available")
			return
		end

		local cursor_tracker = require('hoverfloat.core.cursor_tracker')
		local bufnr = test_env.open_test_file(env.files.lua_file, { 8, 20 })

		cursor_tracker.enable()
		cursor_tracker.clear_position_cache()

		-- Move cursor to different positions and verify tracking
		local test_positions = {
			{ 8,  20 }, -- add_numbers function
			{ 26, 15 }, -- new_calculator function
			{ 45, 10 }, -- calc:add method
			{ 8,  20 }, -- back to add_numbers (should use cache)
		}

		for i, pos in ipairs(test_positions) do
			vim.api.nvim_win_set_cursor(0, pos)

			-- Force update and wait a bit
			cursor_tracker.force_update()
			vim.wait(200)

			print("    🎯 Position " .. i .. ": line " .. pos[1] .. ", col " .. pos[2])
		end

		local stats = cursor_tracker.get_stats()
		if not stats.tracking_enabled then
			error("Cursor tracking should be enabled")
		end

		print("    📊 Tracking stats: " .. vim.inspect(stats))
		cursor_tracker.disable()
	end)

	it('should handle real socket communication', function()
		local socket_client = require('hoverfloat.communication.socket_client')

		-- Test socket setup with real plugin
		socket_client.setup()

		-- Create real context data from actual cursor position
		local bufnr = test_env.open_test_file(env.files.lua_file, { 8, 20 })
		local position = require('hoverfloat.core.position')
		local context = position.get_current_context()

		-- Add some test data
		context.hover = { "Test function documentation" }
		context.definition = { file = env.files.lua_file, line = 8, col = 9 }

		print("    📡 Testing socket with context: " .. context.file .. ":" .. context.line)

		-- Test sending data (will queue if not connected)
		local send_success = socket_client.send_context_update(context)
		print("    📤 Send result: " .. tostring(send_success))

		local status = socket_client.get_status()
		print("    🔌 Socket status: connected=" .. tostring(status.connected))
	end)

	it('should handle real performance metrics', function()
		local performance = require('hoverfloat.core.performance')
		performance.reset_stats()

		if env.lsp_available.lua then
			local bufnr = test_env.open_test_file(env.files.lua_file, { 8, 20 })
			local lsp_service = require('hoverfloat.core.lsp_service')

			-- Make several real LSP requests to generate metrics
			local requests_completed = 0
			local target_requests = 3

			for i = 1, target_requests do
				local start_time = performance.start_request()

				lsp_service.get_hover(bufnr, 8 + i, 20, function(hover_data)
					local response_time = performance.complete_request(start_time, false,
						hover_data == nil)
					print("    ⚡ Request " .. i .. " completed in " .. response_time .. "ms")
					requests_completed = requests_completed + 1
				end)
			end

			-- Wait for all requests to complete
			local timeout = 10000
			local start_wait = vim.uv.now()
			while requests_completed < target_requests and (vim.uv.now() - start_wait) < timeout do
				vim.wait(100)
			end

			local stats = performance.get_stats()
			print("    📈 Performance stats:")
			print("      Total requests: " .. stats.total_requests)
			print("      Average response time: " ..
			string.format("%.2f", stats.average_response_time) .. "ms")
			print("      LSP requests: " .. stats.lsp_requests)

			if stats.total_requests == 0 then
				error("Performance tracking should record requests")
			end
		else
			print("    ⏭️  Skipping performance test: no LSP available")
		end
	end)

	-- Go LSP test removed for simplicity

	it('should handle edge cases with real files', function()
		if not env.lsp_available.lua then
			print("    ⏭️  Skipping: lua_ls not available")
			return
		end

		local bufnr = test_env.open_test_file(env.files.lua_file, { 1, 1 }) -- Beginning of file

		-- Test empty line
		vim.api.nvim_win_set_cursor(0, { 1, 1 })
		local symbols = require('hoverfloat.utils.symbols')
		local word = symbols.get_word_under_cursor()
		print("    🔤 Word at (1,1): '" .. word .. "'")

		-- Test end of file
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		vim.api.nvim_win_set_cursor(0, { line_count, 0 })

		local position = require('hoverfloat.core.position')
		local context = position.get_current_context()
		if not context.file or context.file == '' then
			error("Should have valid file path even at EOF")
		end

		print("    📄 Context at EOF: " .. context.file .. ":" .. context.line)
	end)

	-- Cleanup after all tests
	test_env.cleanup()
	print("🧹 Test environment cleaned up")
end)
