# telescope-zotero.nvim

List references from your local [Zotero](https://www.zotero.org/) library and add them to a bib file.

<div align="center">
<img width="912" height="740" alt="Telescope zotero" src="https://github.com/user-attachments/assets/ea7e84c9-3d36-467c-88e9-39bb0f4d9bb5" />
  <p><em>Telescope zotero picker</em></p>
</div>

<div align="center">
  <img width="912" height="740" alt="Open entry propmt" src="https://github.com/user-attachments/assets/db759bfb-6239-4d39-b797-9e19d99967c2" />
  <p><em>Open entry prompt (Control-O over the current entry)</em></p>
</div>

This does **not** provide autompletion in the document itself, as this is handled by https://github.com/jmbuhr/cmp-pandoc-references
for entries already in `references.bib`. The intended workflow separates already used references from new ones imported from Zotero
via this new plugin.

## Requirements

- [Zotero](https://www.zotero.org/)
- [Better Bib Tex](https://retorque.re/zotero-better-bibtex/)

## Setup

Add to your telescope config, e.g. in lazy.nvim

```lua
{
  'nvim-telescope/telescope.nvim',
  dependencies = {
    -- your other telescope extensions
    -- ...
    {
      'jmbuhr/telescope-zotero.nvim',
      dependencies = {
        { 'kkharji/sqlite.lua' },
      },
      -- options:
      -- to use the default opts:
      opts = {},
      -- to configure manually:
      -- config = function
      --   require'zotero'.setup{ <your options> }
      -- end,
    },
  },
  config = function()
    local telescope = require 'telescope'
    -- other telescope setup
    -- ...
    telescope.load_extension 'zotero'
  end
},
```

Default options:
```lua
---@type Zotero.Configuration
{
  -- File system options
  zotero_db_path        = '~/Zotero/zotero.sqlite',
  better_bibtex_db_path = '~/Zotero/better-bibtex.sqlite',
  zotero_storage_path   = '~/Zotero/storage',
  pdf_opener            = nil,
  collection            = nil,
  on_selection          = nil,

  -- Picker options
  picker = {
    with_icons = true,
    hlgroups = {
      icons       = 'SpecialChar',
      author_date = 'Comment',
      title       = 'Title',
    },
  },

  -- Filetype options (refer to next section)
  ft = { ... }
}
```

## Supported filetypes

`telescope-zotero.nvim` supports formatting and references detection for the following
filetypes:

| Filetype | Format | Reference (fallback) |
|----------|--------|---------------------|
| Quarto | `bibliography: <path>` | N/A |
| AsciiDoc | `:bibliography-database: <path>` or `:bibtex-file: <path>` | `references.bib` |
| TeX/LaTeX | `\bibliography{<path>}` or `\addbibresource{<path>}` | N/A |
| Typst | `#bibliography(<path>)` | `references.bib` |
| Org | `#+BIBLIOGRAPHY: <path>` or `#+bibliography: <path>` | `references.bib` |

For adding support for your filetype, you can add it to the `ft` table found in the options.
Entries in the table accept two parameters:

- `insert_key_formatter`, a function that converts a `citekey` into a citation.
- `locate_bib`, a function that locates the references bib file used in the current buffer.

For example, we can add support for `text` filetype as follows:
```lua
opts = {
  fts = {
    text = {
      insert_key_formatter = function(citekey)
        return '[citation:' .. citekey .. ']'
      end,
      locate_bib = function()
        -- You function that locates the reference file in the current buffer
      end
    },
  },
}
```

For adding support for a specific filetype, please open a PR request.

## Running custom actions on selection

If you need to perform extra work when an entry is chosen (for example, generating an Obsidian-style note) you can supply an `on_selection` callback in `setup` or pass it ad-hoc when invoking the picker. The callback receives the full Zotero entry table and can return either a string to insert or a table with an `insert_text` field (plus any other metadata you want to surface).

```lua
require('zotero').setup {
  on_selection = function(entry)
    local note_dir = vim.fn.expand '~/Notes/Zotero'
    vim.fn.mkdir(note_dir, 'p')

    local title = entry.title or entry.citekey
    local authors = {}
    for _, creator in ipairs(entry.creators or {}) do
      if creator.lastName then
        local name = creator.lastName
        if creator.firstName then
          name = creator.firstName .. ' ' .. name
        end
        table.insert(authors, name)
      end
    end

    local note_path = string.format('%s/%s.md', note_dir, entry.citekey)
    local lines = {
      ('# %s (%s)'):format(title, entry.year or ''),
      '',
      ('- Authors: %s'):format(table.concat(authors, ', ')),
      ('- Citekey: %s'):format(entry.citekey),
      '',
      '## Summary',
      '',
    }
    vim.fn.writefile(lines, note_path)

    return {
      insert_text = '@' .. entry.citekey,
      note_path = note_path,
    }
  end,
}
```

A returned string acts as the text inserted at the cursor. Returning a table allows you to provide `insert_text` and optional metadata such as `note_path`, which will be echoed as an informational notification.

To keep the default picker untouched and run the note-creation flow only on demand, pass `on_selection` when calling the extension:

```lua
local telescope = require 'telescope'

vim.keymap.set('n', '<leader>fz', telescope.extensions.zotero.zotero, { desc = '[z]otero' })

vim.keymap.set('n', '<leader>fn', function()
  telescope.extensions.zotero.zotero {
    on_selection = function(entry)
      local note_dir = vim.fn.expand '~/Notes/Zotero'
      vim.fn.mkdir(note_dir, 'p')

      local note_path = string.format('%s/%s.md', note_dir, entry.citekey)
      vim.fn.writefile({ '# ' .. (entry.title or entry.citekey) }, note_path)

      return {
        insert_text = '@' .. entry.citekey,
        note_path = note_path,
      }
    end,
  }
end, { desc = 'Zotero note' })
```

## Demo

Video (https://www.youtube.com/watch?v=_o5SkTW67do):

[![Link to a YouTube video explaining the telescope-zotero extension](https://img.youtube.com/vi/_o5SkTW67do/0.jpg)](https://www.youtube.com/watch?v=_o5SkTW67do)

## Inspiration

This extension is inspired by the following plugins that all do an amazing job, but not quite what I need.
Depending on your needs, you should take a look at those:

- [zotcite](https://github.com/jalvesaq/zotcite) provides omnicompletion for zotero items in Quarto, Rmarkdown etc., but requires additional dependencies and uses a custom pandoc lua filter instead of a references.bib file
- [zotex.nvim](https://github.com/tiagovla/zotex.nvim) is very close, but as a nvim-cmp completion source, which doesn't fit
  with the intended separation of concerns.

Special Thanks to @kkharji for the `sqlite.lua` extension!
