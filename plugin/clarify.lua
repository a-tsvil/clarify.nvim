if vim.g.loaded_clarify then
  return
end
vim.g.loaded_clarify = true
require('clarify.context')

vim.api.nvim_create_user_command('AIClarify', function(opts)
  require('clarify').explain(opts)
end, { nargs = '*', range = true, desc = 'Briefly explain a feature or selected code' })

vim.api.nvim_create_user_command('AIExplain', function(opts)
  opts.detailed = true
  require('clarify').explain(opts)
end, { nargs = '*', range = true, desc = 'Explain a feature or selected code in detail' })

vim.api.nvim_create_user_command('AIClarifyCancel', function()
  require('clarify').cancel()
end, { desc = 'Cancel the pending AI explanation' })
