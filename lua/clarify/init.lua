local M = {}
local config = { provider = 'gemini', timeout_ms = 30000, lsp_timeout_ms = 200, web_search = false }
local sequence, process, cancel_hover = 0, nil, nil
local pending

function M.cancel()
  sequence = sequence + 1
  if cancel_hover then
    cancel_hover()
    cancel_hover = nil
  end
  if process then
    process:kill(15)
    process = nil
  end
  if pending then
    local previous, cancelled = pending, sequence
    pending = nil
    vim.schedule(function()
      if cancelled == sequence then
        require('clarify.ui').write(previous.pane, previous.label .. '\n\nCancelled.')
      end
    end)
  end
end

function M.setup(opts)
  opts = opts or {}
  local c =
    vim.tbl_extend('force', { provider = 'gemini', timeout_ms = 30000, lsp_timeout_ms = 200, web_search = false }, opts)
  assert(require('clarify.providers').defaults[c.provider], 'Unknown AI provider')
  assert(type(c.web_search) == 'boolean', 'web_search must be a boolean')
  for _, name in ipairs({ 'timeout_ms', 'lsp_timeout_ms' }) do
    assert(type(c[name]) == 'number' and c[name] > 0 and c[name] < math.huge, name .. ' must be positive and finite')
  end
  M.cancel()
  config = c
end

function M.explain(opts)
  opts = vim.tbl_extend('force', { args = '', range = 0, detailed = false }, opts or {})
  local context = require('clarify.context')
  local providers = require('clarify.providers')
  local ui = require('clarify.ui')
  local captured, snapshot = pcall(context.capture, opts)
  if not captured then
    vim.notify(tostring(snapshot), vim.log.levels.ERROR)
    return
  end
  local built, request = pcall(providers.build, config, '', config.web_search, opts.detailed)
  if not built then
    vim.notify(tostring(request), vim.log.levels.ERROR)
    return
  end
  M.cancel()
  local current = sequence
  local pane = ui.open()
  local label = '# ' .. snapshot.target .. '\n\n' .. request.provider .. ' / ' .. request.model
  if opts.detailed then
    label = label .. ' · Detailed'
  end
  pending = { pane = pane, label = label }
  pane.search_html = nil
  ui.write(pane, label .. '\n\nLoading explanation… (`q` closes, :AIClarifyCancel cancels)')
  if pane.cancel_autocmd then
    pcall(vim.api.nvim_del_autocmd, pane.cancel_autocmd)
  end
  pane.cancel_autocmd = vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = pane.buf,
    once = true,
    callback = function()
      if current == sequence then
        M.cancel()
      end
    end,
  })
  cancel_hover = context.hover(snapshot, config.lsp_timeout_ms, function(hover)
    if current ~= sequence then
      return
    end
    local ready, prepared = pcall(
      providers.build,
      vim.tbl_extend('force', config, { api_key = request.key }),
      context.prompt(snapshot, hover),
      config.web_search,
      opts.detailed
    )
    if not ready then
      pending = nil
      ui.write(pane, label .. '\n\n' .. tostring(prepared))
      return
    end
    request = prepared
    local started, result = pcall(providers.request, request, config.timeout_ms, function(err, answer)
      if current ~= sequence then
        return
      end
      process = nil
      pending = nil
      if err then
        ui.write(pane, label .. '\n\nRequest failed: ' .. err)
      else
        ui.result(pane, answer, label)
      end
    end)
    if started then
      process = result
    else
      pending = nil
      ui.write(pane, label .. '\n\n' .. tostring(result))
    end
  end)
end

return M
