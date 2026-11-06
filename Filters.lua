-- PassLoot Forever - Filters: registry of rule conditions.
-- Semantics (same as the original PassLoot): inside one rule, conditions of the SAME filter are OR'ed
-- (minus the excluded ones), and different filters are AND'ed together.
local addonName, ns = ...
local L = ns.L
local API, Items = ns.API, ns.Items

local Filters = { list = {}, byKey = {} }
ns.Filters = Filters

Filters.OPS = { ">=", "<=", ">", "<", "=", "~=" }
Filters.OP_LABEL = { [">="] = ">=", ["<="] = "<=", [">"] = ">", ["<"] = "<", ["="] = "=", ["~="] = "!=" }

local function Compare(a, op, b)
  if type(a) ~= "number" or type(b) ~= "number" then return false end
  if op == ">=" then return a >= b
  elseif op == "<=" then return a <= b
  elseif op == ">" then return a > b
  elseif op == "<" then return a < b
  elseif op == "=" then return a == b
  elseif op == "~=" then return a ~= b end
  return false
end

local function Add(def)
  def.kind = def.kind or "select"
  Filters.list[#Filters.list + 1] = def
  Filters.byKey[def.key] = def
end

------------------------------------------------------------------------
-- Player information (always guarded: values may be secret on this client)
------------------------------------------------------------------------
local function PlayerClass()
  if not UnitClass then return nil end
  local _, token = UnitClass("player")
  if token and not ns.IsSecret(token) then return token end
  return nil
end

local function PlayerLevel()
  local level = UnitLevel and UnitLevel("player")
  if type(level) == "number" and not ns.IsSecret(level) then return level end
  return nil
end
Filters.PlayerClass, Filters.PlayerLevel = PlayerClass, PlayerLevel

------------------------------------------------------------------------
-- Proficiencies. Based on Classic rules (Forever shares the original Azeroth class kit); armor values are
-- the minimum player level to wear that armor type. Adjust here if the live game differs.
-- Armor subclass: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem.
-- Weapon subclass: 0 axe1h, 1 axe2h, 2 bow, 3 gun, 4 mace1h, 5 mace2h, 6 polearm, 7 sword1h, 8 sword2h,
--                  10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand.
------------------------------------------------------------------------
local function W(...)
  local t = {}
  for i = 1, select("#", ...) do t[(select(i, ...))] = 1 end
  return t
end

local PROF = {
  WARRIOR = { armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 }, weapons = W(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18) },
  PALADIN = { armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 }, weapons = W(0, 1, 4, 5, 6, 7, 8) },
  HUNTER = { armor = { [1] = 1, [2] = 1, [3] = 40 }, weapons = W(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18) },
  ROGUE = { armor = { [1] = 1, [2] = 1 }, weapons = W(2, 3, 4, 7, 13, 15, 16, 18) },
  PRIEST = { armor = { [1] = 1 }, weapons = W(4, 10, 15, 19) },
  SHAMAN = { armor = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 }, weapons = W(0, 1, 4, 5, 10, 13, 15) },
  MAGE = { armor = { [1] = 1 }, weapons = W(7, 10, 15, 19) },
  WARLOCK = { armor = { [1] = 1 }, weapons = W(7, 10, 15, 19) },
  DRUID = { armor = { [1] = 1, [2] = 1, [8] = 1 }, weapons = W(4, 5, 6, 10, 13, 15) },
}
Filters.PROF = PROF

-- Gear: "now", "later" or "never" from armor/weapon proficiency and level.
-- Any item: "never" when it carries a red "Classes: ..." line (reserved for other classes).
-- nil when the item is neither gear nor class-locked.
local BaseUsableStatus
function Filters.UsableStatus(item, ctx)
  if Items.ClassLockedOut(item, ctx) then return "never" end
  return BaseUsableStatus(item)
end

function BaseUsableStatus(item)
  local c = item.classID
  if (c ~= 2 and c ~= 4) or not item.equipLoc or item.equipLoc == "" then return nil end
  local class, level = PlayerClass(), PlayerLevel()
  local prof = class and PROF[class]
  local from = 1
  if prof and item.equipLoc ~= "INVTYPE_CLOAK" then
    local sub = item.subClassID
    if sub then
      if c == 4 then
        if sub ~= 0 and sub ~= 5 then from = prof.armor[sub] end
      else
        if sub ~= 14 and sub ~= 20 then from = prof.weapons[sub] end
      end
    end
  end
  if not from then return "never" end
  if level and level < from then return "later" end
  if level and item.minLevel and item.minLevel > level then return "later" end
  return "now"
end

------------------------------------------------------------------------
-- Choice helpers
------------------------------------------------------------------------
local QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff" }
local QUALITY_NAME = {
  [0] = L["Poor"], [1] = L["Common"], [2] = L["Uncommon"], [3] = L["Rare"],
  [4] = L["Epic"], [5] = L["Legendary"], [6] = L["Artifact"], [7] = L["Heirloom"],
}

local function QualityChoices()
  local out = {}
  for q = 0, 7 do
    local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or QUALITY_NAME[q]
    out[#out + 1] = { value = q, label = "|cff" .. QUALITY_HEX[q] .. name .. "|r" }
  end
  return out
end

local SLOT_TOKENS = {
  "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY",
  "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
  "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
  "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
  "INVTYPE_THROWN", "INVTYPE_RELIC", "INVTYPE_BAG",
}

local function SlotChoices()
  local out = {}
  for _, token in ipairs(SLOT_TOKENS) do
    out[#out + 1] = { value = token, label = _G[token] or token }
  end
  return out
end

-- The client still lists retired item classes, flagged "(OBSOLETE)" in their name: never offer them.
local function IsObsolete(name)
  return type(name) ~= "string" or name == "" or name:upper():find("OBSOLETE", 1, true) ~= nil
end

local classChoicesCache
local function ClassChoices()
  if classChoicesCache and #classChoicesCache > 0 then return classChoicesCache end
  local out = {}
  local getClass, getSub = API.GetItemClassInfo, API.GetItemSubClassInfo
  if getClass and getSub then
    for c = 0, 19 do
      local cname = getClass(c)
      if not IsObsolete(cname) then
        out[#out + 1] = { value = c .. ":*", label = cname }
        for s = 0, 25 do
          local sname = getSub(c, s)
          if not IsObsolete(sname) then
            out[#out + 1] = { value = c .. ":" .. s, label = "   " .. cname .. " - " .. sname }
          end
        end
      end
    end
  end
  classChoicesCache = out
  return out
end

local function Static(list)
  return function() return list end
end

------------------------------------------------------------------------
-- Context helpers
------------------------------------------------------------------------
local function OwnedCount(item)
  if not API.GetItemCount or not item.id then return nil end
  local n = API.GetItemCount(item.id)
  if type(n) == "number" then return n end
  return nil
end

local function TextMatch(hay, v)
  if type(hay) ~= "string" or type(v) ~= "table" then return false end
  local s = tostring(v.s or "")
  if s == "" then return false end
  local h, n = hay:lower(), s:lower()
  if v.mode == "exact" then return h == n
  elseif v.mode == "starts" then return h:sub(1, #n) == n
  elseif v.mode == "pattern" then
    local ok, r = pcall(string.find, h, n)
    return ok and r ~= nil
  end
  return h:find(n, 1, true) ~= nil
end

local BIND_SETS = {
  none = { [0] = true }, bop = { [1] = true }, boe = { [2] = true }, bou = { [3] = true },
  quest = { [4] = true }, account = { [7] = true, [8] = true, [9] = true },
}

------------------------------------------------------------------------
-- Filter definitions (order = order in the "add condition" menu)
------------------------------------------------------------------------
Add{ key = "quality", label = L["Quality"], help = L["Item quality (grey, white, green...)."],
  default = 2, choices = QualityChoices,
  eval = function(item, ctx, v) return item.quality ~= nil and item.quality == tonumber(v) end }

Add{ key = "itemClass", label = L["Item type"], help = L["Item class and subclass (armor, weapon, consumable...)."],
  default = "4:*", choices = ClassChoices,
  eval = function(item, ctx, v)
    local c, s = tostring(v):match("^(%d+):([%d%*]+)$")
    if not c or item.classID ~= tonumber(c) then return false end
    if s == "*" then return true end
    return item.subClassID == tonumber(s)
  end }

Add{ key = "equipSlot", label = L["Equipment slot"], help = L["Where the item is worn (head, trinket, two-hand...)."],
  default = "INVTYPE_HEAD", choices = SlotChoices,
  eval = function(item, ctx, v)
    if v == "INVTYPE_CHEST" then return item.equipLoc == "INVTYPE_CHEST" or item.equipLoc == "INVTYPE_ROBE" end
    return item.equipLoc == v
  end }

Add{ key = "usable", label = L["Usable by my class"],
  help = L["Armor/weapon proficiency and level of your character, plus class restrictions shown in red on the item."],
  default = "now",
  choices = Static({
    { value = "now", label = L["Yes, right now"] },
    { value = "later", label = L["Yes, later (level or skill)"] },
    { value = "never", label = L["Never"] },
  }),
  eval = function(item, ctx, v) return Filters.UsableStatus(item, ctx) == v end }

-- Recipes: item class 9. known = learned already (tooltip), mine = belongs to one of the player's professions.
-- "Book" recipes (subclass 0) have no profession and count as "mine". nil = could not be determined, in which
-- case no recipe condition matches (a rule never fires on a guess).
function Filters.RecipeFacts(item)
  if item.classID ~= 9 then return nil end
  local facts = { known = Items.IsKnown(item) }
  local sub = item.subClassID
  if sub == 0 then
    facts.mine = true
  elseif sub ~= nil and API.GetItemSubClassInfo then
    local name = API.GetItemSubClassInfo(9, sub)
    local profs = Items.MyProfessions()
    if type(name) == "string" and name ~= "" and profs then facts.mine = profs[name:lower()] == true end
  end
  return facts
end

local function RecipeFactsCached(item, ctx)
  if ctx then
    if ctx.recipeFacts == nil then ctx.recipeFacts = Filters.RecipeFacts(item) or false end
    return ctx.recipeFacts or nil
  end
  return Filters.RecipeFacts(item)
end

Add{ key = "recipe", label = L["Recipe status"],
  help = L["Recipes only: not learned yet and for one of your professions, already learned, or for a profession you do not have."],
  default = "learnable",
  choices = Static({
    { value = "learnable", label = L["Not learned yet, my profession"] },
    { value = "known", label = L["Already learned"] },
    { value = "foreign", label = L["Not my profession"] },
  }),
  eval = function(item, ctx, v)
    local f = RecipeFactsCached(item, ctx)
    if not f then return false end
    if v == "learnable" then return f.known == false and f.mine == true
    elseif v == "known" then return f.known == true
    elseif v == "foreign" then return f.mine == false end
    return false
  end }

Add{ key = "itemLevel", label = L["Item level"], kind = "number", help = L["Item level of the dropped item."],
  default = { op = ">=", n = 0 },
  eval = function(item, ctx, v) return Compare(item.ilvl, v.op, v.n) end }

Add{ key = "upgrade", label = L["Item level gain vs equipped"], kind = "number",
  help = L["Item level of the drop minus the gear it would replace. Empty slot counts as 0. Gear only."],
  default = { op = ">", n = 0 },
  eval = function(item, ctx, v)
    local gain = Items.EquippedGain(item)
    return gain ~= nil and Compare(gain, v.op, v.n)
  end }

Add{ key = "reqLevel", label = L["Required level"], kind = "number", help = L["Level required to use the item."],
  default = { op = "<=", n = 60 },
  eval = function(item, ctx, v) return Compare(item.minLevel, v.op, v.n) end }

Add{ key = "bind", label = L["Binding"], help = L["When the item becomes soulbound."],
  default = "bop",
  choices = Static({
    { value = "bop", label = L["Bind on pickup"] },
    { value = "boe", label = L["Bind on equip"] },
    { value = "bou", label = L["Bind on use"] },
    { value = "quest", label = L["Quest item"] },
    { value = "account", label = L["Account bound"] },
    { value = "none", label = L["No binding"] },
  }),
  eval = function(item, ctx, v)
    local set = BIND_SETS[v]
    if not set then return false end
    local bt = item.bindType
    if bt == nil and ctx.roll and ctx.roll.bop then bt = 1 end
    if bt == nil then return false end
    return set[bt] == true
  end }

Add{ key = "name", label = L["Item name"], kind = "text", help = L["Matches the item name (not case sensitive)."],
  default = { mode = "contains", s = "" },
  eval = function(item, ctx, v) return TextMatch(item.name, v) end }

Add{ key = "vendorPrice", label = L["Vendor price (gold)"], kind = "number", mult = 10000, unit = "g",
  help = L["Vendor sell price of one item, in gold."],
  default = { op = ">=", n = 10000 },
  eval = function(item, ctx, v) return Compare(item.sellPrice, v.op, v.n) end }

Add{ key = "owned", label = L["Owned in bags"], kind = "number", help = L["How many of this item you already carry."],
  default = { op = ">=", n = 1 },
  eval = function(item, ctx, v) return Compare(OwnedCount(item), v.op, v.n) end }

Add{ key = "canRoll", label = L["Roll option available"], help = L["Whether Need, Greed or Disenchant is offered for this roll."],
  default = "need",
  choices = Static({
    { value = "need", label = NEED or L["Need"] },
    { value = "greed", label = GREED or L["Greed"] },
    { value = "de", label = ROLL_DISENCHANT or L["Disenchant"] },
  }),
  eval = function(item, ctx, v) return ctx.can ~= nil and ctx.can[v] == true end }

Add{ key = "instanceType", label = L["Instance type"], help = L["Where you are right now."],
  default = "party",
  choices = Static({
    { value = "none", label = L["Open world"] },
    { value = "party", label = L["Dungeon"] },
    { value = "raid", label = L["Raid"] },
    { value = "pvp", label = L["Battleground"] },
    { value = "arena", label = L["Arena"] },
    { value = "scenario", label = L["Scenario"] },
  }),
  eval = function(item, ctx, v) return ctx.instanceType == v end }

Add{ key = "groupType", label = L["Group type"], help = L["Whether you are alone, in a party or in a raid."],
  default = "party",
  choices = Static({
    { value = "solo", label = L["Solo"] },
    { value = "party", label = L["Party"] },
    { value = "raid", label = L["Raid group"] },
  }),
  eval = function(item, ctx, v) return ctx.groupType == v end }

Add{ key = "zone", label = L["Zone name"], kind = "text", help = L["Matches the instance name, or the zone name outdoors."],
  default = { mode = "contains", s = "" },
  eval = function(item, ctx, v) return TextMatch(ctx.zone, v) end }

------------------------------------------------------------------------
-- Value helpers shared with the UI and the engine
------------------------------------------------------------------------
function Filters.DefaultValue(def)
  return ns.CopyTable(def.default)
end

function Filters.NormalizeValue(def, v)
  if def.kind == "number" then
    if type(v) ~= "table" then return Filters.DefaultValue(def) end
    local valid = false
    for _, op in ipairs(Filters.OPS) do if op == v.op then valid = true end end
    if not valid then v.op = def.default.op end
    if type(v.n) ~= "number" then v.n = def.default.n end
  elseif def.kind == "text" then
    if type(v) ~= "table" then return Filters.DefaultValue(def) end
    if type(v.s) ~= "string" then v.s = "" end
    if v.mode ~= "contains" and v.mode ~= "exact" and v.mode ~= "starts" and v.mode ~= "pattern" then v.mode = "contains" end
  end
  return v
end

Filters.TEXT_MODES = {
  { value = "contains", label = L["contains"] },
  { value = "exact", label = L["is exactly"] },
  { value = "starts", label = L["starts with"] },
  { value = "pattern", label = L["matches pattern"] },
}

function Filters.ChoiceLabel(def, v)
  if def.choices then
    for _, c in ipairs(def.choices()) do
      if tostring(c.value) == tostring(v) then return (c.label:gsub("^%s+", "")) end
    end
  end
  return tostring(v)
end

function Filters.DescribeValue(def, v)
  v = Filters.NormalizeValue(def, v)
  if def.kind == "number" then
    local mult = def.mult or 1
    return (Filters.OP_LABEL[v.op] or v.op) .. " " .. tostring(v.n / mult) .. (def.unit or "")
  elseif def.kind == "text" then
    local mode = v.mode
    for _, m in ipairs(Filters.TEXT_MODES) do if m.value == v.mode then mode = m.label end end
    return mode .. ' "' .. v.s .. '"'
  end
  return Filters.ChoiceLabel(def, v)
end

function Filters.Describe(cond)
  local def = Filters.byKey[cond.f]
  if not def then return tostring(cond.f) .. " (?)" end
  local value = Filters.DescribeValue(def, cond.v)
  if def.kind == "select" then return def.label .. ": " .. value end
  return def.label .. " " .. value
end

-- Safe evaluation: a filter that errors (for example because of a secret value) simply does not match.
function Filters.Eval(def, item, ctx, v)
  local ok, res = pcall(def.eval, item, ctx, Filters.NormalizeValue(def, v))
  if not ok then
    ns.Debug("filter error", def.key, res)
    return false
  end
  return res and true or false
end
