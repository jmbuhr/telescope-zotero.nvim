local finders = require 'telescope.finders'
local pickers = require 'telescope.pickers'
local previewers = require 'telescope.previewers'
local conf = require('telescope.config').values
local action_state = require 'telescope.actions.state'
local actions = require 'telescope.actions'
local database = require 'zotero.database'

local M = {}

local default_opts = {
  zotero_db_path = '~/Zotero/zotero.sqlite',
  better_bibtex_db_path = '~/Zotero/better-bibtex.sqlite',
}
M.config = default_opts

M.setup = function(opts)
  M.config = vim.tbl_extend('force', default_opts, opts or {})
end

local get_items = function()
  local success = database.connect(M.config)
  if success then
    return database.get_items()
  else
    return {}
  end
end

--- Main entry point of the picker
--- @param opts any
M.picker = function(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      prompt_title = 'Zotoro library',
      finder = finders.new_table {
        results = get_items(),
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.title,
            ordinal = entry.citekey,
          }
        end,
      },
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          vim.api.nvim_put({ '@' .. selection.value.citekey }, '', false, true)
        end)
        return true
      end,
    })
    :find()
end

return M
