local M = {}

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
  local target = opts.args ~= '' and opts.args or vim.fn.expand('<cword>')
  if target == '' then
    target = vim.fn.expand('<cWORD>')
  end
  assert(target ~= '', 'Place the cursor on a feature, select lines, or supply a topic')
  local first = opts.range > 0 and opts.line1 or math.max(1, line - 12)
  local last = opts.range > 0 and opts.line2 or math.min(vim.api.nvim_buf_line_count(buf), line + 12)
  -- Bound both line count and bytes, including pathological minified files.
  last = math.min(last, first + 79)
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local code = clip(table.concat(lines, '\n'), 12000)
  return {
    buf = buf,
    row = line - 1,
    col = cursor[2],
    target = clip(target, 500),
    filetype = vim.bo[buf].filetype,
    code = code,
    first = first,
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
