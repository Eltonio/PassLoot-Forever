-- PassLoot Forever - Items: item data resolution (async cache aware) and gear comparison.
local addonName, ns = ...
local API = ns.API

local Items = {}
ns.Items = Items

-- itemEquipLoc -> inventory slot IDs it can replace. Cosmetic slots (shirt, tabard) are left out.
Items.SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function ItemIDFrom(linkOrId)
  if type(linkOrId) == "number" then return linkOrId end
  if type(linkOrId) ~= "string" then return nil end
  local id = linkOrId:match("item:(%d+)")
  if id then return tonumber(id) end
  return tonumber(linkOrId)
end

-- Builds a plain table describing the item. Never errors; missing data stays nil.
local function BuildItem(linkOrId)
  local item = { source = linkOrId, equipLoc = "", complete = false }
  if type(linkOrId) == "string" and linkOrId:find("|H", 1, true) then item.link = linkOrId end

  if API.GetItemInfoInstant then
    local id, _, _, equipLoc, icon, classID, subClassID = API.GetItemInfoInstant(linkOrId)
    item.id = id
    item.equipLoc = equipLoc or ""
    item.icon = icon
    item.classID = classID
    item.subClassID = subClassID
  end
  if not item.id then item.id = ItemIDFrom(linkOrId) end

  if API.GetItemInfo then
    local name, link, quality, baseLevel, minLevel, typeName, subName, _, equipLoc, icon,
      sellPrice, classID, subClassID, bindType = API.GetItemInfo(linkOrId)
    if name then
      item.complete = true
      item.name = name
      item.link = link or item.link
      item.quality = quality
      item.baseLevel = baseLevel
      item.minLevel = minLevel
      item.typeName = typeName
      item.subTypeName = subName
      if equipLoc then item.equipLoc = equipLoc end
      item.icon = icon or item.icon
      item.sellPrice = sellPrice
      item.classID = classID or item.classID
      item.subClassID = subClassID or item.subClassID
      item.bindType = bindType
    end
  end

  if item.link then
    local eff = API.GetDetailedItemLevelInfo and API.GetDetailedItemLevelInfo(item.link)
    item.ilvl = (type(eff) == "number" and eff > 0) and eff or item.baseLevel
  else
    item.ilvl = item.baseLevel
  end
  return item
end
Items.Build = BuildItem

local pending = {} -- [itemID] = { {source=, cb=, done=} ... }

local function Finish(entry)
  if entry.done then return end
  entry.done = true
  entry.cb(BuildItem(entry.source))
end

-- Calls cb(item) once the item data is available (or after a short timeout with partial data).
function Items.Resolve(linkOrId, cb, timeout)
  local item = BuildItem(linkOrId)
  if item.complete or not item.id then
    cb(item)
    return
  end
  local entry = { source = linkOrId, cb = cb, done = false }
  pending[item.id] = pending[item.id] or {}
  table.insert(pending[item.id], entry)
  if API.RequestItemLoad then API.RequestItemLoad(item.id) end
  if C_Timer and C_Timer.After then
    C_Timer.After(timeout or 2.5, function() Finish(entry) end)
  else
    Finish(entry)
  end
end

ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, id)
  local list = pending[id]
  if not list then return end
  pending[id] = nil
  for i = 1, #list do Finish(list[i]) end
end)

local function SlotItemLevel(slot)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  if not link or ns.IsSecret(link) then return 0 end
  local eff = API.GetDetailedItemLevelInfo and API.GetDetailedItemLevelInfo(link)
  if type(eff) == "number" and eff > 0 then return eff end
  if API.GetItemInfo then
    local _, _, _, base = API.GetItemInfo(link)
    if type(base) == "number" then return base end
  end
  return 0
end

-- Item level gain over what the item would replace (lowest equipped level among its slots).
-- Returns nil for items that are not comparable gear.
function Items.EquippedGain(item)
  local slots = Items.SLOTS[item.equipLoc or ""]
  if not slots or not item.ilvl then return nil end
  local lowest
  for i = 1, #slots do
    local level = SlotItemLevel(slots[i])
    if not lowest or level < lowest then lowest = level end
  end
  return item.ilvl - (lowest or 0)
end

------------------------------------------------------------------------
-- Tooltip reading (same idea as the original PassLoot): the game itself writes "Already known" on learned
-- recipes and colours unmet requirements (such as "Classes: Mage") in red. Every call is guarded.
------------------------------------------------------------------------
local function Str(v)
  if type(v) == "string" and not ns.IsSecret(v) then return v end
  return nil
end

local function Num(v)
  if type(v) == "number" and not ns.IsSecret(v) then return v end
  return nil
end

local function IsRed(r, g, b)
  r, g, b = Num(r), Num(g), Num(b)
  if not r or not g or not b then return false end
  return r >= 0.9 and g <= 0.25 and b <= 0.25
end

local scanTip

-- Returns a list of { left, right, leftRed, rightRed } for the item tooltip (line 1 = item name), or nil.
-- source: "info" (C_TooltipInfo), "frame" (hidden tooltip) or nil (the first one that works).
function Items.TooltipLines(linkOrId, source)
  local link = linkOrId
  if type(link) == "number" then link = "item:" .. link end
  if type(link) ~= "string" or link == "" then return nil end

  if source ~= "frame" and C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" then
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if ok and type(data) == "table" then
      if TooltipUtil and type(TooltipUtil.SurfaceArgs) == "function" then pcall(TooltipUtil.SurfaceArgs, data) end
      if type(data.lines) == "table" then
        local out = {}
        for i = 1, #data.lines do
          local line = data.lines[i]
          if type(line) == "table" then
            if TooltipUtil and type(TooltipUtil.SurfaceArgs) == "function" then pcall(TooltipUtil.SurfaceArgs, line) end
            local lc, rc = line.leftColor, line.rightColor
            out[#out + 1] = {
              left = Str(line.leftText), right = Str(line.rightText),
              leftRed = type(lc) == "table" and IsRed(lc.r, lc.g, lc.b) or false,
              rightRed = type(rc) == "table" and IsRed(rc.r, rc.g, rc.b) or false,
            }
          end
        end
        if #out > 0 then return out end
      end
    end
  end

  if source == "info" then return nil end
  -- Fallback: hidden tooltip frame.
  if not CreateFrame then return nil end
  local ok, result = pcall(function()
    if not scanTip then
      scanTip = CreateFrame("GameTooltip", "PassLootForeverScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    local n = tonumber(scanTip:NumLines()) or 0
    local out = {}
    for i = 1, n do
      local l = _G["PassLootForeverScanTipTextLeft" .. i]
      local r = _G["PassLootForeverScanTipTextRight" .. i]
      local entry = { leftRed = false, rightRed = false }
      if l then
        entry.left = Str(l:GetText())
        entry.leftRed = IsRed(l:GetTextColor())
      end
      if r then
        entry.right = Str(r:GetText())
        entry.rightRed = IsRed(r:GetTextColor())
      end
      out[#out + 1] = entry
    end
    return out
  end)
  if ok and type(result) == "table" and #result > 0 then return result end
  return nil
end

-- Tooltip text without colour codes and surrounding spaces.
-- Tooltip text without colour codes, with French non-breaking spaces turned into plain spaces
-- ("Utiliser\194\160:"), and without spaces around.
local function Plain(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("\226\128\137", " ")
  text = text:gsub("%s+", " ")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
Items.Plain = Plain

-- true / false, or nil when the tooltip could not be read (or looks incomplete).
-- "false" is only answered for a tooltip that is complete: a recipe tooltip always has its "Use:" line,
-- so without it the tooltip was not fully loaded yet and the answer is "unknown" rather than "not learned".
local function KnownFromLines(lines)
  if not lines or #lines < 2 then return nil end
  local known = Plain(_G.ITEM_SPELL_KNOWN)
  if not known or known == "" then known = "Already known" end
  local use = Plain(_G.ITEM_SPELL_TRIGGER_ONUSE)
  if use == "" then use = nil end
  -- A recipe tooltip also contains the tooltip of the item it makes, starting with a line that begins with
  -- a newline. Two layouts exist:
  --   recipe lines ("Use: Teaches...", "Already known") first, then the made item  -> stop at the made item,
  --     so that an "Already known" of the made item (a mount, a pet...) is not taken for the recipe;
  --   made item first, then the recipe lines (WoW Forever)                         -> keep reading after it.
  local sawUse, useBeforeItem, inItem = false, false, false
  for i = 2, #lines do
    local raw = lines[i].left
    if raw then
      if raw:sub(1, 1) == "\n" then
        if useBeforeItem then break end
        inItem = true
      end
      local text = Plain(raw)
      if text == known or text:sub(1, #known) == known then return true end
      if use and text:sub(1, #use) == use then
        sawUse = true
        if not inItem then useBeforeItem = true end
      end
    end
    local right = Plain(lines[i].right)
    if right and right ~= "" and (right == known or right:sub(1, #known) == known) then return true end
  end
  if use and not sawUse then return nil end
  return false
end

-- Both ways of reading the tooltip are tried: the first clear answer (true / false) wins.
function Items.IsKnown(item)
  local ref = item.link or item.id
  local answer = KnownFromLines(Items.TooltipLines(ref, "info"))
  if answer == nil then answer = KnownFromLines(Items.TooltipLines(ref, "frame")) end
  return answer
end

-- Diagnostic: raw tooltip lines as the addon reads them, special characters made visible.
local function Visible(s)
  if s == nil then return "-" end
  if ns.IsSecret(s) then return "<secret>" end
  s = tostring(s)
  s = s:gsub("|", "||"):gsub("\n", "\\n"):gsub("\194\160", "{nbsp}"):gsub("\226\128\175", "{nnbsp}")
  return s
end

function Items.DumpTooltip(ref)
  local out = {}
  out[#out + 1] = "ITEM_SPELL_KNOWN = " .. Visible(_G.ITEM_SPELL_KNOWN) .. "   ITEM_SPELL_TRIGGER_ONUSE = " .. Visible(_G.ITEM_SPELL_TRIGGER_ONUSE)
  for _, source in ipairs({ "info", "frame" }) do
    local lines = Items.TooltipLines(ref, source)
    if not lines then
      out[#out + 1] = source .. ": (nothing)"
    else
      out[#out + 1] = source .. ": " .. #lines .. " lines, known = " .. tostring(KnownFromLines(lines))
      for i, l in ipairs(lines) do
        out[#out + 1] = string.format("  %d. %s%s%s", i, Visible(l.left), l.right and ("  ||  " .. Visible(l.right)) or "", l.leftRed and "  (red)" or "")
      end
    end
  end
  return out
end

-- true when the item carries a red "Classes: ..." line, i.e. it is reserved for other classes.
function Items.ClassLockedOut(item, ctx)
  if ctx and ctx.classLock ~= nil then return ctx.classLock end
  local locked = false
  local fmt = _G.ITEM_CLASSES_ALLOWED
  if type(fmt) ~= "string" or fmt == "" then fmt = "Classes: %s" end
  local prefix = fmt:match("^(.-)%%s")
  if prefix and prefix ~= "" then
    local lines = Items.TooltipLines(item.link or item.id)
    if lines then
      for i = 2, #lines do
        local l = lines[i]
        if l.left and l.leftRed and l.left:sub(1, #prefix) == prefix then locked = true; break end
      end
    end
  end
  if ctx then ctx.classLock = locked end
  return locked
end

-- Set of the player's profession names, lower-cased (matches the recipe subclass names of the item API),
-- or nil when this client exposes no way to read them.
function Items.MyProfessions()
  local set, found = {}, false
  local function add(name)
    name = Str(name)
    if name and name ~= "" then set[name:lower()] = true end
  end
  if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
    local ok = pcall(function()
      local a, b, c, d, e, f = GetProfessions()
      local list = { a, b, c, d, e, f }
      for i = 1, 6 do
        if type(list[i]) == "number" then add((GetProfessionInfo(list[i]))) end
      end
    end)
    if ok then found = true end
  end
  if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
    local ok = pcall(function()
      for i = 1, GetNumSkillLines() do
        local name, isHeader = GetSkillLineInfo(i)
        if not isHeader then add(name) end
      end
    end)
    if ok then found = true end
  end
  if not found then return nil end
  return set
end
