# clarify.nvim

Explanations of selected code, keywords, functions, macros, and other language features
inside Neovim, with small examples and documentation links. Uses nearby code and
available LSP hover text; works without an LSP server too.

> **Web search is disabled by default for both `AIClarify` and `AIExplain`.**
> Set `web_search = true` in `setup()` to opt in. Without search, documentation
> links are model suggestions, not verified sources.

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
  web_search = false, -- disabled by default; set true to opt in
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

The Markdown answer opens beside your cursor, like LSP hover, with a loading spinner.
Moving the source cursor closes the float and cancels any pending explanation.
Focus stays in your code. Use `<C-w>w` to enter the window, `gx` to open a URL,
and `q` or `<Esc>` to close. Set `window = 'split'` for the right/bottom-right pane.
The spinner uses Noice's highlight when available; Noice is optional.
Fenced-code highlighting depends on your Neovim configuration.
For Gemini search answers, `gs` opens Google's Search Suggestions in a browser.

## Providers and keys

Supports **Gemini**, **OpenAI**, **Anthropic**, and **OpenAI-compatible endpoints**.
See `:help clarify-setup` for settings; use your provider's documentation for
models, endpoint URLs, account access, and API keys.

### Default models and overrides

Gemini is the default provider. Each hosted provider has a preconfigured model:

| `provider` | Default `model` | API |
| --- | --- | --- |
| `gemini` | `gemini-3.5-flash-lite` | Gemini generateContent |
| `openai` | `gpt-4.1-mini` | OpenAI Responses |
| `anthropic` | `claude-haiku-5-5` | Anthropic Messages |
| `compatible` | None; set `model` and `base_url` | Chat Completions |

Set `model` in `setup()` to override the selected provider's default:

```lua
require('clarify').setup({
  provider = 'gemini',
  model = 'gemini-3.5-flash-lite', -- replace with your chosen model ID
})
```

The same `model` option works with every provider. Omit it to keep the hosted
provider's default. Choose a model available to your account that supports the
provider's API above; if enabling `web_search`, it must support that tool too.
`base_url` can also override the API root (include `/v1` or `/v1beta` as needed).
Endpoints must use HTTPS, except local HTTP on `localhost` or `127.0.0.1`.

### Local Ollama models

Yes: use Ollama through its
[OpenAI-compatible API](https://docs.ollama.com/api/openai-compatibility).
Start Ollama with `ollama serve` if it is not already running, and download a
local model, for example with `ollama pull llama3.2`. Then configure:

```lua
require('clarify').setup({
  provider = 'compatible',
  base_url = 'http://localhost:11434/v1',
  model = 'llama3.2', -- use the exact name shown by `ollama list`
  api_key = '', -- no key needed; avoid reusing OPENAI_API_KEY
  web_search = false, -- required for compatible endpoints
  timeout_ms = 120000, -- allow time for local model loading and generation
})
```

Both commands use this model. With a downloaded local model and this local URL,
code and LSP context go to your Ollama server. Ollama must be running; the plugin
does not start it or download models. Web search is unavailable through the
compatible provider, so documentation links remain unverified model suggestions.

### API keys

Keys come from the standard environment variables: `GOOGLE_API_KEY` or
`GEMINI_API_KEY` for Gemini, `OPENAI_API_KEY` for OpenAI/compatible, and
`ANTHROPIC_API_KEY` for Anthropic. Google's variable wins if both Gemini variables
are set. Config fields override environment variables:
`api_key` → `<provider>_api_key` → environment. No `.env` files are loaded.

Requests send a bounded code excerpt and available LSP hover text only when
invoked. Explanations and suggested links can be wrong; inspect the sources.
Selections are limited to the first 80 lines and 12,000 bytes.
