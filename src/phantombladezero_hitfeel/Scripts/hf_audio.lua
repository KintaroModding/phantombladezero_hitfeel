-- PBZ HitFeel: audio. (1) Ducks the battle music on confirmed hits so the hit's low end is not masked.
-- (2) Adds a low-end layer to dual-wield hits by posting a one-hand/two-hand hit event.
-- This Wwise build's SetRTPCValue takes an RTPC asset (no name parameter), so the duck works on the
-- RTPC assets listed in config that are actually loaded; the user-setting volume RTPCs are not assets here.
local A = { name = "audio", ducked = false, ducks = 0, dwCount = 0, layers = 0, captured = {}, rtpcs = nil }
local S, U, C

local AK = "/Script/AkAudio.Default__AkGameplayStatics"
A.SET_RTPC = "/Script/AkAudio.AkGameplayStatics:SetRTPCValue"
A.GET_RTPC = "/Script/AkAudio.AkGameplayStatics:GetRTPCValue"
A.POST_AT = "/Script/AkAudio.AkGameplayStatics:PostEventAtLocation"
A.SPAWN_AT = "/Script/AkAudio.AkGameplayStatics:SpawnAkComponentAtLocation"

function A.init(state)
  S, U, C = state, state.U, state.C
end

local function loadObject(path)
  local o = StaticFindObject(path)
  if not U.valid(o) then
    U.note("loaded %s", tostring(path):match("([^%./]+)$") or tostring(path))
    o = U.try("audio.load", LoadAsset, path)
  end
  return U.valid(o) and o or nil
end

local function getRtpc(asset)
  local g = U.cdo(AK)
  if not g then return nil end
  local out = {}
  U.callNamed(g, A.GET_RTPC, { RTPCValue = asset, PlayingID = 0, InputValueType = 1, Value = out, OutputValueType = {} })
  for _, v in pairs(out) do
    if type(v) == "number" then return v end
  end
  return nil
end

local function setRtpc(asset, value, ms)
  U.callNamed(U.cdo(AK), A.SET_RTPC, { RTPCValue = asset, Value = value, InterpolationTimeMs = math.floor(ms) })
end

-- dB-style modifiers sit at 0 (or below); linear and percent ones above 0.
local function duckedValue(base, c)
  if base <= 0.001 then return base - c.DuckDb, "dB" end
  return base * c.DuckFactor, base > 1.5 and "percent" or "linear"
end

local function targets()
  if A.rtpcs then return A.rtpcs end
  A.rtpcs = {}
  for _, path in ipairs(S.cfg.Audio.RtpcAssets or {}) do
    local o = loadObject(path)
    if o then
      A.rtpcs[#A.rtpcs + 1] = { asset = o, path = path, name = U.fname(o) }
    else
      U.log("audio duck: RTPC asset not loaded, skipped: %s", path)
    end
  end
  if #A.rtpcs == 0 then U.log("audio duck: no RTPC asset available, duck disabled") end
  return A.rtpcs
end

-- Assets can be unloaded behind our back; a freed object must never reach an engine call.
local function asset(t)
  if not U.valid(t.asset) then t.asset = loadObject(t.path) end
  return t.asset
end

function A.restore()
  if not A.ducked then return end
  local c = S.cfg.Audio
  for _, t in ipairs(A.rtpcs or {}) do
    local o = t.base and asset(t)
    if o then U.try("audio.restore.set", setRtpc, o, t.base, c.ReleaseMs) end
  end
  A.ducked = false
  A.restoredAt = U.now()
end

function A.release()
  if A.handle then pcall(CancelDelayedAction, A.handle) end
  A.handle = nil
  U.try("audio.release", A.restore)
end

function A.reconfigure()
  A.release()
  A.rtpcs = nil
end

local function duck(ctx)
  local c = S.cfg.Audio
  if not c.Enabled or not ctx.byPlayer or ctx.level < c.MinLevel then return end
  if not A.ducked then
    local any = false
    -- The resting value is read only once our last release has finished: read mid-release it is still ducked,
    -- and v0.2 stacked ducks that way (0 -> -8 -> -16 dB, then stuck at -8).
    local idle = not A.restoredAt or (U.now() - A.restoredAt) * 1000 > c.ReleaseMs + 400
    for _, t in ipairs(targets()) do
      local o = asset(t)
      if o and (t.base == nil or idle) then
        local base = U.try("audio.get", getRtpc, o)
        if type(base) == "number" then t.base = base end
      end
      if o and type(t.base) == "number" then
        local v, mode = duckedValue(t.base, c)
        setRtpc(o, v, c.AttackMs)
        any = true
        if A.ducks < 3 then U.log("audio duck: %s %.3f -> %.3f (%s)", t.name, t.base, v, mode) end
      end
    end
    if not any then return end
    A.ducked = true
    A.ducks = A.ducks + 1
  end
  A.handle = A.handle or MakeActionHandle()
  local hold = c.HoldMs + (ctx.level >= 4 and c.HeavyExtraHoldMs or 0)
  if ctx.kind == "deflect" then hold = C.tier(S.cfg.Deflect.DuckHoldMs, ctx.tierName) or hold end
  RetriggerableExecuteInGameThreadWithDelay(A.handle, hold, function() U.try("audio.restore", A.restore) end)
end

local function post(ev, ctx)
  U.callNamed(U.cdo(AK), A.POST_AT, {
    AkEvent = ev,
    Location = ctx.impact or U.actorLoc(ctx.victim),
    Orientation = { Pitch = 0, Yaw = 0, Roll = 0 },
    WorldContextObject = ctx.victim,
  })
end

-- A turned-down layer: PostEventAtLocation takes no volume, so the event plays on its own short-lived AkComponent at
-- the same place, posted as it spawns and turned down through the component's output bus volume (0-1, its dry path)
-- in the same frame, before the audio thread starts it. False when no component came back (the caller posts it as
-- before).
local function postQuiet(ev, ctx, vol)
  local comp = U.callNamed(U.cdo(AK), A.SPAWN_AT, {
    WorldContextObject = ctx.victim,
    AkEvent = ev,
    Location = ctx.impact or U.actorLoc(ctx.victim),
    Orientation = { Pitch = 0, Yaw = 0, Roll = 0 },
    AutoPost = true,
    AutoDestroy = true,
  })
  if not U.valid(comp) then return false end
  if not pcall(function() comp:SetOutputBusVolume(vol) end) and not A.volumeWarned then
    A.volumeWarned = true
    U.log("audio: the clash layer could not be turned down (AkComponent:SetOutputBusVolume); it plays at full volume")
  end
  return true
end

-- Deflects and blocks: an extra clash layer from the game's own deflect / shield-impact sounds. "{tier}" in a path
-- becomes Light, Middle or Heavy, from the strength of the attack that was stopped.
local function clash(ctx)
  if ctx.kind ~= "deflect" or not ctx.byPlayer then return end
  local d = S.cfg.Deflect
  local vol = math.max(0, math.min(1, tonumber(d.SoundVolume) or 1))
  if d.SoundEnabled == false or vol <= 0 then return end
  local path = ctx.blockSource == "shield" and d.ShieldSound or C.tier(d.Sound, ctx.tierName)
  if not path or path == "" then return end
  path = path:gsub("{tier}", ctx.strengthTier or "Middle")
  A.events = A.events or {}
  if not U.valid(A.events[path]) then A.events[path] = loadObject(path) end
  if U.valid(A.events[path]) then
    if vol >= 0.999 or not U.try("audio.quiet", postQuiet, A.events[path], ctx, vol) then post(A.events[path], ctx) end
    if vol < 0.999 and not A.quietLogged then
      A.quietLogged = true
      U.log("audio: clash layer at volume %.2f", vol)
    end
    A.clashes = (A.clashes or 0) + 1
  elseif not (A.missing or {})[path] then
    A.missing = A.missing or {}
    A.missing[path] = true
    U.log("audio: clash sound not found: %s", path)
  end
end

-- Remembers one-hand/two-hand hit events to reuse as the dual-wield layer; the chooser's own HitSound first.
function A.capture(ctx)
  if not ctx.byPlayer or not ctx.weapon or ctx.weapon == "DW" then return end
  local pick
  for _, o in ipairs(ctx.objects) do
    if o.kind == "object" and U.chainHas(o.chain, "AkAudioEvent") then
      if o.path == "HitSound" then
        pick = o
        break
      end
      if not pick or o.path:lower():find("enemy", 1, true) then pick = o end
    end
  end
  if pick then
    if A.captured[ctx.weapon] == nil then
      U.log("dual layer: first %s hit event %s (%s)", ctx.weapon, U.fullName(pick.obj), pick.path)
    end
    A.captured[ctx.weapon] = pick.obj
  end
end

-- The one-hand flesh hit of the same tier (strong 80-100 Hz body), else whatever one-hand/two-hand hit was captured.
function A.layerEvent(tierName)
  local c = S.cfg.DualLayer
  local fmt = c.EventPathByTier
  if fmt and fmt ~= "" then
    local t = (tierName == "UltraHeavy" or tierName == "Break") and "Heavy" or (tierName == "Default" and "Light" or tierName)
    local path = fmt:gsub("{tier}", t)
    A.tierEvents = A.tierEvents or {}
    if A.tierEvents[path] ~= false and not U.valid(A.tierEvents[path]) then A.tierEvents[path] = loadObject(path) or false end
    if A.tierEvents[path] then return A.tierEvents[path] end
  end
  if c.EventPath and c.EventPath ~= "" then
    if not U.valid(A.cfgEvent) then A.cfgEvent = loadObject(c.EventPath) end
    if U.valid(A.cfgEvent) then return A.cfgEvent end
  end
  for _, k in ipairs({ "1H", "2H" }) do
    if U.valid(A.captured[k]) then return A.captured[k] end
  end
  return nil
end

local function dualLayer(ctx)
  local c = S.cfg.DualLayer
  if not c.Enabled or ctx.kind ~= "hit" or not ctx.byPlayer or ctx.weapon ~= "DW" then return end
  A.dwCount = A.dwCount + 1
  if ctx.level < c.AlwaysAtLevel and (A.dwCount % math.max(1, c.EveryN)) ~= 0 then return end
  local ev = A.layerEvent(ctx.tierName)
  if not ev then
    if not A.dwWarned then
      U.log("dual layer: no source event; set DualLayer.EventPathByTier or EventPath")
      A.dwWarned = true
    end
    return
  end
  post(ev, ctx)
  A.layers = A.layers + 1
end

function A.onHit(ctx)
  U.try("audio.duck", duck, ctx)
  U.try("audio.dual", dualLayer, ctx)
  U.try("audio.clash", clash, ctx)
end

-- Every sound and RTPC asset this module may use, for the preloader ("{tier}" expanded).
function A.assetPaths(out)
  local CLASH, HIT = { "Light", "Middle", "Heavy" }, { "VeryLight", "Light", "Middle", "Heavy" }
  local function add(p, tiers)
    if type(p) ~= "string" or p == "" then return end
    if p:find("{tier}", 1, true) then
      for _, t in ipairs(tiers or CLASH) do out[#out + 1] = (p:gsub("{tier}", t)) end
    else
      out[#out + 1] = p
    end
  end
  for _, p in pairs(S.cfg.Deflect.Sound or {}) do add(p) end
  add(S.cfg.Deflect.ShieldSound)
  if S.cfg.DualLayer.Enabled then
    add(S.cfg.DualLayer.EventPathByTier, HIT)
    add(S.cfg.DualLayer.EventPath)
  end
  for _, p in ipairs(S.cfg.Audio.RtpcAssets or {}) do add(p) end
end

function A.stats()
  return string.format("ducks=%d ducked=%s dualLayers=%d clashLayers=%d", A.ducks, tostring(A.ducked), A.layers, A.clashes or 0)
end

return A
