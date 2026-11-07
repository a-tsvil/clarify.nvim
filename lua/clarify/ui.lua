local M = {}
local panes = {}
local spinner_ns = vim.api.nvim_create_namespace('ClarifySpinner')

local function float_config()
  local width = math.max(1, math.min(88, vim.o.columns - 4))
  local height = math.max(1, math.min(28, vim.o.lines - vim.o.cmdheight - 4))
  local options = vim.lsp.util.make_floating_popup_options(width, height, {
    border = 'rounded',
    title = ' Clarify ',
    title_pos = 'center',
    focusable = true,
  })
  options.height = math.max(1, options.height)
  return options
end

local function position(pane)
  if vim.api.nvim_win_is_valid(pane.origin) then
    vim.api.nvim_win_call(pane.origin, function()
      vim.api.nvim_win_set_config(pane.win, float_config())
    end)
  end
end

function M.open(layout)
  layout = layout or 'float'
  local tab = vim.api.nvim_get_current_tabpage()
  local pane = panes[tab]
  if
    pane
    and vim.api.nvim_win_is_valid(pane.win)
    and vim.api.nvim_buf_is_valid(pane.buf)
    and vim.api.nvim_win_get_buf(pane.win) == pane.buf
  then
    if pane.layout == layout then
      if layout == 'float' then
        if vim.api.nvim_get_current_win() ~= pane.win then
          pane.origin = vim.api.nvim_get_current_win()
        end
        position(pane)
      end
      return pane
    end
    vim.api.nvim_win_close(pane.win, true)
  end
  local origin = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  local win
  if layout == 'float' then
    win = vim.api.nvim_open_win(buf, false, float_config())
  else
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
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end
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
  pane = { win = win, buf = buf, layout = layout, origin = origin }
  panes[tab] = pane
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      M.stop_loading(pane)
      if panes[tab] == pane then
        panes[tab] = nil
      end
    end,
  })
  local function close()
    vim.api.nvim_win_close(win, true)
  end
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, close, { buffer = buf, desc = 'Close AI explanation' })
  end
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

local function set_text(pane, text)
  if not vim.api.nvim_buf_is_valid(pane.buf) then
    return
  end
  vim.bo[pane.buf].modifiable = true
  vim.api.nvim_buf_set_lines(pane.buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  vim.bo[pane.buf].modifiable = false
  vim.bo[pane.buf].modified = false
end

function M.stop_loading(pane)
  if pane.timer then
    pane.timer:stop()
    pane.timer:close()
    pane.timer = nil
  end
  if vim.api.nvim_buf_is_valid(pane.buf) then
    vim.api.nvim_buf_clear_namespace(pane.buf, spinner_ns, 0, -1)
  end
end

function M.write(pane, text)
  M.stop_loading(pane)
  set_text(pane, text)
  if vim.api.nvim_win_is_valid(pane.win) then
    vim.api.nvim_win_set_cursor(pane.win, { 1, 0 })
  end
end

function M.loading(pane)
  M.stop_loading(pane)
  local timer = assert(vim.uv.new_timer())
  pane.timer = timer
  local frames, frame = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }, 0
  local function render()
    if pane.timer ~= timer then
      return
    end
    if not vim.api.nvim_win_is_valid(pane.win) or not vim.api.nvim_buf_is_valid(pane.buf) then
      M.stop_loading(pane)
      return
    end
    frame = frame % #frames + 1
    local message = frames[frame] .. ' Preparing explanation…'
    local row = math.max(0, math.floor(vim.api.nvim_win_get_height(pane.win) / 2) - 1)
    local col = math.max(0, math.floor((vim.api.nvim_win_get_width(pane.win) - vim.fn.strdisplaywidth(message)) / 2))
    set_text(pane, string.rep('\n', row) .. string.rep(' ', col) .. message)
    local highlight = vim.fn.hlexists('NoiceLspProgressSpinner') == 1 and 'NoiceLspProgressSpinner' or 'DiagnosticInfo'
    vim.api.nvim_buf_set_extmark(
      pane.buf,
      spinner_ns,
      row,
      col,
      { id = 1, end_col = col + #frames[frame], hl_group = highlight }
    )
  end
  render()
  timer:start(80, 80, vim.schedule_wrap(render))
end

vim.api.nvim_create_autocmd('VimResized', {
  callback = function()
    for _, pane in pairs(panes) do
      if pane.layout == 'float' and vim.api.nvim_win_is_valid(pane.win) then
        position(pane)
      end
    end
  end,
})

function M.result(pane, result)
  pane.search_html = result.search_html
  local text = result.text
  if #result.sources > 0 then
    text = text .. '\n\n## Sources\n'
    for _, url in ipairs(result.sources) do
      text = text .. '\n- <' .. url .. '>'
    end
  end
  if result.search_html then
    text = text .. '\n\nGoogle Search Suggestions: press `gs` to view in your browser.'
  end
  if result.truncated then
    text = text .. '\n\n> This explanation was cut short. Try a smaller selection.'
  end
  M.write(pane, text)
end

return M
