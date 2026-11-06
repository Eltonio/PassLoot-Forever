-- PassLoot Forever - Core: namespace, compat layer, saved variables, profiles, events, slash commands.
-- Lua 5.1 only (no goto, no //, no bit operators). No library dependency.
local addonName, ns = ...
local L = ns.L

ns.name = addonName
ns.VERSION = "5.0.7"
ns.AUTHOR = "Doel"

------------------------------------------------------------------------
-- Small utilities
------------------------------------------------------------------------
function ns.IsSecret(v)
  return (type(issecretvalue) == "function" and issecretvalue(v)) and true or false
end

-- Returns nil for a secret value, the value itself otherwise.
function ns.Clean(v)
  if ns.IsSecret(v) then return nil end
  return v
end

function ns.Trim(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

function ns.CopyTable(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = ns.CopyTable(v) end
  return out
end

function ns.Print(msg)
  local text = "|cffd4a85aPassLoot|r: " .. tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(text)
  else
    print(text)
  end
end

function ns.Debug(...)
  if not (ns.db and ns.db.debug) then return end
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  ns.Print("|cff888888[debug]|r " .. table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Callbacks and events
------------------------------------------------------------------------
local callbacks = {}

function ns.RegisterCallback(event, fn)
  callbacks[event] = callbacks[event] or {}
  table.insert(callbacks[event], fn)
end

function ns.Fire(event, ...)
  local list = callbacks[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.RegisterEvent(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- An event that does not exist on this client must never break the addon.
    pcall(eventFrame.RegisterEvent, eventFrame, event)
  end
  table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do list[i](event, ...) end
end)

------------------------------------------------------------------------
-- API compatibility layer. Forever uses the modern (Mainline-family) API, but
-- every entry is probed so that a missing function degrades one feature
-- instead of raising errors. "/plf diag" prints what was found.
------------------------------------------------------------------------
local function pick(...)
  for i = 1, select("#", ...) do
    local f = select(i, ...)
    if type(f) == "function" then return f end
  end
  return nil
end

local API = {}
ns.API = API

API.GetItemInfo = pick(C_Item and C_Item.GetItemInfo, _G.GetItemInfo)
API.GetItemInfoInstant = pick(C_Item and C_Item.GetItemInfoInstant, _G.GetItemInfoInstant)
API.RequestItemLoad = pick(C_Item and C_Item.RequestLoadItemDataByID)
API.GetDetailedItemLevelInfo = pick(C_Item and C_Item.GetDetailedItemLevelInfo, _G.GetDetailedItemLevelInfo)
API.GetItemCount = pick(C_Item and C_Item.GetItemCount, _G.GetItemCount)
API.GetItemClassInfo = pick(C_Item and C_Item.GetItemClassInfo, _G.GetItemClassInfo)
API.GetItemSubClassInfo = pick(C_Item and C_Item.GetItemSubClassInfo, _G.GetItemSubClassInfo)
API.GetRollItemLink = pick(_G.GetLootRollItemLink)
API.GetRollItemInfo = pick(_G.GetLootRollItemInfo)
API.RollOnLoot = pick(_G.RollOnLoot, C_Loot and C_Loot.RollOnLoot)
API.ConfirmLootRoll = pick(_G.ConfirmLootRoll, C_Loot and C_Loot.ConfirmLootRoll)

-- Classic-style roll type values used by RollOnLoot.
API.ROLLTYPE = {
  pass = _G.LOOT_ROLL_TYPE_PASS or 0,
  need = _G.LOOT_ROLL_TYPE_NEED or 1,
  greed = _G.LOOT_ROLL_TYPE_GREED or 2,
  de = _G.LOOT_ROLL_TYPE_DISENCHANT or 3,
}

function ns.Diagnostics()
  local function yn(v) return v and "|cff55ff55OK|r" or "|cffff5555missing|r" end
  local lines = {}
  local function add(label, v) lines[#lines + 1] = string.format("  %s: %s", label, yn(v)) end
  add("GetLootRollItemLink", API.GetRollItemLink)
  add("GetLootRollItemInfo", API.GetRollItemInfo)
  add("RollOnLoot", API.RollOnLoot)
  add("ConfirmLootRoll", API.ConfirmLootRoll)
  add("C_Item.GetItemInfo", API.GetItemInfo)
  add("C_Item.GetItemInfoInstant", API.GetItemInfoInstant)
  add("C_Item.RequestLoadItemDataByID", API.RequestItemLoad)
  add("C_Item.GetDetailedItemLevelInfo", API.GetDetailedItemLevelInfo)
  add("C_Item.GetItemCount", API.GetItemCount)
  add("GetItemClassInfo / GetItemSubClassInfo", API.GetItemClassInfo and API.GetItemSubClassInfo)
  add("issecretvalue", type(issecretvalue) == "function")
  add("Tooltip reading (C_TooltipInfo.GetHyperlink or GameTooltip)", (C_TooltipInfo and C_TooltipInfo.GetHyperlink) or (CreateFrame and true))
  add("Profession list (GetProfessions or GetSkillLineInfo)", (GetProfessions and GetProfessionInfo) or (GetNumSkillLines and GetSkillLineInfo))
  add("C_Timer.After", C_Timer and C_Timer.After)
  add("Settings.RegisterCanvasLayoutCategory", Settings and Settings.RegisterCanvasLayoutCategory)
  local rt = API.ROLLTYPE
  lines[#lines + 1] = string.format("  RollOnLoot values: pass=%s need=%s greed=%s de=%s", tostring(rt.pass), tostring(rt.need), tostring(rt.greed), tostring(rt.de))
  if GetBuildInfo then
    local version, build, _, toc = GetBuildInfo()
    lines[#lines + 1] = string.format("  Client: %s (build %s), interface %s", tostring(version), tostring(build), tostring(toc))
  end
  lines[#lines + 1] = string.format("  WOW_PROJECT_ID=%s  WOW_PROJECT_CAMELOT=%s", tostring(_G.WOW_PROJECT_ID), tostring(_G.WOW_PROJECT_CAMELOT))
  return lines
end

------------------------------------------------------------------------
-- Saved variables and profiles
------------------------------------------------------------------------
local VALID_ACTION = { need = true, de = true, greed = true, pass = true }
ns.ORDER = { "need", "de", "greed", "pass" } -- priority: first available wins

function ns.DefaultMessages()
  return {
    need = L["Rolling need on %item% (%rule%)"],
    de = L["Rolling disenchant on %item% (%rule%)"],
    greed = L["Rolling greed on %item% (%rule%)"],
    pass = L["Rolling pass on %item% (%rule%)"],
    ignore = L["Ignoring %item% (%rule%)"],
  }
end

function ns.NewRule()
  -- No action selected: a fresh rule never rolls on its own until the user picks one.
  return { name = L["New rule"], enabled = true, loot = {}, conds = {} }
end

function ns.ExampleRules()
  return {
    {
      name = L["Example: pass on grey and white items"], enabled = false, loot = { "pass" },
      conds = { { f = "quality", v = 0, x = false }, { f = "quality", v = 1, x = false } },
    },
    {
      name = L["Example: disenchant or greed on gear you cannot use"], enabled = false, loot = { "de", "greed" },
      conds = { { f = "quality", v = 2, x = false }, { f = "usable", v = "never", x = false } },
    },
    {
      name = L["Example: need on upgrades you can equip now"], enabled = false, loot = { "need" },
      conds = {
        { f = "usable", v = "now", x = false },
        { f = "upgrade", v = { op = ">", n = 0 }, x = false },
        { f = "quality", v = 0, x = true },
        { f = "quality", v = 1, x = true },
      },
    },
    {
      name = L["Example: need on recipes I have not learned"], enabled = false, loot = { "need" },
      conds = { { f = "recipe", v = "learnable", x = false } },
    },
    {
      name = L["Example: pass on recipes I know or that are not for my professions"], enabled = false, loot = { "pass" },
      conds = { { f = "recipe", v = "known", x = false }, { f = "recipe", v = "foreign", x = false } },
    },
  }
end

function ns.NewProfileTable(withExamples)
  return {
    rules = withExamples and ns.ExampleRules() or {},
    messages = ns.DefaultMessages(),
    quiet = false,
    confirmBoP = false,
    confirmDE = false,
  }
end

function ns.SanitizeProfile(p)
  if type(p.rules) ~= "table" then p.rules = {} end
  if type(p.messages) ~= "table" then p.messages = {} end
  local defaults = ns.DefaultMessages()
  for k, v in pairs(defaults) do
    if type(p.messages[k]) ~= "string" then p.messages[k] = v end
  end
  p.quiet = p.quiet and true or false
  p.confirmBoP = p.confirmBoP and true or false
  p.confirmDE = p.confirmDE and true or false
  local rules = p.rules
  for i = #rules, 1, -1 do
    local r = rules[i]
    if type(r) ~= "table" then
      table.remove(rules, i)
    else
      if type(r.name) ~= "string" then r.name = L["New rule"] end
      if r.enabled == nil then r.enabled = true end
      r.enabled = r.enabled and true or false
      if type(r.loot) ~= "table" then r.loot = {} end
      local seen, clean = {}, {}
      for _, a in ipairs(r.loot) do
        if VALID_ACTION[a] and not seen[a] then seen[a] = true; clean[#clean + 1] = a end
      end
      r.loot = clean
      if type(r.conds) ~= "table" then r.conds = {} end
      for j = #r.conds, 1, -1 do
        local c = r.conds[j]
        if type(c) ~= "table" or type(c.f) ~= "string" then
          table.remove(r.conds, j)
        else
          c.x = c.x and true or false
          c.j = nil -- leftover from 5.0.1 (AND between conditions): conditions of one type are always OR'ed
        end
      end
    end
  end
end

function ns.CharKey()
  local guid = UnitGUID and UnitGUID("player")
  if guid and not ns.IsSecret(guid) then return tostring(guid) end
  local name = UnitName and UnitName("player")
  if name and not ns.IsSecret(name) then
    local realm = GetRealmName and GetRealmName()
    return tostring(name) .. "-" .. ((realm and not ns.IsSecret(realm)) and tostring(realm) or "?")
  end
  return "unknown"
end

function ns.GetProfileNames()
  local names = {}
  if ns.db then
    for name in pairs(ns.db.profiles) do names[#names + 1] = name end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

function ns.SetProfile(name, silent)
  local db = ns.db
  if not db or not db.profiles[name] then return false end
  ns.profileName = name
  ns.profile = db.profiles[name]
  ns.SanitizeProfile(ns.profile)
  db.charProfile[ns.CharKey()] = name
  if not silent then ns.Fire("PROFILE_CHANGED") end
  return true
end

function ns.CreateProfile(name, copyFrom)
  name = ns.Trim(name)
  if name == "" or ns.db.profiles[name] then return false end
  if copyFrom and ns.db.profiles[copyFrom] then
    ns.db.profiles[name] = ns.CopyTable(ns.db.profiles[copyFrom])
  else
    ns.db.profiles[name] = ns.NewProfileTable(false)
  end
  ns.SetProfile(name)
  return true
end

function ns.DeleteProfile(name)
  local db = ns.db
  if not db.profiles[name] then return false end
  local count = 0
  for _ in pairs(db.profiles) do count = count + 1 end
  if count <= 1 then return false end
  db.profiles[name] = nil
  for key, p in pairs(db.charProfile) do
    if p == name then db.charProfile[key] = nil end
  end
  if ns.profileName == name then
    local names = ns.GetProfileNames()
    ns.SetProfile(db.profiles.Default and "Default" or names[1])
  else
    ns.Fire("PROFILE_CHANGED")
  end
  return true
end

local function InitDB()
  if type(PassLootForeverDB) ~= "table" then PassLootForeverDB = {} end
  local db = PassLootForeverDB
  ns.db = db
  db.version = tonumber(db.version) or 1
  if db.enabled == nil then db.enabled = true end
  db.scale = tonumber(db.scale) or 1
  if type(db.minimap) ~= "table" then db.minimap = {} end
  db.minimap.hide = db.minimap.hide and true or false
  db.minimap.angle = tonumber(db.minimap.angle) or 215
  if type(db.profiles) ~= "table" then db.profiles = {} end
  if type(db.charProfile) ~= "table" then db.charProfile = {} end
  if not next(db.profiles) then db.profiles.Default = ns.NewProfileTable(true) end
  local name = db.charProfile[ns.CharKey()]
  if not name or not db.profiles[name] then
    name = db.profiles.Default and "Default" or next(db.profiles)
  end
  ns.SetProfile(name, true)
end

ns.RegisterEvent("ADDON_LOADED", function(_, loaded)
  if loaded ~= addonName then return end
  InitDB()
  ns.Fire("DB_READY")
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function PrintHelp()
  ns.Print(L["Commands:"])
  ns.Print("  /plf - " .. L["open or close the window"])
  ns.Print("  /plf on | off - " .. L["enable or disable the addon"])
  ns.Print("  /plf test <" .. L["item link, ID or name"] .. "> - " .. L["see how an item would be rolled"])
  ns.Print("  /plf profile <" .. L["name"] .. "> - " .. L["switch profile"])
  ns.Print("  /plf diag - " .. L["show API availability on this client"])
  ns.Print("  /plf minimap - " .. L["show or hide the minimap button"])
  ns.Print("  /plf debug - " .. L["toggle debug messages"])
end

SLASH_PASSLOOTFOREVER1 = "/plf"
SLASH_PASSLOOTFOREVER2 = "/passloot"
SlashCmdList["PASSLOOTFOREVER"] = function(msg)
  if not ns.db then return end
  local cmd, rest = tostring(msg or ""):match("^(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.UI then ns.UI.Toggle() end
  elseif cmd == "on" then
    ns.db.enabled = true
    ns.Print(L["Enabled."])
    ns.Fire("ENABLED_CHANGED")
  elseif cmd == "off" then
    ns.db.enabled = false
    ns.Print(L["Disabled."])
    ns.Fire("ENABLED_CHANGED")
  elseif cmd == "test" then
    if rest == "" then
      ns.Print(L["Usage: /plf test <item link, ID or name>"])
    else
      ns.Engine.Test(rest, function(result) ns.Engine.PrintTest(result) end)
    end
  elseif cmd == "profile" then
    if rest == "" then
      ns.Print(L["Current profile:"] .. " " .. tostring(ns.profileName))
    elseif ns.db.profiles[rest] then
      ns.SetProfile(rest)
      ns.Print(L["Current profile:"] .. " " .. rest)
    else
      ns.Print(L["Unknown profile."])
    end
  elseif cmd == "diag" then
    for _, line in ipairs(ns.Diagnostics()) do ns.Print(line) end
  elseif cmd == "minimap" then
    if ns.Minimap then
      local show = ns.db.minimap.hide
      ns.Minimap.SetShown(show)
      ns.Print(show and L["Minimap button shown."] or L["Minimap button hidden."])
      if ns.UI and ns.UI.RefreshOptions then ns.UI.RefreshOptions() end
    end
  elseif cmd == "debug" then
    ns.db.debug = not ns.db.debug
    ns.Print("debug: " .. tostring(ns.db.debug))
  else
    PrintHelp()
  end
end
