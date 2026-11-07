local M = {}
local panes = {}

function M.open()
  local tab = vim.api.nvim_get_current_tabpage()
  local pane = panes[tab]
  if
    pane
    and vim.api.nvim_win_is_valid(pane.win)
    and vim.api.nvim_buf_is_valid(pane.buf)
    and vim.api.nvim_win_get_buf(pane.win) == pane.buf
  then
    return pane
  end
  local origin = vim.api.nvim_get_current_win()
  local source_left = vim.fn.win_screenpos(origin)[2]
  local right
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_config(win).relative == '' and vim.fn.win_gettype(win) == '' then
      local left = vim.fn.win_screenpos(win)[2]
      if left > source_left and (not right or left >= vim.fn.win_screenpos(right)[2]) then
        right = win
      end
    end
  end
  if right then
    vim.api.nvim_set_current_win(right)
    vim.cmd('belowright split')
  else
    vim.cmd('botright vsplit')
  end
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].conceallevel = 2
  pane = { win = win, buf = buf }
  panes[tab] = pane
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = 'Close AI explanation' })
  vim.keymap.set('n', 'gs', function()
    if not pane.search_html then
      vim.notify('No Google Search widget for this answer')
      return
    end
    local path = vim.fn.tempname() .. '.html'
    -- The provider supplies Google's required Search Suggestions widget.
    vim.fn.writefile(vim.split(pane.search_html, '\n', { plain = true }), path)
    vim.fn.setfperm(path, 'rw-------')
    vim.ui.open(path)
  end, { buffer = buf, desc = 'Open Google Search Suggestions in browser' })
  vim.api.nvim_set_current_win(origin)
  return pane
end

function M.write(pane, text)
  if not vim.api.nvim_buf_is_valid(pane.buf) then
    return
  end
  vim.bo[pane.buf].modifiable = true
  vim.api.nvim_buf_set_lines(pane.buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  vim.bo[pane.buf].modifiable = false
  vim.bo[pane.buf].modified = false
end

function M.result(pane, result, label)
  pane.search_html = result.search_html
  local status = #result.sources > 0 and 'Web sources returned; check the linked evidence.'
    or 'No web sources returned. Reference links are model suggestions, not verified.'
  local text = label .. '\n\n' .. status .. '\n\n' .. result.text
  if #result.sources > 0 then
    text = text .. '\n\n## Retrieved sources\n'
    for _, url in ipairs(result.sources) do
      text = text .. '\n- <' .. url .. '>'
    end
  end
  if result.search_html then
    text = text .. '\n\nGoogle Search Suggestions: press `gs` to view in your browser.'
  end
  if result.truncated then
    text = text .. '\n\n> Response incomplete: output limit or provider paused the turn.'
  end
  M.write(pane, text)
end

return M
