local addonName, ns = ...
local L = ns.L

local M = {}
ns.Minimap = M

local button
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local RAD = math.pi / 180

local function Place()
  if not button or not Minimap then return end
  local angle = (ns.db.minimap.angle or 215) * RAD
  local radius = (Minimap:GetWidth() or 140) / 2 + 5
  local x, y = math.cos(angle), math.sin(angle)
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape ~= "ROUND" then
    -- square-ish minimaps: clamp to the square
    local m = math.max(math.abs(x), math.abs(y))
    if m > 0 then x, y = x / m, y / m end
    radius = (Minimap:GetWidth() or 140) / 2 + 3
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

local function OnDragUpdate()
  if not Minimap or not GetCursorPosition then return end
  local mx, my = Minimap:GetCenter()
  if not mx then return end
  local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  ns.db.minimap.angle = (atan2(cy - my, cx - mx) / RAD) % 360
  Place()
end

local function Create()
  if button or not Minimap or not ns.db then return end
  button = CreateFrame("Button", "PassLootForeverMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER", 0, 1)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetSize(18, 18)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetPoint("CENTER", 0, 1)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", 0, 0)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", function() if ns.UI then ns.UI.Toggle() end end)
  button:SetScript("OnDragStart", function(self)
    self.dragging = true
    if GameTooltip then GameTooltip:Hide() end
    self:SetScript("OnUpdate", OnDragUpdate)
  end)
  button:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    if self.dragging or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("PassLoot Forever")
    GameTooltip:AddLine(L["Left-click: open the window"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move the button"], 1, 1, 1)
    local on = ns.db.enabled
    GameTooltip:AddLine(on and L["Addon enabled"] or "|cffff6060" .. L["Disabled."] .. "|r")
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  Place()
  if ns.db.minimap.hide then button:Hide() else button:Show() end
end

function M.IsShown()
  return not (ns.db and ns.db.minimap and ns.db.minimap.hide)
end

function M.SetShown(show)
  if not ns.db then return end
  ns.db.minimap.hide = not show
  Create()
  if button then
    if show then button:Show(); Place() else button:Hide() end
  end
end

M.Place = Place

ns.RegisterCallback("DB_READY", Create)
