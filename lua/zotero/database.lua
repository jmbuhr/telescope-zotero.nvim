local sqlite = require 'sqlite.db'

local db_path = '~/Zotero/zotero.sqlite'
local better_bibtex_db_path = '~/Zotero/better-bibtex.sqlite'

local M = {}

local function connect(path)
  path = vim.fn.expand(path)
  local ok, db = pcall(sqlite.open, sqlite, 'file:' .. path .. '?immutable=1', { open_mode = 'ro' })
  if ok then
    return db
  else
    vim.notify_once(('[zotero] could not open database at %s.'):format(path))
    return nil
  end
end

M.db = connect(db_path)

M.bbt = connect(better_bibtex_db_path)

local query_bbt = [[
  SELECT
    itemKey, citationKey
  FROM
    citationkey
]]

local query_items = [[
    SELECT
      DISTINCT items.key, items.itemID,
      fields.fieldName,
      parentItemDataValues.value,
      itemTypes.typeName
    FROM
      items
      INNER JOIN itemData ON itemData.itemID = items.itemID
      INNER JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
      INNER JOIN itemData as parentItemData ON parentItemData.itemID = items.itemID
      INNER JOIN itemDataValues as parentItemDataValues ON parentItemDataValues.valueID = parentItemData.valueID
      INNER JOIN fields ON fields.fieldID = parentItemData.fieldID
      INNER JOIN itemTypes ON itemTypes.itemTypeID = items.itemTypeID
    ]]

local query_creators = [[
    SELECT
      DISTINCT items.key,
      creators.firstName,
      creators.lastName,
      itemCreators.orderIndex,
      creatorTypes.creatorType
    FROM
      items
      INNER JOIN itemData ON itemData.itemID = items.itemID
      INNER JOIN itemCreators ON itemCreators.itemID = items.itemID
      INNER JOIN creators ON creators.creatorID = itemCreators.creatorID
      INNER JOIN creatorTypes ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
    ]]

function M.get_items()
  local items = {}
  local raw_items = {}
  local sql_data = M.db:eval(query_items)
  local sql_data_creators = M.db:eval(query_creators)
  local bbt_data = M.bbt:eval(query_bbt)

  local bbt_citekeys = {}
  for _, v in pairs(bbt_data) do
    bbt_citekeys[v.itemKey] = v.citationKey
  end

  for _, v in pairs(sql_data) do
    if raw_items[v.key] == nil then
      raw_items[v.key] = { creators = {} }
    end
    raw_items[v.key][v.fieldName] = v.value
    raw_items[v.key].itemType = v.typeName
  end
  for _, v in pairs(sql_data_creators) do
    if raw_items[v.key] ~= nil then
      raw_items[v.key].creators[v.orderIndex + 1] = { firstName = v.firstName, lastName = v.lastName, creatorType = v.creatorType }
    end
  end
  for key, item in pairs(raw_items) do
    local citekey = bbt_citekeys[key]
    if citekey ~= nil then
      item.citekey = citekey
      table.insert(items, item)
    end
  end
  return items
end

return M
