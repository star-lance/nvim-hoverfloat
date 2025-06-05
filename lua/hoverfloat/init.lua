local M = {}

local hover_buf, hover_win

local function create_floating_window()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then return end

  hover_buf = vim.api.nvim_create_buf(false, true)
  local width, height = 60, 15

  hover_win = vim.api.nvim_open_win(hover_buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = 1,
    col = vim.o.columns - width - 1,
    anchor = "NW",
    style = "minimal",
    border = "single",
    focusable = false,
  })

  vim.api.nvim_win_set_option(hover_win, 'winhl', 'Normal:NormalFloat,FloatBorder:FloatBorder')
end

local function update_hover_info()
  if not hover_win or not vim.api.nvim_win_is_valid(hover_win) then
    create_floating_window()
  end

  local params = vim.lsp.util.make_position_params()

  vim.lsp.buf_request(0, 'textDocument/hover', params, function(_, result)
    if not result or not result.contents then return end

    local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    lines = vim.lsp.util.trim_empty_lines(lines)
    if not lines or vim.tbl_isempty(lines) then return end

    vim.api.nvim_buf_set_lines(hover_buf, 0, -1, false, lines)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
      if not vim.lsp.buf.server_ready() then return end
      update_hover_info()
    end,
  })
end

return M

