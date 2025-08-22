-- (Crudely) Locates the bibliography

local M = {}

M.quarto = {}
M.tex = {}
M['quarto.cached_bib'] = nil
M['tex.cached_bib'] = nil

M.locate_quarto_bib = function()
  if M['quarto.cached_bib'] then
    return M['quarto.cached_bib']
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    local location = string.match(line, [[bibliography:[ "']*(.+)["' ]*]])
    if location then
      M['quarto.cached_bib'] = location
      return M['quarto.cached_bib']
    end
  end
  -- no bib locally defined
  -- test for quarto project-wide definition
  local fname = vim.api.nvim_buf_get_name(0)

  -- Iterate up the directory tree to find the _quarto.yml file
  local function find_quarto_root(start_path)
    local current = vim.fn.fnamemodify(start_path, ':p:h')
    local previous = nil
    while current ~= previous do
      local config_file = current .. '/_quarto.yml'
      if vim.fn.filereadable(config_file) == 1 then
        return current
      end
      previous = current
      current = vim.fn.fnamemodify(current, ':h')
    end
    return nil
  end

  local root = find_quarto_root(fname)
  if root then
    local file = root .. '/_quarto.yml'
    for line in io.lines(file) do
      local location = string.match(line, [[bibliography:[ "']*(.+)["' ]*]])
      if location then
        M['quarto.cached_bib'] = location
        return M['quarto.cached_bib']
      end
    end
  end
end

local function resolve_includes(file_path, resolved_lines)
  local lines = vim.fn.readfile(file_path)
  for _, line in ipairs(lines) do
    local include_path = string.match(line, '^include::(.-)%[%]$')
    if include_path then
      local full_path = vim.fn.fnamemodify(include_path, ':p')
      resolve_includes(full_path, resolved_lines)
    else
      table.insert(resolved_lines, line)
    end
  end
end

M.locate_asciidoc_bib = function()
  if M['asciidoc.cached_bib'] then
    return M['asciidoc.cached_bib']
  end

  local current_file = vim.fn.expand '%:p'
  local resolved_lines = {}
  resolve_includes(current_file, resolved_lines)

  local temp_file = vim.fn.tempname()
  vim.fn.writefile(resolved_lines, temp_file)

  for _, line in ipairs(resolved_lines) do
    local location = string.match(line, [[:bibliography-database:[ "']*(.+)["' ]*]])
    if location then
      M['asciidoc.cached_bib'] = location
      return M['asciidoc.cached_bib']
    end
    local location = string.match(line, [[:bibtex-file:[ "']*(.+)["' ]*]])
    if location then
      M['asciidoc.cached_bib'] = location
      return M['asciidoc.cached_bib']
    end
  end

  -- no bib locally defined, default to `references.bib`
  return 'references.bib'
end

M.locate_tex_bib = function()
  if M['tex.cached_bib'] then
    return M['tex.cached_bib']
  end

  -- Helper function
  local function scan_lines(lines)
    for _, line in ipairs(lines) do
      -- ignore commented bibliography
      local comment = string.match(line, '^%%')
      if not comment then
        local location = string.match(line, [[\bibliography{[ "']*([^'"\{\}]+)["' ]*}]])
        if location then
          -- bibliography optionally allows you to add .bib
          return location:gsub('.bib', '') .. '.bib'
        end
        -- checking for biblatex
        location = string.match(line, [[\addbibresource{[ "']*([^'"\{\}]+)["' ]*}]])
        if location then
          -- addbibresource optionally allows you to add .bib
          return location:gsub('.bib', '') .. '.bib'
        end
      end
    end
  end

  -- Scan current buffer
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local bib = scan_lines(buf_lines)
  if bib then
    M._bib_path = bib
    M['tex.cached_bib'] = bib
    return bib
  end

  -- Look for TEX root comment in current buffer
  for _, line in ipairs(buf_lines) do
    local buf_dir = vim.fn.expand '%:p:h'
    local root = line:match '^%%!TEX%s+root%s*=%s*(.+.tex)'

    if root then
      local sep = package.config:sub(1, 1)

      local clean_root = root:gsub('^[/\\]+', ''):gsub('[/\\]+$', ''):gsub('[/\\]', sep)

      local root_abs = buf_dir .. sep .. clean_root
      if vim.fn.filereadable(root_abs) == 1 then
        -- Read root file and scan
        local root_lines = vim.fn.readfile(root_abs)
        bib = scan_lines(root_lines)
        if bib then
          M._bib_path = bib
          M['tex.cached_bib'] = bib
          return bib
        end
        break
      end
    end
  end

  -- Glob for .bib files in cwd
  local cwd = vim.fn.getcwd()
  local files = vim.fn.globpath(cwd, '**/*.bib', false, true)
  if #files == 1 then
    M._bib_path = files[1]
    M['tex.cached_bib'] = files[1]
    return files[1]
  elseif #files > 1 then
    vim.ui.select(files, { prompt = 'Select bibliography file:' }, function(choice)
      if choice then
        M._bib_path = choice
        M['tex.cached_bib'] = choice
        return
      end
    end)
  end

  -- Last resort: prompt explicitly
  local manual = vim.fn.input('Path to bibliography file: ', '', 'file')
  if manual and manual ~= '' then
    M._bib_path = manual
    M['tex.cached_bib'] = manual
    return manual
  end

  return nil
end

M.locate_typst_bib = function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    local location = line:match("^#bibliography%((.+)%)")
    if location then
      return location:sub(2,-2)
    end
  end
  return "references.bib"
end

M.locate_org_bib = function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    local location = line:match("#%+BIBLIOGRAPHY:%s*(.+)") or line:match("#%+bibliography:%s*(.+)")
    if location then
      return location
    end
  end
  return "references.bib"
end

M.entry_to_bib_entry = function(entry)
  local bib_entry = '@'
  local item = entry.value
  local citekey = item.citekey or ''
  bib_entry = bib_entry .. (item.itemType or '') .. '{' .. citekey .. ',\n'
  for k, v in pairs(item) do
    if k == 'creators' then
      bib_entry = bib_entry .. '  author = {'
      local author = ''
      for _, creator in ipairs(v) do
        author = author .. (creator.lastName or '') .. ', ' .. (creator.firstName or '') .. ' and '
      end
      -- remove trailing ' and '
      author = string.sub(author, 1, -6)
      bib_entry = bib_entry .. author .. '},\n'
    elseif k ~= 'citekey' and k ~= 'itemType' and k ~= 'attachment' and type(v) == 'string' then
      bib_entry = bib_entry .. '  ' .. k .. ' = {' .. v .. '},\n'
    end
  end
  bib_entry = bib_entry .. '}\n'
  return bib_entry
end

return M
