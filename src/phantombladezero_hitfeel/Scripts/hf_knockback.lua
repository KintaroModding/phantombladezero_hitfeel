-- PBZ HitFeel: knockback shape. The game pushes characters with HitreactKnockback_RootmotionSource objects (shared
-- data): a root-motion force of Strength for Duration, scaled by a StrengthOverTime curve over normalized time.
-- Without a curve the force is constant, so every push is a uniform glide. This module gives the knockbacks it meets
-- (on the enemy the player hits, and on the player) a falling line from StartSpeed to 2 - StartSpeed: the same
-- average, so the same distance, but fast at first and slowing to a stop.
-- The curve is one object of ours; switching the shape off (or Ctrl+F7) flattens its keys to 1, which equals vanilla.
-- It also measures how far the player and the victim travel after hits and deflects, mod on or off, for comparison.
local K = { name = "knockback" }
local S, U, C
-- State lives in S.knockState so a Ctrl+F8 reload keeps the curve: a second curve under the same name would collide
-- with the first one, which the knockbacks still point at.
local ks

K.CURVE_CLASS = "/Script/Engine.CurveFloat"
K.HITREACT_CLASS = "/Script/SGameCombatSystem.HitreactComponent"
-- Game curves whose key arrays can be copied when the array cannot be grown from Lua (any with 2+ keys will do).
K.KEY_DONORS = {
  "/PBZCombatAsset/Config/HitReact/Slomo_Default.Slomo_Default",
  "/PBZCombatAsset/Config/HitReact/Slomo_Plain.Slomo_Plain",
  "/PBZCombatAsset/Config/HitReact/PhysicsHit_Light.PhysicsHit_Light",
  "/PBZCombatAsset/Config/HitReact/ControlRigHit_Light.ControlRigHit_Light",
}

function K.init(state)
  S, U, C = state, state.U, state.C
  S.knockState = S.knockState or { patched = {}, measures = 0, made = 0 }
  ks = S.knockState
end

local CURVE_PREFIX = "PBZHitFeel_KnockbackEase_"

local function objectPath(o) return (U.fullName(o):gsub("^%S+%s+", "")) end

-- The shape in use: StartSpeed when on and the mod is enabled, 1 (flat, vanilla) otherwise.
local function startSpeed()
  local c = S.cfg.Knockback or {}
  if not S.cfg.Enabled or not c.Enabled then return 1 end
  return math.max(1, math.min(2, tonumber(c.StartSpeed) or 1))
end

local function keyCount(curve)
  local n = 0
  pcall(function() n = #curve.FloatCurve.Keys end)
  return n
end

-- Writes the line into the curve's keys; keys past the second sit beyond t=1 and change nothing.
local function writeKeys(curve, start)
  local keys = curve.FloatCurve.Keys
  local n = #keys
  for i = 1, n do
    local k = keys[i]
    k.InterpMode = 0
    k.ArriveTangent, k.LeaveTangent = 0, 0
    if i == 1 then
      k.Time, k.Value = 0, start
    else
      k.Time, k.Value = (i == 2) and 1 or i, 2 - start
    end
  end
end

local function sample(curve)
  local out = {}
  for _, t in ipairs({ 0, 0.5, 1 }) do
    local v = U.try("knock.sample", function() return curve:GetFloatValue(t) end)
    out[#out + 1] = type(v) == "number" and v or -999
  end
  return out
end

-- Our curve, looked up by path each time so a collected one is never touched; built on first need.
function K.curve()
  if ks.broken then return nil end
  if ks.curvePath then
    local c = StaticFindObject(ks.curvePath)
    if U.valid(c) then return c end
  end
  local cls = StaticFindObject(K.CURVE_CLASS)
  local outer = StaticFindObject("/Engine/Transient")
  if not U.valid(cls) or not U.valid(outer) then
    ks.broken = true
    U.log("knockback: CurveFloat class or transient package not found; knockback shape off")
    return nil
  end
  ks.made = ks.made + 1
  local curve = StaticConstructObject(cls, outer, FName(CURVE_PREFIX .. ks.made))
  if not U.valid(curve) then
    ks.broken = true
    U.log("knockback: could not create a curve; knockback shape off")
    return nil
  end
  -- Keys come from copying a game curve's key array, then are overwritten in place. (Growing an empty array from Lua
  -- is undocumented in UE4SS, and a write past the end could be a native crash rather than an error.)
  local how
  for _, path in ipairs(K.KEY_DONORS) do
    local donor = StaticFindObject(path)
    if not U.valid(donor) then donor = U.try("knock.donor", LoadAsset, path) end
    if U.valid(donor) and keyCount(donor) >= 2 then
      pcall(function() curve.FloatCurve = donor.FloatCurve end)
      if keyCount(curve) >= 2 then
        how = "copied from " .. U.fname(donor)
        break
      end
    end
  end
  if not how then
    ks.broken = true
    U.log("knockback: could not give the curve keys from Lua; knockback shape off (vanilla knockback)")
    return nil
  end
  -- Constant before 0 and after 1: the donor's own extrapolation (cycle, linear) came along with the copy and would
  -- keep pushing past the end of a knockback.
  pcall(function()
    curve.FloatCurve.PreInfinityExtrap = 4
    curve.FloatCurve.PostInfinityExtrap = 4
  end)
  U.try("knock.keys", writeKeys, curve, 1.5)
  local s = sample(curve)
  local after = U.try("knock.after", function() return curve:GetFloatValue(1.5) end) or -999
  if math.abs(s[1] - 1.5) > 0.05 or math.abs(s[2] - 1) > 0.05 or math.abs(s[3] - 0.5) > 0.05 or math.abs(after - 0.5) > 0.05 then
    ks.broken = true
    U.log("knockback: test curve reads %.2f %.2f %.2f (%.2f past the end) instead of 1.50 1.00 0.50 (0.50); knockback shape off",
      s[1], s[2], s[3], after)
    return nil
  end
  ks.curvePath = objectPath(curve)
  ks.shape = nil
  U.log("knockback: curve ready (keys %s, %d keys)", how, keyCount(curve))
  return curve
end

-- Keeps the curve's keys on the current shape (HUD / config changes apply on the next hit).
function K.apply(curve)
  local start = startSpeed()
  if ks.shape ~= start then
    U.try("knock.keys", writeKeys, curve, start)
    ks.shape = start
  end
end

local function hitreactOf(actor)
  local cls = StaticFindObject(K.HITREACT_CLASS)
  if not U.valid(cls) or not U.valid(actor) then return nil end
  local comp = U.try("knock.comp", function() return actor:GetComponentByClass(cls) end)
  return U.valid(comp) and comp or nil
end

-- Gives one root-motion knockback our curve: only with a real duration (an endless one would be evaluated in
-- seconds, past the end of the curve) and only when it has no curve of its own (a stale one of ours is replaced).
-- Returns "patched", "ours" (already current) or "kept".
function K.patchObject(kb, curve)
  local info = { strength = U.try("knock.str", function() return kb.Strength end),
    duration = U.try("knock.dur", function() return kb.duration end) }
  local cur = U.try("knock.sot", function() return kb.StrengthOverTime end)
  local curName = U.valid(cur) and U.fname(cur) or nil
  info.curve = curName or "none"
  local dur = tonumber(info.duration) or 0
  if dur <= 0.01 or dur > 3 then return "kept", info end
  local ours = curName ~= nil and curName:sub(1, #CURVE_PREFIX) == CURVE_PREFIX
  if ours and U.same(cur, curve) then return "ours", info end
  if curName ~= nil and not ours then return "kept", info end
  kb.StrengthOverTime = curve
  local path = objectPath(kb)
  if not ks.patched[path] then
    ks.patched[path] = true
    if ks.loggedPatches == nil or ks.loggedPatches < 10 then
      ks.loggedPatches = (ks.loggedPatches or 0) + 1
      U.log("knockback: %s (Strength %s, Duration %s) now eases out", path, tostring(info.strength), tostring(info.duration))
    end
  end
  return "patched", info
end

K.KNOCK_CLASSES = { "HitreactKnockback_RootmotionSource", "HitreactKnockback_AlignTo", "HitreactKnockback_MotionWarpingBase",
  "Hitreactknockback_CustomLaunchback" }

-- At map load (preloader): every loaded knockback of the root-motion kind gets the curve before its first use; the
-- other kinds are counted, to see what the game actually uses.
function K.discover()
  local patch = S.cfg.Enabled and (S.cfg.Knockback or {}).Enabled
  local curve = patch and K.curve()
  if curve then K.apply(curve) end
  local counts, n = {}, { patched = 0, ours = 0, kept = 0 }
  for _, cname in ipairs(K.KNOCK_CLASSES) do
    local list = FindAllOf(cname) or {}
    counts[#counts + 1] = cname:gsub("^Hitreact[Kk]nockback_", "") .. "=" .. #list
    if curve and cname == "HitreactKnockback_RootmotionSource" then
      for _, kb in ipairs(list) do
        if U.valid(kb) then
          local r = U.try("knock.patch", K.patchObject, kb, curve)
          if r then n[r] = n[r] + 1 end
        end
      end
    end
  end
  U.log("knockback: found %s; eased %d now, %d already, %d kept as they are", table.concat(counts, " "), n.patched, n.ours, n.kept)
end

-- The knockback the actor is running right now (logged with each measurement; patched too, in case it was loaded
-- after the map-load pass).
function K.inspect(actor, patch)
  local comp = hitreactOf(actor)
  if not comp then return { class = "no hit-react component" } end
  local kb = U.try("knock.current", function() return comp.CurrentKnockback end)
  if not U.valid(kb) then return { class = "no current knockback" } end
  local info = { class = U.className(kb) }
  if not U.chainHas(U.classChain(kb), "HitreactKnockback_RootmotionSource") then return info end
  local curve = patch and K.curve()
  if curve then
    K.apply(curve)
    local _, i = U.try("knock.patch", K.patchObject, kb, curve)
    if i then info.strength, info.duration, info.curve = i.strength, i.duration, i.curve end
  end
  return info
end

-- Distance an actor covers in the next `ms`, logged for comparison with the mod on and off.
local function measure(actor, label, info)
  local c = S.cfg.Knockback or {}
  if not c.Measure or ks.measures >= (c.MeasureCount or 40) or not U.valid(actor) then return end
  local from = U.actorLoc(actor)
  if not from then return end
  ks.measures = ks.measures + 1
  local n = ks.measures
  local mod = S.cfg.Enabled and "on" or "off"
  ExecuteInGameThreadWithDelay(c.MeasureMs or 600, function()
    if not U.valid(actor) then return end
    local to = U.actorLoc(actor)
    if not to then return end
    U.write("probe_knockback.txt", string.format("%s #%d mod=%s %s moved %.0f cm in %d ms; knockback %s strength=%s duration=%s curve=%s",
      os.date("%H:%M:%S"), n, mod, label, U.len(U.flat(U.sub(to, from))), c.MeasureMs or 600, tostring(info and info.class),
      tostring(info and info.strength), tostring(info and info.duration), tostring(info and info.curve)))
  end)
end

-- Runs for every event, mod on or off (it is a capture): patching only while on, measuring always.
function K.capture(ctx)
  local target, label
  if ctx.kind == "hit" and ctx.byPlayer and U.valid(ctx.victim) then
    target, label = ctx.victim, "enemy hit " .. tostring(ctx.tierName)
  elseif ctx.kind == "hit" and ctx.playerVictim then
    target, label = ctx.player, "player hit " .. tostring(ctx.tierName)
  elseif ctx.kind == "deflect" and ctx.byPlayer then
    target, label = ctx.player, "player " .. tostring(ctx.tierName)
  end
  if not target then return end
  local info = U.try("knock.inspect", K.inspect, target, S.cfg.Enabled and (S.cfg.Knockback or {}).Enabled)
  measure(target, label, info)
end

function K.onHit() end

function K.assetPaths(out)
  for _, p in ipairs(K.KEY_DONORS) do out[#out + 1] = p end
end

-- Ctrl+F7 off: flatten the curve, so patched knockbacks behave exactly like vanilla until the mod is back on.
function K.release()
  local curve = ks.curvePath and StaticFindObject(ks.curvePath)
  if U.valid(curve) then
    U.try("knock.flat", writeKeys, curve, 1)
    ks.shape = 1
  end
end

function K.describe(L)
  local n = 0
  for _ in pairs(ks.patched) do n = n + 1 end
  L[#L + 1] = string.format("== knockback shape: curve=%s start=%s patched=%d broken=%s", tostring(ks.curvePath),
    tostring(ks.shape), n, tostring(ks.broken == true))
  for path in pairs(ks.patched) do L[#L + 1] = "  " .. path end
end

function K.stats()
  local n = 0
  for _ in pairs(ks.patched) do n = n + 1 end
  return string.format("patched=%d shape=%s broken=%s measures=%d", n, tostring(ks.shape), tostring(ks.broken == true), ks.measures)
end

return K
