-- PassLoot Forever - Share: export a profile to a text string and import it back.
-- Format: "PLF1:<checksum>:<base64 payload>". The payload is a small typed encoding parsed by hand:
-- nothing is ever executed (no loadstring), so a pasted string cannot run code.
local addonName, ns = ...
local L = ns.L

local Share = {}
ns.Share = Share

local PREFIX = "PLF1"
local MAX_DEPTH = 12
local MAX_LEN = 200000

------------------------------------------------------------------------
-- Typed encoding
--   s<len>:<bytes>   string        n<number>;   number
--   T / F            boolean       t ... e      table (key, value pairs)
------------------------------------------------------------------------
local function encode(v, out, depth)
  local tv = type(v)
  if tv == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif tv == "number" then
    out[#out + 1] = "n" .. string.format("%.14g", v) .. ";"
  elseif tv == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif tv == "table" then
    if depth > MAX_DEPTH then error("too deep") end
    out[#out + 1] = "t"
    for k, val in pairs(v) do
      local tk, tval = type(k), type(val)
      if (tk == "string" or tk == "number") and (tval == "string" or tval == "number" or tval == "boolean" or tval == "table") then
        encode(k, out, depth + 1)
        encode(val, out, depth + 1)
      end
    end
    out[#out + 1] = "e"
  end
end

local function decode(s, pos, depth)
  local tag = s:sub(pos, pos)
  if tag == "s" then
    local len, colon = s:match("^(%d+)():", pos + 1)
    len = tonumber(len)
    if not len then return nil, pos, "bad string" end
    local start = colon + 1
    if start + len - 1 > #s then return nil, pos, "truncated string" end
    return s:sub(start, start + len - 1), start + len
  elseif tag == "n" then
    local num, after = s:match("^([%d%.eE%+%-]+);()", pos + 1)
    num = tonumber(num)
    if not num then return nil, pos, "bad number" end
    return num, after
  elseif tag == "T" then
    return true, pos + 1
  elseif tag == "F" then
    return false, pos + 1
  elseif tag == "t" then
    if depth > MAX_DEPTH then return nil, pos, "too deep" end
    local t = {}
    pos = pos + 1
    while true do
      if pos > #s then return nil, pos, "truncated table" end
      if s:sub(pos, pos) == "e" then return t, pos + 1 end
      local k, v, err
      k, pos, err = decode(s, pos, depth + 1)
      if err then return nil, pos, err end
      if type(k) ~= "string" and type(k) ~= "number" then return nil, pos, "bad key" end
      v, pos, err = decode(s, pos, depth + 1)
      if err then return nil, pos, err end
      t[k] = v
    end
  end
  return nil, pos, "unknown tag"
end

------------------------------------------------------------------------
-- Base64 (Lua 5.1, no bit library) and checksum
------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INV = {}
for i = 1, 64 do B64INV[B64:byte(i)] = i - 1 end

local function b64encode(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

local function b64decode(s)
  s = s:gsub("[^%w%+/]", "") -- drops "=", spaces and line breaks added while copying
  local out = {}
  for i = 1, #s, 4 do
    local q = { s:byte(i, i + 3) }
    local n, count = 0, 0
    for j = 1, 4 do
      local v = q[j] and B64INV[q[j]]
      if v then n = n * 64 + v; count = count + 1 else n = n * 64 end
    end
    if count < 2 then break end
    local a = math.floor(n / 65536) % 256
    local b = math.floor(n / 256) % 256
    local c = n % 256
    out[#out + 1] = string.char(a)
    if count >= 3 then out[#out + 1] = string.char(b) end
    if count >= 4 then out[#out + 1] = string.char(c) end
  end
  return table.concat(out)
end

local function checksum(s)
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 16777216 end
  return string.format("%06x", h)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
-- Returns the export string of a profile (the current one by default).
function Share.Export(name)
  name = name or ns.profileName
  local p = ns.db and ns.db.profiles[name]
  if not p then return nil end
  local data = {
    v = 1,
    addon = "PassLootForever",
    version = ns.VERSION,
    name = name,
    profile = {
      rules = ns.CopyTable(p.rules),
      messages = ns.CopyTable(p.messages),
      quiet = p.quiet, confirmBoP = p.confirmBoP, confirmDE = p.confirmDE,
    },
  }
  local out = {}
  encode(data, out, 0)
  local raw = table.concat(out)
  return PREFIX .. ":" .. checksum(raw) .. ":" .. b64encode(raw)
end

-- Returns data ({ name =, profile = }) or nil and an error message for the user.
function Share.Decode(text)
  text = ns.Trim(text)
  if text == "" then return nil, L["Paste an export text first."] end
  if #text > MAX_LEN then return nil, L["This text is too long to be a PassLoot Forever profile."] end
  local prefix, sum, body = text:match("^(%w+):(%x+):(.+)$")
  if not prefix then return nil, L["This is not a PassLoot Forever export text."] end
  if prefix ~= PREFIX then return nil, L["This export comes from a newer version of PassLoot Forever."] end
  local raw = b64decode(body)
  if checksum(raw) ~= sum:lower() then
    return nil, L["The text is incomplete or was modified. Copy it again, entirely."]
  end
  local ok, data, _, err = pcall(decode, raw, 1, 0)
  if not ok or err or type(data) ~= "table" or type(data.profile) ~= "table" then
    return nil, L["The text is incomplete or was modified. Copy it again, entirely."]
  end
  local p = data.profile
  local profile = {
    rules = type(p.rules) == "table" and p.rules or {},
    messages = type(p.messages) == "table" and p.messages or {},
    quiet = p.quiet == true, confirmBoP = p.confirmBoP == true, confirmDE = p.confirmDE == true,
  }
  -- rules arrive as tables keyed 1..n; rebuild clean arrays so ipairs sees every rule
  local rules = {}
  for i = 1, #profile.rules do rules[#rules + 1] = profile.rules[i] end
  for _, r in ipairs(rules) do
    if type(r) == "table" then
      if type(r.loot) == "table" then local l = {}; for i = 1, #r.loot do l[i] = r.loot[i] end; r.loot = l end
      if type(r.conds) == "table" then local c = {}; for i = 1, #r.conds do c[i] = r.conds[i] end; r.conds = c end
    end
  end
  profile.rules = rules
  ns.SanitizeProfile(profile)
  local name = type(data.name) == "string" and ns.Trim(data.name) or ""
  if name == "" then name = L["Imported profile"] end
  return { name = name, profile = profile, count = #profile.rules }
end

-- A name that is not used yet, based on the wanted one.
function Share.FreeName(wanted)
  wanted = ns.Trim(wanted)
  if wanted == "" then wanted = L["Imported profile"] end
  if not ns.db.profiles[wanted] then return wanted end
  local i = 2
  while ns.db.profiles[wanted .. " (" .. i .. ")"] do i = i + 1 end
  return wanted .. " (" .. i .. ")"
end

-- Creates a new profile from decoded data and switches to it.
function Share.Import(data, name)
  name = ns.Trim(name)
  if name == "" or ns.db.profiles[name] then return false end
  ns.db.profiles[name] = ns.CopyTable(data.profile)
  ns.SetProfile(name)
  return true
end
