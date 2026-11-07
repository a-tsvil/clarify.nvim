vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/clarify.lua')

local server
local function run()
  local providers = require('clarify.providers')
  local assistant = require('clarify')
  local context = require('clarify.context')
  local ui = require('clarify.ui')
  local function eq(expected, actual)
    assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
  end
  local function fails(f, needle)
    local ok, err = pcall(f)
    assert(not ok and tostring(err):find(needle, 1, true), tostring(err))
  end

  local port
  server = vim.fn.jobstart({ 'python3', 'tests/server.py' }, {
    on_stdout = function(_, lines)
      for _, line in ipairs(lines) do
        port = tonumber(line) or port
      end
    end,
  })
  assert(
    vim.wait(3000, function()
      return port ~= nil
    end),
    'fixture server did not start'
  )
  local base = 'http://127.0.0.1:' .. port
  local prompt = 'quote " slash \\ newline\nλ'
  for _, provider in ipairs({ 'gemini', 'openai', 'anthropic', 'compatible' }) do
    local cfg = { provider = provider, base_url = base, model = 'fixture' }
    cfg[provider .. '_api_key'] = 'fixture-secret'
    local req = providers.build(cfg, prompt, false)
    eq('fixture-secret', req.key)
    assert(req.body.tools == nil, 'Web search must be opt-in')
    local detailed = providers.build(cfg, prompt, false, true)
    assert(vim.json.encode(req.body):find('Write concise Markdown', 1, true))
    assert(vim.json.encode(detailed.body):find('Write a detailed Markdown explanation', 1, true))
    assert(vim.json.encode(req.body):find('complete flow of the selected', 1, true))
    assert(vim.json.encode(detailed.body):find('every meaningful statement or block', 1, true))
    assert(vim.json.encode(req.body):find('uses the individual-feature style', 1, true))
    assert(vim.json.encode(detailed.body):find('uses the code-walkthrough style', 1, true))
    local budget = detailed.body.max_tokens
      or detailed.body.max_output_tokens
      or detailed.body.generationConfig.maxOutputTokens
    eq(3200, budget)
    assert(detailed.body.tools == nil, 'Detailed mode must not enable web search')
    assert(not req.url:find('fixture-secret', 1, true))
    local done, err, answer
    providers.request(req, 3000, function(e, a)
      err, answer, done = e, a, true
    end)
    assert(
      vim.wait(4000, function()
        return done
      end),
      'request did not complete'
    )
    assert(not err, err)
    assert(answer.text:find('fixture'))
    if provider ~= 'compatible' then
      assert(providers.build(cfg, prompt, true).body.tools)
    end
    local env_name = providers.defaults[provider].api_key_env
    local original_key, original_google = vim.env[env_name], vim.env.GOOGLE_API_KEY
    vim.env[env_name] = 'environment-key'
    vim.env.GOOGLE_API_KEY = nil
    eq('fixture-secret', providers.build(cfg, prompt, false).key)
    cfg.api_key = 'generic-override'
    eq('generic-override', providers.build(cfg, prompt, false).key)
    cfg.api_key = nil
    cfg[provider .. '_api_key'] = function()
      return 'provider-function-key'
    end
    eq('provider-function-key', providers.build(cfg, prompt, false).key)
    cfg[provider .. '_api_key'] = function()
      return nil
    end
    eq('environment-key', providers.build(cfg, prompt, false).key)
    cfg[provider .. '_api_key'] = nil
    eq('environment-key', providers.build(cfg, prompt, false).key)
    cfg.api_key_env = 'CLARIFY_IGNORED_KEY'
    vim.env.CLARIFY_IGNORED_KEY = 'must-not-use'
    eq('environment-key', providers.build(cfg, prompt, false).key)
    vim.env.CLARIFY_IGNORED_KEY = nil
    if provider == 'gemini' then
      vim.env.GOOGLE_API_KEY = 'google-environment-key'
      eq('google-environment-key', providers.build(cfg, prompt, false).key)
      cfg.gemini_api_key = 'gemini-config-key'
      eq('gemini-config-key', providers.build(cfg, prompt, false).key)
      cfg.api_key = 'generic-config-key'
      eq('generic-config-key', providers.build(cfg, prompt, false).key)
      cfg.api_key, cfg.gemini_api_key = nil, nil
      vim.env.GOOGLE_API_KEY = ''
      eq('environment-key', providers.build(cfg, prompt, false).key)
    end
    vim.env[env_name], vim.env.GOOGLE_API_KEY = original_key, original_google
  end
  for _, test in ipairs({ { '/error', '429' }, { '/invalid', 'invalid JSON' } }) do
    local req =
      providers.build({ provider = 'openai', base_url = base .. test[1], api_key = 'fixture-secret' }, prompt, false)
    local done, err
    providers.request(req, 3000, function(e)
      err, done = e, true
    end)
    assert(vim.wait(4000, function()
      return done
    end))
    assert(err:find(test[2], 1, true), err)
    assert(not err:find('fixture-secret', 1, true), 'error leaked key')
  end
  fails(function()
    providers.build({ provider = 'compatible', base_url = base, model = 'x' }, '', true)
  end, 'unavailable')
  fails(function()
    providers.build({ provider = 'compatible', base_url = 'http://example.com', model = 'x' }, '', false)
  end, 'HTTPS')
  fails(function()
    providers.parse('gemini', { candidates = {} })
  end, 'no explanation')
  fails(function()
    assistant.setup({ timeout_ms = -1 })
  end, 'positive')
  fails(function()
    assistant.setup({ web_search = 'false' })
  end, 'boolean')
  fails(function()
    assistant.setup({ window = 'invalid' })
  end, 'window')
  local parsed = providers.parse('gemini', {
    candidates = {
      {
        finishReason = 'MAX_TOKENS',
        content = { parts = { { text = 'hidden', thought = true }, { text = 'answer' } } },
        groundingMetadata = {
          groundingChunks = { { web = { uri = 'https://example.org' } }, { web = { uri = 'https://example.org' } } },
        },
      },
    },
  })
  eq('answer', parsed.text)
  eq({ 'https://example.org' }, parsed.sources)
  assert(parsed.truncated)
  parsed = providers.parse('openai', {
    status = 'incomplete',
    output = {
      {
        content = {
          {
            type = 'output_text',
            text = 'answer',
            annotations = { { type = 'url_citation', url = 'https://example.org' } },
          },
        },
      },
    },
  })
  eq({ 'https://example.org' }, parsed.sources)
  assert(parsed.truncated)
  parsed = providers.parse('anthropic', {
    content = {
      {
        type = 'text',
        text = 'answer',
        citations = {
          { url = 'https://example.org' },
          { url = 'javascript:alert(1)' },
        },
      },
    },
  })
  eq({ 'https://example.org' }, parsed.sources)

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local λ = nil', 'print(λ)' })
  vim.bo.filetype = 'lua'
  vim.api.nvim_win_set_cursor(0, { 1, 11 })
  local snapshot = context.capture({ args = 'nil', range = 0 })
  eq('lua', snapshot.filetype)
  eq('nil', snapshot.target)
  eq(snapshot.code, vim.json.decode(context.prompt(snapshot, 'hover')).code_excerpt)
  local original_clients = vim.lsp.get_clients
  local cancelled, position = false, nil
  vim.lsp.get_clients = function()
    return {
      {
        offset_encoding = 'utf-16',
        request = function(_, _, params)
          position = params.position
          return true, 1
        end,
        cancel_request = function()
          cancelled = true
        end,
      },
    }
  end
  local hovered
  context.hover(snapshot, 10, function(doc)
    hovered = doc
  end)
  assert(vim.wait(1000, function()
    return hovered ~= nil
  end))
  eq('', hovered)
  assert(cancelled)
  eq(10, position.character)
  vim.lsp.get_clients = function()
    return {
      {
        offset_encoding = 'utf-16',
        request = function(_, _, _, callback)
          vim.schedule(function()
            callback(nil, { contents = { kind = 'markdown', value = 'Library hover docs' } })
          end)
          return true, 2
        end,
        cancel_request = function() end,
      },
    }
  end
  hovered = nil
  context.hover(snapshot, 200, function(doc)
    hovered = doc
  end)
  assert(vim.wait(1000, function()
    return hovered ~= nil
  end))
  eq('Library hover docs', hovered)
  vim.lsp.get_clients = original_clients
  local large = {}
  for i = 1, 100 do
    large[i] = string.rep('x', 1000)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, large)
  eq(12000, #context.capture({ args = 'x', range = 1, line1 = 1, line2 = 100 }).code)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep('a', 11999) .. 'λ' })
  snapshot = context.capture({ args = string.rep('a', 499) .. 'λ', range = 0 })
  eq(11999, #snapshot.code)
  eq(499, #snapshot.target)
  assert(vim.json.encode(snapshot))

  local original_selection = vim.o.selection
  vim.o.selection = 'inclusive'
  vim.fn.setreg('z', 'preserved register')
  vim.fn.setreg('"', 'preserved unnamed register')
  local function selection(lines, keys, expected)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.cmd('normal! ' .. keys)
    local captured = context.capture({ args = '', range = 0 })
    eq('Selected code', captured.target)
    eq(expected, captured.code)
    assert(captured.selection)
    assert(vim.json.decode(context.prompt(captured, '')).selection)
    eq('n', vim.fn.mode())
    eq('preserved register', vim.fn.getreg('z'))
    eq('preserved unnamed register', vim.fn.getreg('"'))
    return captured
  end
  selection({ 'left(foo + bar)right' }, 'gg05lv8l', 'foo + bar')
  selection({ 'left(foo + bar)right' }, 'gg013lv8h', 'foo + bar')
  selection({ 'left(λ + β)right' }, 'gg05lv4l', 'λ + β')
  selection({ 'before first', 'second after' }, 'gg07lvj05l', 'first\nsecond')
  selection({ 'first line', 'second line' }, 'ggVj', 'first line\nsecond line')
  selection({ 'abcXYZdef', 'ghiUVWjkl' }, 'gg03l' .. vim.keycode('<C-v>') .. 'j2l', 'XYZ\nUVW')
  vim.o.selection = 'exclusive'
  selection({ 'left(foo + bar)right' }, 'gg05lv9l', 'foo + bar')
  vim.o.selection = original_selection
  local many_lines = {}
  for i = 1, 100 do
    many_lines[i] = 'line ' .. i
  end
  local limited = selection(many_lines, 'gg0vG$', table.concat(many_lines, '\n', 1, 80))
  assert(limited.truncated)
  local blocks, expected_blocks = {}, {}
  for i = 1, 100 do
    blocks[i] = 'abcXYZdef'
  end
  for i = 1, 80 do
    expected_blocks[i] = 'XYZ'
  end
  limited = selection(blocks, 'gg03l' .. vim.keycode('<C-v>') .. 'G2l', table.concat(expected_blocks, '\n'))
  assert(limited.truncated)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, many_lines)
  local ranged = context.capture({ args = '', range = 2, line1 = 1, line2 = 100 })
  eq(80, #vim.split(ranged.code, '\n', { plain = true }))
  assert(ranged.truncated and ranged.selection)
  assert(vim.json.decode(context.prompt(ranged, '')).excerpt_truncated)
  local normal = context.capture({ args = 'line', range = 0 })
  assert(not normal.selection, 'Old visual marks must not affect a normal invocation')

  local origin = vim.api.nvim_get_current_win()
  local source_width = vim.api.nvim_win_get_width(origin)
  local pane = ui.open()
  eq(origin, vim.api.nvim_get_current_win())
  eq(2, #vim.api.nvim_tabpage_list_wins(0))
  eq(pane, ui.open())
  eq('editor', vim.api.nvim_win_get_config(pane.win).relative)
  eq(source_width, vim.api.nvim_win_get_width(origin))
  vim.cmd('wincmd w')
  eq(pane.win, vim.api.nvim_get_current_win())
  vim.api.nvim_set_current_win(origin)
  local geometry = vim.api.nvim_win_get_config(pane.win)
  assert(geometry.width <= vim.o.columns - 2 and geometry.height <= vim.o.lines - 2)
  local columns, screen_lines = vim.o.columns, vim.o.lines
  vim.o.columns, vim.o.lines = 40, 12
  vim.api.nvim_exec_autocmds('VimResized', {})
  geometry = vim.api.nvim_win_get_config(pane.win)
  assert(geometry.width <= 38 and geometry.height <= 10)
  vim.o.columns, vim.o.lines = columns, screen_lines
  vim.api.nvim_exec_autocmds('VimResized', {})
  ui.loading(pane)
  local first_frame = table.concat(vim.api.nvim_buf_get_lines(pane.buf, 0, -1, false), '\n')
  assert(first_frame:find('Preparing explanation', 1, true))
  assert(
    vim.wait(1000, function()
      return table.concat(vim.api.nvim_buf_get_lines(pane.buf, 0, -1, false), '\n') ~= first_frame
    end),
    'Loading spinner did not animate'
  )
  local timer = pane.timer
  ui.result(pane, { text = 'answer', sources = {} })
  eq('answer', table.concat(vim.api.nvim_buf_get_lines(pane.buf, 0, -1, false), '\n'))
  assert(pane.timer == nil and timer:is_closing(), 'Spinner must stop when the answer arrives')
  eq({}, vim.api.nvim_buf_get_extmarks(pane.buf, vim.api.nvim_create_namespace('ClarifySpinner'), 0, -1, {}))
  assert(not vim.bo[pane.buf].modifiable)
  vim.api.nvim_set_hl(0, 'NoiceLspProgressSpinner', { link = 'Special' })
  ui.loading(pane)
  local marks =
    vim.api.nvim_buf_get_extmarks(pane.buf, vim.api.nvim_create_namespace('ClarifySpinner'), 0, -1, { details = true })
  eq('NoiceLspProgressSpinner', marks[1][4].hl_group)
  timer = pane.timer
  vim.api.nvim_set_current_win(pane.win)
  vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'xt', false)
  eq(origin, vim.api.nvim_get_current_win())
  assert(pane.timer == nil and timer:is_closing(), 'Closing the float must stop its spinner')
  pane = ui.open('split')
  assert(vim.fn.win_screenpos(pane.win)[2] > vim.fn.win_screenpos(origin)[2])
  vim.api.nvim_win_close(pane.win, true)
  vim.cmd('botright vsplit')
  local right = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(origin)
  pane = ui.open('split')
  eq(vim.fn.win_screenpos(right)[2], vim.fn.win_screenpos(pane.win)[2])
  assert(vim.fn.win_screenpos(pane.win)[1] > vim.fn.win_screenpos(right)[1])

  local real_request, callbacks, requests, kills = providers.request, {}, {}, 0
  providers.request = function(request, _, callback)
    callbacks[#callbacks + 1] = callback
    requests[#requests + 1] = request
    return {
      kill = function()
        kills = kills + 1
      end,
    }
  end
  assistant.setup({ gemini_api_key = 'fixture-secret' })
  vim.cmd('AIClarify nil')
  pane = ui.open()
  eq(1, #callbacks)
  assert(pane.timer ~= nil)
  assert(requests[1].body.tools == nil)
  assert(not pcall(vim.cmd, 'AIClarify! nil'), 'Search must be configured, not enabled by bang')
  vim.cmd('AIClarify print')
  eq(2, #callbacks)
  eq(1, kills)
  callbacks[2](nil, { text = 'new answer', sources = {} })
  assert(pane.timer == nil)
  callbacks[1](nil, { text = 'stale answer', sources = {} })
  assert(table.concat(vim.api.nvim_buf_get_lines(pane.buf, 0, -1, false), '\n'):find('new answer', 1, true))
  vim.cmd('AIClarify third')
  vim.api.nvim_win_close(pane.win, true)
  eq(2, kills)
  callbacks[3](nil, { text = 'closed answer', sources = {} })
  vim.cmd('AIClarify fourth')
  pane = ui.open()
  vim.cmd('AIClarifyCancel')
  assert(vim.wait(1000, function()
    return table.concat(vim.api.nvim_buf_get_lines(pane.buf, 0, -1, false), '\n'):find('Cancelled.', 1, true) ~= nil
  end))
  callbacks[4](nil, { text = 'cancelled answer', sources = {} })
  eq(3, kills)
  assert(pane.timer == nil, 'Cancellation must stop the spinner')
  vim.cmd('AIExplain nil')
  eq(3200, requests[5].body.generationConfig.maxOutputTokens)
  assert(requests[5].body.tools == nil)
  callbacks[5](nil, { text = 'detailed answer', sources = {} })
  assistant.setup({ gemini_api_key = 'fixture-secret', web_search = true })
  vim.cmd('AIClarify nil')
  assert(requests[6].body.tools[1].google_search)
  eq(1600, requests[6].body.generationConfig.maxOutputTokens)
  callbacks[6](nil, { text = 'searched brief answer', sources = {} })
  vim.cmd('AIExplain nil')
  assert(requests[7].body.tools[1].google_search)
  eq(3200, requests[7].body.generationConfig.maxOutputTokens)
  callbacks[7](nil, { text = 'searched detailed answer', sources = {} })
  assistant.setup({ gemini_api_key = 'fixture-secret' })
  vim.cmd('AIExplain nil')
  assert(requests[8].body.tools == nil, 'setup defaults must reset web search to off')
  callbacks[8](nil, { text = 'detailed answer without search', sources = {} })
  for _, command in ipairs({ 'AIClarify', 'AIExplain' }) do
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'left(foo + bar)right' })
    vim.api.nvim_feedkeys(vim.keycode('gg05lv8l:' .. command .. '<CR>'), 'xt', false)
    local request = requests[#requests]
    local payload = vim.json.decode(request.body.contents[1].parts[1].text)
    eq('Selected code', payload.target)
    eq('foo + bar', payload.code_excerpt)
    assert(payload.selection)
    local system = request.body.systemInstruction.parts[1].text
    assert(
      system:find(
        command == 'AIExplain' and 'every meaningful statement or block' or 'complete flow of the selected',
        1,
        true
      )
    )
    assert(request.body.tools == nil)
    callbacks[#callbacks](nil, { text = 'selected code explanation', sources = {} })
  end
  vim.api.nvim_feedkeys(vim.keycode('gg05lv8l:AIExplain data flow<CR>'), 'xt', false)
  local payload = vim.json.decode(requests[#requests].body.contents[1].parts[1].text)
  eq('data flow', payload.target)
  eq('foo + bar', payload.code_excerpt)
  assert(payload.selection)
  callbacks[#callbacks](nil, { text = 'focused selection explanation', sources = {} })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    'def totals_by_category(purchases):',
    '    totals = {}',
    '    for category, price in purchases:',
    '        totals[category] = totals.get(category, 0) + price',
    '    return totals',
  })
  vim.api.nvim_feedkeys(vim.keycode('ggV4j:<C-u>AIExplain<CR>'), 'xt', false)
  payload = vim.json.decode(requests[#requests].body.contents[1].parts[1].text)
  assert(payload.selection, 'Command entry dropping the Visual range must preserve the selection')
  assert(payload.code_excerpt:find('def totals_by_category', 1, true))
  assert(payload.code_excerpt:find('return totals', 1, true))
  callbacks[#callbacks](nil, { text = 'whole function explanation', sources = {} })
  vim.cmd('AIClarify totals')
  payload = vim.json.decode(requests[#requests].body.contents[1].parts[1].text)
  assert(not payload.selection, 'A recovered selection must be consumed once')
  callbacks[#callbacks](nil, { text = 'keyword explanation', sources = {} })
  vim.cmd('AIClarify totals')
  pane = ui.open()
  assert(pane.timer ~= nil)
  callbacks[#callbacks]('HTTP 429: quota exceeded')
  assert(pane.timer == nil, 'Request errors must stop the spinner')
  assert(
    table.concat(vim.api.nvim_buf_get_lines(pane.buf, 0, -1, false), '\n'):find('Unable to load explanation', 1, true)
  )
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'left(foo + bar)right' })
  vim.api.nvim_feedkeys(vim.keycode('gg05lv8l:<C-u>AIClarify<CR>'), 'xt', false)
  payload = vim.json.decode(requests[#requests].body.contents[1].parts[1].text)
  eq('foo + bar', payload.code_excerpt)
  assert(payload.selection)
  callbacks[#callbacks](nil, { text = 'character selection explanation', sources = {} })
  vim.api.nvim_feedkeys(vim.keycode('ggV4j<Esc>'), 'xt', false)
  vim.api.nvim_exec_autocmds('CursorMoved', {})
  vim.cmd('AIClarify totals')
  payload = vim.json.decode(requests[#requests].body.contents[1].parts[1].text)
  assert(not payload.selection, 'Moving after Visual selection must restore keyword mode')
  callbacks[#callbacks](nil, { text = 'keyword explanation', sources = {} })
  providers.request = real_request
  assistant.cancel()
  print('All clarify tests passed (HTTP adapters, errors, citations, context, LSP timeout, pane layout, cancellation).')
end

local ok, err = xpcall(run, debug.traceback)
if server then
  vim.fn.jobstop(server)
end
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
