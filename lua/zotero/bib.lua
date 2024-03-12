-- (Crudely) Locates the bibliography

local M = {}
M.cached_bib = nil

M.locate_bib = function()
  if M.cached_bib then
    return M.cached_bib
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    local location = string.match(line, [[bibliography:[ "']*([%w./%-\]+)["' ]*]])
    if location then
      M.cached_bib = location
      return location
    end
  end
  -- no bib locally defined
  -- test for quarto project-wide definition
  local fname = vim.api.nvim_buf_get_name(0)
  local root = require('lspconfig.util').root_pattern '_quarto.yml'(fname)
  if root then
    local file = root .. '/_quarto.yml'
    for line in io.lines(file) do
      local location = string.match(line, 'bibliography: (%g+)')
      if location then
        M.cached_bib = location
        return location
      end
    end
  end
end

M.entry_to_bib_entry = function(entry)
  local bib_entry = '@'
  local item = entry.value
  local citekey = item.citekey
  if not citekey then
    citekey = item.citekey
  end
  bib_entry = bib_entry .. item.itemType .. '{' .. citekey .. ',\n'
  for k, v in pairs(item) do
    if k == 'creators' then
      bib_entry = bib_entry .. '  author = {'
      for _, creator in ipairs(v) do
        bib_entry = bib_entry .. creator.lastName .. ', ' .. creator.firstName .. ' and '
      end
      bib_entry = string.sub(bib_entry, 1, -6) .. '},\n'
    elseif k == 'citekey' then
      -- do nothing
    elseif k == 'itemType' then
      -- do nothing
    else
      bib_entry = bib_entry .. '  ' .. k .. ' = {' .. v .. '},\n'
    end
  end
  bib_entry = bib_entry .. '}\n'
  return bib_entry
end

return M
