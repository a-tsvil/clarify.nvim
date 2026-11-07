if vim.g.loaded_clarify then
  return
end
vim.g.loaded_clarify = true

vim.api.nvim_create_user_command('AIClarify', function(opts)
  require('clarify').explain(opts)
end, { nargs = '*', range = true, desc = 'Briefly explain a feature with examples' })

vim.api.nvim_create_user_command('AIExplain', function(opts)
  opts.detailed = true
  require('clarify').explain(opts)
end, { nargs = '*', range = true, desc = 'Explain a feature in detail with more examples' })

vim.api.nvim_create_user_command('AIClarifyCancel', function()
  require('clarify').cancel()
end, { desc = 'Cancel the pending AI explanation' })
