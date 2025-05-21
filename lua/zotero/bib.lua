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
  local root = require('lspconfig.util').root_pattern '_quarto.yml'(fname)
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
