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
  -- zotero_storage_path = "~/Zotero/storage",  Add this line
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

local function get_attachment_options(item)
  local options = {}
  if item.attachment and item.attachment.path then
    table.insert(options, { type = 'pdf', path = item.attachment.path, link_mode = item.attachment.link_mode })
  end
  if item.DOI then
    table.insert(options, { type = 'doi', url = 'https://doi.org/' .. item.DOI })
  end
  return options
end

local function open_url(url)
  local open_cmd
  if vim.fn.has 'win32' == 1 then
    open_cmd = 'start'
  elseif vim.fn.has 'macunix' == 1 then
    open_cmd = 'open'
  else -- Assume Unix
    open_cmd = 'xdg-open'
  end
  vim.fn.system(open_cmd .. ' ' .. vim.fn.shellescape(url))
end

local function open_attachment(item)
  local options = get_attachment_options(item)
  if #options == 0 then
    vim.notify('No PDF or DOI available for this entry', vim.log.levels.WARN)
    return
  elseif #options == 1 then
    -- If only one option, open it directly
    local option = options[1]
    if option.type == 'pdf' then
      local file_path = option.path
      if option.link_mode == 1 then -- 1 typically means stored file
        local zotero_storage = vim.fn.expand(M.config.zotero_storage_path)
        file_path = zotero_storage .. '/' .. file_path
      end
      if file_path ~= 0 then
        open_url(file_path)
      else
        vim.notify('File not found: ' .. file_path, vim.log.levels.ERROR)
      end
    else -- DOI
      open_url(option.url)
    end
  else
    -- If multiple options, use vim.ui.select to let the user choose
    vim.ui.select(options, {
      prompt = 'Choose attachment to open:',
      format_item = function(item)
        return item.type == 'pdf' and 'Open PDF' or 'Open DOI link'
      end,
    }, function(choice)
      if choice then
        if choice.type == 'pdf' then
          local file_path = choice.path
          if choice.link_mode == 1 then -- 1 typically means stored file
            local zotero_storage = vim.fn.expand(M.config.zotero_storage_path)
            file_path = zotero_storage .. '/' .. file_path
          end
          if file_path ~= 0 then
            open_url(file_path)
          else
            vim.notify('File not found: ' .. file_path, vim.log.levels.ERROR)
          end
        else -- DOI
          open_url(choice.url)
        end
      end
    end)
  end
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
  if year ~= nil then
    return year
  else
    return 'NA'
  end
end

local function make_entry(pre_entry)
  local creators = pre_entry.creators or {}
  local author = creators[1] or {}
  local last_name = author.lastName or 'NA'
  local year = pre_entry.year or pre_entry.date or 'NA'
  year = extract_year(year)
  pre_entry.year = year

  local options = get_attachment_options(pre_entry)
  local icon
  if #options > 1 then
    icon = ' ' -- Icon for both PDF and DOI available
  elseif #options == 1 then
    icon = options[1].type == 'pdf' and '󰈙 ' or '󰖟 '
  else
    icon = '  ' -- Blank space
  end
  local display_value = string.format('%s%s, %s) %s', icon, last_name, year, pre_entry.title)
  local highlight = {
    { { 0, #icon }, 'SpecialChar' },
    { { #icon, #icon + #last_name + #year + 3 }, 'Comment' },
    { { #icon + #last_name + 2, #icon + #year + #last_name + 2 }, '@markup.underline' },
  }

  local function make_display(_)
    return display_value, highlight
  end
  return {
    value = pre_entry,
    display = make_display,
    ordinal = display_value,
    preview_command = function(entry, bufnr)
      local bib_entry = bib.entry_to_bib_entry(entry)
      local lines = vim.split(bib_entry, '\n')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value('filetype', 'bibtex', { buf = bufnr })
    end,
  }
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
        entry_maker = make_entry,
      },
      sorter = conf.generic_sorter(opts),
      previewer = previewers.display_content.new(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          insert_entry(entry, ft_options.insert_key_formatter, ft_options.locate_bib)
        end)
        -- Update the mapping to open PDF or DOI
        map('i', '<C-o>', function()
          local entry = action_state.get_selected_entry()
          open_attachment(entry.value)
        end)
        map('n', 'o', function()
          local entry = action_state.get_selected_entry()
          open_attachment(entry.value)
        end)
        return true
      end,
    })
    :find()
end

return M
