-- (Crudely) Locates the bibliography

local M = {}

M.quarto = {}
M.tex = {}
M['quarto.cached_bib'] = nil

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
  -- TODO: Avoid infinite loop by putting paths checked in a HashMap
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

local function locate_tex_bib_of_file(tex_file)
  -- 1. Check if bibliography is included in this file
  local tex_file_dir = vim.fn.fnamemodify(tex_file, ":h")
  local tex_lines = vim.fn.readfile(tex_file)
  for _, line in ipairs(tex_lines) do
    -- ignore commented bibliography
    local comment = string.match(line, '^%%')
    if not comment then
      local location = string.match(line, [[\bibliography{[ "']*([^'"\{\}]+)["' ]*}]])
      if location then
        return tex_file_dir .. '/' .. location .. '.bib'
      end
      -- checking for biblatex
      location = string.match(line, [[\addbibresource{[ "']*([^'"\{\}]+)["' ]*}]])
      if location then
        -- addbibresource optionally allows you to add .bib
        return tex_file_dir .. '/' .. location:gsub('.bib', '') .. '.bib'
      end
    end
  end

  -- 2. Check if this is the main tex file, i.e. it contains \begin{document} and \end{document}, if not, recurse to the file that includes this one
  for _, line in ipairs(tex_lines) do
    -- stop searching if we hit begin or end document
    local begin_doc = string.match(line, [[\begin{document}]])
    local end_doc = string.match(line, [[\end{document}]])
    if begin_doc or end_doc then
      if begin_doc and end_doc then
        return tex_file_dir .. '/references.bib'
      end
      print("Warning: Found only one of \\begin{document} or \\end{document} in " .. tex_file)
      -- return tex_file_dir .. '/references.bib'
    end
  end

  -- If no bib include was found in current file, try to find the main tex file (asssuming project is in git repo),
  -- searching backwards for include until we hit begin/end `document`.
  -- Then do the same as above to extract the file, or default to `references.bib` in the root repo dir
  -- 1.a) Find root dir from `git rev-parse --show-toplevel`
  local root_dir = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  -- 1.b) Else if this is not a git repo, default repo_dir to the dirname of the current file
  if not root_dir or root_dir == '' then
    root_dir = tex_file_dir
  end
  -- 2. Search for all tex files, using `find`
  local tex_files = vim.fn.systemlist('find ' .. root_dir .. ' -type f -name "*.tex"')
  for _,new_tex_file in ipairs(tex_files) do
    -- 3. Get relative path between tex_file and included_file
    local new_tex_file_dir = vim.fn.fnamemodify(tex_file, ":h")
    local relative_path = vim.fn.systemlist('realpath --relative-to=' .. vim.fn.shellescape(new_tex_file_dir) .. ' ' .. vim.fn.shellescape(tex_file))[1]
    -- Only proceed if relative_path is not empty and it only goes down in the directory tree
    if not relative_path or relative_path == "" or string.match(relative_path, "^%.%./") then
      -- print("Skipping " .. new_tex_file .. " because it is not in a subdirectory of " .. new_tex_file_dir)
      goto continue
    end

    -- 4. Search for \input in tex_file and if it contains basename_noextension
    local basename_noextension = vim.fn.fnamemodify(relative_path, ":r")
    local new_tex_lines = vim.fn.readfile(new_tex_file)
    for _, line in ipairs(new_tex_lines) do
      local include = string.match(line, [[\input{[ "']*([^'"\{\}]+)["' ]*}]])
      -- 5. Recursively search for bibliography in files that are including the callee
      if include and include == basename_noextension then
        local reference_location = locate_tex_bib_of_file(new_tex_file)
        if reference_location then
          return reference_location
        end
      end
    end
    ::continue::
  end

  return nil
end

M.locate_tex_bib = function()
  local tex_file = vim.fn.expand("%:p")
  local bib_file = locate_tex_bib_of_file(tex_file)
  if bib_file then
    return bib_file
  end
  return tex_file_dir .. '/references.bib'
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
