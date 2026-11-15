-- PBZ HitFeel: what the mod runs beside. Logged once at the start, for bug reports: the storefront (the folder PBZ.exe
-- is in), the UE4SS build, other loaders next to the game (PBZModLoader's proxy DLL and its mods folder), other mods
-- that change the same hit data, and hotkeys another loader holds. Before any of that, the UE4SS functions the mod
-- calls: one it cannot do without stops the start with a line saying which (instead of an error on every frame),
-- the two it can stand in for get a stand-in, and the per-frame scheduler falls back to timers when the frame-based
-- one is missing. And once per session, at the first map: widgets this mod left in the viewport from an earlier run
-- of its scripts in the same game (UE4SS's own "restart all mods", Ctrl+R when its hot reload is on, drops the old
-- Lua state but not its widgets) are taken down, and the input an open panel held is given back.
-- PBZModLoader (Nexus mod 113, checked against its source 2026-11-05) runs JavaScript mods in the game's own PuerTS
-- through version.dll (or hid / winmm / dsound / dxgi.dll) and patches the game's script start, three PuerTS log
-- functions and five script checks; UE4SS (dwmapi.dll) hooks the engine's ProcessEvent and friends. Different files
-- and different code: the two run side by side, and this mod needs UE4SS either way.
local Env = { name = "env", info = {} }
local S, U, C

-- Without these the mod cannot run at all.
Env.REQUIRED = { "RegisterHook", "StaticFindObject", "StaticConstructObject", "FName", "FText", "ExecuteInGameThread",
  "ExecuteInGameThreadWithDelay", "LoopInGameThreadWithDelay", "CancelDelayedAction" }
-- Used where they exist.
Env.OPTIONAL = { "ExecuteInGameThreadAfterFrames", "LoopInGameThreadAfterFrames", "RetriggerableExecuteInGameThreadWithDelay",
  "MakeActionHandle", "LoadAsset", "FindAllOf", "RegisterKeyBind" }
-- Proxy DLLs other loaders put beside PBZ.exe (UE4SS's own is dwmapi.dll).
Env.PROXIES = { "version.dll", "hid.dll", "winmm.dll", "dsound.dll", "dxgi.dll", "xinput1_3.dll", "d3d11.dll" }

local function fn(name) return type(rawget(_G, name)) == "function" end

-- The UE4SS functions: true when the mod can run, else false and the missing ones. Stand-ins for the two it can do
-- without, and U.frameApi (frame-based scheduling) only when both frame functions are there.
function Env.check()
  local missing, absent = {}, {}
  for _, name in ipairs(Env.REQUIRED) do
    if rawget(_G, name) == nil then missing[#missing + 1] = name end
  end
  for _, name in ipairs(Env.OPTIONAL) do
    if rawget(_G, name) == nil then absent[#absent + 1] = name end
  end
  if not fn("MakeActionHandle") then
    local n = 0
    _G.MakeActionHandle = function()
      n = n + 1
      return { standIn = n }
    end
  end
  if not fn("RetriggerableExecuteInGameThreadWithDelay") and fn("ExecuteInGameThreadWithDelay") and fn("CancelDelayedAction") then
    -- One pending call per handle: a new one replaces it, as the real one moves its time.
    local pending = {}
    _G.RetriggerableExecuteInGameThreadWithDelay = function(handle, ms, f)
      local old = pending[handle]
      if old then pcall(CancelDelayedAction, old) end
      local h
      h = ExecuteInGameThreadWithDelay(ms, function()
        if pending[handle] == h then pending[handle] = nil end
        f()
      end)
      pending[handle] = h
      return handle
    end
  end
  U.frameApi = EngineTickAvailable == true and fn("ExecuteInGameThreadAfterFrames") and fn("LoopInGameThreadAfterFrames")
  Env.info.missing, Env.info.absent = missing, absent
  return #missing == 0, missing
end

-- ------------------------------------------------------------------ the report

local function exists(path) return U.exists(path) end

-- The folder with PBZ.exe: next to ue4ss\ (ue4ss\Mods\PBZHitFeel), or next to Mods\ in older layouts.
local function exeDir()
  for _, up in ipairs({ "/../../..", "/../.." }) do
    local d = U.root .. up
    if exists(d .. "/PBZ.exe") then return d end
  end
end

local function ue4ssVersion()
  local t = rawget(_G, "UE4SS")
  if type(t) ~= "table" and type(t) ~= "userdata" then return nil end
  local ok, a, b, c = pcall(function() return t.GetVersion() end)
  if not ok or a == nil then ok, a, b, c = pcall(function() return t:GetVersion() end) end
  if ok and a ~= nil then return table.concat({ tostring(a), tostring(b or 0), tostring(c or 0) }, ".") end
end

-- A mod folder of UE4SS that is switched on: its enabled.txt, or mods.txt naming it with 1.
local function modOn(name)
  local mods = U.root .. "/.."
  if exists(mods .. "/" .. name .. "/enabled.txt") then return true end
  local list = U.readFile(mods .. "/mods.txt", "rb") or ""
  for line in list:gmatch("[^\r\n]+") do
    local n, v = line:match("^%s*([^:;]-)%s*:%s*(%d)")
    if n and n:lower() == name:lower() then return v == "1" end
  end
  return false
end

function Env.report()
  local i = Env.info
  i.store = (U.root:gsub("\\", "/")):match("/platform/([^/]+)/") or "?"
  i.ue4ss = ue4ssVersion()
  local dir = exeDir()
  i.exe = dir ~= nil
  i.proxies = {}
  if dir then
    for _, p in ipairs(Env.PROXIES) do
      if exists(dir .. "/" .. p) then i.proxies[#i.proxies + 1] = p end
    end
    -- PBZModLoader: its mods.ini under ProjectPBZ\PBZModLoader, two folders above the one with PBZ.exe.
    local ini = U.readFile(dir .. "/../../ProjectPBZ/PBZModLoader/mods.ini", "rb")
    if ini then
      i.modLoader = ini:match("%[Loader%][^%[]-Enabled%s*=%s*0") and "off" or "on"
    end
  end
  i.hitEnhance = modOn("pbz_hit_enhance") or modOn("PBZHitEnhance")
  U.log("env: storefront %s, UE4SS %s, PBZ.exe %s; other proxy DLLs beside it: %s; PBZModLoader %s",
    i.store, i.ue4ss or "version unknown", i.exe and "found" or "not found where expected",
    #i.proxies > 0 and table.concat(i.proxies, ", ") or "none",
    i.modLoader and (i.modLoader .. " (it runs JavaScript mods beside UE4SS; the two do not touch each other)") or "not installed")
  if #i.absent > 0 then
    U.log("env: this UE4SS has no %s; the mod uses stand-ins or timers there", table.concat(i.absent, ", "))
  end
  if i.hitEnhance then
    U.log("env: pbz_hit_enhance is on too: both change the game's hit stop; switch off its hit stop or this mod's (Freeze)")
  end
  local k = S.cfg.Keys or {}
  if i.modLoader == "on" and tostring(k.Modifier or "Ctrl"):lower() == "alt" and (k.Panel or "F5") == "F5" then
    U.log("env: PBZModLoader holds Alt+F5 for its hot reload, so the panel key Alt+F5 never reaches the game; pick another in config.lua (Keys)")
  end
  if i.store ~= "steam" and i.store ~= "?" then
    U.log("env: %s is not the Steam build this mod was tested on; it finds everything by name, so most of it should work", i.store)
  end
end

-- One short line for the panel's status.
function Env.status()
  local i = Env.info
  local parts = { i.store or "?", "UE4SS " .. (i.ue4ss or "?") }
  if i.modLoader then parts[#parts + 1] = "PBZModLoader " .. i.modLoader end
  return table.concat(parts, " · ")
end

-- ------------------------------------------------------------------ widgets from an earlier run of the scripts

-- A name for one of this mod's widgets, unique in the game session (two objects of one name under the same outer would
-- replace each other), so that a later run of the scripts can find the ones an earlier run left.
local serial = 0
function Env.widgetName(kind)
  serial = serial + 1
  return FName(string.format("PBZHitFeel_%s_%d_%d", kind, os.time() % 100000000, serial * 1000 + math.random(0, 999)))
end

-- At the first map of a session: this mod's widgets that no running copy of its scripts owns (left by an earlier
-- Lua state of this mod in the same game) leave the viewport; an open panel among them gives the input back.
function Env.sweep(own)
  -- (Once per Lua state: the state table outlives this mod's own reloads, not UE4SS's restart of its mods.)
  if S.envSwept or not fn("FindAllOf") then return end
  S.envSwept = true
  local all = U.try("env.widgets", FindAllOf, "UserWidget") or {}
  local mine, removed, panel = {}, 0, false
  for _, w in ipairs(own or {}) do
    local a = U.addr(w)
    if a then mine[a] = true end
  end
  for _, w in ipairs(all) do
    local name = U.fname(w)
    if name:find("^PBZHitFeel_") and U.valid(w) and not mine[U.addr(w) or 0] then
      local shown = U.try("env.vis", function() return w:GetVisibility() end)
      if name:find("^PBZHitFeel_Panel") and shown ~= nil and shown ~= 1 and shown ~= 2 then panel = true end
      if U.try("env.remove", function() w:RemoveFromParent() return true end) then removed = removed + 1 end
    end
  end
  if removed == 0 then return end
  U.log("env: %d widget(s) of this mod left by an earlier run of its scripts (UE4SS restarting its mods) were taken down%s",
    removed, panel and "; that run's open panel had the mouse, given back to the game" or "")
  if panel and S.hud and S.hud.releaseInput then U.try("env.input", S.hud.releaseInput) end
end

function Env.init(state)
  S, U, C = state, state.U, state.C
  -- (What the start found stays for the panel's status over reloads.)
  S.envInfo = S.envInfo or {}
  Env.info = S.envInfo
end

return Env
