-- PassLoot Forever - Stats: a stat score for an item, compared with what you wear (in the spirit of Pawn).
-- Used by the "Stat score gain vs equipped" condition and shown in the Test tab.
local addonName, ns = ...
local L = ns.L
local API = ns.API

local Stats = {}
ns.Stats = Stats

------------------------------------------------------------------------
-- Stat keys returned by GetItemStats -> short codes
------------------------------------------------------------------------
local KEY = {
  ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
  ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
  RESISTANCE0_NAME = "ARMOR", ITEM_MOD_EXTRA_ARMOR_SHORT = "ARMOR",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
  ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "AP",
  ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
  ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
  ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
  ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT", ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
  ITEM_MOD_SPELL_CRIT_RATING_SHORT = "SPELLCRIT", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT",
  ITEM_MOD_SPELL_HIT_RATING_SHORT = "SPELLHIT", ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELLHIT",
  ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
  ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF", ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
  ITEM_MOD_PARRY_RATING_SHORT = "PARRY", ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
  ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVAL", ITEM_MOD_SHIELD_BLOCK_VALUE_SHORT = "BLOCKVAL",
  ITEM_MOD_MASTERY_RATING_SHORT = "MASTERY", ITEM_MOD_VERSATILITY = "VERS",
}

-- Old-style items give these as a percentage (+1% crit). Small values are converted to a rating-like
-- number so that one weight table works for both kinds of items.
local PERCENT_LIKE = { CRIT = true, HIT = true, SPELLCRIT = true, SPELLHIT = true, DODGE = true, PARRY = true, BLOCK = true }
local PERCENT_TO_RATING = 14

local STAT_NAME = {
  STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit", ARMOR = "Armor",
  DPS = "Weapon DPS", RDPS = "Ranged weapon DPS", AP = "Attack power", RAP = "Ranged attack power",
  SP = "Spell power", HEAL = "Healing", CRIT = "Critical strike", HIT = "Hit", SPELLCRIT = "Spell critical strike",
  SPELLHIT = "Spell hit", HASTE = "Haste", MP5 = "Mana per 5 sec.", DEF = "Defense", DODGE = "Dodge",
  PARRY = "Parry", BLOCK = "Block", BLOCKVAL = "Block value", MASTERY = "Mastery", VERS = "Versatility",
}

------------------------------------------------------------------------
-- Weight presets per class (starting values, meant to be adjusted after testing)
------------------------------------------------------------------------
local MELEE_STR = { STR = 1, AGI = 0.6, STA = 0.25, AP = 0.5, CRIT = 0.8, HIT = 0.9, HASTE = 0.6, DPS = 3, RDPS = 0.3, ARMOR = 0.005 }
local TANK = { STA = 1, STR = 0.5, AGI = 0.5, ARMOR = 0.05, DEF = 1, DODGE = 0.8, PARRY = 0.7, BLOCK = 0.5, BLOCKVAL = 0.3, HIT = 0.4, DPS = 1, RDPS = 0.2 }
local HEALER = { INT = 1, HEAL = 0.9, SP = 0.9, MP5 = 1.5, SPI = 0.4, SPELLCRIT = 0.5, CRIT = 0.3, HASTE = 0.5, STA = 0.2 }
local CASTER = { SP = 1, INT = 0.6, SPELLHIT = 1, SPELLCRIT = 0.8, HASTE = 0.7, STA = 0.3, SPI = 0.2, MP5 = 0.5 }

local function with(base, changes)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(changes or {}) do t[k] = v end
  return t
end

Stats.PRESETS = {
  WARRIOR = {
    { id = "WARRIOR_DPS", spec = "Arms / Fury", w = MELEE_STR },
    { id = "WARRIOR_TANK", spec = "Protection", w = TANK },
  },
  PALADIN = {
    { id = "PALADIN_HOLY", spec = "Holy", w = with(HEALER, { SPI = 0.2 }) },
    { id = "PALADIN_TANK", spec = "Protection", w = with(TANK, { SP = 0.3, INT = 0.2 }) },
    { id = "PALADIN_RET", spec = "Retribution", w = with(MELEE_STR, { INT = 0.15 }) },
  },
  HUNTER = {
    { id = "HUNTER", spec = "All specs", w = { AGI = 1, RAP = 0.5, AP = 0.4, INT = 0.2, STA = 0.2, CRIT = 0.8, HIT = 0.9, HASTE = 0.6, RDPS = 2, DPS = 0.3, ARMOR = 0.005 } },
  },
  ROGUE = {
    { id = "ROGUE", spec = "All specs", w = { AGI = 1, STR = 0.5, AP = 0.5, STA = 0.25, CRIT = 0.8, HIT = 1, HASTE = 0.6, DPS = 3, RDPS = 0.3, ARMOR = 0.005 } },
  },
  PRIEST = {
    { id = "PRIEST_HEAL", spec = "Holy / Discipline", w = with(HEALER, { SPI = 0.6 }) },
    { id = "PRIEST_SHADOW", spec = "Shadow", w = with(CASTER, { SPI = 0.3 }) },
  },
  SHAMAN = {
    { id = "SHAMAN_ELE", spec = "Elemental", w = with(CASTER, { MP5 = 1 }) },
    { id = "SHAMAN_ENH", spec = "Enhancement", w = with(MELEE_STR, { AGI = 0.7, INT = 0.2 }) },
    { id = "SHAMAN_RESTO", spec = "Restoration", w = with(HEALER, { MP5 = 1.6, SPI = 0.3 }) },
  },
  MAGE = {
    { id = "MAGE", spec = "All specs", w = CASTER },
  },
  WARLOCK = {
    { id = "WARLOCK", spec = "All specs", w = with(CASTER, { STA = 0.5, INT = 0.4 }) },
  },
  DRUID = {
    { id = "DRUID_BALANCE", spec = "Balance", w = with(CASTER, { MP5 = 0.8, SPI = 0.3 }) },
    { id = "DRUID_BEAR", spec = "Feral (tank)", w = { STA = 1, AGI = 0.8, ARMOR = 0.06, STR = 0.4, DEF = 0.8, DODGE = 0.8, HIT = 0.4, AP = 0.2 } },
    { id = "DRUID_CAT", spec = "Feral (damage)", w = { AGI = 1, STR = 0.9, AP = 0.5, CRIT = 0.8, HIT = 0.9, HASTE = 0.6, STA = 0.2 } },
    { id = "DRUID_RESTO", spec = "Restoration", w = with(HEALER, { HEAL = 1, SPI = 0.7, INT = 0.9 }) },
  },
}
local GENERIC = { id = "GENERIC", spec = "Generic", w = { STR = 1, AGI = 1, STA = 1, INT = 1, SPI = 0.5, AP = 0.5, SP = 1, HEAL = 1, DPS = 1 } }

local function ClassToken()
  if not UnitClass then return nil end
  local _, token = UnitClass("player") -- (an "and" here would keep only the first return value)
  return token
end

function Stats.ClassPresets()
  return Stats.PRESETS[ClassToken() or ""] or { GENERIC }
end

function Stats.Available()
  return API.GetItemStats ~= nil
end

-- The preset chosen for this character (first one of the class by default).
function Stats.CurrentPreset()
  local list = Stats.ClassPresets()
  local wanted = ns.db and ns.db.statPreset and ns.db.statPreset[ns.CharKey()]
  for _, p in ipairs(list) do if p.id == wanted then return p end end
  return list[1]
end

function Stats.SetPreset(id)
  if type(ns.db.statPreset) ~= "table" then ns.db.statPreset = {} end
  ns.db.statPreset[ns.CharKey()] = id
end

function Stats.PresetLabel(p)
  local className = UnitClass and (UnitClass("player")) or ""
  return className .. " - " .. L[p.spec]
end

------------------------------------------------------------------------
-- Reading and scoring
------------------------------------------------------------------------
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- Returns { code = value }, the list of unknown raw keys, or nil when stats cannot be read.
function Stats.Read(link, equipLoc)
  if not API.GetItemStats or type(link) ~= "string" or ns.IsSecret(link) then return nil end
  local ok, raw = pcall(API.GetItemStats, link)
  if not ok then return nil end
  if type(raw) ~= "table" then raw = {} end
  local out, unknown = {}, {}
  for k, v in pairs(raw) do
    if type(k) == "string" and type(v) == "number" and not ns.IsSecret(v) then
      local code = KEY[k]
      if code == "DPS" and RANGED[equipLoc or ""] then code = "RDPS" end
      if code then
        if PERCENT_LIKE[code] and v > 0 and v <= 3 then v = v * PERCENT_TO_RATING end
        out[code] = (out[code] or 0) + v
      elseif not k:find("^RESISTANCE%d") and not k:find("^EMPTY_SOCKET") then
        unknown[#unknown + 1] = k .. "=" .. v
      end
    end
  end
  return out, unknown
end

function Stats.Score(stats, weights)
  local total = 0
  for code, v in pairs(stats or {}) do total = total + v * (weights[code] or 0) end
  return total
end

local function EquipLocOf(link)
  if not API.GetItemInfoInstant then return nil end
  local ok, _, _, _, loc = pcall(API.GetItemInfoInstant, link)
  if ok then return loc end
  return nil
end

local function SlotScore(slot, weights)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  if not link or ns.IsSecret(link) then return nil end
  local stats = Stats.Read(link, EquipLocOf(link))
  if not stats then return nil end
  return Stats.Score(stats, weights), link
end

-- Compares an item with what it would replace. Returns a table or nil (not gear / stats unavailable).
--   { score, old, gain (percent or nil), empty, replaced (link), stats, unknown, preset }
function Stats.Compare(item)
  local slots = ns.Items.SLOTS[item.equipLoc or ""]
  if not slots or not item.link then return nil end
  local preset = Stats.CurrentPreset()
  local w = preset.w
  local stats, unknown = Stats.Read(item.link, item.equipLoc)
  if not stats then return nil end
  local res = { score = Stats.Score(stats, w), stats = stats, unknown = unknown, preset = preset }
  if item.equipLoc == "INVTYPE_2HWEAPON" then
    -- a two-hander replaces both hands
    local mh, mhLink = SlotScore(16, w)
    local oh = SlotScore(17, w)
    if not mh and not oh then res.empty = true end
    res.old, res.replaced = (mh or 0) + (oh or 0), mhLink
  else
    -- rings, trinkets, one-handers: compare with the weakest of the possible slots
    for i = 1, #slots do
      local s, link = SlotScore(slots[i], w)
      if not s then res.empty, res.old, res.replaced = true, 0, nil; break end
      if not res.old or s < res.old then res.old, res.replaced = s, link end
    end
  end
  if not res.empty and res.old and res.old > 0 then
    res.gain = (res.score - res.old) / res.old * 100
  end
  return res
end

-- Percent gain used by the rule condition. nil when the item is not comparable gear or stats
-- cannot be read (the condition then does not match). An empty slot is always an upgrade.
function Stats.Gain(item)
  local r = Stats.Compare(item)
  if not r then return nil end
  if r.empty then return math.huge end
  if r.gain then return r.gain end
  if (r.old or 0) <= 0 then return (r.score > 0) and math.huge or 0 end
  return 0
end

-- Lines for the Test tab.
function Stats.Describe(item)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  if not Stats.Available() then
    add("|cff9a9a9a" .. L["Stat score: GetItemStats is not available on this client."] .. "|r")
    return lines
  end
  local r = Stats.Compare(item)
  if not r then return lines end
  local head = string.format("|cffd4a85a%s|r |cff9a9a9a(%s)|r", L["Stat score"], Stats.PresetLabel(r.preset))
  add(head)
  local verdict
  if r.empty then
    verdict = string.format("%.1f  |cff55dd55%s|r", r.score, L["empty slot: upgrade"])
  elseif r.gain then
    local color = r.gain > 0.5 and "55dd55" or (r.gain < -0.5 and "ff7a5c" or "cccccc")
    verdict = string.format("%.1f %s %.1f  |cff%s%+.0f %%|r", r.score, L["vs equipped"], r.old, color, r.gain)
  else
    verdict = string.format("%.1f %s %.1f", r.score, L["vs equipped"], r.old or 0)
  end
  add("   " .. verdict .. ((r.replaced and not r.empty) and ("   " .. r.replaced) or ""))
  local parts = {}
  local codes = {}
  for code in pairs(r.stats) do codes[#codes + 1] = code end
  table.sort(codes)
  for _, code in ipairs(codes) do
    local wv = r.preset.w[code] or 0
    parts[#parts + 1] = string.format("%s %g x%g", L[STAT_NAME[code] or code], r.stats[code], wv)
  end
  add("   |cff9a9a9a" .. (#parts > 0 and table.concat(parts, "  |  ") or L["no stats"]) .. "|r")
  if r.unknown and #r.unknown > 0 then
    add("   |cff777777" .. L["Unrecognised stats (ignored):"] .. " " .. table.concat(r.unknown, ", ") .. "|r")
  end
  return lines
end
