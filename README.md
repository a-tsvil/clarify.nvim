# clarify.nvim

Explanations of selected code, keywords, functions, macros, and other language features
inside Neovim, with small examples and documentation links. Uses nearby code and
available LSP hover text; works without an LSP server too.

Requires **Neovim 0.11+** and **curl**.

## Install with vim-plug

Inside your `plug#begin()` / `plug#end()` block:

```lua
Plug('a-tsvil/clarify.nvim')
```

For a local checkout, use `Plug('/absolute/path/to/clarify.nvim')` instead.
Local plugins load directly; no `:PlugInstall` is needed. Restart Neovim.

## Gemini example

Export your key before launching Neovim:

```sh
export GEMINI_API_KEY='your-key'
```

After `plug#end()`:

```lua
require('clarify').setup({
  provider = 'gemini',
  web_search = false, -- opt in by setting true
  window = 'float', -- use 'split' for the right/bottom-right pane
  -- gemini_api_key = 'your-key', -- optional override; keep secrets out of Git
})

vim.keymap.set('n', '<leader>ae', '<cmd>AIClarify<cr>', { desc = 'Explain feature' })
vim.keymap.set('x', '<leader>ae', ':AIClarify<cr>', { desc = 'Explain selected lines' })
vim.keymap.set('x', '<leader>aE', ':AIExplain<cr>', { desc = 'Explain selection in detail' })
```

Place your cursor on a feature and press `<leader>ae`, or run
`:AIClarify yield from` to explain an explicit topic.

## Commands and pane

- `:AIClarify [topic]` — explain the cursor word or an explicit topic.
- `:AIExplain [topic]` — explain in detail with more examples.
- Select code with `v`, `V`, or `<C-v>`, then run `:AIClarify` or `:AIExplain`
  to explain the whole selection. An optional topic focuses the explanation.
- Single keywords or symbols get feature explanations; expressions and larger
  selections get a walkthrough of how the code works together.
- `:AIClarifyCancel` — cancel either pending explanation.

**Web search is off by default.** Set `web_search = true` in `setup()` to enable
provider search for both commands. With `false`, neither command enables search tools.

The Markdown answer opens in a floating window with an animated loading spinner.
Focus stays in your code. Use `<C-w>w` to enter the window, `gx` to open a URL,
and `q` or `<Esc>` to close. Set `window = 'split'` for the right/bottom-right pane.
The spinner uses Noice's highlight when available; Noice is optional.
Fenced-code highlighting depends on your Neovim configuration.
For Gemini search answers, `gs` opens Google's Search Suggestions in a browser.

## Providers and keys

Supports **Gemini**, **OpenAI**, **Anthropic**, and **OpenAI-compatible endpoints**.
See `:help clarify-setup` for settings; use your provider's documentation for
models, endpoint URLs, account access, and API keys.

Keys come from the standard environment variables: `GOOGLE_API_KEY` or
`GEMINI_API_KEY` for Gemini, `OPENAI_API_KEY` for OpenAI/compatible, and
`ANTHROPIC_API_KEY` for Anthropic. Google's variable wins if both Gemini variables
are set. Config fields override environment variables:
`api_key` → `<provider>_api_key` → environment. No `.env` files are loaded.

Requests send a bounded code excerpt and available LSP hover text only when
invoked. Explanations and suggested links can be wrong; inspect the sources.
Selections are limited to the first 80 lines and 12,000 bytes.
