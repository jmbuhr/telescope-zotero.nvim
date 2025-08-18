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

M.connect = function(opts)
  M.db = connect(opts.zotero_db_path)
  M.bbt = connect(opts.better_bibtex_db_path)
  if M.db == nil or M.bbt == nil then
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

local query_items = [[
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

local query_annotations_template = [[
  SELECT
    itemAnnotations.type,
    itemAnnotations.authorName,
    itemAnnotations.text,
    itemAnnotations.comment,
    itemAnnotations.pageLabel,
    itemAnnotations.color,        -- Added color, might be useful
    itemAnnotations.sortIndex     -- Added for potential sorting later
  FROM items
  JOIN itemAttachments ON items.itemID = itemAttachments.parentItemID
  JOIN itemAnnotations ON itemAnnotations.parentItemID = itemAttachments.ItemID
  WHERE items.key = '%s'
  ORDER BY CAST(itemAnnotations.pageLabel AS INTEGER), itemAnnotations.sortIndex; -- Order by page, then position
]]


local query_tags = [[
    SELECT
      DISTINCT items.key,
      tags.name AS tag_name
    FROM
      items
      INNER JOIN itemTags ON itemTags.itemID = items.itemID
      INNER JOIN tags ON tags.tagID = itemTags.tagID
]]


local query_abstract = [[
    SELECT
      items.key,
      itemDataValues.value AS abstractText
    FROM
      items
      INNER JOIN itemData ON itemData.itemID = items.itemID
      INNER JOIN itemDataValues ON itemDataValues.valueID = itemData.valueID
      INNER JOIN fields ON fields.fieldID = itemData.fieldID
    WHERE
      fields.fieldName = 'abstractNote'
]]

local query_pages = [[
    SELECT
      items.key,
      itemDataValues.value AS pages
    FROM
      items
      INNER JOIN itemData ON itemData.itemID = items.itemID
      INNER JOIN itemDataValues ON itemDataValues.valueID = itemData.valueID
      INNER JOIN fields ON fields.fieldID = itemData.fieldID
    WHERE
      fields.fieldName = 'pages'
]]


-- Add this new function to fetch annotations
function M.get_annotations(itemKey)
  if not M.db then
    vim.notify_once('[zotero] Zotero database not connected.', vim.log.levels.ERROR)
    return nil, 'Database not connected' -- Return error message
  end

  -- Basic string formatting. Assumes itemKey is safe as it comes from our own DB query.
  -- For robustness, parameterized queries would be better if the library supports them easily.
  local query = string.format(query_annotations_template, itemKey)

  local ok, results = pcall(M.db.eval, M.db, query)

  if not ok then
    local err_msg = results or 'Unknown database error' -- pcall returns error message as second arg
    vim.notify('[zotero] Error querying annotations: ' .. err_msg, vim.log.levels.ERROR)
    return nil, err_msg
  end

  if results == nil then
    -- This might happen if the query itself fails silently sometimes, though pcall should catch errors
     vim.notify('[zotero] Annotation query returned nil results.', vim.log.levels.WARN)
    return {}, nil -- Return empty table, no specific error
  end

  -- No need to check #results == 0 here, just return the (potentially empty) list
  return results, nil -- Return results table and nil error
end


function M.get_items()
  local items = {}
  local raw_items = {}
  local sql_items = M.db:eval(query_items)
  local sql_creators = M.db:eval(query_creators)
  local sql_tags = M.db:eval(query_tags)
  local sql_abstract = M.db:eval(query_abstract)
  local sql_pages = M.db:eval(query_pages)
  local sql_bbt = M.bbt:eval(query_bbt)

  if sql_items == nil or sql_creators == nil or sql_tags == nil or sql_bbt == nil then
    vim.notify_once('[zotero] could not query database.', vim.log.levels.WARN, {})
    return {}
  end
  
  local bbt_citekeys = {}
  for _, v in pairs(sql_bbt) do
    bbt_citekeys[v.itemKey] = v.citationKey
  end

  for _, v in pairs(sql_items) do
    if raw_items[v.key] == nil then
      raw_items[v.key] = { creators = {}, attachment = {}, key = v.key, tags = {} }
    end
    raw_items[v.key][v.fieldName] = v.value
    raw_items[v.key].itemType = v.typeName
    if v.attachment_path then
      raw_items[v.key].attachment.path = v.attachment_path
      raw_items[v.key].attachment.content_type = v.attachment_content_type
      raw_items[v.key].attachment.link_mode = v.attachment_link_mode
      -- Extract folder name for creating file path
      raw_items[v.key].attachment.folder_name = v.folder_name
    end
    if v.fieldName == 'DOI' then
      raw_items[v.key].DOI = v.value
    end
  end

  -- Add abstract data
  for _, v in pairs(sql_abstract) do
    if raw_items[v.key] then
      raw_items[v.key].abstractNote = v.abstractText
    end
  end
  
  -- Add pages data
  for _, v in pairs(sql_pages) do
    if raw_items[v.key] then
      raw_items[v.key].pages = v.pages
    end
  end

  -- Add tags
  for _, v in pairs(sql_tags) do
    if raw_items[v.key] ~= nil then
      table.insert(raw_items[v.key].tags, v.tag_name)
    end
  end

  -- Add creators
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

