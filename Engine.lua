-- PassLoot Forever - Engine: rule evaluation, rolling, confirmation, log and test mode.
local addonName, ns = ...
local L = ns.L
local API, Items, Filters = ns.API, ns.Items, ns.Filters

local Engine = {}
ns.Engine = Engine

Engine.handled = {}   -- [rollID] = true once we looked at that roll
Engine.cancelled = {} -- [rollID] = true if the roll vanished before we answered
Engine.pending = {}   -- [rollID] = roll type we sent (used to auto-confirm only our own rolls)
Engine.awaiting = {}  -- [rollID] = roll sent, waiting for the game's "You have selected ..." message

-- Delays (seconds): before the first roll, and before checking that the game took it into account.
Engine.ROLL_DELAY = 0.3
Engine.CONFIRM_TIMEOUT = 3
Engine.RECIPE_RETRY_DELAY = 0.8
Engine.log = {}
local MAX_LOG = 50

function Engine.ActionLabel(action)
  if action == "need" then return NEED or L["Need"]
  elseif action == "greed" then return GREED or L["Greed"]
  elseif action == "de" then return ROLL_DISENCHANT or L["Disenchant"]
  elseif action == "pass" then return PASS or L["Pass"] end
  return L["Ignored"]
end

Engine.ACTION_COLOR = {
  need = "ff55dd55", greed = "ffffd34d", de = "ffb06cff", pass = "ff9a9a9a", ignored = "ffff7a5c",
}

------------------------------------------------------------------------
-- Context (information about the situation that is not in the item)
------------------------------------------------------------------------
local function ReadPlace()
  local iname, itype
  if GetInstanceInfo then iname, itype = GetInstanceInfo() end
  if ns.IsSecret(iname) then iname = nil end
  if ns.IsSecret(itype) then itype = nil end
  local zone = iname
  if (not zone or zone == "") and GetRealZoneText then
    zone = GetRealZoneText()
    if ns.IsSecret(zone) then zone = nil end
  end
  return itype or "none", zone
end

function Engine.BuildContext(info, allAvailable)
  local ctx = { roll = info or {}, can = { need = false, greed = false, de = false } }
  if allAvailable then
    ctx.can.need, ctx.can.greed, ctx.can.de = true, true, true
  elseif info then
    ctx.can.need = info.canNeed == true
    ctx.can.greed = info.canGreed == true
    ctx.can.de = info.canDE == true
  end
  if IsInRaid and IsInRaid() then ctx.groupType = "raid"
  elseif IsInGroup and IsInGroup() then ctx.groupType = "party"
  else ctx.groupType = "solo" end
  ctx.instanceType, ctx.zone = ReadPlace()
  return ctx
end

------------------------------------------------------------------------
-- Rule evaluation
------------------------------------------------------------------------
local function GroupDescription(g)
  local parts = {}
  for _, c in ipairs(g.normal) do parts[#parts + 1] = Filters.Describe(c) end
  local text = table.concat(parts, " " .. L["OR"] .. " ")
  if #g.exc > 0 then
    local ex = {}
    for _, c in ipairs(g.exc) do ex[#ex + 1] = Filters.Describe(c) end
    local excText = L["NOT"] .. " (" .. table.concat(ex, " " .. L["OR"] .. " ") .. ")"
    text = (text ~= "") and (text .. " " .. L["AND"] .. " " .. excText) or excText
  end
  return text
end

-- Returns true, false (+ description of the failing filter) or nil (+ reason) if the rule cannot be evaluated.
function Engine.RuleMatches(rule, item, ctx)
  local order, groups = {}, {}
  for _, c in ipairs(rule.conds) do
    local g = groups[c.f]
    if not g then
      g = { normal = {}, exc = {} }
      groups[c.f] = g
      order[#order + 1] = c.f
    end
    table.insert(c.x and g.exc or g.normal, c)
  end
  for _, key in ipairs(order) do
    local def = Filters.byKey[key]
    if not def then return nil, L["unknown filter"] .. ": " .. tostring(key) end
    local g = groups[key]
    local normalMatch, excMatch = false, false
    for _, c in ipairs(g.normal) do
      if Filters.Eval(def, item, ctx, c.v) then normalMatch = true; break end
    end
    for _, c in ipairs(g.exc) do
      if Filters.Eval(def, item, ctx, c.v) then excMatch = true; break end
    end
    local pass = (#g.normal == 0 or normalMatch) and not excMatch
    if not pass then return false, GroupDescription(g) end
  end
  return true
end

function Engine.PickAction(rule, ctx)
  local want = {}
  for _, a in ipairs(rule.loot) do want[a] = true end
  for _, a in ipairs(ns.ORDER) do
    if want[a] and (a == "pass" or ctx.can[a]) then return a end
  end
  return nil
end

-- The first enabled rule that matches decides (even if it ends up "ignore").
function Engine.Decide(item, ctx, trace)
  for i, rule in ipairs(ns.profile.rules) do
    if rule.enabled then
      local matched, why = Engine.RuleMatches(rule, item, ctx)
      if trace then trace[#trace + 1] = { index = i, rule = rule, matched = matched, why = why } end
      if matched then
        return { index = i, rule = rule, action = Engine.PickAction(rule, ctx) }
      end
    elseif trace then
      trace[#trace + 1] = { index = i, rule = rule, disabled = true }
    end
  end
  return nil
end

------------------------------------------------------------------------
-- Log
------------------------------------------------------------------------
function Engine.AddLog(entry)
  table.insert(Engine.log, entry)
  while #Engine.log > MAX_LOG do table.remove(Engine.log, 1) end
  ns.Fire("LOG_UPDATED")
end

function Engine.ClearLog()
  for i = #Engine.log, 1, -1 do Engine.log[i] = nil end
  ns.Fire("LOG_UPDATED")
end

------------------------------------------------------------------------
-- Real rolls
------------------------------------------------------------------------
local function ReadRollInfo(rollID)
  local info = {}
  if not API.GetRollItemInfo then return info end
  local texture, name, count, quality, bop, canNeed, canGreed, canDE = API.GetRollItemInfo(rollID)
  info.texture = ns.Clean(texture)
  info.name = ns.Clean(name)
  info.count = ns.Clean(count)
  info.quality = ns.Clean(quality)
  info.bop = ns.Clean(bop) == true
  info.canNeed = ns.Clean(canNeed) == true
  info.canGreed = ns.Clean(canGreed) == true
  info.canDE = ns.Clean(canDE) == true
  return info
end

local function FormatMessage(template, itemLink, ruleName)
  local msg = tostring(template or "")
  msg = msg:gsub("%%item%%", function() return itemLink end)
  msg = msg:gsub("%%rule%%", function() return ruleName end)
  return msg
end

------------------------------------------------------------------------
-- Checking that a roll really went through
-- The game confirms each of your own rolls with a chat line ("You have selected Greed for: [item]").
-- The addon waits for that line before announcing the roll; without it, it tries once more, then warns.
------------------------------------------------------------------------
local SELF_STRINGS = {
  need = { "LOOT_ROLL_NEED_SELF" },
  greed = { "LOOT_ROLL_GREED_SELF" },
  de = { "LOOT_ROLL_DISENCHANT_SELF" },
  pass = { "LOOT_ROLL_PASSED_SELF", "LOOT_ROLL_PASSED_SELF_AUTO" },
}
local selfPatterns

-- "You have selected Greed for: %s" -> "^You have selected Greed for: (.+)$"
local function ToPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local p = fmt:gsub("%%%d?%$?s", "\001")
  p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("\001", "(.+)")
  if not p:find("(.+)", 1, true) then return nil end
  return "^" .. p .. "$"
end

local function SelfPatterns()
  if selfPatterns then return selfPatterns end
  selfPatterns = {}
  for action, names in pairs(SELF_STRINGS) do
    for _, name in ipairs(names) do
      local pat = ToPattern(_G[name])
      if pat then selfPatterns[#selfPatterns + 1] = { action = action, pattern = pat } end
    end
  end
  return selfPatterns
end

function Engine.CanVerify()
  return C_Timer ~= nil and C_Timer.After ~= nil and #SelfPatterns() > 0
end

-- The game's own roll window (GroupLootFrame1..4) for a roll, if it is shown.
local function RollFrameShown(rollID)
  for i = 1, (tonumber(NUM_GROUP_LOOT_FRAMES) or 4) do
    local f = _G["GroupLootFrame" .. i]
    if f and f.IsShown and f:IsShown() and ns.Clean(f.rollID) == rollID then return true end
  end
  return false
end

local function Later(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

local function Announce(entry, ok)
  if entry.finished then return end
  entry.finished = true
  Engine.awaiting[entry.rollID] = nil
  local action = ok and entry.action or nil
  Engine.AddLog({
    t = time and time() or 0, link = entry.item.link, name = entry.item.name or entry.info.name,
    icon = entry.item.icon or entry.info.texture, action = action or "ignored", rule = entry.rule.name, index = entry.index,
  })
  if ok then
    if not ns.profile.quiet then
      ns.Print(FormatMessage(ns.profile.messages[action], entry.itemLink, entry.rule.name))
    end
  else
    -- always shown, even in quiet mode: the player has to roll by hand
    ns.Print(string.format(L["|cffff7a5cThe game did not confirm the automatic roll (%s) on %s: check the roll window.|r (%s)"],
      Engine.ActionLabel(entry.action), entry.itemLink, entry.rule.name))
  end
end

local function Send(entry)
  if entry.finished then return end
  if Engine.cancelled[entry.rollID] then
    -- the roll ended before we could send ours
    Announce(entry, false)
    return
  end
  entry.tries = entry.tries + 1
  -- the game's roll window closes once our roll is accepted: remember that it was open
  if RollFrameShown(entry.rollID) then entry.frameSeen = true end
  Engine.pending[entry.rollID] = API.ROLLTYPE[entry.action]
  local ok = pcall(API.RollOnLoot, entry.rollID, API.ROLLTYPE[entry.action])
  ns.Debug("RollOnLoot", entry.rollID, entry.action, "try", entry.tries, ok and "" or "(error)")
  if not entry.verify then Announce(entry, true) return end
  Later(Engine.CONFIRM_TIMEOUT, function()
    if entry.finished or entry.waitingPopup then return end
    if entry.secretSeen then
      ns.Debug("roll", entry.rollID, "taken as confirmed (game message hidden from addons)")
      Announce(entry, true)
    elseif entry.frameSeen and not RollFrameShown(entry.rollID) then
      -- the roll window was open and closed itself: the game accepted the roll
      ns.Debug("roll", entry.rollID, "confirmed by the roll window closing")
      Announce(entry, true)
    elseif Engine.cancelled[entry.rollID] then
      -- the roll is over and the game never confirmed ours
      Announce(entry, false)
    elseif entry.tries < 2 then
      Send(entry)
    else
      Announce(entry, false)
    end
  end)
end

-- Game chat line about one of our own rolls.
local function OldestAwaiting()
  local best
  for _, entry in pairs(Engine.awaiting) do
    if not entry.finished and entry.tries > 0 and (not best or entry.rollID < best.rollID) then best = entry end
  end
  return best
end

-- Own rolls seen in chat, by item ID (time), so that a roll the player already made by hand is left alone.
Engine.selfRolled = {}
local function Now() return GetTime and GetTime() or 0 end

local function SelfRolledSince(itemID, since)
  local t = itemID and Engine.selfRolled[itemID]
  return t ~= nil and t >= since
end

local function OnLootMessage(_, msg)
  if ns.IsSecret(msg) then
    if not next(Engine.awaiting) then return end
    -- some game messages are hidden from addons (boss loot, encounters): we cannot read it, but a loot
    -- line arriving right after our roll is taken as its confirmation rather than raising a false alarm
    ns.Debug("CHAT_MSG_LOOT: <hidden from addons>")
    local entry = OldestAwaiting()
    if entry and not entry.secretSeen then entry.secretSeen = true end
    return
  end
  if type(msg) ~= "string" then return end
  if next(Engine.awaiting) then ns.Debug("CHAT_MSG_LOOT:", msg) end
  for _, p in ipairs(SelfPatterns()) do
    local link = msg:match(p.pattern)
    if link then
      local id = tonumber(link:match("item:(%d+)"))
      local best
      for _, entry in pairs(Engine.awaiting) do
        if not entry.finished and (not id or entry.item.id == id) and (not best or entry.rollID < best.rollID) then
          best = entry
        end
      end
      if not best and id then
        -- not one of ours: the player rolled this item by hand
        Engine.selfRolled[id] = Now()
      end
      if best then
        if best.action == p.action then
          Announce(best, true)
        else
          -- the player rolled something else by hand: nothing to announce
          best.finished = true
          Engine.awaiting[best.rollID] = nil
        end
      end
      return
    end
  end
end
ns.RegisterEvent("CHAT_MSG_LOOT", OnLootMessage)

local function Apply(rollID, item, info, decision)
  if not decision then return end
  local rule, action = decision.rule, decision.action
  local itemLink = item.link or item.name or info.name or "?"

  if action and not API.RollOnLoot then
    ns.Print(L["RollOnLoot is not available on this client. Run /plf diag."])
    action = nil
  end

  if not action then
    Engine.AddLog({
      t = time and time() or 0, link = item.link, name = item.name or info.name,
      icon = item.icon or info.texture, action = "ignored", rule = rule.name, index = decision.index,
    })
    if not ns.profile.quiet then ns.Print(FormatMessage(ns.profile.messages.ignore, itemLink, rule.name)) end
    return
  end

  local entry = {
    rollID = rollID, item = item, info = info, rule = rule, index = decision.index, action = action,
    itemLink = itemLink, tries = 0, verify = Engine.CanVerify(),
  }
  if entry.verify then Engine.awaiting[rollID] = entry end
  Send(entry)
end

function Engine.OnStartRoll(_, rollID)
  if not ns.db or not ns.db.enabled or not ns.profile then return end
  rollID = ns.Clean(rollID)
  if not rollID or Engine.handled[rollID] then return end
  Engine.handled[rollID] = true

  -- keep the bookkeeping tables small
  local n = 0
  for _ in pairs(Engine.handled) do n = n + 1 end
  if n > 300 then
    Engine.handled, Engine.cancelled, Engine.pending, Engine.awaiting = { [rollID] = true }, {}, {}, {}
    Engine.selfRolled = {}
  end

  if not API.GetRollItemLink then
    ns.Debug("GetLootRollItemLink is missing")
    return
  end
  local link = API.GetRollItemLink(rollID)
  if not link or ns.IsSecret(link) then
    ns.Debug("no usable item link for roll", rollID)
    return
  end

  local info = ReadRollInfo(rollID)
  local started = Now()
  -- A short delay before deciding lets the game finish loading the item and its tooltip (needed for
  -- "Already known" on recipes) and lets interface addons set up their roll window.
  Later(Engine.ROLL_DELAY, function()
    if Engine.cancelled[rollID] then return end
    Items.Resolve(link, function(item)
      if Engine.cancelled[rollID] then return end
      if not item.quality then item.quality = info.quality end
      if not item.name then item.name = info.name end
      if not item.icon then item.icon = info.texture end
      local function decide(lastTry)
        if Engine.cancelled[rollID] then return end
        if SelfRolledSince(item.id, started) then
          ns.Debug("roll", rollID, "already rolled by hand")
          return
        end
        -- recipe tooltip not complete yet: give it one more moment before deciding
        if not lastTry and item.classID == 9 and Items.IsKnown(item) == nil then
          ns.Debug("roll", rollID, "recipe tooltip not ready, waiting")
          Later(Engine.RECIPE_RETRY_DELAY, function() decide(true) end)
          return
        end
        local ctx = Engine.BuildContext(info, false)
        Apply(rollID, item, info, Engine.Decide(item, ctx))
      end
      decide(false)
    end)
  end)
end

ns.RegisterEvent("START_LOOT_ROLL", Engine.OnStartRoll)

ns.RegisterEvent("CANCEL_LOOT_ROLL", function(_, rollID)
  rollID = ns.Clean(rollID)
  if not rollID then return end
  Engine.cancelled[rollID] = true
  Engine.pending[rollID] = nil
end)

-- Auto-confirm "this will bind" / disenchant popups, but only for rolls this addon sent itself.
local function MakeConfirmHandler(optionKey)
  return function(_, rollID, rollType)
    rollID = ns.Clean(rollID)
    if not rollID or not ns.profile then return end
    local waiting = Engine.awaiting[rollID]
    if not ns.profile[optionKey] then
      -- the game asks the player to confirm: the roll will only go through once they click
      if waiting then waiting.waitingPopup = true end
      return
    end
    local sent = Engine.pending[rollID]
    if sent == nil then return end
    rollType = ns.Clean(rollType)
    if rollType ~= nil and rollType ~= sent then return end
    if API.ConfirmLootRoll then
      API.ConfirmLootRoll(rollID, sent)
      if StaticPopup_Hide then pcall(StaticPopup_Hide, "CONFIRM_LOOT_ROLL", rollID) end
    end
  end
end
ns.RegisterEvent("CONFIRM_LOOT_ROLL", MakeConfirmHandler("confirmBoP"))
ns.RegisterEvent("CONFIRM_DISENCHANT_ROLL", MakeConfirmHandler("confirmDE"))

------------------------------------------------------------------------
-- Test mode
------------------------------------------------------------------------
function Engine.Test(text, cb)
  text = ns.Trim(text)
  if text == "" then
    cb({ error = L["Enter an item link, ID or name."] })
    return
  end
  -- Any colour code (|cffxxxxxx or the newer |cnIQ4:) followed by an item hyperlink, or a bare "item:12345..." string.
  local link = text:match("(|c[^|]*|Hitem:.-|h.-|h|r)") or text:match("(|Hitem:.-|h.-|h)") or text:match("(item:[%d:%-]+)")
  local source = link or tonumber(text) or text
  Items.Resolve(source, function(item)
    if not item.id then
      cb({ error = L["Item not found. Names only work for items already seen this session."] })
      return
    end
    local ctx = Engine.BuildContext(nil, true)
    local trace = {}
    local decision = Engine.Decide(item, ctx, trace)
    cb({ item = item, ctx = ctx, trace = trace, decision = decision })
  end)
end

-- Turns a test result into printable lines (shared by chat and by the Test tab).
function Engine.DescribeResult(result)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  if result.error then
    add("|cffff7a5c" .. result.error .. "|r")
    return lines
  end
  local item = result.item
  add("|cffd4a85a" .. (item.link or item.name or ("item:" .. tostring(item.id))) .. "|r")
  if not item.complete then
    add("|cffff7a5c" .. L["Item data is not fully loaded yet; some conditions may not match. Try again in a moment."] .. "|r")
  end
  add(string.format("|cff9a9a9a%s %s  |  %s %s  |  %s %s|r",
    L["Item level"], tostring(item.ilvl or "?"),
    L["Required level"], tostring(item.minLevel or "?"),
    L["Quality"], tostring(item.quality or "?")))
  if item.classID == 9 and ns.Filters and ns.Filters.RecipeFacts then
    local ok, f = pcall(ns.Filters.RecipeFacts, item)
    if ok and f then
      local function yn(v) return v == true and L["yes"] or (v == false and L["no"] or L["unknown"]) end
      add(string.format("|cff9a9a9a%s  |  %s %s  |  %s %s|r", L["Recipe"],
        L["already learned:"], yn(f.known), L["for my profession:"], yn(f.mine)))
    end
  end
  for _, t in ipairs(result.trace) do
    local head = string.format("%d. %s", t.index, t.rule.name)
    if t.disabled then
      add("|cff777777" .. head .. " - " .. L["disabled"] .. "|r")
    elseif t.matched == nil then
      add("|cffff7a5c" .. head .. " - " .. L["skipped"] .. " (" .. tostring(t.why) .. ")|r")
    elseif t.matched then
      add("|cff55dd55" .. head .. " - " .. L["matches"] .. "|r")
    else
      add("|cff9a9a9a" .. head .. " - " .. L["does not match"] .. ": " .. tostring(t.why) .. "|r")
    end
  end
  local d = result.decision
  if not d then
    add("|cffd4a85a" .. L["Result:"] .. "|r " .. L["No rule matched. You would roll manually."])
  elseif d.action then
    add("|cffd4a85a" .. L["Result:"] .. "|r |c" .. Engine.ACTION_COLOR[d.action] .. Engine.ActionLabel(d.action) .. "|r (" .. d.rule.name .. ")")
  else
    add("|cffd4a85a" .. L["Result:"] .. "|r |c" .. Engine.ACTION_COLOR.ignored .. L["Ignored"] .. "|r (" .. d.rule.name .. ") - " .. L["no available choice"])
  end
  if ns.Stats then
    local ok, extra = pcall(ns.Stats.Describe, item)
    if ok and #extra > 0 then
      add(" ")
      for _, s in ipairs(extra) do add(s) end
    end
  end
  return lines
end

function Engine.PrintTest(result)
  for _, line in ipairs(Engine.DescribeResult(result)) do ns.Print(line) end
end
