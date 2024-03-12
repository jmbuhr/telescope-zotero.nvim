local sqlite = require 'sqlite.db'

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

M.connected = false
M.connect = function(opts)
  if M.connected then
    return true
  end
  M.db = connect(opts.zotero_db_path)
  M.bbt = connect(opts.better_bibtex_db_path)
  if M.db == nil or M.bbt == nil then
    return false
  end
  M.connected = true
  return true
end

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
  local sql_items = M.db:eval(query_items)
  local sql_creators = M.db:eval(query_creators)
  local sql_bbt = M.bbt:eval(query_bbt)

  if sql_items == nil or sql_creators == nil or sql_bbt == nil then
    vim.notify_once('[zotero] could not query database.', vim.log.levels.WARN, {})
    return {}
  end

  local bbt_citekeys = {}
  for _, v in pairs(sql_bbt) do
    bbt_citekeys[v.itemKey] = v.citationKey
  end

  for _, v in pairs(sql_items) do
    if raw_items[v.key] == nil then
      raw_items[v.key] = { creators = {} }
    end
    raw_items[v.key][v.fieldName] = v.value
    raw_items[v.key].itemType = v.typeName
  end
  for _, v in pairs(sql_creators) do
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
