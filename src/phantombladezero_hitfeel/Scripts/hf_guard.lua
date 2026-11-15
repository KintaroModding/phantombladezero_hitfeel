-- PBZ HitFeel: your guard. Sha-Chi is the game's one resource for both sides: holding guard drains it, a blocked blow
-- drains more (your blows on a blocking enemy too), and when it runs out your guard breaks. The game shows it as a
-- bar; this makes it felt where the eyes are, in the fight:
-- - Draining: in a fight (Sha-Chi fell in the last few seconds), once it is below half, the screen's edges darken toward
--   red, more the lower it gets, and near empty they beat like a pulse, quicker as it nears zero. It fades as soon
--   as Sha-Chi comes back or the fight goes quiet.
-- - Each block on a weak guard lands heavier: the rhythm weight of the clash (camera, rumble, sparks) and your
--   recoil grow up to Guard.Strain.Max as Sha-Chi nears zero, and the edges flick darker with it.
-- - The break (the game's Income.Break.Deflect blow on you): the edges flash dark red and ebb over a second and a
--   half with two beats, the camera is knocked back and tips (a stagger), and the controller gives a heavy double
--   thump. The usual being-hit feedback stays out of it (hf_receive), so it reads as its own moment.
-- Sha-Chi comes from your ability system's attribute set (BasicAttributeSet: Shachi, Shachi_Max, Shachi_Min; the
-- names are in config.lua), read every other frame. The red edge is hf_overlay. Nothing here changes the game's guard.
local G = { name = "guard", breaks = 0, strained = 0, reads = 0 }
local S, U, C
local gs

G.BREAK_TAG = "Hitreact.Strength.Income.Break.Deflect"

local function cfg() return S.cfg.Guard or {} end
local function mult() return tonumber((S.cfg.Tuning or {}).Guard) or 1 end

function G.init(state)
  S, U, C = state, state.U, state.C
  S.guardState = S.guardState or { edge = 0, spike = 0, phase = 0 }
  gs = S.guardState
end

-- ------------------------------------------------------------------ Sha-Chi

local function attr(set, name)
  local ok, v = pcall(function() return set[name].CurrentValue end)
  return ok and type(v) == "number" and v or nil
end

local function first(set, names)
  for _, n in ipairs(names or {}) do
    local v = attr(set, n)
    if v then return v, n end
  end
end

-- The attribute set holding Sha-Chi among the pawn's ability system's sets.
local function findSet(player)
  local asc = U.asc(player)
  if not asc then return nil, "no ability system" end
  local sets = U.arrayObjects(U.try("guard.sets", function() return asc.SpawnedAttributes end))
  local names = cfg().Attributes or {}
  for _, set in ipairs(sets) do
    local v, n = first(set, names.Value)
    if v then return set, n end
  end
  return nil, string.format("none of %d attribute set(s) has %s", #sets, table.concat(names.Value or {}, "/"))
end

-- Sha-Chi as a share of its range (0 empty, 1 full), and the raw value and maximum; nil when it cannot be read. The set
-- is found once per pawn and checked on every read.
function G.read()
  local player = U.player()
  if not player then return nil end
  local key = U.addr(player)
  if gs.pawn ~= key or not U.valid(gs.set) then
    gs.pawn = key
    local set, why = findSet(player)
    gs.set = set
    if set and not gs.found then
      gs.found = true
      U.log("guard: 杀气 is read from %s.%s", U.className(set), tostring(why))
    elseif not set and not gs.warned then
      gs.warned = true
      U.log("guard: 杀气 cannot be read (%s); only the guard break is shown", tostring(why))
    end
  end
  if not gs.set then return nil end
  local names = cfg().Attributes or {}
  local v, mx = first(gs.set, names.Value), first(gs.set, names.Max)
  local mn = first(gs.set, names.Min) or 0
  if not (v and mx) or mx <= mn then return nil end
  G.reads = G.reads + 1
  return math.max(0, math.min(1, (v - mn) / (mx - mn))), v, mx
end

-- ------------------------------------------------------------------ the edge, every frame

-- A heartbeat over one beat (phase 0..1): a strong pulse and a weaker one just after it.
local function beat(p)
  local function bump(c, w)
    local d = (p - c) / w
    return math.exp(-d * d)
  end
  return bump(0.10, 0.055) + 0.55 * bump(0.30, 0.06)
end

-- The break's flash: held, then ebbing with its beats.
local function breakLevel(now)
  local b = cfg().Break or {}
  local t = now - (gs.breakAt or -1e9)
  local hold, fade = (b.HoldMs or 140) / 1000, (b.FadeMs or 1500) / 1000
  if t < 0 or t > hold + fade then return 0 end
  local peak = b.Edge or 0.9
  if t <= hold then return peak end
  local k = 1 - (t - hold) / fade
  local beats = b.Beats or 2
  local wave = beats > 0 and (0.75 + 0.25 * beat(((t - hold) / fade * beats) % 1)) or 1
  return peak * k ^ 1.6 * wave
end

-- The edge's level: how low Sha-Chi is, eased in and out (InMs / OutMs: the time to all but reach a new level), with the
-- pulse and the flick of a strained block on top as they come, and the break's flash over all of it at once.
local function step()
  local c = cfg()
  local now = U.frameNow or U.now()
  local dt = math.min(0.1, (U.frameMs or 16.7) / 1000)
  local on = S.cfg.Enabled and c.Enabled ~= false
  local low = c.Low or {}
  gs.frame = (gs.frame or 0) + 1
  if on and gs.frame % math.max(1, c.PollFrames or 3) == 0 then
    local r = G.read()
    if r then
      -- Sha-Chi going down means a fight (a held guard, blows on it, skills spent).
      if gs.ratio and r < gs.ratio - 0.002 then gs.activeAt = now end
      gs.ratio = r
    end
  end
  local base, pulse = 0, 0
  if on and low.Enabled ~= false and gs.ratio and now - (gs.activeAt or -1e9) < (low.CombatSec or 4) then
    local below, full = low.Below or 0.5, low.Full or 0.12
    local t = 1 - math.max(0, math.min(1, (gs.ratio - full) / math.max(0.01, below - full)))
    base = (low.Edge or 0.45) * t * t
    local pb = low.PulseBelow or 0.3
    if gs.ratio < pb then
      local k = 1 - gs.ratio / pb
      local hz = low.PulseHz or { 0.9, 1.7 }
      gs.phase = (gs.phase + ((hz[1] or 0.9) + ((hz[2] or 1.7) - (hz[1] or 0.9)) * k) * dt) % 1
      pulse = (low.PulseAdd or 0.22) * k * beat(gs.phase)
    end
  end
  local ms = (base > gs.edge and (low.InMs or 120) or (low.OutMs or 700)) / 3000
  gs.edge = gs.edge + (base - gs.edge) * math.min(1, dt / math.max(0.001, ms))
  if gs.edge < 0.005 and base == 0 then gs.edge = 0 end
  -- A block on a weak guard flicks the edge darker; the flick dies away within a third of a second.
  gs.spike = (gs.spike or 0) * math.exp(-dt / 0.1)
  if gs.spike < 0.005 then gs.spike = 0 end
  local level = gs.edge + (gs.edge > 0 and pulse or 0) + gs.spike
  if on and (c.Break or {}).Enabled ~= false then level = math.max(level, breakLevel(now)) end
  if S.overlay then S.overlay.set(level * mult()) end
  return false
end

-- ------------------------------------------------------------------ the break and blocks on a weak guard

-- The way the blow pushes you: from the attacker if one is known, else straight back.
local function blowDir(player, ctx)
  local attacker = S.hit and S.hit.otherOwner and S.hit.otherOwner(ctx.slomos or {}, player)
  local pl, al = U.actorLoc(player), attacker and U.actorLoc(attacker)
  if pl and al then
    local d = U.v3(pl.X - al.X, pl.Y - al.Y, 0)
    if U.len(d) > 1 then return U.norm(d) end
  end
  local yaw = math.rad(U.actorYaw(player))
  return U.v3(-math.cos(yaw), -math.sin(yaw), 0)
end

local function guardBreak(ctx)
  local b = cfg().Break or {}
  if b.Enabled == false then return end
  local now = U.now()
  gs.breakAt, gs.activeAt = now, now
  G.breaks = G.breaks + 1
  U.crumb("guard break (杀气 %s)", gs.ratio and string.format("%.0f%%", gs.ratio * 100) or "?")
  local m = mult()
  local player = ctx.player
  if S.camera and S.cfg.Camera.Enabled and U.valid(player) then
    U.try("guard.camera", S.camera.punch, (b.RecoilCm or 30) * m, (b.KickDeg or 2.2) * m, nil, S.cfg.Camera.Punch or {},
      blowDir(player, ctx))
  end
  local r = b.Rumble or {}
  if S.rumble and S.cfg.Rumble.Enabled then
    local sc = (S.cfg.Rumble.Scale or 1) * m
    U.try("guard.rumble", S.rumble.play, (r.Body or 1) * sc, r.BodyMs or 260, true, false)
    U.try("guard.rumble2", S.rumble.play, (r.Edge or 0.8) * sc, r.EdgeMs or 110, false, true)
    if (r.ThenBody or 0) > 0 then
      ExecuteInGameThreadWithDelay(math.floor(r.GapMs or 170), function()
        local rm = S.rumble
        if rm and S.cfg.Enabled then U.try("guard.rumble3", rm.play, (r.ThenBody or 0) * sc, r.ThenMs or 220, true, false) end
      end)
    end
  end
  if G.breaks <= 5 then
    U.log("guard: your guard broke (杀气 %s just before)", gs.ratio and string.format("%.0f%%", gs.ratio * 100) or "unknown")
  end
end

function G.breakCueOn()
  local c = cfg()
  return c.Enabled ~= false and (c.Break or {}).Enabled ~= false
end

-- Runs first among the features: it marks the blow so that the others (hf_receive, the rumble, the camera) read it.
function G.onHit(ctx)
  local c = cfg()
  if c.Enabled == false then return end
  if ctx.kind == "hit" and ctx.playerVictim and ctx.guardBreak then
    U.try("guard.break", guardBreak, ctx)
  elseif ctx.kind == "deflect" and (ctx.playerDefended or ctx.byPlayer) and ctx.tierName ~= "Perfect" then
    gs.activeAt = U.now()
    local s, r = c.Strain or {}, gs.ratio
    local below = s.Below or 0.5
    if r and r < below and (s.Max or 1) > 1 then
      local k = 1 - r / below
      local f = 1 + ((s.Max or 1.6) - 1) * k
      -- (A copy: the clash's rhythm entry is kept by hf_rhythm.)
      local rh = {}
      for key, v in pairs(ctx.rhythm or {}) do rh[key] = v end
      rh.emph = (rh.emph or 1) * f
      ctx.rhythm, ctx.guardStrain = rh, f
      gs.spike = math.max(gs.spike or 0, (s.Tick or 0.25) * k)
      G.strained = G.strained + 1
    end
  end
end

function G.start()
  U.loop("guard.edge", step)
end

-- Mod off or a reload: the edge goes clear at once.
function G.release()
  gs.edge, gs.spike, gs.breakAt = 0, 0, nil
  if S.overlay then S.overlay.set(0) end
end

function G.stats()
  return string.format("杀气=%s breaks=%d strained=%d reads=%d edge=%.2f", gs.ratio and string.format("%.2f", gs.ratio) or "-",
    G.breaks, G.strained, G.reads, gs.edge or 0)
end

return G
