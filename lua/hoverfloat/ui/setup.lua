-- lua/hoverfloat/ui/setup.lua - UI components setup (commands, keymaps, etc.)
local M = {}

local tui_manager = require('hoverfloat.process.tui_manager')
local logger = require('hoverfloat.utils.logger')

-- Setup user commands
function M.setup_commands()
  vim.api.nvim_create_user_command('ContextWindow', function(opts)
    local action = opts.args ~= '' and opts.args or 'toggle'

    if action == 'open' or action == 'start' then
      tui_manager.start()
    elseif action == 'close' or action == 'stop' then
      tui_manager.stop()
    elseif action == 'toggle' then
      tui_manager.toggle()
    elseif action == 'restart' then
      tui_manager.restart()
    elseif action == 'status' then
      -- Get status from main module
      local hoverfloat = require('hoverfloat')
      local status = hoverfloat.get_status()
      logger.plugin("info", "HoverFloat Status", status)
    else
      logger.plugin("info", 'Usage: ContextWindow [open|close|toggle|restart|status]')
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'open', 'close', 'toggle', 'restart', 'status' }
    end,
    desc = 'Manage LSP context window'
  })

  -- Additional shorter commands for convenience
  vim.api.nvim_create_user_command('ContextWindowOpen', function()
    tui_manager.start()
  end, { desc = 'Open LSP context window' })

  vim.api.nvim_create_user_command('ContextWindowClose', function()
    tui_manager.stop()
  end, { desc = 'Close LSP context window' })

  vim.api.nvim_create_user_command('ContextWindowToggle', function()
    tui_manager.toggle()
  end, { desc = 'Toggle LSP context window' })

  logger.info("UI", "Commands registered successfully")
end

-- Setup default keymaps
function M.setup_keymaps()
  local keymap_configs = {
    {
      mode = 'n',
      lhs = '<leader>co',
      rhs = ':ContextWindow open<CR>',
      opts = { desc = 'Open Context Window', silent = true }
    },
    {
      mode = 'n',
      lhs = '<leader>cc',
      rhs = ':ContextWindow close<CR>',
      opts = { desc = 'Close Context Window', silent = true }
    },
    {
      mode = 'n',
      lhs = '<leader>ct',
      rhs = ':ContextWindow toggle<CR>',
      opts = { desc = 'Toggle Context Window', silent = true }
    },
    {
      mode = 'n',
      lhs = '<leader>cr',
      rhs = ':ContextWindow restart<CR>',
      opts = { desc = 'Restart Context Window', silent = true }
    },
    {
      mode = 'n',
      lhs = '<leader>cs',
      rhs = ':ContextWindow status<CR>',
      opts = { desc = 'Context Window Status', silent = true }
    }
  }

  for _, config in ipairs(keymap_configs) do
    vim.keymap.set(config.mode, config.lhs, config.rhs, config.opts)
  end

  logger.info("UI", "Default keymaps registered successfully")
end

-- Setup custom keymaps (for users who want different mappings)
function M.setup_custom_keymaps(keymap_table)
  if not keymap_table or type(keymap_table) ~= 'table' then
    logger.plugin("warn", "Invalid keymap configuration provided")
    return
  end

  for action, mapping in pairs(keymap_table) do
    local command
    if action == 'open' then
      command = ':ContextWindow open<CR>'
    elseif action == 'close' then
      command = ':ContextWindow close<CR>'
    elseif action == 'toggle' then
      command = ':ContextWindow toggle<CR>'
    elseif action == 'restart' then
      command = ':ContextWindow restart<CR>'
    elseif action == 'status' then
      command = ':ContextWindow status<CR>'
    else
      logger.plugin("warn", "Unknown action for keymap: " .. action)
      goto continue
    end

    if mapping.key then
      local opts = vim.tbl_deep_extend('force', {
        desc = 'Context Window ' .. action,
        silent = true
      }, mapping.opts or {})

      vim.keymap.set(mapping.mode or 'n', mapping.key, command, opts)
    end

    ::continue::
  end

  logger.info("UI", "Custom keymaps registered successfully")
end

-- Remove default keymaps (for users who want to use custom ones)
function M.remove_default_keymaps()
  local default_keys = {
    '<leader>co', '<leader>cc', '<leader>ct', '<leader>cr', '<leader>cs'
  }

  for _, key in ipairs(default_keys) do
    pcall(vim.keymap.del, 'n', key)
  end

  logger.info("UI", "Default keymaps removed")
end

-- Setup help documentation commands
function M.setup_help_commands()
  vim.api.nvim_create_user_command('HoverFloatHelp', function()
    vim.cmd('help nvim-hoverfloat')
  end, { desc = 'Show HoverFloat help documentation' })

  vim.api.nvim_create_user_command('HoverFloatHealth', function()
    vim.cmd('checkhealth nvim-hoverfloat')
  end, { desc = 'Run HoverFloat health check' })
end

-- Setup all UI components with default configuration
function M.setup_all()
  M.setup_commands()
  M.setup_keymaps()
  M.setup_help_commands()
  logger.info("UI", "All UI components initialized")
end

-- Get UI setup status
function M.get_status()
  -- Check if commands exist
  local commands_exist = pcall(function()
    vim.api.nvim_get_commands({})['ContextWindow']
  end)

  -- Check if default keymaps exist
  local keymaps_exist = false
  local keymaps = vim.api.nvim_get_keymap('n')
  for _, keymap in ipairs(keymaps) do
    if keymap.lhs == '<leader>ct' then
      keymaps_exist = true
      break
    end
  end

  return {
    commands_registered = commands_exist,
    default_keymaps_active = keymaps_exist,
  }
end

return M
