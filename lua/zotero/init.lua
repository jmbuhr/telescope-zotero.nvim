local finders = require 'telescope.finders'
local pickers = require 'telescope.pickers'
local previewers = require 'telescope.previewers'
local conf = require('telescope.config').values
local action_state = require 'telescope.actions.state'
local actions = require 'telescope.actions'
local database = require 'zotero.database'

local M = {}

M.previewer = function(opts)
  opts = opts or {}
  return previewers.new(opts)
end

--- Main entry point of the picker
--- @param opts any
M.picker = function(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      prompt_title = 'Zotoro library',
      finder = finders.new_table {
        results = database.get_items(),
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

-- M.picker()

return M
