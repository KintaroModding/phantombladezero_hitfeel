-- PBZ HitFeel: VFX. The hit is marked where it lands: a slash line or an air slash at the contact point, its long axis
-- along the swing (the blade tip's motion into the hit) and its face turned to the camera, so it reads from any angle.
-- Ctrl+F6 steps through the candidates with a preview in front of you; each one's strength step, size and angle are
-- set in the Ctrl+F5 panel. The blade's own swing trail is left as the game made it (an extra hit trail on the blade
-- and an extra impact are options, off by default). Clash sparks on deflects. Everything spawned is switched off after
-- a cap: some systems loop forever.
-- Size: the game's hit effects are authored at one size each, and the game makes a heavier hit look bigger by playing
-- a different file (_101 light, _103 middle, _105 heavy), never by scaling. The spawn scale only spreads such sprite
-- effects a little (0.01 still looked full size), so a set written with "{n}" follows the hit's strength like the
-- game, and the panel's step moves it a version lighter or heavier; the scale stays for the effects that follow it.
-- Every hit gets its effect: our spawns are kept out of the engine's effect culling (Vfx.NeverCull, see V.spawn), and
-- the mod keeps that budget itself (Vfx.MaxAlive at once, none past Vfx.KillAfterMs).
local V = { name = "vfx", spawned = 0, slashes = 0, trails = 0, sparks = 0, captured = {}, assets = {},
  missing = {}, logged = {}, lastTrail = {}, lost = 0, skips = {} }
local S, U, C
local Lang = require("hf_lang")

local NIAGARA_LIB = "/Script/Niagara.Default__NiagaraFunctionLibrary"
V.NIAGARA_AT = "/Script/Niagara.NiagaraFunctionLibrary:SpawnSystemAtLocation"
V.NIAGARA_ATTACHED = "/Script/Niagara.NiagaraFunctionLibrary:SpawnSystemAttached"
local GS = "/Script/Engine.Default__GameplayStatics"
V.EMITTER_AT = "/Script/Engine.GameplayStatics:SpawnEmitterAtLocation"

-- The Ctrl+F6 choice and each effect's panel settings are kept across restarts; delete the files to go back to
-- config.lua.
V.CHOICE_FILE, V.TUNING_FILE = "slash_choice.txt", "slash_tuning.lua"
V.FX_KEYS = { "Step", "Scale", "Angle", "Roll", "Pitch" }

local function rootFile(name) return U.root .. "/" .. name end

local function readChoice()
  local f = io.open(rootFile(V.CHOICE_FILE), "r")
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  if s and s ~= "" then return s end
end

local function writeChoice(s)
  local f = io.open(rootFile(V.CHOICE_FILE), "w")
  if not f then return end
  f:write(s, "\n")
  f:close()
end

local function readTuning()
  local ok, t = pcall(dofile, rootFile(V.TUNING_FILE))
  return ok and type(t) == "table" and t or {}
end

local function writeTuning()
  local keys = {}
  for k in pairs(V.fxTuning) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = { "-- PBZHitFeel: each hit effect's step, scale and angle, set in the Ctrl+F5 panel. Delete this file to go back to config.lua.",
    "return {" }
  for _, k in ipairs(keys) do
    local parts = {}
    for _, f in ipairs(V.FX_KEYS) do
      local v = V.fxTuning[k][f]
      if v ~= nil then parts[#parts + 1] = string.format("%s = %.4g", f, v) end
    end
    lines[#lines + 1] = string.format("  [%q] = { %s },", k, table.concat(parts, ", "))
  end
  lines[#lines + 1] = "}"
  local f = io.open(rootFile(V.TUNING_FILE), "w")
  if not f then return false end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  return true
end

-- ------------------------------------------------------------------ sets by strength

-- The numbers a "{n}" set has: "{n:1,3,5}" lists them, a plain "{n}" has 1 to 5.
local function setNumbers(path)
  local out, list = {}, path:match("{n:([%d,%s]+)}")
  if list then
    for d in list:gmatch("%d+") do out[#out + 1] = tonumber(d) end
    table.sort(out)
  else
    for i = 1, 5 do out[i] = i end
  end
  return out
end

local function isSet(path) return type(path) == "string" and path:find("{n", 1, true) ~= nil end
local function withNumber(path, n) return (path:gsub("{n[^}]*}", tostring(math.floor(n)))) end

-- Index of the number nearest `want`; between two equally near, the one further from the middle (3), so a heavy
-- hit (4) on a 1-3-5 set gets 5 and a light one (2) gets 1.
local function nearest(nums, want)
  local best = 1
  for i, n in ipairs(nums) do
    local d, bd = math.abs(n - want), math.abs(nums[best] - want)
    if d < bd or (d == bd and math.abs(n - 3) > math.abs(nums[best] - 3)) then best = i end
  end
  return best
end

-- "{n}" in an effect path becomes the hit's strength, numbered like the game's own hit effects (1 = lightest), or
-- the set's nearest number; `step` then moves that many versions lighter (negative) or heavier within the set.
function V.expand(path, tierName, step)
  if not isSet(path) then return path end
  local nums = setNumbers(path)
  local want = C.tier(S.cfg.Vfx.AirTrail.TierNumber, tierName or "Default") or 2
  local at = math.max(1, math.min(#nums, nearest(nums, want) + math.floor(tonumber(step) or 0)))
  return withNumber(path, nums[at])
end

-- A choice saved as one file of what is now a set ("..._103" before "..._10{n:1,3,5}") means that set.
local function migrateChoice(choice)
  if not choice or choice == "off" then return choice end
  local list = V.slashCandidates()
  for _, p in ipairs(list) do
    if p == choice then return choice end
  end
  for _, p in ipairs(list) do
    if isSet(p) then
      for _, n in ipairs(setNumbers(p)) do
        if withNumber(p, n) == choice then return p end
      end
    end
  end
  return choice
end

function V.init(state)
  S, U, C = state, state.U, state.C
  S.ourEffects = S.ourEffects or {}
  V.slashChoice = migrateChoice(readChoice())
  V.fxTuning = readTuning()
end

-- HUD multipliers (Tuning.*), 1.0 when absent.
function V.mult(key)
  local t = S.cfg.Tuning or {}
  return tonumber(t[key]) or 1
end

-- The vanilla hit effect of this weapon; body effects first, since trails only show when attached and moving. Also
-- the full names of everything the game plays for this hit, so a set the game already uses is not doubled.
function V.capture(ctx)
  if not ctx.byPlayer then return end
  local pick
  ctx.vanillaFxPaths = {}
  for _, o in ipairs(ctx.objects) do
    if o.kind == "object" and (U.chainHas(o.chain, "NiagaraSystem") or U.chainHas(o.chain, "ParticleSystem")) then
      ctx.vanillaFxPaths[#ctx.vanillaFxPaths + 1] = U.fullName(o.obj)
      local trail = U.fname(o.obj):lower():find("trail", 1, true) ~= nil
      if not pick or (pick.trail and not trail) then pick = { o = o, trail = trail } end
    end
  end
  if not pick then return end
  local w = ctx.weapon or "any"
  if not V.captured[w] then U.log("vfx: captured %s hit effect %s (%s)", w, U.fullName(pick.o.obj), pick.o.path) end
  V.captured[w] = pick.o.obj
  V.captured.any = pick.o.obj
  ctx.vanillaVfx = ctx.vanillaVfx or pick.o
end

-- What a spawn template is: "niagara", "cascade" (a ParticleSystem; the game's own hit effects may be one), or nil for
-- anything else, with the class chain it was read from. Read again on every use, never kept by address: an asset the
-- engine has freed can leave its address to another object.
function V.effectKind(sys)
  local chain = U.classChain(sys)
  if U.chainHas(chain, "NiagaraSystem") then return "niagara", chain end
  if U.chainHas(chain, "ParticleSystem") then return "cascade", chain end
  return nil, chain
end

-- Assets by path, re-found when the engine has unloaded one (the preloader keeps them referenced) or when the object
-- kept for a path is no effect any more (its address taken by another object). A path that does not load is not tried
-- again (a load attempt on the game thread is a hitch on every hit).
function V.asset(path)
  if not path or path == "" or path == "off" or V.missing[path] then return nil end
  local o = V.assets[path]
  if U.valid(o) and V.effectKind(o) then return o end
  o = StaticFindObject(path)
  if not U.valid(o) then
    U.note("loaded %s", tostring(path):match("([^%./]+)$") or tostring(path))
    o = U.try("vfx.load", LoadAsset, path)
  end
  V.assets[path] = U.valid(o) and o or nil
  if not V.assets[path] then
    V.missing[path] = true
    U.log("vfx: %s could not be loaded; not trying it again until Ctrl+F8", path)
  end
  return V.assets[path]
end

-- Our spawned components are remembered for a while, so the weapon-trail search never mistakes one for the game's.
local function remember(comp, ms)
  local key = U.addr(comp)
  if not key then return end
  S.ourEffects[key] = true
  ExecuteInGameThreadWithDelay(math.floor(ms + 3000), function() S.ourEffects[key] = nil end)
end

-- Switches a spawned effect off after `ms`: looping systems (trails, buffs) never end on their own. Ones that have
-- finished by then have auto-destroyed and fail the validity check.
function V.limit(comp, ms)
  if not ms or ms <= 0 or not U.valid(comp) then return comp end
  remember(comp, ms)
  ExecuteInGameThreadWithDelay(math.floor(ms), function()
    if U.valid(comp) then U.try("vfx.limit", function() comp:Deactivate() end) end
  end)
  return comp
end

V.spawnedOnce = {}

-- ------------------------------------------------------------------ black-red tint

-- A Niagara system's user parameters (the ones a spawned component can be given), read once per system and logged
-- the first time it is spawned: an effect tints only through a color parameter of its own.
V.paramsBySys = {}

function V.userParams(sys)
  local key = U.addr(sys)
  if not key then return { names = {}, colors = {} } end
  local p = V.paramsBySys[key]
  if p then return p end
  p = { names = {}, colors = {} }
  V.paramsBySys[key] = p
  if not U.isA(sys, "NiagaraSystem") then return p end
  local read = U.try("vfx.params", function()
    local ep = sys.ExposedParameters
    local list = ep and ep.SortedParameterOffsets
    if not list then return false end
    list:ForEach(function(_, e)
      local n = e:get().Name:ToString()
      p.names[#p.names + 1] = n
      -- ("tint" only where a word starts: UE_LightIntensity holds "tint" as well, and v0.6.1 set a color on it.)
      local low = n:lower()
      if low:find("colou?r") or low:find("%f[%a]tint") then p.colors[#p.colors + 1] = n end
    end)
    return true
  end)
  U.log("vfx: %s user parameters: %s; %s", U.fname(sys), read and (#p.names > 0 and table.concat(p.names, ", ") or "none")
    or "not readable", #p.colors > 0 and ("tinted through " .. table.concat(p.colors, ", "))
    or "no color parameter, so it keeps its own colors")
  return p
end

-- The second way, for an effect with no color parameter (v0.6.0 in game: the metal sparks and the doll hit trails have
-- only User.UE_Direction): its materials. Each material slot of the spawned component becomes a dynamic instance of
-- its material (CreateDynamicMaterialInstance, as the flash does on bodies), and the color-like vector parameters it
-- has are set to the tint at the brightness they had. Whether a Niagara component of this engine build lists its
-- materials and takes such an override is not known: the first spawn of each system finds out and logs what it found
-- (slots, materials, color parameters, whether the instance took); later spawns repeat only what took.
V.CREATE_MID = "/Script/Engine.PrimitiveComponent:CreateDynamicMaterialInstance"
-- Tried on every material; a material instance adds the color-like names it sets itself.
V.MAT_COLOR_NAMES = { "Color", "Tint", "TintColor", "EmissiveColor", "Emissive Color", "BaseColor", "Base Color",
  "ParticleColor", "Particle Color", "Emissive" }
V.matsBySys = {}

local function looksLikeColor(n)
  local low = n:lower()
  return low:find("colou?r") or low:find("%f[%a]tint") or low:find("emiss")
end

-- The color-like vector parameters a material instance sets (a base material lists none from here).
local function instanceColorNames(m)
  local out = {}
  U.try("vfx.matparams", function()
    local arr = m.VectorParameterValues
    if not arr then return end
    arr:ForEach(function(_, e)
      local n = e:get().ParameterInfo.Name:ToString()
      if looksLikeColor(n) then out[#out + 1] = n end
    end)
  end)
  return out
end

-- The tint's hue at the brightness of `v` (an emissive color of 8 stays 8 bright), `v`'s alpha kept.
local function tinted(col, v)
  local cmax = math.max(col.R, col.G, col.B, 0.0001)
  local peak = math.max(v.R or 0, v.G or 0, v.B or 0)
  return { R = col.R / cmax * peak, G = col.G / cmax * peak, B = col.B / cmax * peak, A = v.A or 1 }
end

local function readColor(mid, name)
  local c = mid:K2_GetVectorParameterValue(FName(name))
  return { R = c.R, G = c.G, B = c.B, A = c.A }
end

-- The first spawn of a system: every slot looked at, tinted where it can be. Returns what to repeat on later spawns.
local function probeMaterials(comp, sys, col)
  local slots, seen = {}, {}
  local n = tonumber(U.try("vfx.matnum", function() return comp:GetNumMaterials() end)) or 0
  for i = 0, math.min(n, 8) - 1 do
    local m = U.try("vfx.mat", function() return comp:GetMaterial(i) end)
    if U.valid(m) then
      local mid = U.isA(m, "MaterialInstanceDynamic") and m or U.try("vfx.mid", U.callNamed, comp, V.CREATE_MID, { ElementIndex = i })
      local took = U.valid(mid) and U.same(U.try("vfx.matback", function() return comp:GetMaterial(i) end), mid)
      local found, names, tried = {}, instanceColorNames(m), {}
      for _, nm in ipairs(V.MAT_COLOR_NAMES) do names[#names + 1] = nm end
      for _, nm in ipairs(took and names or {}) do
        if not tried[nm] then
          tried[nm] = true
          local v = U.try("vfx.matget", readColor, mid, nm)
          if v and (v.R + v.G + v.B) > 0.001 then
            found[#found + 1] = { name = nm, value = v }
            U.try("vfx.matset", function() mid:SetVectorParameterValue(FName(nm), tinted(col, v)) end)
          end
        end
      end
      local listed = {}
      for _, f in ipairs(found) do listed[#listed + 1] = string.format("%s (%.2f, %.2f, %.2f)", f.name, f.value.R, f.value.G, f.value.B) end
      seen[#seen + 1] = string.format("slot %d %s: %s", i, U.fname(m), not U.valid(mid) and "no instance made"
        or (not took and "the instance did not take" or (#listed > 0 and ("tinted " .. table.concat(listed, ", ")) or "no color parameter")))
      if #found > 0 then slots[#slots + 1] = { slot = i, colors = found } end
    end
  end
  U.log("vfx: %s has no color parameter; through its materials: %s", U.fname(sys),
    n == 0 and "the component lists none (no material override here)" or table.concat(seen, "; "))
  return slots
end

local function tintMaterials(comp, sys, col)
  local key = U.addr(sys)
  if not key then return end
  local info = V.matsBySys[key]
  if info == nil then
    V.matsBySys[key] = { slots = probeMaterials(comp, sys, col) }
    return
  end
  for _, sl in ipairs(info.slots) do
    local mid = U.try("vfx.mid", U.callNamed, comp, V.CREATE_MID, { ElementIndex = sl.slot })
    if U.valid(mid) then
      for _, f in ipairs(sl.colors) do
        U.try("vfx.matset", function() mid:SetVectorParameterValue(FName(f.name), tinted(col, f.value)) end)
      end
    end
  end
end

-- Whether this system takes the tint: true (a color parameter, or materials that took it), false (neither), nil (no
-- color parameter, and its materials not looked at yet: that happens on its first spawn).
function V.tintable(sys)
  if not U.valid(sys) then return nil end
  if #V.userParams(sys).colors > 0 then return true end
  if (S.cfg.Vfx.Tint or {}).Materials == false then return false end
  local m = V.matsBySys[U.addr(sys) or 0]
  if m == nil then return nil end
  return #m.slots > 0
end

-- Our spawned hit effects (the one at the contact, the blade's hit trail, the extra impact) in Vfx.Tint.Color. The
-- type of a color parameter is not known from here, so it is set as both a color and a 4-vector; the wrong one is
-- added unused. Without one, the materials (Vfx.Tint.Materials).
function V.tint(comp, sys)
  local t = S.cfg.Vfx.Tint or {}
  if not t.Enabled or not U.valid(comp) or not U.valid(sys) then return end
  local col = t.Color or { R = 0.3, G = 0, B = 0.01, A = 1 }
  local colors = V.userParams(sys).colors
  for _, n in ipairs(colors) do
    local name = FName(n)
    U.try("vfx.tint", function() comp:SetVariableLinearColor(name, col) end)
    U.try("vfx.tint4", function() comp:SetVariableVec4(name, { X = col.R, Y = col.G, Z = col.B, W = col.A or 1 }) end)
  end
  if #colors == 0 and t.Materials ~= false then U.try("vfx.tintmat", tintMaterials, comp, sys, col) end
end

-- Our effects sort over the game's own translucent ones (blood mist, smoke) at the same depth: Vfx.SortPriority.
-- Bodies in front still hide them; the hit effect is moved out of the struck body for that (V.towardCamera).
local function onTop(nc)
  local prio = tonumber(S.cfg.Vfx.SortPriority) or 0
  if prio ~= 0 and U.valid(nc) then U.try("vfx.sort", function() nc:SetTranslucentSortPriority(prio) end) end
  return nc
end

-- Niagara may cull a system it is asked to play, on activation and while it runs, by its effect type's limits (how
-- many may play at once, distance, time off screen); bPreCullCheck = false only skips the check before spawning.
-- Skill effects carry such limits: in the v0.6.2 footage the ink blade showed on the first hit of each string looked
-- at and not on the quick ones after it while the first still played, though the mod spawned one for each. So a
-- Niagara effect of ours is spawned switched off, taken out of scalability and then switched on (Vfx.NeverCull); all
-- of them are short and capped by V.limit. Where a component does not switch on that way, later ones are spawned on
-- as before.
local function manualActivation()
  return S.cfg.Vfx.NeverCull ~= false and not V.activateBroken
end

local function activate(comp)
  if not U.valid(comp) then return comp end
  if not V.noScalabilitySwitch and not pcall(function() comp:SetAllowScalability(false) end) then
    V.noScalabilitySwitch = true
    U.log("vfx: SetAllowScalability could not be called; the engine may still cull our effects")
  end
  local ok, err = pcall(function() comp:Activate(true) end)
  if not ok then
    V.activateBroken = true
    U.log("vfx: a spawned effect would not switch on (%s); effects are spawned switched on from now on, without Vfx.NeverCull",
      tostring(err))
  end
  return comp
end

-- The budget the engine would keep, kept here, since our effects are out of its culling: at most Vfx.MaxAlive of ours
-- play at once, and one more ends the oldest (one already switched off and fading first); none lasts past
-- Vfx.KillAfterMs. The list is swept every 10 frames (hf_perf calls V.sweep): an effect that has finished has
-- destroyed itself, and how long it lasted goes to the perf log.
V.live, V.budgetCuts = {}, 0

local function kill(e)
  if not U.valid(e.comp) then return end
  if not pcall(function() e.comp:DeactivateImmediate() end) then pcall(function() e.comp:Deactivate() end) end
end

function V.sweep(now)
  now = now or U.now()
  local keep, maxMs = {}, tonumber(S.cfg.Vfx.KillAfterMs) or 0
  for _, e in ipairs(V.live) do
    if not U.valid(e.comp) then
      if S.perf then S.perf.gone(now - e.at) end
    elseif maxMs > 0 and (now - e.at) * 1000 >= maxMs then
      kill(e)
      if S.perf then S.perf.gone(now - e.at, "aged") end
    else
      keep[#keep + 1] = e
    end
  end
  V.live = keep
end

local function track(comp, lifeMs)
  if not U.valid(comp) then return end
  local now = U.now()
  local most = tonumber(S.cfg.Vfx.MaxAlive) or 0
  if most > 0 and #V.live >= most then V.sweep(now) end
  if most > 0 and #V.live >= most then
    local pick = 1
    for i, e in ipairs(V.live) do
      if now >= e.offAt then
        pick = i
        break
      end
    end
    local e = table.remove(V.live, pick)
    kill(e)
    V.budgetCuts = V.budgetCuts + 1
    if V.budgetCuts == 1 then U.log("vfx: %d of our effects were playing at once (Vfx.MaxAlive); the oldest was ended for a new one", most) end
    if S.perf then S.perf.gone(now - e.at, "cut") end
  end
  V.live[#V.live + 1] = { comp = comp, at = now, offAt = now + (lifeMs or 0) / 1000 }
  if S.perf then S.perf.spawned(#V.live) end
end

-- A template that is not the kind its spawner takes is not spawned. The engine does not check it: given anything but a
-- ParticleSystem, SpawnEmitterAtLocation reads the object as one and crashes the game (a player's crash dump,
-- 2026-11-05), and SpawnSystemAttached reads it as a NiagaraSystem. Up to v0.7.1 every template whose class did not
-- read as NiagaraSystem went to SpawnEmitterAtLocation unchecked. Counted for the summary; the first few are logged
-- with the class chain that was read.
V.refused = 0

local function refuse(sys, chain, wanted)
  V.refused = V.refused + 1
  if V.refused <= 5 then
    U.log("vfx: not spawning %s: its class reads %s, not %s (%d so far)", U.fname(sys),
      #chain > 0 and table.concat(chain, " < ") or "nothing", wanted, V.refused)
  end
end

-- The first spawn of each system is timed for the hitch log: a long call is the spawn itself, a short one before a
-- hitch points at the renderer (its first draw).
function V.spawn(sys, loc, rot, scale, world, lifeMs)
  if not U.valid(sys) then return nil end
  local kind, chain = V.effectKind(sys)
  if not kind then
    refuse(sys, chain, "a Niagara or particle system")
    return nil
  end
  local s = U.v3(scale, scale, scale)
  local key = U.addr(sys)
  local first = key and not V.spawnedOnce[key]
  if first then V.spawnedOnce[key] = true end
  local t0 = os.clock()
  local comp
  if kind == "niagara" then
    local manual = manualActivation()
    comp = U.callNamed(U.cdo(NIAGARA_LIB), V.NIAGARA_AT, {
      WorldContextObject = world, SystemTemplate = sys, Location = loc, Rotation = rot, Scale = s,
      bAutoDestroy = true, bAutoActivate = not manual, PoolingMethod = 0, bPreCullCheck = false,
    })
    if manual then activate(comp) end
  else
    comp = U.callNamed(U.cdo(GS), V.EMITTER_AT, {
      WorldContextObject = world, EmitterTemplate = sys, Location = loc, Rotation = rot, Scale = s,
      bAutoDestroy = true, PoolingMethod = 0, bAutoActivateSystem = true,
    })
  end
  if first then U.note("first spawn of %s (the call took %.0f ms)", U.fname(sys), (os.clock() - t0) * 1000) end
  U.crumb("vfx %s (%s)", V.nameOf(sys, key), kind)
  local life = lifeMs or S.cfg.Vfx.MaxLifeMs or 1500
  track(comp, life)
  return V.limit(onTop(comp), life)
end

-- An effect's name for logs/recent.txt, read once per asset.
V.names = {}
function V.nameOf(sys, key)
  key = key or U.addr(sys)
  local n = key and V.names[key]
  if not n then
    n = U.fname(sys)
    if key then V.names[key] = n end
  end
  return n
end

-- Attached to a blade socket (at an offset relative to it) for `ms`, then deactivated (its particles fade out on
-- their own). LocationType 0 keeps the offset relative to the socket. Niagara systems only.
function V.spawnAttached(sys, comp, socket, ms, loc, rot)
  if not U.valid(sys) then return nil end
  local kind, chain = V.effectKind(sys)
  if kind ~= "niagara" then
    refuse(sys, chain, "a Niagara system")
    return nil
  end
  U.crumb("vfx %s (attached)", V.nameOf(sys))
  local manual = manualActivation()
  local nc = U.callNamed(U.cdo(NIAGARA_LIB), V.NIAGARA_ATTACHED, {
    SystemTemplate = sys, AttachToComponent = comp, AttachPointName = socket, Location = loc or U.v3(0, 0, 0),
    Rotation = rot or { Pitch = 0, Yaw = 0, Roll = 0 }, LocationType = 0, bAutoDestroy = true, bAutoActivate = not manual,
    PoolingMethod = 0, bPreCullCheck = false,
  })
  if manual then activate(nc) end
  track(nc, ms)
  return V.limit(onTop(nc), ms)
end

-- Whether the engine let a hit effect play: one it culls is off at once or within a frame or two (a hit effect plays
-- for half a second or more). Counted for the summary; the first few are logged by name.
local function watch(comp, name)
  local function playing()
    return U.valid(comp) and U.try("vfx.active", function() return comp:IsActive() end) == true
  end
  local function lost(when)
    V.lost = V.lost + 1
    if V.lost <= 3 then U.log("vfx: the engine stopped hit effect %s %s (%d so far)", name, when, V.lost) end
  end
  if not playing() then return lost("as it spawned") end
  U.afterFrames(2, function()
    if not playing() then lost("within two frames") end
  end)
end

-- Why a hit went without its hit effect, counted for the summary.
local function skip(why) V.skips[why] = (V.skips[why] or 0) + 1 end

-- True when the game already plays an effect from the same folder for this hit: the doll set on an enemy that does
-- not bleed (the YuCong boss) gets nothing more from us.
function V.gameUsesSet(ctx, path)
  if not S.cfg.Vfx.SkipWhenGameUsesSameSet or type(path) ~= "string" then return false end
  local dir = path:match("^(.*/)[^/]*$")
  if not dir then return false end
  for _, p in ipairs(ctx.vanillaFxPaths or {}) do
    if p:find(dir, 1, true) then
      if not V.skipLogged then
        V.skipLogged = true
        U.log("vfx: the game already plays %s on this enemy; adding nothing from that set", p)
      end
      return true
    end
  end
  return false
end

-- The effect's file name; a set ends in "(by strength)". On screen (`ui`) without the NS_ prefix and in the panel's
-- language; the logs keep the full name, in English.
local function shortName(path, ui)
  local name = tostring(path):match("([^%./]+)$") or tostring(path)
  if ui then name = name:gsub("^NS_", "") end
  if not isSet(name) then return name end
  return name:gsub("_?%d*{n[^}]*}", "") .. (ui and Lang.t(" (按力度)") or " (by strength)")
end

local function notice(msg)
  if S.hud and S.hud.toast then U.try("hud.toast", S.hud.toast, msg) end
end

-- ------------------------------------------------------------------ orientation

local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return U.v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end

-- v turned `deg` degrees about the unit axis k (Rodrigues).
local function rotateAbout(v, k, deg)
  local a = math.rad(deg)
  local c, s = math.cos(a), math.sin(a)
  local kv, kd = cross(k, v), dot(k, v) * (1 - c)
  return U.v3(v.X * c + kv.X * s + k.X * kd, v.Y * c + kv.Y * s + k.Y * kd, v.Z * c + kv.Z * s + k.Z * kd)
end

-- The rotator with these axes, as UE's FMatrix::Rotator computes it.
local function rotatorFromAxes(X, Y, Z)
  local pitch = math.deg(math.atan(X.Z, math.sqrt(X.X * X.X + X.Y * X.Y)))
  local yaw = math.deg(math.atan(X.Y, X.X))
  local r = math.rad(yaw)
  local sy = U.v3(-math.sin(r), math.cos(r), 0)
  return { Pitch = pitch, Yaw = yaw, Roll = math.deg(math.atan(dot(Z, sy), dot(Y, sy))) }
end
V.rotatorFromAxes = rotatorFromAxes

local function cameraLoc()
  local pcm = U.pcm()
  return pcm and U.try("vfx.cam", function() return U.copyv(pcm:GetCameraLocation()) end)
end

local function cameraYaw()
  local pcm = U.pcm()
  local rot = pcm and U.try("vfx.camrot", function() return U.copyr(pcm:GetCameraRotation()) end)
  return math.rad(rot and rot.Yaw or 0)
end

-- Where a hit effect is drawn so that the body it lands on does not hide it: moved along the line to the camera (so
-- it stays at the same place on screen; only its depth changes) until it is out of the struck body's capsule on the
-- camera's side, plus Vfx.Slash.BodyMarginCm; at least TowardCameraCm, at most MaxTowardCameraCm and never past half
-- the way to the camera. v0.6.1 moved it a flat 15 cm, and an effect on the far side of a body stayed inside it.
function V.towardCamera(at, cam, victim, c)
  local d = U.sub(cam, at)
  local dist = U.len(d)
  if dist < 1 then return at, 0 end
  local dir = U.mul(d, 1 / dist)
  local need = c.TowardCameraCm or 0
  local o = victim and U.actorLoc(victim)
  if o then
    local hh, r = U.capsule(victim)
    local margin = c.BodyMarginCm or 12
    r = r + margin
    -- Where the line leaves the capsule's side (its circle seen from above) toward the camera...
    local px, py, dx, dy = at.X - o.X, at.Y - o.Y, dir.X, dir.Y
    local a = dx * dx + dy * dy
    local exit
    if a > 1e-4 then
      local b = 2 * (px * dx + py * dy)
      local disc = b * b - 4 * a * (px * px + py * py - r * r)
      if disc > 0 then exit = (-b + math.sqrt(disc)) / (2 * a) end
    end
    -- ... or its top, for a camera looking down.
    if exit and exit > 0 and dir.Z > 1e-3 then
      local top = (o.Z + hh + margin - at.Z) / dir.Z
      if top > 0 then exit = math.min(exit, top) end
    end
    if exit and exit > need then need = exit end
  end
  local pull = math.max(0, math.min(need, c.MaxTowardCameraCm or 120, dist * 0.5))
  return U.add(at, U.mul(dir, pull)), pull
end

-- The swing when the blade's own motion is unknown: across the screen, a little downward.
local function fallbackSweep()
  local y = cameraYaw()
  return U.norm(U.v3(-math.sin(y), math.cos(y), -0.35))
end

-- The effect's axes: X along the swing, Z toward the camera (a flat effect faces you), then its own corrections:
-- Angle turns it in the screen plane (about Z), Pitch about Y, Roll about the swing (X).
function V.slashRotation(at, sweep, fx, cam)
  local X = U.norm(sweep)
  local c = cam and U.norm(U.sub(cam, at)) or U.v3(0, 0, 1)
  local Z = U.sub(c, U.mul(X, dot(c, X)))
  if U.len(Z) < 0.05 then Z = U.sub(U.v3(0, 0, 1), U.mul(X, X.Z)) end
  if U.len(Z) < 0.05 then Z = U.v3(1, 0, 0) end
  Z = U.norm(Z)
  local Y = cross(Z, X)
  if fx.Angle ~= 0 then X, Y = rotateAbout(X, Z, fx.Angle), rotateAbout(Y, Z, fx.Angle) end
  if fx.Pitch ~= 0 then X, Z = rotateAbout(X, Y, fx.Pitch), rotateAbout(Z, Y, fx.Pitch) end
  if fx.Roll ~= 0 then Y, Z = rotateAbout(Y, X, fx.Roll), rotateAbout(Z, X, fx.Roll) end
  return rotatorFromAxes(X, Y, Z)
end

-- ------------------------------------------------------------------ the hit effect (Slash)

function V.slashCandidates()
  local list = {}
  for _, p in ipairs(S.cfg.Vfx.Slash.Candidates or {}) do
    if type(p) == "string" and p ~= "" then list[#list + 1] = p end
  end
  return list
end

-- The effect with no Ctrl+F6 choice saved: Vfx.Slash.Default, else the first candidate. (v0.6.2 always took the first,
-- the ZuoShang QTE hit, which filled the screen with purple flames on every hit.)
function V.defaultSlash()
  local d = S.cfg.Vfx.Slash.Default
  if type(d) == "string" and d ~= "" then return d end
  return V.slashCandidates()[1]
end

-- The effect in use: the Ctrl+F6 choice ("off" for none), else the default.
function V.slashPath()
  local p = V.slashChoice or V.defaultSlash()
  if p == "off" then return nil end
  return p
end

-- Its size and angle: the panel's values over config.lua's Effects over plain defaults.
function V.fx(path)
  local base = (S.cfg.Vfx.Slash.Effects or {})[path or ""] or {}
  local over = V.fxTuning[path or ""] or {}
  local out = {}
  for _, k in ipairs(V.FX_KEYS) do
    out[k] = tonumber(over[k]) or tonumber(base[k]) or (k == "Scale" and 1 or 0)
  end
  return out
end

-- One hit effect at `at`, along `sweep`, at strength `tierName`: the version of a set for that strength and the
-- panel's step, drawn toward the camera out of the struck body (`victim`, V.towardCamera). Returns the rotation, the
-- scale, the file used and the spawned component; nil and why when there is none.
local function slashAt(path, at, sweep, tierName, world, victim)
  local c = S.cfg.Vfx.Slash
  local fx = V.fx(path)
  local file = V.expand(path, tierName, fx.Step)
  local sys = V.asset(file)
  if not U.valid(sys) then return nil, "asset not loaded" end
  local scale = (C.tier(c.Scale, tierName) or 1) * fx.Scale * V.mult("Slash")
  if scale <= 0 then return nil, "size 0" end
  local cam = cameraLoc()
  local loc = at
  if cam then loc = V.towardCamera(at, cam, victim, c) end
  local rot = V.slashRotation(at, sweep, fx, cam)
  local comp = V.spawn(sys, loc, rot, scale, world, c.MaxMs)
  if not comp then return nil, "not an effect" end
  V.tint(comp, sys)
  return rot, scale, file, comp
end

local function slash(ctx)
  local path = V.slashPath()
  if not path then return skip("off") end
  if V.gameUsesSet(ctx, V.expand(path, ctx.tierName)) then return skip("the game plays this set") end
  local sweep = ctx.sweep or fallbackSweep()
  local rot, scale, file, comp = slashAt(path, ctx.impact, sweep, ctx.tierName, ctx.victim, ctx.victim)
  if not rot then return skip(scale) end
  V.slashes = V.slashes + 1
  watch(comp, shortName(file))
  if not V.logged[path] then
    V.logged[path] = true
    U.log("vfx: hit effect %s%s at %s, swing (%.2f, %.2f, %.2f) from %s, size %.2f, rotation (P%.0f Y%.0f R%.0f)",
      shortName(path), isSet(path) and string.format(" (%s for this %s hit)", shortName(file), tostring(ctx.tierName)) or "",
      tostring(ctx.hitBone), sweep.X, sweep.Y, sweep.Z, ctx.sweep and tostring(ctx.sweepFrom) or "camera (blade motion unknown)",
      scale, rot.Pitch, rot.Yaw, rot.Roll)
  end
end

-- A preview in front of you, as a horizontal swing across the screen at chest height, at middle strength. Returns
-- the name of the file shown.
function V.previewSlash()
  local path = V.slashPath()
  local p = U.player()
  local pl = p and U.actorLoc(p)
  if not path or not pl then return nil end
  local y = cameraYaw()
  local at = U.add(U.add(pl, U.v3(math.cos(y) * (S.cfg.Vfx.Slash.PreviewDistanceCm or 180),
    math.sin(y) * (S.cfg.Vfx.Slash.PreviewDistanceCm or 180), 0)), U.v3(0, 0, 40))
  local rot, _, file = U.try("vfx.preview", slashAt, path, at, U.v3(-math.sin(y), math.cos(y), 0), "Middle", p)
  if not rot then
    U.log("vfx: hit effect %s could not be loaded", tostring(path))
    return nil
  end
  return shortName(file)
end

-- Ctrl+F6 (d = 1) and the panel (d = +-1): next or previous candidate, then "off", round again. Named on screen and
-- previewed in front of you.
function V.cycleSlash(d)
  local list = V.slashCandidates()
  list[#list + 1] = "off"
  local at = 0
  for i, p in ipairs(list) do
    if p == (V.slashChoice or V.defaultSlash()) then at = i end
  end
  at = (at - 1 + (d or 1)) % #list + 1
  V.slashChoice = list[at]
  writeChoice(V.slashChoice)
  if V.slashChoice == "off" then
    U.log("hit effect: off")
    notice(Lang.t("命中特效：关"))
    return
  end
  U.log("hit effect %d/%d: %s", at, #list - 1, V.slashChoice)
  notice(Lang.f("命中特效 %d/%d：%s", at, #list - 1, shortName(V.slashChoice, true)))
  V.previewSlash()
end

-- For the panel's hit-effect page.
function V.slashLabel()
  local path = V.slashPath()
  if not path then return Lang.t("关") end
  local list = V.slashCandidates()
  for i, p in ipairs(list) do
    if p == path then return string.format("%d/%d %s", i, #list, shortName(path, true)) end
  end
  return shortName(path, true)
end

function V.fxGet(key)
  return V.fx(V.slashPath())[key]
end

-- True when the effect in use is a set with lighter and heavier versions (the panel's step applies).
function V.hasSteps()
  local path = V.slashPath()
  return isSet(path) and #setNumbers(path) > 1
end

-- Saves one setting for the effect in use and previews it; returns whether it was saved and the file previewed.
function V.fxSet(key, v)
  local path = V.slashPath()
  if not path then return false end
  if key == "Step" and v then
    local most = isSet(path) and #setNumbers(path) - 1 or 0
    v = math.max(-most, math.min(most, v))
  end
  V.fxTuning[path] = V.fxTuning[path] or {}
  V.fxTuning[path][key] = v
  local ok = writeTuning()
  return ok, V.previewSlash()
end

-- ------------------------------------------------------------------ hit trail on the blade (off by default)

-- The trail for this hit: the weapon's own trail when wanted and playing, else the one configured for the weapon type.
function V.trailPath(blade, weapon)
  local c = S.cfg.Vfx.AirTrail
  if c.UseWeaponTrail and blade and blade.ownTrail then return blade.ownTrail end
  local by = c.ByWeapon or {}
  return by[weapon or ""] or by.Default
end

local function isHitTrail(path, c)
  for _, k in ipairs(c.HitTrailKeywords or {}) do
    if tostring(path):find(k, 1, true) then return true end
  end
  return false
end

-- Where the trail goes on the blade. A hit trail goes on the blade socket, where the game attaches its own on a hit.
-- A swing trail goes where the game attached this weapon's own trail, once seen (trails are authored for their
-- attach point); before that, on the tip (AtTip) or the blade socket.
local function placement(b, c, path)
  if path and isHitTrail(path, c) then return b.socket, nil, nil, b.name end
  local at = b.trailAt
  if at then return at.socket, at.loc, at.rot, at.socketName end
  local s = (c.AtTip and b.tip) or b.socket
  return s, nil, nil, (c.AtTip and b.tipName) or b.name
end

local function airTrail(ctx, c, ms)
  local b = ctx.blade or (S.hit and S.hit.blade)
  if not b or not U.valid(b.comp) then return end
  -- One swing that strikes two enemies hangs one trail on the blade, not two.
  local bk = U.addr(b.comp)
  local last = bk and V.lastTrail[bk]
  if last and (ctx.time - last) * 1000 < (S.cfg.Vfx.MinIntervalMs or 0) then return end
  if bk then V.lastTrail[bk] = ctx.time end
  local path = V.expand(V.trailPath(b, ctx.weapon), ctx.tierName)
  if V.gameUsesSet(ctx, path) then return end
  local sys = V.asset(path)
  if not U.valid(sys) or ms <= 0 then return end
  local socket, loc, rot, socketName = placement(b, c, path)
  local key = tostring(socketName) .. (isHitTrail(path, c) and "/hit" or "/swing")
  if V.lastPlacement ~= key then
    V.lastPlacement = key
    local why = isHitTrail(path, c) and " (the blade socket, where the game puts its own hit trails)"
      or (b.trailAt and " (where the game puts this weapon's trail)" or "")
    U.log("vfx: air trail %s at %s%s", tostring(path), tostring(socketName), why)
  end
  V.tint(U.try("vfx.trail", V.spawnAttached, sys, b.comp, socket, ms, loc, rot), sys)
  V.trails = V.trails + 1
end

-- ------------------------------------------------------------------ the air trail through every swing

-- A swing is the blade's tip moving fast relative to you (running does not count): Vfx.SwingTrail.StartCmPerSec two
-- frames in a row starts the trail on that blade, where the game attaches its own hit trails, and it follows the
-- whole swing. StopFrames frames below StopCmPerSec end it (the ribbon fades out on its own), MaxMs at the latest. One
-- trail per blade, so both blades of a pair can swing. The hit trail (AirTrail) stays an extra layer on hits. Driven
-- by the blade-tip samples hf_hit takes every frame (H.sampleTips).
V.swings, V.swingTrails = {}, 0

local function endSwing(sw)
  if U.valid(sw.comp) then U.try("vfx.swingend", function() sw.comp:Deactivate() end) end
  sw.comp, sw.endedAt, sw.fast = nil, sw.now, 0
end

local function startSwing(b, sw, c, now)
  local sys = V.asset(c.Path)
  if not U.valid(sys) or not U.valid(b.comp) then return end
  local socket, loc, rot = placement(b, S.cfg.Vfx.AirTrail, c.Path)
  sw.comp = U.try("vfx.swing", V.spawnAttached, sys, b.comp, socket, c.MaxMs or 900, loc, rot)
  sw.started, sw.slow, sw.fast = now, 0, 0
  if not sw.comp then return end
  V.swingTrails = V.swingTrails + 1
  -- (The first 10 of a session name the weapon too, for the weapon lines of hf_hit: which ones start trails.)
  S.swingLogs = (S.swingLogs or 0) + 1
  if S.swingLogs <= 10 then
    U.log("vfx: swing trail %s on %s (%s)", shortName(c.Path), S.hit and S.hit.weaponName and S.hit.weaponName(b) or "?", tostring(b.name))
  end
end

function V.swingStep(player, blades, now)
  local c = S.cfg.Vfx.SwingTrail
  local on = c and c.Enabled and S.cfg.Enabled and S.cfg.Vfx.Enabled and c.Path
  local pl = on and U.actorLoc(player)
  local prevPl, prevT = V.swingPl, V.swingT
  V.swingPl, V.swingT = pl, now
  if not (on and pl and prevPl and prevT) then
    for _, sw in pairs(V.swings) do if sw.comp then sw.now = now; endSwing(sw) end end
    return
  end
  -- `blades` are the weapons in use (hf_hit): a trail on one put away or hidden in the middle of its swing ends now.
  local passed = {}
  for _, b in ipairs(blades) do passed[b.key or U.addr(b.comp) or 0] = true end
  for key, sw in pairs(V.swings) do
    if sw.comp and not passed[key] then
      sw.now = now
      endSwing(sw)
    end
  end
  local dt = now - prevT
  if dt <= 0.002 or dt > 0.1 then return end
  local body = U.sub(pl, prevPl)
  for _, b in ipairs(blades) do
    local key = b.key or U.addr(b.comp)
    local e = key and S.tips and S.tips[key]
    if e and e.last and e.prev then
      local speed = U.len(U.sub(U.sub(e.last, e.prev), body)) / dt
      local sw = V.swings[key]
      if not sw then
        sw = {}
        V.swings[key] = sw
      end
      sw.now = now
      if sw.comp then
        sw.slow = speed < (c.StopCmPerSec or 350) and (sw.slow or 0) + 1 or 0
        local age = (now - sw.started) * 1000
        if (sw.slow >= (c.StopFrames or 4) and age >= (c.MinMs or 120)) or age >= (c.MaxMs or 900) or not U.valid(sw.comp) then
          endSwing(sw)
        end
      else
        sw.fast = speed >= (c.StartCmPerSec or 700) and (sw.fast or 0) + 1 or 0
        if sw.fast >= 2 and (not sw.endedAt or (now - sw.endedAt) * 1000 >= (c.GapMs or 60)) then startSwing(b, sw, c, now) end
      end
    end
  end
end

-- Mod off (Ctrl+F7) or a feature switched off: running swing trails end.
function V.release()
  for _, sw in pairs(V.swings) do if sw.comp then endSwing(sw) end end
end

-- ------------------------------------------------------------------ hits and deflects

-- Clash sparks: two layers, each played some number of times. Scale barely changes these sprite bursts, so the
-- amount (Deflect.SparkAmount for the tier, times the panel's Sparks x) is a number of copies: 1 = each layer once,
-- 1.5 = the first layer twice, 2 = both twice, 0.5 = the first layer only. Copies after the first are spun apart, so
-- they add sparks instead of stacking. Drawn a little toward the camera, like the hit effect: at the blades
-- themselves the sparks were half hidden by the two bodies.
function V.sparkCopies(amount, layer)
  if layer == 1 then return math.floor(amount + 0.5) end
  return math.floor(amount)
end

local function deflect(ctx, faceYaw)
  local d = S.cfg.Deflect
  local scale = C.tier(d.VfxScale, ctx.tierName) or 1
  local amount = (C.tier(d.SparkAmount, ctx.tierName) or 1) * V.mult("Sparks")
  local at, cam = ctx.impact, cameraLoc()
  if cam and (d.SparkTowardCameraCm or 0) > 0 then at = U.add(at, U.mul(U.norm(U.sub(cam, at)), d.SparkTowardCameraCm)) end
  for layer, key in ipairs({ "Vfx", "Vfx2" }) do
    local sys = V.asset(C.tier(d[key], ctx.tierName))
    if U.valid(sys) then
      for i = 1, V.sparkCopies(amount, layer) do
        local spin = (i % 2 == 0 and 1 or -1) * 35 * math.floor(i / 2)
        U.try("vfx.deflect", V.spawn, sys, at, { Pitch = 0, Yaw = faceYaw + spin, Roll = spin * 0.5 }, scale, ctx.victim)
        V.sparks = V.sparks + 1
      end
    end
  end
end

-- Every hit gets its effect, each struck enemy its own. v0.6.2 let one hit through every 30 ms over all enemies, and in
-- the v0.6.2 log a middle hit 29 ms after a very light one on the same enemy went without; the hit bus already merges
-- the game's double reports of one hit (Hit.DedupeMs, which lets a stronger one through). Vfx.MinIntervalMs now only
-- spaces the hit trails on one blade.
function V.onHit(ctx)
  local c = S.cfg.Vfx
  if not c.Enabled or not ctx.byPlayer then return end
  if not ctx.impact or not ctx.dirVec then
    if ctx.kind ~= "deflect" then skip("no contact point") end
    return
  end
  local faceYaw = U.yawDeg(U.mul(ctx.dirVec, -1))
  if ctx.kind == "deflect" then return deflect(ctx, faceYaw) end

  if c.Slash.Enabled then
    if ctx.level >= (c.Slash.MinLevel or 1) then U.try("vfx.slash", slash, ctx) else skip("below MinLevel") end
  end

  local t = c.AirTrail
  if t.Enabled and ctx.level >= (t.MinLevel or 1) then
    U.try("vfx.airtrail", airTrail, ctx, t, (C.tier(t.Ms, ctx.tierName) or 120) * V.mult("AirTrail"))
  end

  local h = c.HitVfx
  if h.Enabled then
    local scale = (C.tier(h.Scale, ctx.tierName) or 0) * V.mult("HitVfx")
    local path = V.expand(h.AssetPath, ctx.tierName)
    local sys = not V.gameUsesSet(ctx, path) and V.asset(path) or nil
    if not sys and (path == nil or path == "") then
      sys = V.captured[ctx.weapon or "any"] or V.captured.any
      if not U.valid(sys) then sys = nil end
    end
    if scale > 0 and sys then
      -- Along the swing and facing the camera, like the hit effect above; else facing the attacker.
      local cam = cameraLoc()
      local rot = h.UseSweep and V.slashRotation(ctx.impact, ctx.sweep or fallbackSweep(), { Angle = 0, Pitch = 0, Roll = 0 }, cam)
        or { Pitch = 0, Yaw = faceYaw, Roll = 0 }
      local at = cam and V.towardCamera(ctx.impact, cam, ctx.victim, c.Slash) or ctx.impact
      V.tint(U.try("vfx.hit", V.spawn, sys, at, rot, scale, ctx.victim), sys)
      V.spawned = V.spawned + 1
    end
  end
end

-- Every asset path this module may spawn, for the preloader; a "{n}" set once per number it has.
function V.assetPaths(out)
  local c = S.cfg.Vfx
  local function add(p)
    if type(p) ~= "string" or p == "" or p == "off" then return end
    if not isSet(p) then
      out[#out + 1] = p
      return
    end
    for _, n in ipairs(setNumbers(p)) do out[#out + 1] = withNumber(p, n) end
  end
  if c.AirTrail.Enabled then
    for _, p in pairs(c.AirTrail.ByWeapon or {}) do add(p) end
  end
  if c.HitVfx.Enabled then add(c.HitVfx.AssetPath) end
  if c.Slash.Enabled then add(V.slashPath()) end
  if c.SwingTrail and c.SwingTrail.Enabled then add(c.SwingTrail.Path) end
  for _, key in ipairs({ "Vfx", "Vfx2" }) do
    for _, p in pairs(S.cfg.Deflect[key] or {}) do add(p) end
  end
end

function V.stats()
  local why = {}
  for k, n in pairs(V.skips) do why[#why + 1] = k .. " " .. n end
  table.sort(why)
  return string.format("slashes=%d stoppedByEngine=%d skipped=[%s] neverCull=%s hitVfx=%d airTrails=%d swingTrails=%d deflectSparks=%d alive=%d budgetCuts=%d notEffects=%d hitEffect=%s%s",
    V.slashes, V.lost, table.concat(why, ", "), tostring(manualActivation() and not V.noScalabilitySwitch), V.spawned,
    V.trails, V.swingTrails, V.sparks, #V.live, V.budgetCuts, V.refused, tostring(V.slashPath() or "off"), V.slashChoice and "" or " (default)")
end

return V
