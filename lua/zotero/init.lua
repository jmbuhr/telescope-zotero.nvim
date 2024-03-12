local finders = require 'telescope.finders'
local pickers = require 'telescope.pickers'
local previewers = require 'telescope.previewers'
local conf = require('telescope.config').values
local action_state = require 'telescope.actions.state'
local actions = require 'telescope.actions'
local bib = require 'zotero.bib'
local database = require 'zotero.database'

local M = {}

local default_opts = {
  zotero_db_path = '~/Zotero/zotero.sqlite',
  better_bibtex_db_path = '~/Zotero/better-bibtex.sqlite',
  quarto_integration = true,
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

local insert_entry = function(entry)
  local bib_path = bib.locate_bib()
  local bib_entry = bib.entry_to_bib_entry(entry)
  local citekey = entry.value.citekey
  vim.api.nvim_put({ '@' .. citekey }, '', false, true)

  -- check if is already in the bib file on
  -- in a line that starts with @
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    if string.match(line, '^@') and string.match(line, citekey) then
      return
    end
  end

  -- otherwise append the entry to the bib file at bib_path
  local file = io.open(bib_path, 'a')
  if file == nil then
    vim.notify('Could not open ' .. bib_path .. ' for appending', vim.log.levels.ERROR)
    return
  end
  file:write(bib_entry)
  file:close()
  vim.print('wrote ' .. citekey .. ' to ' .. bib_path)
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
          insert_entry(selection)
        end)
        return true
      end,
    })
    :find()
end

return M
