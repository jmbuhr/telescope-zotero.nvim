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
  annotation_grouping = 'chronological', -- Options: 'chronological', 'highlight'
  headings = true, -- Options true or false/ "On" or "Off"
  yaml = true,
  info = true,
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
    vim.notify_once('Could not find a bibliography file', vim.log.levels.WARN)
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

local function generate_yaml_frontmatter(item)
  local lines = { '---' }

  -- Add citekey
  if item.citekey then
    table.insert(lines, 'citekey: ' .. item.citekey)
  end

  -- Add aliases (title with authors)
  if item.title and item.creators and #item.creators > 0 then
    local authors_str = ''
    if item.creators[1] and item.creators[1].lastName then
      authors_str = item.creators[1].lastName
      if #item.creators > 1 and item.creators[2].lastName then
        authors_str = authors_str .. ' & ' .. item.creators[2].lastName
      elseif #item.creators > 1 then
        authors_str = authors_str .. ' et al.'
      end
    end

    local year_str = item.year or ''
    if year_str ~= '' then
      year_str = ' (' .. year_str .. ')'
    end

    table.insert(lines, 'aliases:')
    table.insert(lines, '- "' .. authors_str .. year_str .. ' ' .. item.title .. '"')
  end

  -- Add title
  if item.title then
    table.insert(lines, 'title: "' .. item.title .. '"')
  end

  -- Add authors list
  if item.creators and #item.creators > 0 then
    table.insert(lines, 'authors:')
    for _, creator in ipairs(item.creators) do
      if creator.firstName and creator.lastName then
        table.insert(lines, '- ' .. creator.firstName .. ' ' .. creator.lastName)
      elseif creator.lastName then
        table.insert(lines, '- ' .. creator.lastName)
      end
    end
  end

  -- Add year
  if item.year then
    table.insert(lines, 'year: ' .. item.year)
  end

  -- Add item type
  if item.itemType then
    table.insert(lines, 'item-type: ' .. item.itemType)
  end

  -- Add publisher/journal
  if item.publicationTitle then
    table.insert(lines, 'publisher: "' .. item.publicationTitle .. '"')
  elseif item.publisher then
    table.insert(lines, 'publisher: "' .. item.publisher .. '"')
  end

  -- Add tags if available
  if item.tags and #item.tags > 0 then
    table.insert(lines, 'tags:')
    for _, tag in ipairs(item.tags) do
      table.insert(lines, '- ' .. tag)
    end
  end

  -- Add DOI if available
  if item.DOI then
    table.insert(lines, 'doi: https://doi.org/' .. item.DOI)
  end

  -- Close YAML block
  table.insert(lines, '---')
  table.insert(lines, '') -- Add an empty line after YAML block

  return lines
end

local function format_bibliography(item)
  local bib = ''

  -- Format authors
  local authors = ''
  if item.creators and #item.creators > 0 then
    for i, creator in ipairs(item.creators) do
      if creator.creatorType == 'author' then
        if i > 1 then
          authors = authors .. ', '
        end
        if creator.lastName and creator.firstName then
          authors = authors .. creator.lastName .. ', ' .. creator.firstName:sub(1, 1) .. '.'
        elseif creator.lastName then
          authors = authors .. creator.lastName
        end
      end
    end
  end

  -- Title with proper formatting
  local title = item.title or ''

  -- Publication details
  local publication = item.publicationTitle or item.publisher or ''
  local year = item.year or ''
  local volume = item.volume or ''
  local issue = item.issue or ''
  local pages = item.pages or ''
  local doi = item.DOI or ''

  -- Format based on item type
  if item.itemType == 'journalArticle' then
    bib = authors .. ' (' .. year .. '). ' .. title .. '. *' .. publication .. '*'

    if volume ~= '' then
      bib = bib .. ', *' .. volume .. '*'
      if issue ~= '' then
        bib = bib .. '(' .. issue .. ')'
      end
    end

    if pages ~= '' then
      bib = bib .. ', ' .. pages
    end

    if doi ~= '' then
      bib = bib .. '. [https://doi.org/' .. doi .. '](https://doi.org/' .. doi .. ')'
    end
  else
    -- Default format for other item types
    bib = authors .. ' (' .. year .. '). ' .. title

    if publication ~= '' then
      bib = bib .. '. *' .. publication .. '*'
    end

    if doi ~= '' then
      bib = bib .. '. [https://doi.org/' .. doi .. '](https://doi.org/' .. doi .. ')'
    end
  end

  return bib
end

-- Function to generate formatted Obsidian-style info
local function generate_obsidian_info(item)
  local lines = {}

  -- Start info callout
  table.insert(
    lines,
    '> [!info]- Info 🔗 [**Zotero**](zotero://select/library/items/'
      .. item.key
      .. ')'
      .. (item.DOI and ' | [**DOI**](https://doi.org/' .. item.DOI .. ')' or '')
  )

  -- Add PDF link if available
  if item.attachment and item.attachment.path then
    local path = item.attachment.path
    if item.attachment.link_mode == 1 and item.attachment.folder_name then -- Stored file
      -- Construct a file path - adjust this to match your storage path format
      local storage_path = vim.fn.expand(M.config.zotero_storage_path)
      local pdf_path = 'file://' .. storage_path .. '/' .. item.attachment.folder_name
      table.insert(lines, '> | [**PDF-1**](' .. pdf_path .. ')')
    end
  end

  -- Bibliography
  table.insert(lines, '>')
  table.insert(lines, '>**Bibliography**: ' .. format_bibliography(item))
  table.insert(lines, '> ')

  -- Authors with wiki links
  if item.creators and #item.creators > 0 then
    local authors_links = {}
    for _, creator in ipairs(item.creators) do
      if creator.creatorType == 'author' and creator.firstName and creator.lastName then
        local full_name = creator.firstName .. ' ' .. creator.lastName
        table.insert(authors_links, '[[' .. full_name .. '|' .. full_name .. ']]')
      end
    end
    if #authors_links > 0 then
      table.insert(lines, '> **Authors**::  ' .. table.concat(authors_links, ',  '))
      table.insert(lines, '> ')
    end
  end

  -- Tags
  if item.tags and #item.tags > 0 then
    local tag_str = ''
    for i, tag in ipairs(item.tags) do
      tag_str = tag_str .. '#' .. tag:gsub('%s+', '-')
      if i < #item.tags then
        tag_str = tag_str .. ', '
      end
    end
    table.insert(lines, '> **Tags**: ' .. tag_str)
    table.insert(lines, '> ')
  end

  -- Collections (placeholder, would need additional query)
  table.insert(lines, '> **Collections**:: ')
  table.insert(lines, '>')

  -- Page information
  if item.pages then
    local pages = item.pages
    local first_page, last_page = pages:match '(%d+)%s*%-%s*(%d+)'
    if first_page then
      table.insert(lines, '> **First-page**:: ' .. first_page)
      table.insert(lines, '> ')
      local page_count = tonumber(last_page) - tonumber(first_page) + 1
      table.insert(lines, '> **Page-count**:: ' .. page_count)
      table.insert(lines, '> ')
      -- Calculate estimated reading time (approx 2 minutes per page for academic papers)
      local reading_time = page_count * 2
      table.insert(lines, '> **Reading-time**:: ' .. reading_time .. ' minutes')
    end
  end

  -- Abstract in a collapsible callout
  if item.abstractNote then
    table.insert(lines, '')
    table.insert(lines, '> [!abstract]-')
    table.insert(lines, '> ')
    -- Split abstract by newlines and format each line
    for _, line in ipairs(vim.split(item.abstractNote, '\n')) do
      table.insert(lines, '> ' .. line)
    end
    table.insert(lines, '>')
  end

  return lines
end

local function display_annotations(annotations, item)
  local color_headings_map = M.config.annotation_color_headings or {}
  local grouping_mode = M.config.annotation_grouping or 'chronological'
  local citekey = item.citekey or item.key
  local show_headings = M.config.headings == 'on' or M.config.headings == true
  local show_yaml = M.config.yaml == 'on' or M.config.yaml == true
  local show_info = M.config.info == 'on' or M.config.info == true

  -- Initialize lines as an empty table
  local lines = {}

  if show_yaml then
    -- Add YAML frontmatter to lines
    local yaml_lines = generate_yaml_frontmatter(item)
    for _, line in ipairs(yaml_lines) do
      table.insert(lines, line)
    end
  end

  if show_info then
    -- Add the Obsidian-style info section
    local info_lines = generate_obsidian_info(item)
    for _, line in ipairs(info_lines) do
      table.insert(lines, line)
    end
  end
  -- Add the annotation title
  table.insert(lines, '## Annotations for: ' .. (item.title or item.citekey or item.key))
  table.insert(lines, '') -- Empty line after title

  -- Rest of the function for annotations remains the same

  -- Check if headings should be shown
  -- Check if headings should be shown

  if #annotations == 0 then
    table.insert(lines, '> No annotations found for this item.')
  else
    -- Helper function to format a single annotation entry (comment/highlight/other)
    local function format_single_annotation(ann, metadata_string, color_key)
      local output_lines = {}
      local annotation_lines_added = false

      -- Handle comment with potential newlines
      if ann.comment and #ann.comment > 0 then
        local comment_lines = vim.split(ann.comment, '\n')
        -- Add the first line with metadata
        table.insert(output_lines, string.format('- *%s*%s', comment_lines[1], metadata_string))
        -- Add any additional comment lines with proper indentation
        for i = 2, #comment_lines do
          table.insert(output_lines, string.format('  *%s*', comment_lines[i]))
        end
        annotation_lines_added = true
      end

      -- Handle text with potential newlines
      if ann.text and #ann.text > 0 then
        local text_lines = vim.split(ann.text, '\n')
        -- Add the first line with metadata
        table.insert(output_lines, string.format('> %s%s', text_lines[1], metadata_string))
        -- Add any additional text lines with proper blockquote formatting
        for i = 2, #text_lines do
          table.insert(output_lines, string.format('> %s', text_lines[i]))
        end
        annotation_lines_added = true
      end

      if not annotation_lines_added then
        table.insert(
          output_lines,
          string.format(
            '- *Annotation entry (Type: %s, Color: %s)*%s',
            ann.type or '?',
            color_key or 'N/A',
            metadata_string
          )
        )
        annotation_lines_added = true
      end
      return output_lines, annotation_lines_added
    end

    -- Ensure annotations are always sorted by page/position initially
    table.sort(annotations, function(a, b)
      local page_a = tonumber(a.pageLabel) or -1
      local page_b = tonumber(b.pageLabel) or -1
      if page_a ~= page_b then
        return page_a < page_b
      end
      return (a.sortIndex or -1) < (b.sortIndex or -1)
    end)

    -- ============================================
    --  Mode 1: Group by chronological (Default)
    -- ============================================
    if grouping_mode == 'chronological' then
      local current_page = nil
      for _, ann in ipairs(annotations) do
        local color_key = ann.color and string.lower(ann.color) or nil
        if ann.pageLabel ~= current_page then
          if current_page ~= nil then
            table.insert(lines, '---')
            table.insert(lines, '')
          end
          -- Always show page headers regardless of headings setting
          table.insert(lines, string.format('### Page %s', ann.pageLabel or 'N/A'))
          table.insert(lines, '')
          current_page = ann.pageLabel
        end

        -- Only add color headings if headings are enabled
        if show_headings then
          local custom_heading = color_key and color_headings_map[color_key] or nil
          if custom_heading then
            table.insert(lines, custom_heading)
          end
        end

        local page_str = ann.pageLabel and #ann.pageLabel > 0 and ('p. ' .. ann.pageLabel) or nil
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
        end
        local metadata_string = #metadata_parts > 0 and (' [' .. table.concat(metadata_parts, ', ') .. ']') or ''

        local output_lines, added = format_single_annotation(ann, metadata_string, color_key)
        for _, line_content in ipairs(output_lines) do
          table.insert(lines, line_content)
        end
        if added then
          table.insert(lines, '')
        end
      end

      -- ============================================
      --  Mode 2: Group by Highlight Color
      -- ============================================
    elseif grouping_mode == 'highlight' then
      -- We need to define the color order from default_annotation_color_headings
      -- This ensures annotations are displayed in the same order as the colors were defined
      local color_order = {
        '#ffd400', -- Yellow
        '#ff6666', -- Red / Pink
        '#5fb236', -- Green
        '#2ea8e5', -- Blue
        '#a28ae5', -- Purple
        '#e56eee', -- Magenta
        '#f19837', -- Orange
        '#aaaaaa', -- Grey
        '#ffde5c', -- Alternate Yellow
      }

      -- Create color-to-index mapping for ordering
      local color_index_map = {}
      for idx, color in ipairs(color_order) do
        color_index_map[string.lower(color)] = idx
      end

      -- Map from color to annotations and headings
      local color_annotations_map = {}
      local color_heading_lookup = {}
      local unknown_colors = {}
      local other_annotations = {}

      -- Group annotations by their color
      for _, ann in ipairs(annotations) do
        local color_key = ann.color and string.lower(ann.color) or nil
        if color_key and color_index_map[color_key] then
          if not color_annotations_map[color_key] then
            color_annotations_map[color_key] = {}
            color_heading_lookup[color_key] = color_headings_map[color_key] or ('## Color: ' .. color_key)
          end
          table.insert(color_annotations_map[color_key], ann)
        elseif color_key then
          -- Unknown color but has a color
          if not unknown_colors[color_key] then
            unknown_colors[color_key] = {}
          end
          table.insert(unknown_colors[color_key], ann)
        else
          -- No color information
          table.insert(other_annotations, ann)
        end
      end

      -- Helper function to print a group's content
      local function print_annotation_group(heading, group_annotations)
        -- Only add the heading if headings are enabled
        if show_headings then
          table.insert(lines, heading)
          table.insert(lines, '')
        end

        for _, ann in ipairs(group_annotations) do -- Annotations already sorted by page/index
          local color_key = ann.color and string.lower(ann.color) or nil
          local page_str = ann.pageLabel and #ann.pageLabel > 0 and ('p. ' .. ann.pageLabel) or nil
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
          end
          local metadata_string = #metadata_parts > 0 and (' [' .. table.concat(metadata_parts, ', ') .. ']') or ''

          local output_lines, added = format_single_annotation(ann, metadata_string, color_key)
          for _, line_content in ipairs(output_lines) do
            table.insert(lines, line_content)
          end
          if added then
            table.insert(lines, '')
          end
        end
      end

      -- Print annotations in color order
      local first_group_printed = false

      -- First print annotations in the predefined color order
      for _, color in ipairs(color_order) do
        local color_key = string.lower(color)
        if color_annotations_map[color_key] and #color_annotations_map[color_key] > 0 then
          if first_group_printed then
            table.insert(lines, '---')
            table.insert(lines, '')
          end
          print_annotation_group(color_heading_lookup[color_key], color_annotations_map[color_key])
          first_group_printed = true
        end
      end

      -- Then print annotations with unknown colors
      for color_key, anns in pairs(unknown_colors) do
        if first_group_printed then
          table.insert(lines, '---')
          table.insert(lines, '')
        end
        local heading = color_headings_map[color_key] or ('## Unknown Color: ' .. color_key)
        print_annotation_group(heading, anns)
        first_group_printed = true
      end

      -- Finally print annotations with no color
      if #other_annotations > 0 then
        if first_group_printed then
          table.insert(lines, '---')
          table.insert(lines, '')
        end
        print_annotation_group('## Other Annotations', other_annotations)
      end
    else
      table.insert(lines, string.format('> [Error] Invalid annotation_grouping mode: "%s"', grouping_mode))
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
    title = 'Zotero Annotations (' .. (citekey or item.key) .. ')',
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
          local item_data = entry.value

          -- Call the database function
          local annotations, err = database.get_annotations(itemKey)

          -- Call the display function
          display_annotations(annotations, item_data)
        end)

        return true
      end,
    })
    :find()
end
return M

