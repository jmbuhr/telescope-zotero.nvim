# telescope-zotero.nvim

List references from your local [Zotero](https://www.zotero.org/) library and add them to a bib file.

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

Default options: <https://github.com/jmbuhr/telescope-zotero.nvim/blob/main/lua/zotero/init.lua#L12>

## Demo

Video (https://www.youtube.com/watch?v=_o5SkTW67do):

[![Link to a YouTube video explaining the telescope-zotero extension](https://img.youtube.com/vi/_o5SkTW67do/0.jpg)](https://www.youtube.com/watch?v=_o5SkTW67do)

## Inspiration

This extension is inspired by the following plugins that all do an amazing job, but not quite what I need.
Depending on your needs, you should have a look at those:

- [zotcite](https://github.com/jalvesaq/zotcite) provides omnicompletion for zotero items in Quarto, Rmarkdown etc., but requires additional dependencies and uses a custom pandoc lua filter instead of a references.bib file
- [zotex.nvim](https://github.com/tiagovla/zotex.nvim) is very close, but as a nvim-cmp completion source, which doesn't fit
  with the intended separation of concerns.

Special Thanks to @kkharji for the `sqlite.lua` extension!
