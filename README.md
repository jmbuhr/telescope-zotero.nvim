# telescope-zotero.nvim [WIP]

List references from your local [Zotero](https://www.zotero.org/) library and add them to a bib file.

## Plan

- [ ] open a telescope list with Zotero items.
- [ ] on selection, add the item to the `.bib` file configured in the yaml header of the current quarto document or project.

This does **not** provide autompletion in the document itself, as this is handled by https://github.com/jmbuhr/cmp-pandoc-references
for entries already in `references.bib`. The intended workflow separates already used references from new ones imported from Zotero
via this new plugin.

## Notes

<https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md#introduction>

## Inspiration

This extension is inspired by the following plugins that all do an amazing job, but not quite what I need.
Depending on your needs, you should have a look at those:

- [zotcite](https://github.com/jalvesaq/zotcite) provides omnicompletion for zotero items in Quarto, Rmarkdown etc., but requires additional dependencies and uses a custom pandoc lua filter instead of a references.bib file
- [zotex.nvim](https://github.com/tiagovla/zotex.nvim) is very close, but as a nvim-cmp completion source, which doesn't fit
  with the intended separation of concerns.
