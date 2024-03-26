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
  -- specify options for different filetypes
  -- locate_bib can be a string or a function
  ft = {
    quarto = {
      insert_key_formatter = function(citekey)
        return '@' .. citekey
      end,
      locate_bib = bib.locate_quarto_bib,
    },
    tex = {
      insert_key_formatter = function(citekey)
        return '\\cite{' .. citekey .. '}'
      end,
      locate_bib = bib.locate_tex_bib,
    },
    plaintex = {
      insert_key_formatter = function(citekey)
        return '\\cite{' .. citekey .. '}'
      end,
      locate_bib = bib.locate_tex_bib,
    },
    -- fallback for unlisted filetypes
    default = {
      insert_key_formatter = function(citekey)
        return '@' .. citekey
      end,
      locate_bib = bib.locate_quarto_bib,
    },
  },
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

local insert_entry = function(entry, insert_key_fn, locate_bib_fn)
  local citekey = entry.value.citekey
  local insert_key = insert_key_fn(citekey)
  vim.api.nvim_put({ insert_key }, '', false, true)
  local bib_path = nil
  if type(locate_bib_fn) == 'string' then
    bib_path = locate_bib_fn
  elseif type(locate_bib_fn) == 'function' then
    bib_path = locate_bib_fn()
  end
  if bib_path == nil then
    vim.notify_once('Could not find a bibliography file', vim.log.levels.WARN)
    return
  end
  bib_path = vim.fn.expand(bib_path)

  -- check if is already in the bib filen
  for line in io.lines(bib_path) do
    if string.match(line, '^@') and string.match(line, citekey) then
      return
    end
  end

  local bib_entry = bib.entry_to_bib_entry(entry)
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

local function extract_year(date)
  local year = date:match '(%d%d%d%d)'
  return year
end

--- Main entry point of the picker
--- @param opts any
M.picker = function(opts)
  opts = opts or {}
  local ft_options = M.config.ft[vim.bo.filetype] or M.config.ft.default
  pickers
    .new(opts, {
      prompt_title = 'Zotero library',
      finder = finders.new_table {
        results = get_items(),
        entry_maker = function(pre_entry)
          local creators = pre_entry.creators or {}
          local author = creators[1] or {}
          local last_name = author.lastName or ''
          local year = pre_entry.year or pre_entry.date or ''
          pre_entry.year = extract_year(year)

          local display = string.format('%s (%s et al., %s)', pre_entry.title, last_name, year)
          return {
            value = pre_entry,
            display = display,
            ordinal = display,
            preview_command = function(entry, bufnr)
              local bib_entry = bib.entry_to_bib_entry(entry)
              local lines = vim.split(bib_entry, '\n')
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
              vim.api.nvim_set_option_value('filetype', 'bibtex', { buf = bufnr })
            end,
          }
        end,
      },
      sorter = conf.generic_sorter(opts),
      previewer = previewers.display_content.new(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          insert_entry(entry, ft_options.insert_key_formatter, ft_options.locate_bib)
        end)
        return true
      end,
    })
    :find()
end

return M
