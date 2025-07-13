-- tests/test_env.lua - Real Neovim test environment with actual LSP
-- Now uses unified LSP setup module

local lsp_setup = require('tests.test_lsp_setup')

-- Simple logging functions (kept for backward compatibility)
local function print_info(message)
	print('[INFO] ' .. message)
end

local function print_success(message)
	print('[SUCCESS] ' .. message)
end

local function print_warning(message)
	print('[WARNING] ' .. message)
end

local function print_error(message)
	print('[ERROR] ' .. message)
end

-- Minimal Neovim configuration for testing with real LSP
local M = {}

-- Test environment paths
local test_dir = vim.fn.expand('<sfile>:h')
local plugin_dir = vim.fn.fnamemodify(test_dir, ':h')
local temp_dir = '/tmp/hoverfloat_test_' .. os.time() .. '_' .. math.random(1000, 9999)

-- State tracking for cleanup
local state = {
	temp_dir_created = false,
	lsp_clients_started = {},
	test_files_created = {},
	plugin_initialized = false,
}

-- Create temp directory for test files with error handling
local function create_temp_dir()
	local ok, err = pcall(vim.fn.mkdir, temp_dir, 'p')
	if not ok then
		print_error('Failed to create temp directory: ' .. tostring(err))
		return false
	end

	-- Verify directory was created
	if vim.fn.isdirectory(temp_dir) == 0 then
		print_error('Temp directory was not created: ' .. temp_dir)
		return false
	end

	state.temp_dir_created = true
	print_info('Created temp directory: ' .. temp_dir)
	return true
end

-- Basic Neovim settings for testing
local function setup_neovim_settings()
	vim.opt.swapfile = false
	vim.opt.backup = false
	vim.opt.undofile = false
	vim.opt.compatible = false
	vim.opt.hidden = true

	-- Add our plugin to runtime path
	vim.opt.rtp:prepend(plugin_dir)
	print_info('Added plugin to runtime path: ' .. plugin_dir)
end

-- Use unified LSP setup (simplified)
local function setup_lua_lsp()
	return lsp_setup.setup_lua_lsp({ 
		root_dir = function() return temp_dir end,
		on_attach = function(client, bufnr)
			table.insert(state.lsp_clients_started, client)
		end
	})
end

-- Go LSP setup removed for simplicity
local function setup_go_lsp()
	print_info('Go LSP testing disabled for simplicity')
	return false
end

-- Create realistic test files with actual code
function M.create_test_files()
	if not state.temp_dir_created then
		print_error('Cannot create test files: temp directory not created')
		return nil
	end

	-- Lua test file with actual LSP-analyzable code
	local lua_content = [[
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

--- Configuration table
TestModule.config = {
    timeout = 5000,
    max_retries = 3,
    debug = false
}

return TestModule
]]

	local lua_file = temp_dir .. '/test_module.lua'
	local file, err = io.open(lua_file, 'w')
	if not file then
		print_error('Failed to create Lua test file: ' .. tostring(err))
		return nil
	end

	file:write(lua_content)
	file:close()
	table.insert(state.test_files_created, lua_file)
	print_success('Created Lua test file: ' .. lua_file)

	-- Go test file creation removed for simplicity
	local go_file = nil

	return {
		lua_file = lua_file,
		temp_dir = temp_dir
	}
end

-- Setup the test environment with comprehensive error handling
function M.setup()
	print_info('Setting up real Neovim test environment...')

	-- Create temp directory first
	if not create_temp_dir() then
		return nil
	end

	-- Setup Neovim settings
	setup_neovim_settings()

	-- Create test files
	local files = M.create_test_files()
	if not files then
		print_error('Failed to create test files')
		M.cleanup()
		return nil
	end

	-- Try to setup LSP servers
	local lsp_available = {
		lua = setup_lua_lsp(),
		go = setup_go_lsp()
	}

	-- Initialize our plugin with error handling
	local plugin_ok, plugin_err = pcall(function()
		local hoverfloat = require('hoverfloat')
		hoverfloat.setup()
		state.plugin_initialized = true
	end)

	if not plugin_ok then
		print_error('Failed to initialize hoverfloat plugin: ' .. tostring(plugin_err))
		M.cleanup()
		return nil
	end

	print_success('Plugin initialized successfully')

	local env = {
		files = files,
		lsp_available = lsp_available,
		temp_dir = temp_dir
	}

	print_success('Test environment setup complete')
	return env
end

-- Use unified LSP wait function
function M.wait_for_lsp(bufnr, timeout_ms)
	return lsp_setup.wait_for_lsp(bufnr, timeout_ms)
end

-- Open a test file and wait for LSP with better error handling
function M.open_test_file(filepath, position)
	if not filepath or vim.fn.filereadable(filepath) == 0 then
		error('Test file does not exist or is not readable: ' .. tostring(filepath))
	end

	print_info('Opening test file: ' .. filepath)

	local edit_ok, edit_err = pcall(vim.cmd, 'edit ' .. filepath)
	if not edit_ok then
		error('Failed to open file: ' .. tostring(edit_err))
	end

	local bufnr = vim.api.nvim_get_current_buf()
	if bufnr == 0 then
		error('Failed to get current buffer after opening file')
	end

	if position then
		local pos_ok, pos_err = pcall(vim.api.nvim_win_set_cursor, 0, position)
		if not pos_ok then
			print_warning('Failed to set cursor position: ' .. tostring(pos_err))
		else
			print_info('Set cursor to line ' .. position[1] .. ', col ' .. position[2])
		end
	end

	-- Wait for LSP to attach (not required for all tests)
	M.wait_for_lsp(bufnr)

	return bufnr
end

-- Comprehensive cleanup with error handling
function M.cleanup()
	print_info('Cleaning up test environment...')

	-- Stop plugin if initialized
	if state.plugin_initialized then
		local cleanup_ok, cleanup_err = pcall(function()
			local hoverfloat = require('hoverfloat')
			if hoverfloat.stop then
				hoverfloat.stop()
			end
		end)
		if not cleanup_ok then
			print_warning('Failed to stop plugin: ' .. tostring(cleanup_err))
		else
			print_success('Plugin stopped')
		end
	end

	-- Use unified LSP cleanup
	lsp_setup.cleanup_lsp()

	-- Remove temp files and directory
	if state.temp_dir_created then
		local delete_ok, delete_err = pcall(vim.fn.delete, temp_dir, 'rf')
		if not delete_ok then
			print_warning('Failed to remove temp directory: ' .. tostring(delete_err))
		else
			print_success('Removed temp directory: ' .. temp_dir)
		end
	end

	-- Reset state
	state = {
		temp_dir_created = false,
		lsp_clients_started = {},
		test_files_created = {},
		plugin_initialized = false,
	}

	print_success('Cleanup complete')
end

-- Get environment status for debugging
function M.get_status()
	return {
		temp_dir = temp_dir,
		temp_dir_created = state.temp_dir_created,
		lsp_clients_count = #state.lsp_clients_started,
		test_files_count = #state.test_files_created,
		plugin_initialized = state.plugin_initialized,
	}
end

return M
