-- tests/test_framework.lua - Unified test framework for nvim-hoverfloat
-- Consolidates all shared test utilities and framework code

local M = {}

-- Test framework functions
function M.describe(name, func)
	print("📝 " .. name)
	func()
end

function M.it(name, func)
	local ok, err = pcall(func)
	if ok then
		print("  ✅ " .. name)
	else
		print("  ❌ " .. name .. ": " .. tostring(err))
		error("Test failed: " .. name)
	end
end

-- Unified assertion functions
function M.assert_ok(condition, message)
	if not condition then
		error(message or "Assertion failed")
	end
end

function M.assert_type(expected_type, value, message)
	if type(value) ~= expected_type then
		local msg = message or ("Expected " .. expected_type .. " but got " .. type(value))
		error(msg)
	end
end

function M.assert_has_hover_data(data, message)
	if not data or not data.hover or #data.hover == 0 then
		error(message or "Expected hover data but got none")
	end
end

function M.assert_has_definition(data, message)
	if not data or not data.definition then
		error(message or "Expected definition but got none")
	end
	if not data.definition.file or not data.definition.line then
		error(message or "Definition missing file or line information")
	end
end

function M.assert_has_references(data, message)
	if not data or not data.references or #data.references == 0 then
		error(message or "Expected references but got none")
	end
end

-- Test file creation utilities
function M.create_temp_test_file()
	local temp_file = '/tmp/test_' .. os.time() .. '.lua'
	local test_content = [[
-- Test Lua file for LSP analysis
local TestModule = {}

local CONSTANT_VALUE = 42

--- Calculate the sum of two numbers
--- @param x number First number
--- @param y number Second number
--- @return number The sum of x and y
function TestModule.add_numbers(x, y)
    if type(x) ~= 'number' or type(y) ~= 'number' then
        error("Arguments must be numbers")
    end
    return x + y
end

--- Create a new calculator instance  
--- @return table Calculator instance
function TestModule.new_calculator()
    local calc = {
        value = 0,
        history = {}
    }

    function calc:add(num)
        self.value = self.value + num
        table.insert(self.history, {op = 'add', value = num})
        return self
    end

    function calc:multiply(num)
        self.value = self.value * num  
        table.insert(self.history, {op = 'mul', value = num})
        return self
    end

    function calc:get_result()
        return self.value
    end

    return calc
end

--- Example function call for testing definitions
local function example_usage()
    local result = TestModule.add_numbers(10, 20)
    local calc = TestModule.new_calculator()
    return calc:add(result):multiply(2):get_result()
end

--- Configuration table
TestModule.config = {
    timeout = 5000,
    max_retries = 3,
    debug = false
}

return TestModule
]]

	local file = io.open(temp_file, 'w')
	if not file then
		error('Failed to create temp test file: ' .. temp_file)
	end
	file:write(test_content)
	file:close()
	
	return temp_file
end

function M.cleanup_temp_file(filepath)
	if filepath and vim.fn.filereadable(filepath) == 1 then
		os.remove(filepath)
	end
end

-- LSP waiting utilities
function M.wait_for_lsp_response(check_fn, timeout_ms, description)
	timeout_ms = timeout_ms or 5000
	description = description or "LSP response"
	
	local start_time = vim.uv.now()
	local received = false
	local result = nil
	
	check_fn(function(data)
		result = data
		received = true
	end)
	
	while not received and (vim.uv.now() - start_time) < timeout_ms do
		vim.wait(100)
	end
	
	if not received then
		error(description .. " did not respond within timeout (" .. timeout_ms .. "ms)")
	end
	
	return result
end

-- Common test patterns
function M.test_cursor_positioning(test_positions, description)
	description = description or "cursor positioning"
	
	for i, pos in ipairs(test_positions) do
		vim.api.nvim_win_set_cursor(0, pos)
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		
		M.assert_ok(cursor_pos[1] == pos[1], "Cursor should be on line " .. pos[1])
		M.assert_ok(cursor_pos[2] == pos[2], "Cursor should be on column " .. pos[2])
		
		print("    🎯 Position " .. i .. ": line " .. cursor_pos[1] .. ", col " .. cursor_pos[2])
	end
	
	print("    ✅ " .. description .. " working")
end

function M.test_plugin_module_loading(modules, description)
	description = description or "plugin module loading"
	
	for _, module_name in ipairs(modules) do
		local ok, module = pcall(require, module_name)
		M.assert_ok(ok, "Should be able to load " .. module_name .. ": " .. tostring(module))
		M.assert_type('table', module, module_name .. " should return a table")
		print("    📦 Loaded: " .. module_name)
	end
	
	print("    ✅ " .. description .. " working")
end

-- Environment validation
function M.validate_test_environment()
	-- Check if we're in test mode
	if not _G.TEST_MODE then
		print("    ⚠️  Warning: TEST_MODE not set, may interfere with user config")
	end
	
	-- Check basic Neovim functionality
	local bufnr = vim.api.nvim_get_current_buf()
	M.assert_type('number', bufnr)
	M.assert_ok(bufnr > 0, "Should have valid buffer")
	
	-- Check plugin is loadable
	local ok, plugin = pcall(require, 'hoverfloat')
	M.assert_ok(ok, "hoverfloat plugin should be loadable: " .. tostring(plugin))
	
	print("    ✅ Test environment validated")
end

return M