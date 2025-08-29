local finders = require 'telescope.finders'
local pickers = require 'telescope.pickers'
local entry_display = require 'telescope.pickers.entry_display'
local previewers = require 'telescope.previewers'
local conf = require('telescope.config').values
local action_state = require 'telescope.actions.state'
local actions = require 'telescope.actions'

local bib = require 'zotero.bib'
local database = require 'zotero.database'

local M = {}

---@class Zotero.Configuration
---@field zotero_db_path string File path to Zotero SQLite database
---@field better_bibtex_db_path string File path to BetterBibTeX SQLite database
---@field zotero_storage_path string File path to Zotero's Storage directory
---@field pdf_opener string|nil Program to use for opening PDFs
---@field picker Zotero.Picker.Configuration Configuration for the picker
---@field ft Zotero.FileType[] Table with filetype configuration
---@field collection string? Table with filetype configuration

---@class Zotero.Picker.Configuration
---@field with_icons boolean Whether the picker uses NerdFont icons
---@field hlgroups Zotero.Picker.Highlights Highlight groups for picker elements
---
---@class Zotero.Picker.Highlights
---@field icons string Higlight groups used for icons
---@field author_year string Higlight groups used for author and publishing year
---@field title string Higlight groups used for title

---@class Zotero.FileType
---@field insert_key_formatted function Function that formats the entry to insert
---@field locate_bib string|function File path or function that locates reference bib file

---@type Zotero.Configuration
local default_opts = {
  zotero_db_path = '~/Zotero/zotero.sqlite',
  better_bibtex_db_path = '~/Zotero/better-bibtex.sqlite',
  zotero_storage_path = '~/Zotero/storage',
  pdf_opener = nil,
  collection = nil,
  picker = {
    with_icons = true,
    hlgroups = {
      icons = 'SpecialChar',
      author_year = 'Comment',
      title = 'Title',
    },
  },
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
    asciidoc = {
      insert_key_formatter = function(citekey)
        return 'cite:[' .. citekey .. ']'
      end,
      locate_bib = bib.locate_asciidoc_bib,
    },
    typst = {
      insert_key_formatter = function(citekey)
        return '@' .. citekey
      end,
      locate_bib = bib.locate_typst_bib,
    },
    org = {
      insert_key_formatter = function(citekey)
        return '[cite:@' .. citekey .. ']'
      end,
      locate_bib = bib.locate_org_bib,
    },
    default = {
      insert_key_formatter = function(citekey)
        return '@' .. citekey
      end,
      locate_bib = bib.locate_quarto_bib,
    },
  },
}

M.config = default_opts

---@param opts Zotero.Configuration User configuration
M.setup = function(opts)
  M.config = vim.tbl_deep_extend('force', default_opts, opts or {})
end

---Gets available attachments for Zotero biliography item
---@param item table Zotero bilbiography item
local function get_attachment_options(item)
  local options = {}
  -- Add option to open PDF...
  if item.attachment and item.attachment.path then
    table.insert(options, {
      type = 'pdf',
      path = item.attachment.path,
      link_mode = item.attachment.link_mode,
    })
  end
  -- DOI...
  if item.DOI then
    table.insert(options, { type = 'doi', url = 'https://doi.org/' .. item.DOI })
  end
  -- and option to open entry in Zotero.
  table.insert(options, { type = 'zotero', key = item.key })
  return options
end

---Opens URL of Zotero item
---@param url string The URL to open
---@param filetype string|nil Filetype of URL to open (defaults to system's opener program)
local function open_url(url, filetype)
  local open_cmd
  if filetype == 'pdf' and M.config.pdf_opener then
    -- Use the custom PDF opener if specified
    vim.notify('[zotero] Opening PDF with: ' .. M.config.pdf_opener .. ' ' .. vim.fn.shellescape(url), vim.log.levels.INFO)
    vim.fn.jobstart({ M.config.pdf_opener, url }, { detach = true })
  elseif vim.fn.has 'win32' == 1 then
    open_cmd = 'start'
  elseif vim.fn.has 'macunix' == 1 then
    open_cmd = 'open'
  else -- Assume Unix
    open_cmd = 'xdg-open'
  end
  vim.notify('[zotero] Opening URL with: ' .. open_cmd .. ' ' .. vim.fn.shellescape(url), vim.log.levels.INFO)
  vim.fn.jobstart({ open_cmd, url }, { detach = true })
end

---Opens item in Zotero
---@param item_key table The key of the Zotero bibliography item to open
local function open_in_zotero(item_key)
  local zotero_url = 'zotero://select/library/items/' .. item_key
  open_url(zotero_url)
end

---Opens attachments for a Zotero bibliography item
---@param item table The Zotero bibliography item containing attachment information
local function open_attachment(item)
  local options = get_attachment_options(item)

  local function execute_option(choice)
    if choice.type == 'pdf' then
      local file_path = choice.path
      if choice.link_mode == 1 then -- 1 typically means stored file
        local zotero_storage = vim.fn.expand(M.config.zotero_storage_path)
        -- Remove the ':storage' prefix from the path
        file_path = file_path:gsub('^storage:', '')
        -- Use a wildcard to search for the PDF file in subdirectories
        local search_path = zotero_storage .. '/*/' .. file_path
        local matches = vim.fn.glob(search_path, true, true) -- Returns a list of matching files
        if #matches > 0 then
          file_path = matches[1] -- Use the first match
        else
          vim.notify('[zotero] File not found: ' .. search_path, vim.log.levels.ERROR)
          return
        end
      end
      -- Debug: Print the full path
      vim.notify('[zotero] Attempting to open PDF: ' .. file_path, vim.log.levels.INFO)
      if file_path ~= 0 then
        open_url(file_path, 'pdf')
      else
        vim.notify('[zotero] File not found: ' .. file_path, vim.log.levels.ERROR)
      end
    elseif choice.type == 'doi' then
      vim.ui.open(choice.url)
    elseif choice.type == 'zotero' then
      open_in_zotero(choice.key)
    end
  end

  if #options == 1 then
    -- If there's only one option, execute it immediately
    execute_option(options[1])
  elseif #options > 1 then
    -- If there are multiple options, use ui.select

    vim.ui.select(options, {
      prompt = 'Choose action:',
      format_item = function(option)
        if option.type == 'pdf' then
          return 'Open PDF'
        elseif option.type == 'doi' then
          return 'Open DOI link'
        elseif option.type == 'zotero' then
          return 'Open in Zotero'
        end
      end,
    }, execute_option)
  else
    -- If there are no options, notify the user
    vim.notify('[zotero] No attachments or links available for this item', vim.log.levels.INFO)
  end
end

---Gets items from database
---@return table items Zotero bilbiography item
local get_items = function(collection)
  local success = database.connect(M.config)
  if success then
    return database.get_items(collection)
  else
    return {}
  end
end

---Extract year for date entry
---@param entry table Citation entry to insert
---@param insert_key_fn function Function that formats citation entry
---@param locate_bib_fn function Functoin that locate references bib file
local insert_entry = function(entry, insert_key_fn, locate_bib_fn)
  -- Insert selected citation in file
  local citekey = entry.value.citekey
  local insert_key = insert_key_fn(citekey)
  vim.api.nvim_put({ insert_key }, '', false, true)

  -- Get bib file path
  local bib_path = nil
  if type(locate_bib_fn) == 'string' then
    bib_path = locate_bib_fn
  elseif type(locate_bib_fn) == 'function' then
    bib_path = locate_bib_fn()
  end
  if bib_path == nil then
    vim.notify_once('[zotero] Could not find a bibliography file', vim.log.levels.WARN)
    return
  end
  bib_path = vim.fn.expand(bib_path)

  -- Check if bib file exists at bib_path
  local ok, lines = pcall(io.lines, bib_path)
  if not ok then
    if vim.fn.confirm("Bibliography file missing. Create '" .. bib_path .. "'?", '&Yes\n&No', 1) == 1 then
      vim.fn.writefile({}, bib_path)
      lines = io.lines(bib_path)
    end
  end

  -- Check if citation has already been placed in bib file at bib_path
  for line in lines do
    if string.match(line, '^@') and string.match(line, citekey) then
      return
    end
  end

  -- Otherwise, append the entry to the bib file at bib_path
  local bib_entry = bib.entry_to_bib_entry(entry)
  local file = io.open(bib_path, 'a')
  if file == nil then
    vim.notify('[zotero] Could not open ' .. bib_path .. ' for appending', vim.log.levels.ERROR)
    return
  end
  file:write(bib_entry)
  file:close()
  vim.print('wrote ' .. citekey .. ' to ' .. bib_path)
end

---Extract year for date entry
---@param date string Date to parse
---@return string year Year of date entry or ' ¿? ' is not found
local function extract_year(date)
  local year = date:match '(%d%d%d%d)'
  if year ~= nil then
    return year
  else
    return ' ¿? '
  end
end

local function make_entry(pre_entry)
  -- Process entry
  local creators = pre_entry.creators or {}
  local author = creators[1] or {}
  local last_name = author.lastName or 'NA'
  local year = pre_entry.year or pre_entry.date or 'NA'
  year = extract_year(year)
  pre_entry.year = year

  -- Check if entry has attachments
  local options = get_attachment_options(pre_entry)
  local empty_icon = ' '
  local icon_tbl = { empty_icon, empty_icon, empty_icon }
  for _, entry in ipairs(options) do
    if entry.type == 'zotero' then
      icon_tbl[1] = M.config.picker.with_icons and '' or 'Z'
    elseif entry.type == 'doi' then
      icon_tbl[2] = M.config.picker.with_icons and '󰖟' or 'D'
    elseif entry.type == 'pdf' then
      icon_tbl[3] = M.config.picker.with_icons and '󰈙' or 'P'
    end
  end
  local icon = table.concat(icon_tbl, '')

  -- Create display maker
  local displayer = entry_display.create {
    separator = ' ',
    items = {
      { width = 3 },
      { width = 24, right_justify = true },
      { remaining = true },
    },
  }

  local function make_display(_)
    return displayer {
      { icon, M.config.picker.hlgroups.icons },
      { last_name .. ', ' .. year, M.config.picker.hlgroups.author_year },
      { pre_entry.title, M.config.picker.hlgroups.title },
    }
  end

  -- Return entry maker
  local ordinal = string.format('%s %s %s %s', icon, last_name, year, pre_entry.title)
  return {
    value = pre_entry,
    display = make_display,
    ordinal = ordinal,
    preview_command = function(entry, bufnr)
      local bib_entry = bib.entry_to_bib_entry(entry)
      local lines = vim.split(bib_entry, '\n')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value('filetype', 'bibtex', { buf = bufnr })
    end,
  }
end

---Main entry point of the picker
---@param opts Zotero.Configuration User configuration
M.picker = function(opts)
  opts = opts or {}
  local ft_options = M.config.ft[vim.bo.filetype] or M.config.ft.default --[[@as Zotero.FileType]]
  pickers
    .new(opts, {
      prompt_title = 'Zotero library',
      finder = finders.new_table {
        results = get_items(M.config.collection),
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
