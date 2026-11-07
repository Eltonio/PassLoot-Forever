-- PassLoot Forever - UI: custom window (rules editor, options, journal, test) built from plain frames and textures.
-- No Blizzard templates are used on purpose: they are the most likely thing to change between builds.
local addonName, ns = ...
local L = ns.L
local Filters, Engine = ns.Filters, ns.Engine

local UI = {}
ns.UI = UI

local COL = {
  bg = { 0.055, 0.055, 0.07, 0.97 }, panel = { 0.095, 0.095, 0.12, 1 },
  row = { 0.115, 0.115, 0.145, 1 }, rowAlt = { 0.098, 0.098, 0.126, 1 },
  hover = { 0.22, 0.19, 0.11, 1 }, select = { 0.30, 0.23, 0.09, 1 }, active = { 0.33, 0.26, 0.10, 1 },
  border = { 0.30, 0.26, 0.17, 1 }, gold = { 0.83, 0.66, 0.35 }, text = { 0.92, 0.92, 0.92 },
  muted = { 0.60, 0.60, 0.64 }, good = { 0.35, 0.80, 0.45 }, bad = { 0.92, 0.38, 0.32 },
}

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local function Rect(parent, layer, c)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return t
end

-- 1-point borders can fall under one real pixel with some resolutions / UI scales, and the game then
-- rounds some edges away. Every edge is sized to at least one physical pixel, and resized when the
-- scale changes.
local allEdges = {}
local function SizeEdge(t)
  local horizontal = t.horizontal
  if PixelUtil and PixelUtil.SetHeight and PixelUtil.SetWidth then
    local ok = pcall(horizontal and PixelUtil.SetHeight or PixelUtil.SetWidth, t, 1, 1)
    if ok then return end
  end
  if horizontal then t:SetHeight(1) else t:SetWidth(1) end
end

function UI.RefreshEdges()
  for i = 1, #allEdges do SizeEdge(allEdges[i]) end
end

local function Border(frame, c)
  c = c or COL.border
  local function edge(p1, p2, horizontal)
    local t = Rect(frame, "BORDER", c)
    t:SetPoint(p1); t:SetPoint(p2)
    t.horizontal = horizontal
    SizeEdge(t)
    allEdges[#allEdges + 1] = t
    return t
  end
  local top = edge("TOPLEFT", "TOPRIGHT", true)
  local bottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  local left = edge("TOPLEFT", "BOTTOMLEFT", false)
  local right = edge("TOPRIGHT", "BOTTOMRIGHT", false)
  frame.edges = { top, bottom, left, right }
  frame.SetBorderColor = function(self, color)
    for _, e in ipairs(self.edges) do e:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
  end
end

local function Label(parent, text, font, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetText(text or "")
  local c = color or COL.text
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function ShowIf(frame, cond)
  if cond then frame:Show() else frame:Hide() end
end

-- True when a single-line font string does not show its whole text.
local function IsCut(fs)
  if not fs or not fs:IsShown() then return false end
  if fs.IsTruncated then
    local ok, cut = pcall(fs.IsTruncated, fs)
    if ok and cut ~= nil then return cut and true or false end
  end
  local w = fs:GetWidth() or 0
  return w > 0 and (fs:GetStringWidth() or 0) > w + 1
end

local function AttachTip(frame, title, text)
  frame:HookScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0.3)
    if text and text ~= "" then GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = Rect(b, "BACKGROUND", COL.panel)
  b.bg:SetAllPoints()
  Border(b)
  b.label = Label(b, text, "GameFontHighlightSmall", COL.text, "CENTER")
  b.label:SetPoint("LEFT", 4, 0)
  b.label:SetPoint("RIGHT", -4, 0)
  b.label:SetWordWrap(false) -- never spill on two lines over the neighbours; "..." instead
  b.baseColor = COL.panel
  b.SetLabel = function(self, t) self.label:SetText(t) end
  b.SetBase = function(self, c)
    self.baseColor = c
    self.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  end
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(COL.hover[1], COL.hover[2], COL.hover[3], 1)
    if GameTooltip and IsCut(self.label) then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.label:GetText() or "", 1, 1, 1, 1, true)
      GameTooltip:Show()
      self.cutTip = true
    end
  end)
  b:SetScript("OnLeave", function(self)
    self:SetBase(self.baseColor)
    if self.cutTip and GameTooltip then GameTooltip:Hide() end
    self.cutTip = nil
  end)
  b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
  return b
end

-- Small square button with a drawn cross (a font "x" never sits exactly in the middle).
local function CrossButton(parent, size, onClick)
  local b = Button(parent, "", size, size, onClick)
  local canRotate = false
  for i = 1, 2 do
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(COL.text[1], COL.text[2], COL.text[3], 1)
    t:SetSize(math.floor(size * 0.55 + 0.5), 2)
    t:SetPoint("CENTER", b, "CENTER", 0, 0)
    if t.SetRotation then
      canRotate = pcall(t.SetRotation, t, (i == 1) and math.rad(45) or math.rad(-45)) or canRotate
    end
    b["bar" .. i] = t
  end
  if not canRotate then
    b.bar1:Hide(); b.bar2:Hide()
    b:SetLabel("x")
    b.label:ClearAllPoints()
    b.label:SetPoint("CENTER", b, "CENTER", 1, 1)
  end
  return b
end

-- Button that needs a second click within three seconds (used for destructive actions).
local function ConfirmButton(parent, text, w, h, onConfirm)
  local armedToken = 0
  local b
  b = Button(parent, text, w, h, function(self)
    if self.armed then
      self.armed = false
      armedToken = armedToken + 1
      self:SetLabel(text)
      onConfirm()
    else
      self.armed = true
      armedToken = armedToken + 1
      local token = armedToken
      self:SetLabel(L["Confirm?"])
      if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
          if token == armedToken and b.armed then
            b.armed = false
            b:SetLabel(text)
          end
        end)
      end
    end
  end)
  return b
end

local function Check(parent, text, width, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 20)
  local box = CreateFrame("Frame", nil, b)
  box:SetSize(16, 16)
  box:SetPoint("LEFT")
  local bg = Rect(box, "BACKGROUND", COL.panel)
  bg:SetAllPoints()
  Border(box)
  local mark = Rect(box, "ARTWORK", COL.gold)
  mark:SetPoint("TOPLEFT", 3, -3)
  mark:SetPoint("BOTTOMRIGHT", -3, 3)
  local label = Label(b, text, "GameFontHighlight")
  label:SetPoint("LEFT", box, "RIGHT", 8, 0)
  b.Refresh = function(self) ShowIf(mark, get()) end
  b:SetScript("OnClick", function(self) set(not get()); self:Refresh() end)
  b:SetScript("OnEnter", function() box:SetBorderColor(COL.gold) end)
  b:SetScript("OnLeave", function() box:SetBorderColor(COL.border) end)
  b:Refresh()
  return b
end

local function Edit(parent, w, h, onCommit)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, h)
  e:SetAutoFocus(false)
  e:SetMultiLine(false)
  e:SetFontObject(ChatFontNormal)
  e:SetTextInsets(6, 6, 0, 0)
  local bg = Rect(e, "BACKGROUND", { 0.04, 0.04, 0.05, 1 })
  bg:SetAllPoints()
  Border(e)
  e:SetScript("OnEditFocusGained", function(self)
    self.original = self:GetText()
    self:SetBorderColor(COL.gold)
  end)
  e:SetScript("OnEscapePressed", function(self)
    self.cancelled = true
    self:SetText(self.original or "")
    self:ClearFocus()
  end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self)
    self:SetBorderColor(COL.border)
    if self.cancelled then self.cancelled = false; return end
    if onCommit then onCommit(self:GetText(), self) end
  end)
  return e
end

-- Virtual scrolling list: a fixed number of row frames re-bound to the data.
local function List(parent, width, rowH, nRows, buildRow, bindRow)
  local list = CreateFrame("Frame", nil, parent)
  list:SetSize(width, rowH * nRows)
  list.offset, list.count, list.rows = 0, 0, {}
  local track = Rect(list, "BACKGROUND", { 0.14, 0.14, 0.18, 1 })
  track:SetWidth(4)
  track:SetPoint("TOPRIGHT")
  track:SetPoint("BOTTOMRIGHT")
  local thumb = Rect(list, "ARTWORK", { 0.55, 0.45, 0.25, 1 })
  thumb:SetWidth(4)

  for i = 1, nRows do
    local row = buildRow(list, i)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowH)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -(i - 1) * rowH)
    row:SetHeight(rowH)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) list:Scroll(delta) end)
    list.rows[i] = row
  end

  list.Refresh = function(self)
    local maxOffset = math.max(0, self.count - nRows)
    if self.offset > maxOffset then self.offset = maxOffset end
    if self.offset < 0 then self.offset = 0 end
    for i, row in ipairs(self.rows) do
      local idx = self.offset + i
      if idx <= self.count then
        row.index = idx
        bindRow(row, idx)
        row:Show()
      else
        row:Hide()
      end
    end
    if self.count > nRows then
      local trackH = rowH * nRows
      local h = math.max(16, trackH * nRows / self.count)
      local y = (trackH - h) * self.offset / (self.count - nRows)
      thumb:SetHeight(h)
      thumb:ClearAllPoints()
      thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -y)
      thumb:Show()
    else
      thumb:Hide()
    end
  end
  list.SetCount = function(self, n) self.count = n; self:Refresh() end
  list.Scroll = function(self, delta) self.offset = self.offset - delta * 2; self:Refresh() end
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, delta) self:Scroll(delta) end)
  return list
end

------------------------------------------------------------------------
-- Popup menu (one shared instance)
------------------------------------------------------------------------
local MENU_ROWS, MENU_ROW_H = 14, 22
local menu, menuCatcher

function UI.CloseMenu()
  if menu then menu:Hide() end
  if menuCatcher then menuCatcher:Hide() end
end

local function BuildMenu()
  if menu then return end
  menuCatcher = CreateFrame("Button", nil, UIParent)
  menuCatcher:SetAllPoints(UIParent)
  menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
  menuCatcher:SetFrameLevel(1)
  menuCatcher:Hide()
  menuCatcher:SetScript("OnClick", UI.CloseMenu)

  menu = CreateFrame("Frame", "PassLootForeverMenu", UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetFrameLevel(10)
  menu:EnableMouse(true)
  menu:Hide()
  local bg = Rect(menu, "BACKGROUND", { 0.07, 0.07, 0.09, 0.99 })
  bg:SetAllPoints()
  Border(menu)
  menu.rows, menu.offset = {}, 0

  for i = 1, MENU_ROWS do
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(MENU_ROW_H)
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * MENU_ROW_H)
    row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * MENU_ROW_H)
    row.hl = Rect(row, "BACKGROUND", COL.hover)
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.text = Label(row, "", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetPoint("RIGHT", -8, 0)
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
      self.hl:Show()
      local e = self.entry
      if e and e.tip and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.tip, 0.9, 0.9, 0.9, 1, true)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function(self)
      self.hl:Hide()
      if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
      local e = self.entry
      if not e then return end
      local cb = menu.onSelect
      UI.CloseMenu()
      if cb then cb(e.value, e) end
    end)
    menu.rows[i] = row
  end

  menu.RefreshRows = function(self)
    local n = #self.entries
    local maxOffset = math.max(0, n - MENU_ROWS)
    if self.offset > maxOffset then self.offset = maxOffset end
    if self.offset < 0 then self.offset = 0 end
    for i, row in ipairs(self.rows) do
      local e = self.entries[self.offset + i]
      if e then
        row.entry = e
        local selected = self.selected ~= nil and tostring(e.value) == tostring(self.selected)
        row.text:SetText(e.label)
        if selected then SetColor(row.text, COL.gold) else SetColor(row.text, COL.text) end
        row:Show()
      else
        row.entry = nil
        row:Hide()
      end
    end
  end
  menu:EnableMouseWheel(true)
  menu:SetScript("OnMouseWheel", function(self, delta)
    self.offset = self.offset - delta * 3
    self:RefreshRows()
  end)
end

-- entries = { { value=, label=, tip= }, ... }; onSelect(value, entry)
function UI.ShowMenu(anchor, entries, onSelect, selected, width)
  if #entries == 0 then return end
  BuildMenu()
  menu.entries, menu.onSelect, menu.selected, menu.offset = entries, onSelect, selected, 0
  local n = #entries
  local visible = math.min(n, MENU_ROWS)
  local height = visible * MENU_ROW_H + 8
  menu:SetSize(width or 240, height)

  local scale = anchor:GetEffectiveScale()
  local uiScale = UIParent:GetEffectiveScale()
  if type(scale) == "number" and type(uiScale) == "number" and uiScale > 0 then
    menu:SetScale(scale / uiScale)
  end
  menu:ClearAllPoints()
  local bottom = anchor:GetBottom()
  local flip = false
  if type(bottom) == "number" and type(scale) == "number" and type(uiScale) == "number" and uiScale > 0 then
    flip = (bottom * scale / uiScale) - height * (scale / uiScale) < 0
  end
  if flip then
    menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
  else
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  end

  if selected ~= nil then
    for i, e in ipairs(entries) do
      if tostring(e.value) == tostring(selected) then
        menu.offset = math.max(0, math.min(i - 4, n - visible))
        break
      end
    end
  end
  menu:RefreshRows()
  menuCatcher:Show()
  menu:Show()
end

------------------------------------------------------------------------
-- Prompt dialog (one text field)
------------------------------------------------------------------------
local prompt
function UI.Prompt(title, default, onAccept)
  if not prompt then
    prompt = CreateFrame("Frame", "PassLootForeverPrompt", UIParent)
    prompt:SetSize(340, 124)
    prompt:SetPoint("CENTER")
    prompt:SetFrameStrata("FULLSCREEN_DIALOG")
    prompt:SetFrameLevel(30)
    prompt:EnableMouse(true)
    prompt:Hide()
    local bg = Rect(prompt, "BACKGROUND", COL.bg)
    bg:SetAllPoints()
    Border(prompt, COL.gold)
    prompt.title = Label(prompt, "", "GameFontNormal", COL.gold, "CENTER")
    prompt.title:SetPoint("TOP", 0, -14)
    prompt.edit = Edit(prompt, 300, 26, nil)
    prompt.edit:SetPoint("TOP", 0, -42)
    local function accept()
      local text = ns.Trim(prompt.edit:GetText())
      local cb = prompt.onAccept
      prompt:Hide()
      if cb and text ~= "" then cb(text) end
    end
    prompt.edit:SetScript("OnEnterPressed", accept)
    prompt.ok = Button(prompt, OKAY or "OK", 110, 24, accept)
    prompt.ok:SetPoint("BOTTOMLEFT", 24, 14)
    prompt.cancel = Button(prompt, CANCEL or L["Cancel"], 110, 24, function() prompt:Hide() end)
    prompt.cancel:SetPoint("BOTTOMRIGHT", -24, 14)
    table.insert(UISpecialFrames, "PassLootForeverPrompt")
  end
  prompt.title:SetText(title)
  prompt.onAccept = onAccept
  prompt.edit:SetText(default or "")
  prompt:Show()
  prompt.edit:SetFocus()
  prompt.edit:HighlightText()
end

------------------------------------------------------------------------
-- Text dialog for profile export / import (multi-line, scrollable)
------------------------------------------------------------------------
local shareDlg
local function BuildShareDialog()
  local d = CreateFrame("Frame", "PassLootForeverShare", UIParent)
  d:SetSize(560, 330)
  d:SetPoint("CENTER")
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:SetFrameLevel(20)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  d:SetClampedToScreen(true)
  d:Hide()
  local bg = Rect(d, "BACKGROUND", COL.bg)
  bg:SetAllPoints()
  Border(d, COL.gold)
  d.title = Label(d, "", "GameFontNormal", COL.gold, "CENTER")
  d.title:SetPoint("TOP", 0, -14)
  d.help = Label(d, "", "GameFontHighlightSmall", COL.muted, "CENTER")
  d.help:SetPoint("TOP", 0, -36)
  d.help:SetWidth(520)

  local box = CreateFrame("Frame", nil, d)
  box:SetPoint("TOPLEFT", 20, -58)
  box:SetPoint("BOTTOMRIGHT", -20, 74)
  local boxBg = Rect(box, "BACKGROUND", { 0.04, 0.04, 0.05, 1 })
  boxBg:SetAllPoints()
  Border(box)

  local sf = CreateFrame("ScrollFrame", nil, box)
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -6, 6)
  local edit = CreateFrame("EditBox", nil, sf)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(508)
  edit:SetHeight(200)
  if edit.SetMaxLetters then edit:SetMaxLetters(0) end
  sf:SetScrollChild(edit)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local v = (self:GetVerticalScroll() or 0) - delta * 28
    if v < 0 then v = 0 elseif v > range then v = range end
    self:SetVerticalScroll(v)
  end)
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() edit:SetFocus() end)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() edit:SetFocus() end)
  edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
    y = -(y or 0)
    local top, height = sf:GetVerticalScroll() or 0, sf:GetHeight() or 0
    if y < top then sf:SetVerticalScroll(y)
    elseif y + (h or 0) > top + height then sf:SetVerticalScroll(y + (h or 0) - height) end
  end)
  edit:SetScript("OnEscapePressed", function() d:Hide() end)
  edit:SetScript("OnTextChanged", function(self, userInput)
    if d.mode == "export" and userInput then
      -- read-only in export mode: put the text back and keep it selected for Ctrl+C
      self:SetText(d.exportText or "")
      self:HighlightText()
    elseif d.mode == "import" then
      d.status:SetText("")
    end
  end)
  d.edit = edit

  d.status = Label(d, "", "GameFontHighlightSmall", COL.bad, "CENTER")
  d.status:SetPoint("BOTTOM", 0, 50)
  d.status:SetWidth(520)

  d.primary = Button(d, "", 150, 26, function() if d.onPrimary then d.onPrimary() end end)
  d.primary:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
  d.close = Button(d, CLOSE or L["Close"], 150, 26, function() d:Hide() end)
  d.close:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 16)
  table.insert(UISpecialFrames, "PassLootForeverShare")
  return d
end

function UI.ShowExport()
  local text = ns.Share and ns.Share.Export()
  if not text then return end
  shareDlg = shareDlg or BuildShareDialog()
  local d = shareDlg
  d.mode = "export"
  d.exportText = text
  d.title:SetText(L["Export profile"] .. " : " .. tostring(ns.profileName))
  d.help:SetText(L["The text is selected: press Ctrl+C to copy it, then paste it wherever you want (Discord, a text file...)."])
  d.status:SetText("")
  d.primary:SetLabel(L["Select all"])
  d.onPrimary = function() d.edit:SetFocus(); d.edit:HighlightText() end
  d.close:SetLabel(CLOSE or L["Close"])
  d:Show()
  d.edit:SetText(text)
  d.edit:SetFocus()
  d.edit:HighlightText()
end

function UI.ShowImport()
  shareDlg = shareDlg or BuildShareDialog()
  local d = shareDlg
  d.mode = "import"
  d.exportText = nil
  d.title:SetText(L["Import a profile"])
  d.help:SetText(L["Paste (Ctrl+V) a text made with Export, then click Import. A new profile is created."])
  d.status:SetText("")
  d.primary:SetLabel(L["Import"])
  d.close:SetLabel(CANCEL or L["Cancel"])
  d.onPrimary = function()
    local data, err = ns.Share.Decode(d.edit:GetText())
    if not data then d.status:SetText(err); return end
    d:Hide()
    UI.Prompt(L["Name of the imported profile"], ns.Share.FreeName(data.name), function(name)
      if ns.Share.Import(data, name) then
        ns.Print(string.format(L["Profile \"%s\" imported (%d rules) and selected."], name, data.count))
      else
        ns.Print(L["That profile name is not available."])
      end
    end)
  end
  d:Show()
  d.edit:SetText("")
  d.edit:SetFocus()
end

------------------------------------------------------------------------
-- State shared by the pages
------------------------------------------------------------------------
local main, pages, tabs
local rulesList, condList, editor, hintLabel
local nameBox, actionButtons, warnLabel
local journalList, testList, testBox
local optionWidgets = {}
UI.sel = nil
UI.testLines = {}

local function CurrentRule()
  if not ns.profile or not UI.sel then return nil end
  return ns.profile.rules[UI.sel]
end

local function ActionSummary(rule)
  if #rule.loot == 0 then return "|cff9a9a9a" .. L["Ignore (you decide)"] .. "|r" end
  local want, parts = {}, {}
  for _, a in ipairs(rule.loot) do want[a] = true end
  for _, a in ipairs(ns.ORDER) do
    if want[a] then parts[#parts + 1] = "|c" .. Engine.ACTION_COLOR[a] .. Engine.ActionLabel(a) .. "|r" end
  end
  return table.concat(parts, " > ")
end

function UI.RefreshEditor()
  local rule = CurrentRule()
  if not editor then return end
  if not rule then
    editor:Hide()
    hintLabel:Show()
    return
  end
  hintLabel:Hide()
  editor:Show()
  nameBox:SetText(rule.name)
  local want = {}
  for _, a in ipairs(rule.loot) do want[a] = true end
  for _, b in ipairs(actionButtons) do
    if want[b.action] then b:SetBase(COL.active); b.label:SetTextColor(1, 0.9, 0.55)
    else b:SetBase(COL.panel); b.label:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3]) end
  end
  ShowIf(warnLabel, #rule.conds == 0 and #rule.loot > 0)
  condList:SetCount(#rule.conds)
end

function UI.RefreshRules()
  if not rulesList or not ns.profile then return end
  rulesList:SetCount(#ns.profile.rules)
end

function UI.Changed()
  UI.RefreshRules()
  UI.RefreshEditor()
end

local function SelectRule(idx)
  UI.sel = idx
  UI.Changed()
end

------------------------------------------------------------------------
-- Rules page
------------------------------------------------------------------------
local function BuildRuleRow(list, i)
  local row = CreateFrame("Button", nil, list)
  row.bg = Rect(row, "BACKGROUND", COL.row)
  row.bg:SetPoint("TOPLEFT", 0, -1)
  row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
  row.check = CreateFrame("Button", nil, row)
  row.check:SetSize(18, 18)
  row.check:SetPoint("LEFT", 8, 0)
  local box = Rect(row.check, "BACKGROUND", { 0.04, 0.04, 0.05, 1 })
  box:SetAllPoints()
  Border(row.check)
  row.mark = Rect(row.check, "ARTWORK", COL.good)
  row.mark:SetPoint("TOPLEFT", 3, -3)
  row.mark:SetPoint("BOTTOMRIGHT", -3, 3)
  row.check:SetScript("OnClick", function()
    local rule = ns.profile.rules[row.index]
    if rule then rule.enabled = not rule.enabled; UI.RefreshRules() end
  end)
  AttachTip(row.check, L["Enabled"], L["Disabled rules are skipped."])
  row.name = Label(row, "", "GameFontHighlight")
  row.name:SetPoint("TOPLEFT", 34, -5)
  row.name:SetPoint("TOPRIGHT", -6, -5)
  row.name:SetWordWrap(false)
  row.sub = Label(row, "", "GameFontHighlightSmall", COL.muted)
  row.sub:SetPoint("BOTTOMLEFT", 34, 5)
  row.sub:SetPoint("BOTTOMRIGHT", -6, 5)
  row.sub:SetWordWrap(false)
  row:SetScript("OnClick", function(self) SelectRule(self.index) end)
  row:SetScript("OnEnter", function(self) self.hover = true; self.bg:SetColorTexture(COL.hover[1], COL.hover[2], COL.hover[3], 1) end)
  row:SetScript("OnLeave", function(self) self.hover = false; UI.RefreshRules() end)
  return row
end

local function BindRuleRow(row, idx)
  local rule = ns.profile.rules[idx]
  row.name:SetText(rule.name)
  if rule.enabled then SetColor(row.name, COL.text) else SetColor(row.name, COL.muted) end
  row.sub:SetText(ActionSummary(rule) .. "  -  " .. #rule.conds .. " " .. L["conditions"])
  ShowIf(row.mark, rule.enabled)
  local c = (idx == UI.sel) and COL.select or ((idx % 2 == 0) and COL.rowAlt or COL.row)
  row.bg:SetColorTexture(c[1], c[2], c[3], 1)
end

local function BuildCondRow(list, i)
  local row = CreateFrame("Frame", nil, list)
  row.bg = Rect(row, "BACKGROUND", COL.row)
  row.bg:SetPoint("TOPLEFT", 0, -1)
  row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
  row.label = Label(row, "", "GameFontNormalSmall", COL.gold)
  row.label:SetPoint("LEFT", 8, 0)
  row.label:SetWidth(150)
  row.label:SetWordWrap(false) -- long names end with "..." and show in full in a tooltip
  row.labelHit = CreateFrame("Frame", nil, row)
  row.labelHit:SetPoint("LEFT", 4, 0)
  row.labelHit:SetSize(156, 26)
  row.labelHit:EnableMouse(true)
  row.labelHit:SetScript("OnEnter", function(self)
    if not GameTooltip or not row.fullLabel then return end
    if not IsCut(row.label) and not row.help then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.fullLabel, 1, 0.82, 0.3, 1, true)
    if row.help then GameTooltip:AddLine(row.help, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
  end)
  row.labelHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  local function cond()
    local rule = CurrentRule()
    return rule and rule.conds[row.index], rule
  end
  local function def()
    local c = cond()
    return c and Filters.byKey[c.f]
  end

  row.sel = Button(row, "", 262, 24, function(self)
    local c = cond()
    local d = def()
    if not c or not d or not d.choices then return end
    UI.ShowMenu(self, d.choices(), function(value)
      c.v = value
      UI.Changed()
    end, c.v, 300)
  end)
  row.sel:SetPoint("LEFT", 162, 0)

  row.op = Button(row, "", 56, 24, function(self)
    local c = cond()
    local d = def()
    if not c or not d then return end
    local entries = {}
    for _, op in ipairs(Filters.OPS) do entries[#entries + 1] = { value = op, label = Filters.OP_LABEL[op] } end
    c.v = Filters.NormalizeValue(d, c.v)
    UI.ShowMenu(self, entries, function(value) c.v.op = value; UI.Changed() end, c.v.op, 70)
  end)
  row.op:SetPoint("LEFT", 162, 0)
  row.num = Edit(row, 90, 24, function(text)
    local c = cond()
    local d = def()
    if not c or not d then return end
    local n = tonumber((tostring(text):gsub(",", ".")))
    if n then
      c.v = Filters.NormalizeValue(d, c.v)
      c.v.n = math.floor(n * (d.mult or 1) + 0.5)
    end
    UI.Changed()
  end)
  row.num:SetPoint("LEFT", 224, 0)
  row.unit = Label(row, "", "GameFontHighlightSmall", COL.muted)
  row.unit:SetPoint("LEFT", row.num, "RIGHT", 6, 0)

  row.mode = Button(row, "", 110, 24, function(self)
    local c = cond()
    local d = def()
    if not c or not d then return end
    c.v = Filters.NormalizeValue(d, c.v)
    local entries = {}
    for _, m in ipairs(Filters.TEXT_MODES) do entries[#entries + 1] = { value = m.value, label = m.label } end
    UI.ShowMenu(self, entries, function(value) c.v.mode = value; UI.Changed() end, c.v.mode, 150)
  end)
  row.mode:SetPoint("LEFT", 162, 0)
  row.txt = Edit(row, 146, 24, function(text)
    local c = cond()
    local d = def()
    if not c or not d then return end
    c.v = Filters.NormalizeValue(d, c.v)
    c.v.s = text
    UI.Changed()
  end)
  row.txt:SetPoint("LEFT", 278, 0)

  row.excl = Button(row, "", 64, 24, function()
    local c = cond()
    if c then c.x = not c.x; UI.Changed() end
  end)
  row.excl:SetPoint("LEFT", 430, 0)
  AttachTip(row.excl, L["Include / Exclude"], L["Exclude: the rule does NOT apply when this condition is true."])
  row.del = CrossButton(row, 24, function()
    local c, rule = cond()
    if c then table.remove(rule.conds, row.index); UI.Changed() end
  end)
  row.del:SetPoint("LEFT", 500, 0)
  return row
end

local function BindCondRow(row, idx)
  local rule = CurrentRule()
  local c = rule and rule.conds[idx]
  if not c then return end
  local d = Filters.byKey[c.f]
  local bgc = (idx % 2 == 0) and COL.rowAlt or COL.row
  row.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], 1)
  row.sel:Hide(); row.op:Hide(); row.num:Hide(); row.unit:Hide(); row.mode:Hide(); row.txt:Hide()

  local prev = rule.conds[idx - 1]
  if prev and prev.f == c.f then
    row.label:SetText("   " .. L["or"])
    SetColor(row.label, COL.muted)
    row.fullLabel, row.help = nil, nil
  else
    row.label:SetText(d and d.label or (tostring(c.f) .. " (?)"))
    row.fullLabel, row.help = row.label:GetText(), d and d.help
    if d then SetColor(row.label, COL.gold) else SetColor(row.label, COL.bad) end
  end

  if d then
    c.v = Filters.NormalizeValue(d, c.v)
    if d.kind == "number" then
      row.op:SetLabel(Filters.OP_LABEL[c.v.op] or c.v.op)
      row.num:SetText(tostring(c.v.n / (d.mult or 1)))
      row.unit:SetText(d.unit or "")
      row.op:Show(); row.num:Show(); row.unit:Show()
    elseif d.kind == "text" then
      local label = c.v.mode
      for _, m in ipairs(Filters.TEXT_MODES) do if m.value == c.v.mode then label = m.label end end
      row.mode:SetLabel(label)
      row.txt:SetText(c.v.s)
      row.mode:Show(); row.txt:Show()
    else
      row.sel:SetLabel(Filters.ChoiceLabel(d, c.v))
      row.sel:Show()
    end
  end
  if c.x then
    row.excl:SetLabel(L["Exclude"]); row.excl:SetBase({ 0.35, 0.12, 0.10, 1 })
  else
    row.excl:SetLabel(L["Include"]); row.excl:SetBase(COL.panel)
  end
end

local function AddCondition(key)
  local rule = CurrentRule()
  local def = Filters.byKey[key]
  if not rule or not def then return end
  local cond = { f = key, v = Filters.DefaultValue(def), x = false }
  -- keep conditions of the same filter next to each other (they are OR'ed)
  local at = #rule.conds + 1
  for i = #rule.conds, 1, -1 do
    if rule.conds[i].f == key then at = i + 1; break end
  end
  table.insert(rule.conds, at, cond)
  UI.Changed()
end

local function BuildRulesPage(page)
  -- left column: rule list
  local left = CreateFrame("Frame", nil, page)
  left:SetPoint("TOPLEFT")
  left:SetSize(270, 528)
  local leftBg = Rect(left, "BACKGROUND", COL.panel)
  leftBg:SetPoint("TOPLEFT")
  leftBg:SetSize(270, 468)
  rulesList = List(left, 270, 36, 13, BuildRuleRow, BindRuleRow)
  rulesList:SetPoint("TOPLEFT")

  local newBtn = Button(left, L["New rule"], 96, 24, function()
    table.insert(ns.profile.rules, ns.NewRule())
    SelectRule(#ns.profile.rules)
    if rulesList.count > 13 then rulesList.offset = rulesList.count; rulesList:Refresh() end
    nameBox:SetFocus()
    nameBox:HighlightText()
  end)
  newBtn:SetPoint("TOPLEFT", 0, -474)
  local dupBtn = Button(left, L["Duplicate"], 84, 24, function()
    local rule = CurrentRule()
    if not rule then return end
    local copy = ns.CopyTable(rule)
    copy.name = rule.name .. " " .. L["(copy)"]
    table.insert(ns.profile.rules, UI.sel + 1, copy)
    SelectRule(UI.sel + 1)
  end)
  dupBtn:SetPoint("TOPLEFT", 100, -474)
  local delBtn = ConfirmButton(left, L["Delete"], 80, 24, function()
    if not CurrentRule() then return end
    table.remove(ns.profile.rules, UI.sel)
    if UI.sel > #ns.profile.rules then UI.sel = #ns.profile.rules end
    if UI.sel == 0 then UI.sel = nil end
    UI.Changed()
  end)
  delBtn:SetPoint("TOPLEFT", 188, -474)
  local function move(dir)
    local rules, i = ns.profile.rules, UI.sel
    if not i or not rules[i + dir] then return end
    rules[i], rules[i + dir] = rules[i + dir], rules[i]
    SelectRule(i + dir)
  end
  local upBtn = Button(left, L["Move up"], 133, 24, function() move(-1) end)
  upBtn:SetPoint("TOPLEFT", 0, -502)
  AttachTip(upBtn, L["Rule order"], L["Rules are checked from top to bottom. The first rule that matches decides."])
  local downBtn = Button(left, L["Move down"], 133, 24, function() move(1) end)
  downBtn:SetPoint("TOPLEFT", 137, -502)

  -- right column: editor
  hintLabel = Label(page, L["Select a rule on the left, or create a new one."], "GameFontHighlight", COL.muted, "CENTER")
  hintLabel:SetPoint("TOPLEFT", 285, -200)
  hintLabel:SetWidth(565)

  editor = CreateFrame("Frame", nil, page)
  editor:SetPoint("TOPLEFT", 285, 0)
  editor:SetSize(565, 528)

  local nameLabel = Label(editor, L["Rule name"], "GameFontNormalSmall", COL.gold)
  nameLabel:SetPoint("TOPLEFT", 0, 0)
  nameBox = Edit(editor, 565, 24, function(text)
    local rule = CurrentRule()
    if rule and ns.Trim(text) ~= "" then rule.name = ns.Trim(text) end
    UI.Changed()
  end)
  nameBox:SetPoint("TOPLEFT", 0, -16)

  local actionLabel = Label(editor, L["Action (first available choice, in this order)"], "GameFontNormalSmall", COL.gold)
  actionLabel:SetPoint("TOPLEFT", 0, -52)
  actionButtons = {}
  for i, action in ipairs(ns.ORDER) do
    local b = Button(editor, Engine.ActionLabel(action), 130, 26, function(self)
      local rule = CurrentRule()
      if not rule then return end
      local found
      for k, a in ipairs(rule.loot) do if a == action then found = k end end
      if found then table.remove(rule.loot, found) else table.insert(rule.loot, action) end
      UI.Changed()
    end)
    b.action = action
    b:SetPoint("TOPLEFT", (i - 1) * 138, -68)
    actionButtons[i] = b
  end
  local help = Label(editor, L["Select several: the first one the game offers is used (Need, then Disenchant, then Greed, then Pass). None selected = you roll by hand."], "GameFontHighlightSmall", COL.muted)
  help:SetPoint("TOPLEFT", 0, -98)
  help:SetWidth(565)
  help:SetHeight(30)
  help:SetJustifyV("TOP")

  local condHeader = Label(editor, L["Conditions"], "GameFontNormal", COL.gold)
  condHeader:SetPoint("TOPLEFT", 0, -136)
  local addBtn = Button(editor, L["+ Add a condition"], 190, 24, function(self)
    local entries = {}
    for _, d in ipairs(Filters.list) do
      entries[#entries + 1] = { value = d.key, label = d.label, tip = d.help }
    end
    UI.ShowMenu(self, entries, AddCondition, nil, 260)
  end)
  addBtn:SetPoint("TOPRIGHT", 0, -130)

  warnLabel = Label(editor, L["No condition: this rule applies to EVERY item."], "GameFontHighlightSmall", COL.bad)
  warnLabel:SetPoint("TOPLEFT", 0, -158)

  condList = List(editor, 565, 30, 10, BuildCondRow, BindCondRow)
  condList:SetPoint("TOPLEFT", 0, -176)

  local note = Label(editor, L["Several conditions of the same type: any of them is enough (OR). Different types must all be true (AND). \"Exclude\" blocks the rule when that condition is true."], "GameFontHighlightSmall", COL.muted)
  note:SetPoint("TOPLEFT", 0, -488)
  note:SetWidth(565)
  note:SetHeight(40)
  note:SetJustifyV("TOP")
end

------------------------------------------------------------------------
-- Options page
------------------------------------------------------------------------
local function BuildOptionsPage(page)
  local profLabel = Label(page, L["Profile"], "GameFontNormalSmall", COL.gold)
  profLabel:SetPoint("TOPLEFT", 0, 0)
  local profBtn = Button(page, "", 230, 26, function(self)
    local entries = {}
    for _, name in ipairs(ns.GetProfileNames()) do entries[#entries + 1] = { value = name, label = name } end
    UI.ShowMenu(self, entries, function(name) ns.SetProfile(name) end, ns.profileName, 230)
  end)
  profBtn:SetPoint("TOPLEFT", 0, -16)
  optionWidgets.profile = profBtn
  local profNew = Button(page, L["New"], 80, 26, function()
    UI.Prompt(L["New profile name"], "", function(name)
      if not ns.CreateProfile(name) then ns.Print(L["That profile name is not available."]) end
    end)
  end)
  profNew:SetPoint("TOPLEFT", 236, -16)
  local profCopy = Button(page, L["Duplicate"], 90, 26, function()
    UI.Prompt(L["Name of the copy"], tostring(ns.profileName) .. " " .. L["(copy)"], function(name)
      if not ns.CreateProfile(name, ns.profileName) then ns.Print(L["That profile name is not available."]) end
    end)
  end)
  profCopy:SetPoint("TOPLEFT", 322, -16)
  local profDel = ConfirmButton(page, L["Delete"], 90, 26, function()
    if not ns.DeleteProfile(ns.profileName) then ns.Print(L["You cannot delete the last profile."]) end
  end)
  profDel:SetPoint("TOPLEFT", 418, -16)
  local profExport = Button(page, L["Export"], 84, 26, function() UI.ShowExport() end)
  profExport:SetPoint("TOPLEFT", 514, -16)
  AttachTip(profExport, L["Export"], L["Gives a text containing the rules and messages of this profile, to share with friends or keep as a backup."])
  local profImport = Button(page, L["Import"], 84, 26, function() UI.ShowImport() end)
  profImport:SetPoint("TOPLEFT", 604, -16)
  AttachTip(profImport, L["Import"], L["Creates a new profile from a text made with Export. Your current profiles are not changed."])

  -- Each option sits under the help line of the previous one, so bigger fonts push the rows down
  -- instead of overlapping them.
  local lastHelp
  local function addCheck(_, text, help, get, set)
    local c = Check(page, text, 500, get, set)
    if lastHelp then c:SetPoint("TOPLEFT", lastHelp, "BOTTOMLEFT", -26, -8) else c:SetPoint("TOPLEFT", 0, -70) end
    local h = Label(page, help, "GameFontHighlightSmall", COL.muted)
    h:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 26, -1)
    h:SetWidth(800)
    h:SetWordWrap(false)
    lastHelp = h
    optionWidgets[#optionWidgets + 1] = c
    return c
  end
  addCheck(-70, L["Addon enabled"], L["Master switch. When off, nothing is rolled automatically."],
    function() return ns.db.enabled end,
    function(v) ns.db.enabled = v; ns.Fire("ENABLED_CHANGED") end)
  addCheck(-108, L["Quiet mode"], L["Do not print a chat message for each automatic roll."],
    function() return ns.profile.quiet end, function(v) ns.profile.quiet = v end)
  addCheck(-146, L["Auto-confirm bind-on-pickup"], L["Confirms the \"this item will bind\" popup, only for rolls made by this addon."],
    function() return ns.profile.confirmBoP end, function(v) ns.profile.confirmBoP = v end)
  addCheck(-184, L["Auto-confirm disenchant"], L["Confirms the disenchant popup, only for rolls made by this addon."],
    function() return ns.profile.confirmDE end, function(v) ns.profile.confirmDE = v end)
  addCheck(-222, L["Show minimap button"], L["Round button next to the minimap. Left-click opens this window, drag to move it."],
    function() return not (ns.db.minimap and ns.db.minimap.hide) end,
    function(v) if ns.Minimap then ns.Minimap.SetShown(v) end end)

  local scaleLabel = Label(page, L["Window scale"], "GameFontNormalSmall", COL.gold)
  scaleLabel:SetPoint("TOPLEFT", 700, 0)
  local scaleValue = Label(page, "", "GameFontHighlight", COL.text, "CENTER")
  scaleValue:SetPoint("TOPLEFT", 734, -21)
  scaleValue:SetWidth(50)
  local function applyScale(delta)
    local s = math.floor(((ns.db.scale or 1) + delta) * 10 + 0.5) / 10
    if s < 0.7 then s = 0.7 elseif s > 1.5 then s = 1.5 end
    ns.db.scale = s
    main:SetScale(s)
    UI.RefreshEdges()
    scaleValue:SetText(string.format("%.1f", s))
  end
  local minus = Button(page, "-", 30, 24, function() applyScale(-0.1) end)
  minus:SetPoint("TOPLEFT", 700, -16)
  local plus = Button(page, "+", 30, 24, function() applyScale(0.1) end)
  plus:SetPoint("TOPLEFT", 790, -16)
  optionWidgets.scaleValue = scaleValue

  local msgHeader = Label(page, L["Chat messages"], "GameFontNormal", COL.gold)
  msgHeader:SetPoint("TOPLEFT", lastHelp, "BOTTOMLEFT", -26, -18)
  local msgHelp = Label(page, L["%item% and %rule% are replaced by the item link and the rule name."], "GameFontHighlightSmall", COL.muted)
  msgHelp:SetPoint("LEFT", msgHeader, "LEFT", 200, -1)
  optionWidgets.msg = {}
  local keys = { "need", "de", "greed", "pass", "ignore" }
  for i, key in ipairs(keys) do
    local y = -8 - (i - 1) * 30
    local text = (key == "ignore") and L["Ignored"] or Engine.ActionLabel(key)
    local l = Label(page, text, "GameFontHighlight")
    l:SetPoint("TOPLEFT", msgHeader, "BOTTOMLEFT", 0, y - 5)
    l:SetWidth(124)
    l:SetWordWrap(false)
    local e = Edit(page, 650, 24, function(value) ns.profile.messages[key] = value end)
    e:SetPoint("TOPLEFT", msgHeader, "BOTTOMLEFT", 130, y)
    optionWidgets.lastMsg = e
    optionWidgets.msg[key] = e
  end
  local credit = Label(page, "PassLoot Forever v" .. ns.VERSION .. "  -  " .. L["by"] .. " |cffd4a85a" .. ns.AUTHOR .. "|r   |   PassLoot " .. L["by"] .. " nebula169", "GameFontHighlightSmall", COL.muted)
  credit:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 2)
  credit:SetWidth(850)
  credit:SetWordWrap(false)

  local resetMsg = Button(page, L["Reset messages"], 170, 26, function()
    ns.profile.messages = ns.DefaultMessages()
    UI.RefreshOptions()
  end)
  resetMsg:SetPoint("TOPLEFT", optionWidgets.lastMsg, "BOTTOMLEFT", 0, -16)
  local examples = Button(page, L["Add example rules"], 200, 26, function()
    for _, r in ipairs(ns.ExampleRules()) do table.insert(ns.profile.rules, r) end
    UI.Changed()
    ns.Print(L["Example rules added (disabled). Enable the ones you want in the Rules tab."])
  end)
  examples:SetPoint("LEFT", resetMsg, "RIGHT", 10, 0)
end

function UI.RefreshOptions()
  if not optionWidgets.profile or not ns.profile then return end
  optionWidgets.profile:SetLabel(tostring(ns.profileName))
  for _, w in ipairs(optionWidgets) do w:Refresh() end
  optionWidgets.scaleValue:SetText(string.format("%.1f", ns.db.scale or 1))
  for key, e in pairs(optionWidgets.msg) do e:SetText(ns.profile.messages[key] or "") end
end

------------------------------------------------------------------------
-- Journal page
------------------------------------------------------------------------
local function BuildJournalRow(list, i)
  local row = CreateFrame("Button", nil, list)
  row.bg = Rect(row, "BACKGROUND", COL.row)
  row.bg:SetPoint("TOPLEFT", 0, -1)
  row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", 6, 0)
  row.time = Label(row, "", "GameFontHighlightSmall", COL.muted)
  row.time:SetPoint("LEFT", 32, 0)
  row.time:SetWidth(60)
  row.item = Label(row, "", "GameFontHighlightSmall")
  row.item:SetPoint("LEFT", 96, 0)
  row.item:SetWidth(300)
  row.item:SetWordWrap(false)
  row.action = Label(row, "", "GameFontHighlightSmall")
  row.action:SetPoint("LEFT", 404, 0)
  row.action:SetWidth(110)
  row.rule = Label(row, "", "GameFontHighlightSmall", COL.muted)
  row.rule:SetPoint("LEFT", 520, 0)
  row.rule:SetWidth(300)
  row.rule:SetWordWrap(false)
  row:SetScript("OnEnter", function(self)
    local e = self.entry
    if e and e.link and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
      pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return row
end

local function BindJournalRow(row, idx)
  local log = Engine.log
  local e = log[#log - idx + 1] -- newest first
  row.entry = e
  if not e then return end
  local c = (idx % 2 == 0) and COL.rowAlt or COL.row
  row.bg:SetColorTexture(c[1], c[2], c[3], 1)
  if e.icon then row.icon:SetTexture(e.icon) end
  row.time:SetText(date and date("%H:%M:%S", e.t) or "")
  row.item:SetText(e.link or e.name or "?")
  row.action:SetText("|c" .. (Engine.ACTION_COLOR[e.action] or "ffffffff") .. Engine.ActionLabel(e.action) .. "|r")
  row.rule:SetText(string.format("#%d %s", e.index or 0, e.rule or ""))
end

local function BuildJournalPage(page)
  local h1 = Label(page, L["Time"], "GameFontNormalSmall", COL.gold); h1:SetPoint("TOPLEFT", 32, 0)
  local h2 = Label(page, L["Item"], "GameFontNormalSmall", COL.gold); h2:SetPoint("TOPLEFT", 96, 0)
  local h3 = Label(page, L["Action"], "GameFontNormalSmall", COL.gold); h3:SetPoint("TOPLEFT", 404, 0)
  local h4 = Label(page, L["Rule"], "GameFontNormalSmall", COL.gold); h4:SetPoint("TOPLEFT", 520, 0)
  journalList = List(page, 850, 22, 21, BuildJournalRow, BindJournalRow)
  journalList:SetPoint("TOPLEFT", 0, -18)
  local clear = Button(page, L["Clear"], 140, 26, function() Engine.ClearLog() end)
  clear:SetPoint("TOPLEFT", 0, -500)
  local note = Label(page, L["Automatic rolls of this session (last 50). Hover an item to see it."], "GameFontHighlightSmall", COL.muted)
  note:SetPoint("TOPLEFT", 150, -506)
end

function UI.RefreshJournal()
  if journalList then journalList:SetCount(#Engine.log) end
end

------------------------------------------------------------------------
-- Test page
------------------------------------------------------------------------
local function BuildTestPage(page)
  local info = Label(page, L["Shift + click an item (or drag it onto the box), or type an item ID, to see which rule would match and what would be rolled."], "GameFontHighlightSmall", COL.muted)
  info:SetPoint("TOPLEFT", 0, 0)
  local function run()
    Engine.Test(testBox:GetText(), function(result)
      UI.testLines = Engine.DescribeResult(result)
      testList:SetCount(#UI.testLines)
    end)
  end
  testBox = Edit(page, 500, 26, nil)
  testBox:SetPoint("TOPLEFT", 0, -20)
  testBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); run() end)
  -- Drag an item from the bags (or anywhere) and drop it on the box.
  local function dropFromCursor()
    if type(GetCursorInfo) ~= "function" then return false end
    local kind, id, link = GetCursorInfo()
    if kind ~= "item" then return false end
    if ns.IsSecret(link) then link = nil end
    if type(link) ~= "string" then link = id and ("item:" .. tostring(id)) or nil end
    if ClearCursor then ClearCursor() end
    if link then UI.SetTestItem(link) end
    return true
  end
  testBox:SetScript("OnReceiveDrag", dropFromCursor)
  testBox:SetScript("OnMouseDown", function() dropFromCursor() end)
  UI.testBox = testBox
  UI.RunTest = run
  local go = Button(page, L["Test"], 100, 26, run)
  go:SetPoint("TOPLEFT", 510, -20)
  -- Stat weights used for the score (per character). Test version: display only.
  local presetBtn
  local function presetText()
    local p = ns.Stats and ns.Stats.CurrentPreset()
    return p and (L["Score:"] .. " " .. ns.Stats.PresetLabel(p)) or ""
  end
  presetBtn = Button(page, "", 230, 26, function(self)
    local entries = {}
    for _, p in ipairs(ns.Stats.ClassPresets()) do entries[#entries + 1] = { value = p.id, label = ns.Stats.PresetLabel(p) } end
    UI.ShowMenu(self, entries, function(id)
      ns.Stats.SetPreset(id)
      presetBtn:SetLabel(presetText())
      if testBox:GetText() ~= "" then run() end
    end, ns.Stats.CurrentPreset().id, 230)
  end)
  presetBtn:SetPoint("TOPLEFT", 620, -20)
  AttachTip(presetBtn, L["Stat score"], L["Stat weights used to score items for this character, here and in the \"Stat score gain vs equipped\" condition."])
  page:HookScript("OnShow", function() presetBtn:SetLabel(presetText()) end)
  presetBtn:SetLabel(presetText())
  testList = List(page, 850, 22, 21, function(list, i)
    local row = CreateFrame("Frame", nil, list)
    row.text = Label(row, "", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetWordWrap(false)
    return row
  end, function(row, idx) row.text:SetText(UI.testLines[idx] or "") end)
  testList:SetPoint("TOPLEFT", 0, -62)
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local TAB_ORDER = { "rules", "options", "journal", "test" }

function UI.ShowTab(name)
  for key, page in pairs(pages) do ShowIf(page, key == name) end
  for key, b in pairs(tabs) do
    if key == name then b:SetBase(COL.active); b.label:SetTextColor(1, 0.9, 0.55)
    else b:SetBase(COL.panel); b.label:SetTextColor(COL.text[1], COL.text[2], COL.text[3]) end
  end
  UI.tab = name
  if name == "options" then UI.RefreshOptions() elseif name == "journal" then UI.RefreshJournal() end
end

local function SavePosition()
  local point, _, relPoint, x, y = main:GetPoint()
  if point then ns.db.window = { point = point, relPoint = relPoint or point, x = x, y = y } end
end

local function Build()
  if main then return end
  main = CreateFrame("Frame", "PassLootForeverFrame", UIParent)
  main:SetSize(880, 616)
  main:SetFrameStrata("DIALOG")
  main:SetClampedToScreen(true)
  main:SetMovable(true)
  main:EnableMouse(true)
  main:SetScale(ns.db.scale or 1)
  UI.RefreshEdges()
  main:HookScript("OnShow", UI.RefreshEdges)
  local w = ns.db.window
  if type(w) == "table" and w.point then
    main:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
  else
    main:SetPoint("CENTER")
  end
  local bg = Rect(main, "BACKGROUND", COL.bg)
  bg:SetAllPoints()
  Border(main)
  main:Hide()
  table.insert(UISpecialFrames, "PassLootForeverFrame")

  local bar = CreateFrame("Frame", nil, main)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(36)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() main:StartMoving() end)
  bar:SetScript("OnDragStop", function() main:StopMovingOrSizing(); SavePosition() end)
  local barBg = Rect(bar, "BACKGROUND", { 0.09, 0.075, 0.05, 1 })
  barBg:SetAllPoints()
  local title = Label(bar, "PassLoot Forever", "GameFontNormalLarge", COL.gold)
  title:SetPoint("LEFT", 16, 0)
  local ver = Label(bar, "v" .. ns.VERSION .. "  -  " .. L["by"] .. " " .. ns.AUTHOR, "GameFontHighlightSmall", COL.muted)
  ver:SetPoint("LEFT", title, "RIGHT", 10, -1)
  local close = CrossButton(main, 24, function() main:Hide() end)
  close:SetPoint("TOPRIGHT", -8, -6)
  close:SetFrameLevel(bar:GetFrameLevel() + 5)
  local master = Check(main, L["Addon enabled"], 160,
    function() return ns.db.enabled end,
    function(v) ns.db.enabled = v; ns.Fire("ENABLED_CHANGED") end)
  master:SetPoint("TOPRIGHT", -44, -8)
  master:SetFrameLevel(bar:GetFrameLevel() + 5)
  UI.master = master

  pages, tabs = {}, {}
  local labels = { rules = L["Rules"], options = L["Options"], journal = L["Journal"], test = L["Test"] }
  for i, key in ipairs(TAB_ORDER) do
    local b = Button(main, labels[key], 120, 28, function() UI.ShowTab(key) end)
    b:SetPoint("TOPLEFT", 15 + (i - 1) * 126, -44)
    tabs[key] = b
    local page = CreateFrame("Frame", nil, main)
    page:SetPoint("TOPLEFT", 15, -82)
    page:SetSize(850, 528)
    page:Hide()
    pages[key] = page
  end
  BuildRulesPage(pages.rules)
  BuildOptionsPage(pages.options)
  BuildJournalPage(pages.journal)
  BuildTestPage(pages.test)
  UI.ShowTab("rules")
  UI.Changed()
end

function UI.Show(tab)
  if not ns.db then ns.Print(L["Not ready yet."]); return end
  Build()
  if tab then UI.ShowTab(tab) end
  main:Show()
end

function UI.Toggle()
  if not ns.db then ns.Print(L["Not ready yet."]); return end
  Build()
  if main:IsShown() then main:Hide() else main:Show() end
end

ns.RegisterCallback("PROFILE_CHANGED", function()
  UI.sel = nil
  if main then UI.Changed(); UI.RefreshOptions() end
end)
ns.RegisterCallback("LOG_UPDATED", function() if main then UI.RefreshJournal() end end)
ns.RegisterCallback("ENABLED_CHANGED", function()
  if main then
    UI.master:Refresh()
    UI.RefreshOptions()
  end
end)

------------------------------------------------------------------------
-- Item links for the Test tab
------------------------------------------------------------------------
local function ChatInputOpen()
  local f = (type(_G.ChatEdit_GetActiveWindow) == "function" and _G.ChatEdit_GetActiveWindow())
  if not f and type(_G.ChatFrameUtil) == "table" and type(_G.ChatFrameUtil.GetActiveWindow) == "function" then
    f = _G.ChatFrameUtil.GetActiveWindow()
  end
  return f and f.IsShown and f:IsShown() and f.HasFocus and f:HasFocus() or false
end

function UI.SetTestItem(link)
  if not testBox then return end
  testBox:SetText(link)
  testBox.original = link
  testBox:ClearFocus()
  if UI.RunTest then UI.RunTest() end
end

local lastLink, lastTime
function UI.OfferLink(link)
  if not testBox or not testBox:IsVisible() then return end
  -- The box takes the link when it has the focus, or when the Test tab is open and the chat input is not.
  if not testBox:HasFocus() and ChatInputOpen() then return end
  local now = GetTime and GetTime() or 0
  if link == lastLink and lastTime and (now - lastTime) < 0.2 then return end
  lastLink, lastTime = link, now
  UI.SetTestItem(link)
end

------------------------------------------------------------------------
-- Entry points: Addon Compartment, Settings panel, shift-click into the test box
------------------------------------------------------------------------
function PassLootForever_OnCompartmentClick()
  UI.Toggle()
end

ns.RegisterCallback("DB_READY", function()
  pcall(function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    panel.name = "PassLoot Forever"
    local t = Label(panel, "PassLoot Forever", "GameFontNormalLarge", COL.gold)
    t:SetPoint("TOPLEFT", 16, -16)
    local d = Label(panel, L["Automatic Need / Greed / Disenchant / Pass rules for group loot."], "GameFontHighlight")
    d:SetPoint("TOPLEFT", 16, -44)
    local by = Label(panel, "v" .. ns.VERSION .. "  -  " .. L["by"] .. " " .. ns.AUTHOR, "GameFontHighlightSmall", COL.muted)
    by:SetPoint("TOPLEFT", 16, -64)
    local open = Button(panel, L["Open PassLoot Forever"], 220, 28, function() UI.Show() end)
    open:SetPoint("TOPLEFT", 16, -92)
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
  end)
  -- Shift + click on an item (bags, character sheet, chat link, loot roll frame...) puts its link in the
  -- Test box, exactly like it would go into the chat. Recent clients route the link through
  -- ChatFrameUtil.InsertLink, older ones through ChatEdit_InsertLink; HandleModifiedItemClick is the
  -- common caller. All are hooked; a link seen twice in the same frame is only inserted once.
  if type(hooksecurefunc) == "function" then
    local function onLink(link)
      if type(link) == "string" and not ns.IsSecret(link) and link:find("item:", 1, true) then UI.OfferLink(link) end
    end
    if type(_G.ChatFrameUtil) == "table" and type(_G.ChatFrameUtil.InsertLink) == "function" then
      pcall(hooksecurefunc, _G.ChatFrameUtil, "InsertLink", onLink)
    end
    if type(_G.ChatEdit_InsertLink) == "function" then
      pcall(hooksecurefunc, "ChatEdit_InsertLink", onLink)
    end
    if type(_G.HandleModifiedItemClick) == "function" then
      pcall(hooksecurefunc, "HandleModifiedItemClick", function(link)
        local chatLink
        if type(IsModifiedClick) == "function" then chatLink = IsModifiedClick("CHATLINK") end
        if chatLink == nil and type(IsShiftKeyDown) == "function" then chatLink = IsShiftKeyDown() end
        if chatLink then onLink(link) end
      end)
    end
  end
end)

-- Resolution or UI scale changed while playing: recompute the 1-pixel borders.
ns.RegisterEvent("UI_SCALE_CHANGED", function() if UI.RefreshEdges then UI.RefreshEdges() end end)
ns.RegisterEvent("DISPLAY_SIZE_CHANGED", function() if UI.RefreshEdges then UI.RefreshEdges() end end)
