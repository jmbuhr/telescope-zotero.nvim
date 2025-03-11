-- (Crudely) Locates the bibliography
local Path = require 'plenary.path' -- delete if not using get_bib_path_plenary

local M = {}

M.quarto = {}
M.tex = {}
M['quarto.cached_bib'] = nil

local function get_absolute_path(yaml_bib)
  local bufnr = vim.api.nvim_get_current_buf()
  local bufpath = vim.api.nvim_buf_get_name(bufnr)
  local dir = vim.fn.fnamemodify(bufpath, ':h')
  return vim.fs.joinpath(dir, yaml_bib)
end

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
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    -- ignore commented bibliography
    local comment = string.match(line, '^%%')
    if not comment then
      local location = string.match(line, [[\bibliography{[ "']*([^'"\{\}]+)["' ]*}]])
      if location then
        return location .. '.bib'
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

--- Resolves bibliography file path from string or function
--- @param locate_bib_fn string|function Path or function that returns path
--- @return string|nil Absolute path to bibliography file or nil if not found
M.get_bib_path = function(locate_bib_fn)
  local initial_bib = nil
  -- Get path string from function or use directly
  if type(locate_bib_fn) == 'string' then
    initial_bib = locate_bib_fn
  elseif type(locate_bib_fn) == 'function' then
    initial_bib = locate_bib_fn()
  end
  -- return nil if no matches
  if initial_bib == nil then
    return nil
  end
  -- Try direct path first and return an absolute path if readable
  if vim.fn.filereadable(initial_bib) == 1 then
    return vim.fn.fnamemodify(initial_bib, ':p')
  end
  -- Use buffer directory to try and resolve relative path
  local buf_dir = vim.fn.expand '%:p:h'
  local full_path = buf_dir .. '/' .. initial_bib
  -- return an abosulte path if readable
  if vim.fn.filereadable(full_path) == 1 then
    return vim.fn.fnamemodify(full_path, ':p')
  end
  -- if no readable file found return nil
  return nil
end

-- as above; arguably more robust but requires external dependencies
M.get_bib_path_plenary = function(locate_bib_fn)
  local initial_bib = nil
  if type(locate_bib_fn) == 'string' then
    initial_bib = locate_bib_fn
  elseif type(locate_bib_fn) == 'function' then
    initial_bib = locate_bib_fn()
  end
  if initial_bib then
    local bib_path = Path:new(initial_bib)
    if bib_path:is_file() then
      return bib_path:absolute()
    else
      local abs_path = Path:new(get_absolute_path(initial_bib))
      if abs_path:is_file() then
        return abs_path:absolute()
      else
        return nil
      end
    end
  end
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
