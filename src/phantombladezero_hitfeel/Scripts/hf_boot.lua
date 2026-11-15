-- PBZ HitFeel: the mod as the kernel (main.lua) starts it: the config, the hit bus and the feature modules, the
-- hotkeys and the probe. Every script but main.lua is loaded afresh on a reload (Ctrl+F8; Hit Feel has no in-game updater,
-- see hf_hud.lua); start() then takes over the running mod's state table (RT.S) and its session loops, and stop() lets the
-- running copy put back what it changed in the game first. Every script is loaded here, at the top, so that a file
-- that does not load stops a reload before anything of the running mod is touched.
local B = { name = "boot", VERSION = "0.7.3", KERNEL = 1 }
-- Hit Feel (phantombladezero_hitfeel, Kintaro): its own version, in the log lines below, so a player's log shows which
-- build runs. VERSION above stays the PBZHitFeel release it is based on.
B.HITFEEL_VERSION = "1.2"

local U = require("hf_util")
U.version = B.VERSION
local C = require("hf_config")

-- Order matters: the guard marks a blow first (its strain weighs on everything after), the time freeze lands next,
-- then the reactions that read the frozen pose.
local FEATURES = { "hf_guard", "hf_rhythm", "hf_freeze", "hf_react", "hf_flash", "hf_knockback", "hf_camera", "hf_screen",
  "hf_vfx", "hf_rumble", "hf_audio", "hf_receive", "hf_kill", "hf_overlay", "hf_hud", "hf_preload", "hf_perf" }
local MODULES = { hf_lang = require("hf_lang"), hf_env = require("hf_env"), hf_hit = require("hf_hit"),
  hf_probe = require("hf_probe") }
for _, name in ipairs(FEATURES) do MODULES[name] = require(name) end
local COUNTERS = { "hits", "deflects", "effects", "ignored", "slomos" }

local RT, S

-- The hitch log (hf_util) reads its settings from here; set again on every start.
local function applyDiagnostics()
  local d = S.cfg.Diagnostics or {}
  U.hitchMs, U.maxHitchLogs = tonumber(d.HitchMs) or 0, tonumber(d.MaxHitchLogs) or 30
end

-- The game build, for reports from either side of a game update: PBZ.exe's size tells which build is running (one
-- kept from before an update too), Steam's manifest which one is installed. The mod finds everything by name, so it
-- also runs on builds it was not tested on; a part that finds nothing to work on says so in this log.
local TESTED_BUILDS = { [511072344] = "26266538", [498913272] = "26367565" }
local function logGameBuild()
  local f = io.open(U.root .. "/../../../PBZ.exe", "rb")
  local size = f and f:seek("end")
  if f then f:close() end
  local m = io.open(U.root .. "/../../../../../../../appmanifest_4115450.acf", "r")
  local steam = m and (m:read("*a") or ""):match('"buildid"%s+"(%d+)"')
  if m then m:close() end
  local known = size and TESTED_BUILDS[size]
  U.log("game: PBZ.exe %s bytes%s, Steam build %s%s", tostring(size or "?"), known and (" = build " .. known) or "",
    steam or "?", (known or not size) and "" or "; this version was not tested on this build")
end

local function install()
  local hit, probe, features = MODULES.hf_hit, MODULES.hf_probe, {}
  for _, name in ipairs(FEATURES) do features[#features + 1] = MODULES[name] end
  S.hit, S.probe, S.features = hit, probe, features
  hit.init(S)
  probe.init(S)
  local byName = {}
  for _, m in ipairs(features) do
    m.init(S)
    byName[m.name] = m
  end
  S.freeze = byName.freeze
  S.vfx, S.rumble, S.camera, S.knockback, S.hud = byName.vfx, byName.rumble, byName.camera, byName.knockback, byName.hud
  S.preload, S.flash, S.react, S.receive = byName.preload, byName.flash, byName.react, byName.receive
  S.rhythm, S.screen, S.kill, S.perf = byName.rhythm, byName.screen, byName.kill, byName.perf
  S.guard, S.overlay = byName.guard, byName.overlay
  -- Captures run for every event, mod on or off.
  S.capture = function(ctx)
    byName.camera.capture(ctx)
    byName.vfx.capture(ctx)
    byName.audio.capture(ctx)
    U.try("knockback.capture", byName.knockback.capture, ctx)
    byName.hud.capture(ctx)
  end
  -- (The perf log has no part in a hit's feedback: the hit bus tells it about hits itself.)
  for _, m in ipairs(features) do
    if m.onHit then hit.subscribe(m.name, m.onHit) end
  end
end

local function releaseAll()
  for _, m in ipairs(S.features or {}) do
    if m.release then U.try(m.name .. ".release", m.release) end
  end
end

-- Hotkeys: a modifier (Keys.Modifier: "Ctrl", "Alt", "Shift" or "None") with the key each one names in config.lua
-- (Keys.Panel F5, Keys.Effect F6, Keys.Toggle F7, Keys.Reload F8, Keys.Probe F9, by the engine's key names), so a clash
-- with another mod's keys can be moved. Not F10: UE4SS's ConsoleEnablerMod binds F10 to the engine console; not Alt+F5
-- with PBZModLoader installed, which holds it for its own hot reload. The tuning panel is used with the mouse
-- (hf_hud), but its keys are read here: the panel key opens and closes it, and Esc closes it too unless Hud.EscCloses
-- is off (it does nothing else, and the panel keeps that Esc from the game). Esc is only read while the panel is open.
-- Texts are written with the default keys; U.keys shows the ones in use.
-- { id, default key, action; repeats = acts again while held, bare = no modifier, when = read only then }
local HOTKEYS = {
  { id = "Toggle", key = "F7", act = function()
    S.cfg.Enabled = not S.cfg.Enabled
    if S.hud.cancelTrial then S.hud.cancelTrial() end
    if not S.cfg.Enabled then releaseAll() end
    U.log("toggled %s", S.cfg.Enabled and "ON" or "OFF")
    S.rumble.pulse(S.cfg.Enabled and 1 or 2)
    U.try("hud.render", S.hud.render)
  end },
  -- config.lua and every script but main.lua, loaded afresh (the kernel swaps them in at the next frame).
  { id = "Reload", key = "F8", act = function() RT.request(U.keys("Ctrl+F8")) end },
  { id = "Effect", key = "F6", act = function() S.vfx.cycleSlash(1) end },
  { id = "Probe", key = "F9", act = function()
    S.probe.values()
    S.probe.writeSummary()
    U.log("probe values and summary written")
  end },
  { id = "Panel", key = "F5", act = function() S.hud.toggle() end },
  { id = "Esc", key = "Escape", bare = true, act = function()
    if S.hudState and S.hudState.shown then S.hud.close("esc") end
  end, when = function()
    return S.hudState and S.hudState.shown and S.hud.escCloses and S.hud.escCloses()
  end },
}
-- { the two engine keys of a modifier, its UE4SS ModifierKey (the keybind fallback), how it is written }
local MODIFIERS = { ctrl = { "LeftControl", "RightControl", "CONTROL", "Ctrl" }, alt = { "LeftAlt", "RightAlt", "ALT", "Alt" },
  shift = { "LeftShift", "RightShift", "SHIFT", "Shift" }, none = { nil, nil, nil, nil } }
local DEFAULT_LABEL = { Panel = "Ctrl+F5", Effect = "Ctrl+F6", Toggle = "Ctrl+F7", Reload = "Ctrl+F8", Probe = "Ctrl+F9" }

-- The keys from config.lua: each hotkey's key name (h.name) and label, and the modifier. Shown texts follow (U.keys).
local function keyConfig()
  local k = S.cfg.Keys or {}
  local mod = MODIFIERS[tostring(k.Modifier or "Ctrl"):lower()]
  if not mod then
    U.log("keys: Keys.Modifier %q is not Ctrl, Alt, Shift or None; using Ctrl", tostring(k.Modifier))
    mod = MODIFIERS.ctrl
  end
  local labels = {}
  for _, h in ipairs(HOTKEYS) do
    local name = not h.bare and k[h.id]
    h.name = type(name) == "string" and name:match("^%s*(.-)%s*$") ~= "" and name:match("^%s*(.-)%s*$") or h.key
    h.label = h.bare and h.name or ((mod[4] and (mod[4] .. "+") or "") .. h.name)
    if DEFAULT_LABEL[h.id] and h.label ~= DEFAULT_LABEL[h.id] then labels[DEFAULT_LABEL[h.id]] = h.label end
  end
  U.keyLabels = labels
  return mod
end

local function label(id)
  for _, h in ipairs(HOTKEYS) do
    if h.id == id then return h.label or DEFAULT_LABEL[id] end
  end
end

-- A hotkey's action in the copy of the scripts running now (the keybind fallback's callbacks outlive reloads).
function B.press(id)
  for _, h in ipairs(HOTKEYS) do
    if h.id == id then return U.try("key." .. id, h.act) end
  end
end

-- The old way: UE4SS's RegisterKeyBind. Its callbacks run on UE4SS's own thread, so even the hand-off to the game
-- thread is Lua running beside this mod's per-frame Lua, unlocked, in the same Lua state; holding Ctrl+Left/Right in
-- the panel crashed the game that way (v0.5.4). Only used when config.lua asks for it or the key state cannot be read.
-- Bound once a session: a keybind cannot be taken back, so each one calls whichever copy of the scripts is running.
local function bindKeys(mod)
  if S.keysBound then return end
  S.keysBound = true
  local mods = mod[3] and ModifierKey and { ModifierKey[mod[3]] } or {}
  for _, h in ipairs(HOTKEYS) do
    local key = not h.bare and Key and (Key[h.name] or Key[h.name:upper()])
    local id = h.id
    if h.bare then
      -- (Esc is not bound this way: a bare Esc would also reach the game.)
    elseif key == nil then
      U.log("keys: %s not available in this UE4SS build", h.label)
    else
      local ok, err = pcall(RegisterKeyBind, key, mods, function()
        ExecuteInGameThread(function()
          local boot = S.boot
          if boot and boot.press then boot.press(id) end
        end)
      end)
      if not ok then U.log("keys: could not bind %s: %s", h.label, tostring(err)) end
    end
  end
end

-- The default: the player controller's key state, read on the game thread once a frame, so every line of this mod
-- runs on the game thread. A key acts when it goes down while the modifier is held. A session loop: a reload starts
-- the new copy's in its place.
local function pollKeys(mod)
  local MOD = mod[1] and { { KeyName = FName(mod[1]) }, { KeyName = FName(mod[2]) } }
  for _, h in ipairs(HOTKEYS) do h.fkey = { KeyName = FName(h.name) } end
  -- held[h]: when a held key acts again (repeating keys), false for the others. A key held over a reload (the reload
  -- key that asked for it) does not act again in the new copy.
  local held, logged = {}, S.keysLogged
  for _, h in ipairs(HOTKEYS) do
    if S.keysHeld and S.keysHeld[h.id] then held[h] = false end
  end
  local function scan(pc, modDown)
    -- (The frame's time from the clock: U.now() asks the engine, every frame, for a time only key repeats use.)
    local keys, now = S.cfg.Keys or {}, U.frameNow or U.now()
    local down = {}
    for _, h in ipairs(HOTKEYS) do
      local isDown = (h.bare or modDown) and (not h.when or h.when()) and pc:IsInputKeyDown(h.fkey) == true
      local due = held[h]
      if not isDown then
        held[h] = nil
      else
        down[h.id] = true
        if due == nil or (due and now >= due) then
          held[h] = h.repeats and now + (due and (keys.RepeatMs or 110) or (keys.RepeatDelayMs or 450)) / 1000 or false
          if not logged and not h.bare then
            logged = true
            S.keysLogged = true
            U.log("keys: %s seen (keys are read on the game thread)", h.label)
          end
          U.try("key." .. h.id, h.act)
        end
      end
    end
    S.keysHeld = down
  end
  U.loop("keys", function()
    local pc = U.pc()
    if not pc then return false end
    local ok, modDown = pcall(function() return not MOD or pc:IsInputKeyDown(MOD[1]) or pc:IsInputKeyDown(MOD[2]) end)
    if not ok then
      U.log("keys: the key state cannot be read here (%s); using UE4SS keybinds instead", tostring(modDown))
      bindKeys(mod)
      return true
    end
    U.try("keys", scan, pc, modDown == true)
    return false
  end)
end

-- Starts this copy of the scripts on the kernel's state table. `why` is nil for the game's start, else the reason for
-- a reload; `prev` holds the modules of the copy that ran until now (empty at the start).
function B.start(rt, why, prev)
  RT = rt
  S = RT.S or { hooked = {} }
  RT.S = S
  S.U, S.C, S.boot, S.RT, S.releaseAll = U, C, B, RT, releaseAll
  S.cfg = C.load(U)
  applyDiagnostics()
  S.env = MODULES.hf_env
  S.env.init(S)
  if not why then
    U.log("Hit Feel %s (PBZHitFeel %s without the physics jiggle) loading (root %s, EngineTick %s)", B.HITFEEL_VERSION,
      B.VERSION, U.root, tostring(EngineTickAvailable))
    U.try("game build", logGameBuild)
  end
  local usable, missing = S.env.check()
  if not usable then
    U.log("this UE4SS has no %s, which PBZHitFeel cannot do without, so it does not start; use a current UE4SS for Phantom Blade Zero (KintaroModding's or Vercadi's)",
      table.concat(missing, ", "))
    return
  end
  install()
  local old = prev and prev.hf_hit
  if type(old) == "table" and old ~= S.hit then
    for _, k in ipairs(COUNTERS) do S.hit[k] = old[k] or S.hit[k] end
    S.hit.blade = old.blade
    -- (The blade lists too: the tip samples, and the swing trail with them, need one between hits.)
    S.hit.bladeCaches = old.bladeCaches or S.hit.bladeCaches
  end
  local mod = keyConfig()
  if (S.cfg.Keys or {}).ReadOnGameThread == false or S.keysBound then
    if not S.keysBound then U.log("keys: UE4SS keybinds (Keys.ReadOnGameThread = false)") end
    bindKeys(mod)
  else
    pollKeys(mod)
  end
  if not why then U.try("env.report", S.env.report) end
  U.startClock()
  S.hit.start()
  S.preload.start()
  S.guard.start()
  if S.cfg.Probe.Enabled then
    S.probe.schedule()
  else
    U.stopLoop("probe.scan")
    U.stopLoop("probe.summary")
  end
  U.crumb("%s PBZHitFeel %s", why and ("reloaded (" .. tostring(why) .. ")") or "started", B.VERSION)
  if why then
    U.log("scripts reloaded (%s): PBZHitFeel %s, enabled %s", tostring(why), B.VERSION, tostring(S.cfg.Enabled))
    U.try("rumble.pulse", S.rumble.pulse, 1)
  else
    U.log("Hit Feel %s (PBZHitFeel %s) ready: %s tuning panel, %s on/off, %s reload config and scripts, %s next hit effect (previewed in front of you), %s write probe values",
      B.HITFEEL_VERSION, B.VERSION, label("Panel"), label("Toggle"), label("Reload"), label("Effect"), label("Probe"))
  end
end

-- Before a reload swaps in another copy: what the features changed in the game goes back (effects, the camera, the
-- music, the screen's edges, model offsets). The panel, the hooks and the session loops stay for the new copy.
function B.stop(why)
  if S then releaseAll() end
end

return B
