local finders = require 'telescope.finders'
local pickers = require 'telescope.pickers'
local previewers = require 'telescope.previewers'
local conf = require('telescope.config').values
local action_state = require 'telescope.actions.state'
local actions = require 'telescope.actions'
local bib = require 'zotero.bib'
local database = require 'zotero.database'

local M = {}

local default_annotation_color_headings = {
  ['#ffd400'] = '## Key Points', -- Yellow
  ['#ff6666'] = '## Background', -- Red / Pink
  ['#5fb236'] = '## Hypothesis / Positive', -- Green
  ['#2ea8e5'] = '## Methods / Process', -- Blue
  ['#a28ae5'] = '## Results / Data', -- Purple
  ['#e56eee'] = '## Conclusions / Questions', -- Magenta
  ['#f19837'] = '## Implications / ToDo', -- Orange
  ['#aaaaaa'] = '## Further Reading / Misc', -- Grey
  -- Zotero default highlight color (if different from #ffd400) might need adding:
  ['#ffde5c'] = '## Key Points', -- Another common Yellow in some versions?
  -- Add mappings for other Zotero default colors if needed (e.g., drawings)
}

local default_opts = {
  zotero_db_path = '~/Zotero/zotero.sqlite',
  better_bibtex_db_path = '~/Zotero/better-bibtex.sqlite',
  zotero_storage_path = '~/Zotero/storage',
  pdf_opener = nil,
  annotation_color_headings = default_annotation_color_headings,
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
  opts = opts or {}
  -- Use deep extend to merge user options with defaults
  -- 'force' ensures nested tables like annotation_color_headings are merged, not replaced entirely.
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(default_opts), opts)

  -- Normalize the keys (colors) in the final annotation_color_headings map to lowercase
  -- This handles potential inconsistencies like #FFD400 vs #ffd400
  local normalized_headings = {}
  if M.config.annotation_color_headings and type(M.config.annotation_color_headings) == 'table' then
    for color, heading in pairs(M.config.annotation_color_headings) do
      if type(color) == 'string' and type(heading) == 'string' then
        normalized_headings[string.lower(color)] = heading
      end
    end
  end
  M.config.annotation_color_headings = normalized_headings

  -- Optional: Print effective config for debugging
  -- print(vim.inspect(M.config.annotation_color_headings))
end

local function get_attachment_options(item)
  local options = {}
  if item.attachment and item.attachment.path then
    table.insert(options, {
      type = 'pdf',
      path = item.attachment.path,
      link_mode = item.attachment.link_mode,
    })
  end
  if item.DOI then
    table.insert(options, { type = 'doi', url = 'https://doi.org/' .. item.DOI })
  end
  -- Add option to open in Zotero
  table.insert(options, { type = 'zotero', key = item.key })
  return options
end

local function open_url(url, file_type)
  local open_cmd
  if file_type == 'pdf' and M.config.pdf_opener then
    -- Use the custom PDF opener if specified
    vim.notify('Opening PDF with: ' .. M.config.pdf_opener .. ' ' .. vim.fn.shellescape(url), vim.log.levels.INFO)
    vim.fn.jobstart({ M.config.pdf_opener, url }, { detach = true })
  elseif vim.fn.has 'win32' == 1 then
    open_cmd = 'start'
  elseif vim.fn.has 'macunix' == 1 then
    open_cmd = 'open'
  else -- Assume Unix
    open_cmd = 'xdg-open'
  end
  vim.notify('Opening URL with: ' .. open_cmd .. ' ' .. vim.fn.shellescape(url), vim.log.levels.INFO)
  vim.fn.jobstart({ open_cmd, url }, { detach = true })
end
local function open_in_zotero(item_key)
  local zotero_url = 'zotero://select/library/items/' .. item_key
  open_url(zotero_url)
end

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
          vim.notify('File not found: ' .. search_path, vim.log.levels.ERROR)
          return
        end
      end
      -- Debug: Print the full path
      vim.notify('Attempting to open PDF: ' .. file_path, vim.log.levels.INFO)
      if file_path ~= 0 then
        open_url(file_path, 'pdf')
      else
        vim.notify('File not found: ' .. file_path, vim.log.levels.ERROR)
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
    vim.notify('No attachments or links available for this item', vim.log.levels.INFO)
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

  -- check if is already in the bib file
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
  local icon = ''
  if #options > 2 then
    icon = ' ' -- Icon for both PDF and DOI available
  elseif #options == 2 then
    icon = options[1].type == 'pdf' and '󰈙 ' or '󰖟 '
  else
    icon = ' ' -- Two spaces for blank icon
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

local function display_annotations(annotations, item)
  local lines = { '# Annotations for: ' .. (item.title or item.citekey or item.key), '' } -- Main Title
  local color_headings_map = M.config.annotation_color_headings or {} -- Get the normalized map
  local citekey = item.citekey or item.key -- Get the citation key for metadata

  if #annotations == 0 then
    table.insert(lines, '> No annotations found for this item.')
  else
    local current_page = nil
    -- Ensure annotations are sorted by page and then position within the page
    table.sort(annotations, function(a, b)
      local page_a = tonumber(a.pageLabel) or -1
      local page_b = tonumber(b.pageLabel) or -1
      if page_a ~= page_b then
        return page_a < page_b
      end
      -- Use sortIndex which usually reflects Zotero's internal order
      return (a.sortIndex or -1) < (b.sortIndex or -1)
    end)

    for _, ann in ipairs(annotations) do
      -- Normalize color key for lookup
      local color_key = ann.color and string.lower(ann.color) or nil

      -- --- Page Separator and Heading ---
      if ann.pageLabel ~= current_page then
        if current_page ~= nil then
          table.insert(lines, '---') -- Horizontal rule between pages
          table.insert(lines, '')
        end
        table.insert(lines, string.format('### Page %s', ann.pageLabel or 'N/A')) -- Page heading
        table.insert(lines, '')
        current_page = ann.pageLabel
      end

      -- --- Color-Based Heading ---
      local custom_heading = color_key and color_headings_map[color_key] or nil
      if custom_heading then
        table.insert(lines, custom_heading)
        -- table.insert(lines, '') -- Optional extra space after heading? Maybe not needed now.
      end

      -- --- Prepare Metadata String ---
      local page_str = ann.pageLabel and #ann.pageLabel > 0 and ('p. ' .. ann.pageLabel) or nil
      -- Let's keep the author too, as it can be useful
      local author_str = ann.authorName and #ann.authorName > 0 and ('by ' .. ann.authorName) or nil

      local metadata_parts = {}
      if citekey then
        table.insert(metadata_parts, '@' .. citekey)
      end
      if page_str then
        table.insert(metadata_parts, page_str)
      end
      if author_str then
        table.insert(metadata_parts, author_str)
      end -- Added author back

      -- Format: " [@citekey, p. X, by Author]" or similar variations if parts are missing
      local metadata_string = #metadata_parts > 0 and (' [' .. table.concat(metadata_parts, ', ') .. ']') or ''

      -- --- Annotation Details (Comment First) ---
      local annotation_lines_added = false -- Track if we added anything for this ann

      -- 1. Process Comment (if it exists)
      if ann.comment and #ann.comment > 0 then
        -- Format as: "- *Comment text* [@citekey, p. X, by Author]"
        table.insert(lines, string.format('- *%s*%s', ann.comment, metadata_string))
        annotation_lines_added = true
      end

      -- 2. Process Highlight Text (if it exists)
      if ann.text and #ann.text > 0 then
        -- Format as: "> Highlight text [@citekey, p. X, by Author]"
        table.insert(lines, string.format('> %s%s', ann.text, metadata_string))
        annotation_lines_added = true
      end

      -- 3. Handle annotations with neither text nor comment (e.g., drawing/shape)
      if not annotation_lines_added then
        -- Format as: "- *Annotation entry (Type: X, Color: Y)* [@citekey, p. X, by Author]"
        table.insert(
          lines,
          string.format(
            '- *Annotation entry (Type: %s, Color: %s)*%s',
            ann.type or '?',
            color_key or 'N/A',
            metadata_string
          )
        )
        annotation_lines_added = true
      end

      -- Add spacing *after* the complete annotation block (comment+highlight, or standalone)
      if annotation_lines_added then
        table.insert(lines, '') -- Add a blank line after each annotation block for spacing
      end
    end
  end

  -- --- Create and open the floating window (code remains the same) ---
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local width = math.floor(vim.api.nvim_get_option 'columns' * 0.75)
  local height = math.floor(vim.api.nvim_get_option 'lines' * 0.75)
  local row = math.floor((vim.api.nvim_get_option 'lines' - height) / 2)
  local col = math.floor((vim.api.nvim_get_option 'columns' - width) / 2)

  local winid = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = 'Zotero Annotations (' .. (citekey or item.key) .. ')', -- Use citekey in title too
    title_pos = 'center',
  })

  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    'q',
    '<cmd>close<CR>',
    { noremap = true, silent = true, desc = 'Close Annotation Window' }
  )
  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    '<Esc>',
    '<cmd>close<CR>',
    { noremap = true, silent = true, desc = 'Close Annotation Window' }
  )

  if winid then
    vim.api.nvim_set_option_value('conceallevel', 2, { win = winid })
    vim.api.nvim_set_option_value('concealcursor', 'nc', { win = winid })
  end
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

        map('i', '<C-o>', function()
          local entry = action_state.get_selected_entry()
          open_attachment(entry.value)
        end)
        map('n', 'o', function()
          local entry = action_state.get_selected_entry()
          open_attachment(entry.value)
        end)

        -- Add the NEW mapping for annotations (e.g., <C-a>)
        map({ 'i', 'n' }, '<C-a>', function()
          local entry = action_state.get_selected_entry()
          if not entry or not entry.value or not entry.value.key then
            vim.notify('[zotero] Could not get selected item key.', vim.log.levels.WARN)
            return
          end
          local itemKey = entry.value.key
          local item_data = entry.value -- Pass the whole item data for context

          -- Call the database function
          local annotations, err = database.get_annotations(itemKey)

          -- Optional: Close the picker window before showing annotations
          -- actions.close(prompt_bufnr)

          if err then
            -- Notification already handled in get_annotations
            -- vim.notify('[zotero] Failed to get annotations: ' .. err, vim.log.levels.ERROR)
            return
          end

          -- Call the display function
          display_annotations(annotations, item_data)
        end)
        -- End of NEW mapping

        return true
      end,
    })
    :find()
end
return M

