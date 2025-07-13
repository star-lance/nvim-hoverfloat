-- tests/test_lsp_setup.lua - Unified LSP setup for testing
-- Consolidates all LSP configuration and setup logic

local M = {}

-- Simple logging functions
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

-- LSP client tracking for cleanup
local lsp_clients_started = {}

-- Auto-install LSP servers for testing (used by isolated test environment)
function M.ensure_lsp_server(repo, name, build_cmd)
	local plugin_path = vim.env.XDG_DATA_HOME .. '/plugins/' .. name
	
	if not vim.loop.fs_stat(plugin_path) then
		print_info("Installing " .. name .. "...")
		vim.fn.mkdir(vim.fn.fnamemodify(plugin_path, ':h'), 'p')
		
		local result = vim.fn.system({
			'git', 'clone', '--depth=1', 
			'https://github.com/' .. repo .. '.git',
			plugin_path
		})
		
		if vim.v.shell_error ~= 0 then
			error("Failed to clone " .. repo .. ": " .. result)
		end
		
		-- Run build command if provided
		if build_cmd then
			print_info("Building " .. name .. "...")
			local build_result = vim.fn.system('cd ' .. plugin_path .. ' && ' .. build_cmd)
			if vim.v.shell_error ~= 0 then
				error("Failed to build " .. name .. ": " .. build_result)
			end
		end
		
		print_success(name .. " installed")
	else
		print_success(name .. " already available")
	end
	
	-- Add to runtime path
	vim.opt.rtp:prepend(plugin_path)
	return plugin_path
end

-- Setup Lua LSP with comprehensive error handling
function M.setup_lua_lsp(config)
	config = config or {}
	
	-- Check if lua-language-server is available
	local lua_ls_cmd = config.lua_ls_path and (config.lua_ls_path .. '/bin/lua-language-server') or 'lua-language-server'
	
	if config.lua_ls_path then
		-- Use provided path (for isolated testing)
		print_info("Using lua-language-server from: " .. config.lua_ls_path)
	elseif vim.fn.executable('lua-language-server') == 0 then
		print_warning('lua-language-server not found, skipping Lua LSP tests')
		return false
	end

	-- Try to require lspconfig
	local ok, lspconfig = pcall(require, 'lspconfig')
	if not ok then
		print_warning('lspconfig not available, cannot setup Lua LSP')
		return false
	end

	-- Setup lua_ls with error handling
	local setup_ok, setup_err = pcall(function()
		lspconfig.lua_ls.setup({
			cmd = config.lua_ls_path and { lua_ls_cmd } or nil,
			settings = {
				Lua = {
					runtime = { version = 'LuaJIT' },
					diagnostics = {
						globals = { 'vim' },
						disable = { 'lowercase-global', 'undefined-global' }
					},
					workspace = {
						library = vim.api.nvim_get_runtime_file("", true),
						checkThirdParty = false,
					},
					telemetry = { enable = false },
					completion = { enable = true },
					hover = { enable = true },
					signatureHelp = { enable = true },
				},
			},
			root_dir = config.root_dir or function() return vim.fn.getcwd() end,
			single_file_support = true,
			on_attach = function(client, bufnr)
				table.insert(lsp_clients_started, client)
				print_info('Lua LSP attached to buffer ' .. bufnr)
				if config.on_attach then
					config.on_attach(client, bufnr)
				end
			end,
		})
	end)

	if not setup_ok then
		print_error('Failed to setup lua_ls: ' .. tostring(setup_err))
		return false
	end

	print_success('Lua LSP configured successfully')
	return true
end

-- Wait for LSP to attach and be ready
function M.wait_for_lsp(bufnr, timeout_ms)
	timeout_ms = timeout_ms or 5000
	local start_time = vim.uv.now()

	print_info('Waiting for LSP to attach to buffer ' .. bufnr .. '...')

	while vim.uv.now() - start_time < timeout_ms do
		local clients = vim.lsp.get_clients({ bufnr = bufnr })
		if #clients > 0 then
			print_success('LSP attached (' .. #clients .. ' clients)')
			-- Wait a bit more for LSP to be fully ready
			vim.wait(500)
			return true
		end
		vim.wait(100)
	end

	print_warning('LSP did not attach within timeout (' .. timeout_ms .. 'ms)')
	return false
end

-- Check LSP availability
function M.check_lsp_availability()
	local availability = {
		lua = vim.fn.executable('lua-language-server') == 1,
		lspconfig = pcall(require, 'lspconfig')
	}
	
	if availability.lua then
		print_success("lua-language-server found")
	else
		print_warning("lua-language-server not found")
	end
	
	if availability.lspconfig then
		print_success("nvim-lspconfig available")
	else
		print_warning("nvim-lspconfig not available")
	end
	
	return availability
end

-- Setup full LSP environment for testing
function M.setup_test_lsp_environment(config)
	config = config or {}
	
	print_info('Setting up LSP test environment...')
	
	local availability = M.check_lsp_availability()
	local lsp_available = {}
	
	-- Setup Lua LSP
	if availability.lua and availability.lspconfig then
		lsp_available.lua = M.setup_lua_lsp(config)
	else
		lsp_available.lua = false
		print_warning('Lua LSP not available for testing')
	end
	
	-- Future: Add other LSP servers here
	lsp_available.go = false -- Simplified for now
	
	print_success('LSP environment setup complete')
	return lsp_available
end

-- Cleanup LSP clients
function M.cleanup_lsp()
	print_info('Cleaning up LSP clients...')
	
	for i, client in ipairs(lsp_clients_started) do
		local stop_ok, stop_err = pcall(function()
			client.stop()
		end)
		if not stop_ok then
			print_warning('Failed to stop LSP client ' .. i .. ': ' .. tostring(stop_err))
		end
	end
	
	if #lsp_clients_started > 0 then
		print_success('Stopped ' .. #lsp_clients_started .. ' LSP clients')
	end
	
	lsp_clients_started = {}
end

-- Get LSP clients status
function M.get_lsp_status()
	return {
		clients_started = #lsp_clients_started,
		lua_available = vim.fn.executable('lua-language-server') == 1,
		lspconfig_available = pcall(require, 'lspconfig')
	}
end

return M