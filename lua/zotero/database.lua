local sqlite = require 'sqlite.db'

local M = {}

local function connect(path, optional)
  path = vim.fn.expand(path)
  local ok, db = pcall(sqlite.open, sqlite, 'file:' .. path .. '?immutable=1', { open_mode = 'ro' })
  if ok then
    return db
  else
    if not optional then
      vim.notify_once(('[zotero] could not open database at %s.'):format(path))
    end
    return nil
  end
end

M.connect = function(opts)
  M.db = connect(opts.zotero_db_path, false)
  -- BBT database is optional: Zotero 8+ migrates citation keys into zotero.sqlite
  M.bbt = connect(opts.better_bibtex_db_path, true)
  if M.db == nil then
    return false
  end
  return true
end

local query_bbt = [[
  SELECT
    itemKey, citationKey
  FROM
    citationkey
]]

-- Zotero 8+: citation keys are stored natively in zotero.sqlite
local query_native_citekeys = [[
  SELECT
    items.key AS itemKey,
    itemDataValues.value AS citationKey
  FROM
    items
    INNER JOIN itemData ON itemData.itemID = items.itemID
    INNER JOIN fields ON fields.fieldID = itemData.fieldID
    INNER JOIN itemDataValues ON itemDataValues.valueID = itemData.valueID
  WHERE
    fields.fieldName = 'citationKey'
]]

local function get_query_items(collection)
  if collection == nil then
    return [[
        SELECT
          DISTINCT items.key, items.itemID,
          fields.fieldName,
          parentItemDataValues.value,
          itemTypes.typeName,
          itemAttachments.path AS attachment_path,
          itemAttachments.contentType AS attachment_content_type,
          itemAttachments.linkMode AS attachment_link_mode,
          -- Fetch the folder name from the itemAttachments table
          SUBSTR(itemAttachments.path, INSTR(itemAttachments.path, ':') + 1) AS folder_name
        FROM
          items
          INNER JOIN itemData ON itemData.itemID = items.itemID
          INNER JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
          INNER JOIN itemData as parentItemData ON parentItemData.itemID = items.itemID
          INNER JOIN itemDataValues as parentItemDataValues ON parentItemDataValues.valueID = parentItemData.valueID
          INNER JOIN fields ON fields.fieldID = parentItemData.fieldID
          INNER JOIN itemTypes ON itemTypes.itemTypeID = items.itemTypeID
          LEFT JOIN itemAttachments ON items.itemID = itemAttachments.parentItemID AND itemAttachments.contentType = 'application/pdf'
    ]]
  else
    return [[
        SELECT
          DISTINCT items.key, items.itemID,
          fields.fieldName,
          parentItemDataValues.value,
          itemTypes.typeName,
          itemAttachments.path AS attachment_path,
          itemAttachments.contentType AS attachment_content_type,
          itemAttachments.linkMode AS attachment_link_mode,
          -- Fetch the folder name from the itemAttachments table
          SUBSTR(itemAttachments.path, INSTR(itemAttachments.path, ':') + 1) AS folder_name
        FROM
          items
          INNER JOIN collectionItems ON collectionItems.itemID = items.itemID
          INNER JOIN collections ON collections.collectionID = collectionItems.collectionID
          INNER JOIN itemData ON itemData.itemID = items.itemID
          INNER JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
          INNER JOIN itemData as parentItemData ON parentItemData.itemID = items.itemID
          INNER JOIN itemDataValues as parentItemDataValues ON parentItemDataValues.valueID = parentItemData.valueID
          INNER JOIN fields ON fields.fieldID = parentItemData.fieldID
          INNER JOIN itemTypes ON itemTypes.itemTypeID = items.itemTypeID
          LEFT JOIN itemAttachments ON items.itemID = itemAttachments.parentItemID AND itemAttachments.contentType = 'application/pdf'
          WHERE
            collectionName = ']] .. collection .. [['
    ]]
  end
end


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

function M.get_items(collection)
  local items = {}
  local raw_items = {}
  local query_items = get_query_items(collection)
  local sql_items = M.db:eval(query_items)
  local sql_creators = M.db:eval(query_creators)

  if sql_items == nil or sql_creators == nil then
    vim.notify_once('[zotero] could not query database.', vim.log.levels.WARN, {})
    return {}
  end

  local bbt_citekeys = {}
  -- Zotero 8+: read citation keys stored natively in zotero.sqlite
  local sql_native = M.db:eval(query_native_citekeys)
  if sql_native ~= nil then
    for _, v in pairs(sql_native) do
      bbt_citekeys[v.itemKey] = v.citationKey
    end
  end
  -- Zotero 7: read citation keys from the Better BibTeX database (overrides native if present)
  if M.bbt ~= nil then
    local ok, sql_bbt = pcall(function()
      return M.bbt:eval(query_bbt)
    end)
    if ok and sql_bbt ~= nil then
      for _, v in pairs(sql_bbt) do
        bbt_citekeys[v.itemKey] = v.citationKey
      end
    end
  end

  for _, v in pairs(sql_items) do
    if raw_items[v.key] == nil then
      raw_items[v.key] = { creators = {}, attachment = {}, key = v.key }
    end
    raw_items[v.key][v.fieldName] = v.value
    raw_items[v.key].itemType = v.typeName
    if v.attachment_path then
      raw_items[v.key].attachment.path = v.attachment_path
      raw_items[v.key].attachment.content_type = v.attachment_content_type
      raw_items[v.key].attachment.link_mode = v.attachment_link_mode
    end
    if v.fieldName == 'DOI' then
      raw_items[v.key].DOI = v.value
    end
  end

  for _, v in pairs(sql_creators) do
    if raw_items[v.key] ~= nil then
      raw_items[v.key].creators[v.orderIndex + 1] =
        { firstName = v.firstName, lastName = v.lastName, creatorType = v.creatorType }
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
