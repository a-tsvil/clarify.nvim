local M = {}
local pending_selection

-- Command entry can drop Visual ranges; retain the selection until a move or edit.
local group = vim.api.nvim_create_augroup('ClarifySelection', { clear = true })
vim.api.nvim_create_autocmd('ModeChanged', {
  group = group,
  pattern = { 'v:*', 'V:*', '\22:*' },
  callback = function()
    pending_selection = {
      buf = vim.api.nvim_get_current_buf(),
      tick = vim.b.changedtick,
      first = vim.fn.getpos("'<"),
      last = vim.fn.getpos("'>"),
      type = vim.v.event.old_mode,
    }
  end,
})
vim.api.nvim_create_autocmd({ 'CursorMoved', 'TextChanged', 'TextChangedI', 'BufLeave', 'InsertEnter' }, {
  group = group,
  callback = function()
    pending_selection = nil
  end,
})

local function clip(text, limit)
  if #text <= limit then
    return text
  end
  while limit > 0 and text:byte(limit + 1) >= 128 and text:byte(limit + 1) <= 191 do
    limit = limit - 1
  end
  return text:sub(1, limit)
end

function M.capture(opts)
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local mode = vim.fn.mode()
  local active = mode == 'v' or mode == 'V' or mode == '\22'
  local start_pos, end_pos, selection_type
  if active then
    start_pos, end_pos, selection_type = vim.fn.getpos('v'), vim.fn.getpos('.'), mode
  elseif opts.range > 0 then
    start_pos, end_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    if start_pos[2] == opts.line1 and end_pos[2] == opts.line2 then
      selection_type = vim.fn.visualmode()
    else
      start_pos, end_pos = { 0, opts.line1, 1, 0 }, { 0, opts.line2, 1, 0 }
      selection_type = 'V'
    end
  elseif pending_selection and pending_selection.buf == buf and pending_selection.tick == vim.b.changedtick then
    start_pos, end_pos, selection_type = pending_selection.first, pending_selection.last, pending_selection.type
  end
  pending_selection = nil
  local selected = start_pos ~= nil
  local target = opts.args ~= '' and opts.args or (selected and 'Selected code' or vim.fn.expand('<cword>'))
  if target == '' then
    target = vim.fn.expand('<cWORD>')
  end
  assert(target ~= '', 'Place the cursor on a feature, select lines, or supply a topic')
  local first = selected and math.min(start_pos[2], end_pos[2]) or math.max(1, line - 12)
  local last = selected and math.max(start_pos[2], end_pos[2]) or math.min(vim.api.nvim_buf_line_count(buf), line + 12)
  local lines
  if selected then
    -- shortcut: getregion reads the full selection; bound endpoints if huge selections cause memory pressure.
    lines = vim.fn.getregion(start_pos, end_pos, { type = selection_type })
  else
    lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  end
  local text = table.concat(lines, '\n', 1, math.min(#lines, 80))
  local code = clip(text, 12000)
  if active then
    vim.cmd('normal! ' .. vim.keycode('<Esc>'))
  end
  pending_selection = nil
  return {
    buf = buf,
    row = line - 1,
    col = cursor[2],
    target = clip(target, 500),
    filetype = vim.bo[buf].filetype,
    code = code,
    first = first,
    selection = selected,
    truncated = #lines > 80 or #text > #code,
  }
end

function M.prompt(context, hover)
  return vim.json.encode({
    target = context.target,
    language = context.filetype,
    cursor_line = context.row + 1,
    cursor_byte_column = context.col + 1,
    excerpt_first_line = context.first,
    code_excerpt = context.code,
    lsp_hover = hover,
    selection = context.selection,
    excerpt_truncated = context.truncated,
  })
end

function M.hover(context, timeout_ms, callback)
  local clients = vim.lsp.get_clients({ bufnr = context.buf, method = 'textDocument/hover' })
  if #clients == 0 then
    callback('')
    return function() end
  end
  local pending, finished, cancels, docs = #clients, false, {}, {}
  local timer = assert(vim.uv.new_timer())
  local function finish()
    if finished then
      return
    end
    finished = true
    timer:stop()
    timer:close()
    for _, cancel in ipairs(cancels) do
      cancel()
    end
    callback(clip(table.concat(docs, '\n\n'), 8000))
  end
  timer:start(timeout_ms, 0, vim.schedule_wrap(finish))
  for _, client in ipairs(clients) do
    local text = vim.api.nvim_buf_get_lines(context.buf, context.row, context.row + 1, false)[1] or ''
    local character = vim.str_utfindex(text, client.offset_encoding or 'utf-16', context.col, false)
    local params = {
      textDocument = { uri = vim.uri_from_bufnr(context.buf) },
      position = { line = context.row, character = character },
    }
    local ok, id = client:request('textDocument/hover', params, function(err, result)
      if finished then
        return
      end
      if not err and result and result.contents then
        local markdown = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
        docs[#docs + 1] = table.concat(markdown, '\n')
      end
      pending = pending - 1
      if pending == 0 then
        finish()
      end
    end, context.buf)
    if ok then
      cancels[#cancels + 1] = function()
        client:cancel_request(id)
      end
    else
      pending = pending - 1
    end
  end
  if pending == 0 then
    finish()
  end
  return function()
    if finished then
      return
    end
    finished = true
    timer:stop()
    timer:close()
    for _, cancel in ipairs(cancels) do
      cancel()
    end
  end
end

return M
