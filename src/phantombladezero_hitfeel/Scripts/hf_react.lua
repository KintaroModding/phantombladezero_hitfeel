-- PBZ HitFeel: visual hit reaction that never touches the enemy's capsule, AI or animation state.
-- The mesh (not the capsule) moves by the sum of two offsets, through one controller per mesh so they never fight:
--   push: a jolt of a few cm along the hit that springs back;
--   shake: side to side across the hit while the enemy is held, fading out (the fighting-game hit shake).
-- Hit Feel (Kintaro, 2026-11-15): the physics jiggle of PBZHitFeel 0.7.3 is removed. It turned physics on for the
-- bones below the hit bone of a living, animated enemy, in the middle of its hit animation, and faded it out over a
-- few frames; a player's crash in the game's animation code (stale bone data under a montage ability task) points to
-- it. It was off by default since v0.5.3 ("nobody could feel it").
local R = { name = "react", motion = {}, displaces = 0, shakes = 0 }
local S, U, C

R.SET_REL = "/Script/Engine.SceneComponent:K2_SetRelativeLocation"

function R.init(state)
  S, U, C = state, state.U, state.C
end

local function meshOf(actor)
  local ok, m = pcall(function() return actor.Mesh end)
  if ok and U.valid(m) then return m end
end

local function setRel(mesh, loc)
  U.callNamed(mesh, R.SET_REL, { NewLocation = loc, bSweep = false, SweepHitResult = {}, bTeleport = true })
end

-- The component-level flag is set when the game ragdolls the whole mesh (SetSimulatePhysics). (IsSimulatingPhysics
-- is not a reflected function in this build.)
local function wholeBodySimulating(mesh)
  local ok, v = pcall(function() return mesh.BodyInstance.bSimulatePhysics end)
  return ok and v == true
end

-- ------------------------------------------------------------------ push and shake

-- The offset now: the push decays (1 - t)^2; the shake changes side Hz times a second (by real time, so it reads the
-- same at any frame rate while the enemy's own clock is held) and fades linearly.
local function offsetOf(m)
  local o = U.v3(0, 0, 0)
  local p = m.push
  if p then
    local f = 1 - p.k / p.n
    local a = p.amp * f * f
    o = U.v3(p.dir.X * a, p.dir.Y * a, -0.1 * a)
  end
  local s = m.shake
  if s then
    local side = math.floor(((U.realTime() or 0) - s.t0) * 2 * s.hz) % 2 == 0 and 1 or -1
    o = U.add(o, U.mul(s.lat, s.amp * (1 - s.k / s.n) * side))
  end
  return o
end

-- One frame of a mesh's motion. True when both offsets are done (the mesh is back where it was) or the mesh is gone.
function R.step(m)
  if m.cancelled or not U.valid(m.mesh) then
    R.motion[m.key] = nil
    return true
  end
  -- If the game ragdolls the whole body (death), its physics owns the mesh now.
  if wholeBodySimulating(m.mesh) then
    R.motion[m.key] = nil
    return true
  end
  for _, part in ipairs({ "push", "shake" }) do
    local p = m[part]
    if p then
      p.k = p.k + 1
      if p.k >= p.n then m[part] = nil end
    end
  end
  if not m.push and not m.shake then
    setRel(m.mesh, m.base)
    R.motion[m.key] = nil
    return true
  end
  setRel(m.mesh, U.add(m.base, offsetOf(m)))
  return false
end

-- The mesh's controller, made on first use with the mesh's resting offset from the capsule.
local function motionOf(mesh)
  local key = U.addr(mesh)
  if not key then return nil end
  local m = R.motion[key]
  if m then return m end
  local base = U.copyv(mesh.RelativeLocation)
  if not base then return nil end
  m = { mesh = mesh, base = base, key = key }
  R.motion[key] = m
  U.everyFrame("react.motion.step", function() return R.step(m) end)
  return m
end

-- Pushes an actor's model `cm` along a world direction and lets it spring back over `frames60` frames.
function R.pushActor(actor, dirWorld, cm, frames60)
  cm = cm or 0
  if cm <= 0 or not dirWorld then return end
  local mesh = meshOf(actor)
  local m = mesh and motionOf(mesh)
  if not m then return end
  local p = m.push
  -- A new hit during the spring-back restarts it from at least the new amplitude.
  local amp = p and math.max(p.amp * (1 - p.k / p.n), cm) or cm
  m.push = { amp = amp, dir = U.toLocal(actor, dirWorld), k = 0, n = math.max(2, U.gameFrames(frames60)) }
  R.displaces = R.displaces + 1
  setRel(m.mesh, U.add(m.base, offsetOf(m)))
end

function R.displace(ctx, mesh, cm)
  R.pushActor(ctx.victim, ctx.dirVec, cm, S.cfg.React.Displace.Frames)
end

function R.shake(ctx, mesh, cm, frames60)
  cm = cm or 0
  if cm <= 0 or not ctx.dirVec then return end
  local m = motionOf(mesh)
  if not m then return end
  local d = U.toLocal(ctx.victim, ctx.dirVec)
  local lat = U.v3(-d.Y, d.X, 0)
  local l = U.len(lat)
  lat = l > 0.01 and U.mul(lat, 1 / l) or U.v3(0, 1, 0)
  local s = m.shake
  local amp = s and math.max(s.amp * (1 - s.k / s.n), cm) or cm
  m.shake = { amp = amp, lat = lat, k = 0, n = math.max(2, U.gameFrames(frames60)), hz = S.cfg.React.Shake.Hz or 30,
    t0 = U.realTime() or 0 }
  R.shakes = R.shakes + 1
  setRel(m.mesh, U.add(m.base, offsetOf(m)))
end

function R.release()
  for key, m in pairs(R.motion) do
    m.cancelled = true
    if U.valid(m.mesh) then U.try("react.release", setRel, m.mesh, m.base) end
    R.motion[key] = nil
  end
end

function R.onHit(ctx)
  local c = S.cfg.React
  if not c.Enabled or not ctx.byPlayer or not U.valid(ctx.victim) then return end
  local mesh = meshOf(ctx.victim)
  if not mesh then return end
  local d = S.cfg.Deflect
  local cm, shakeCm, shakeFrames
  if ctx.kind == "deflect" then
    cm = C.tier(d.EnemyPushCm, ctx.tierName)
    shakeCm, shakeFrames = C.tier(d.EnemyShakeCm, ctx.tierName), C.tier(d.EnemyFreeze, ctx.tierName)
  else
    cm = C.tier(c.Displace.Cm, ctx.tierName)
    shakeCm, shakeFrames = C.tier((c.Shake or {}).Cm, ctx.tierName), C.tier((c.Shake or {}).Frames, ctx.tierName)
  end
  local t, e = S.cfg.Tuning or {}, U.emph(ctx)
  cm = (cm or 0) * (tonumber(t.Push) or 1) * e
  shakeCm = (shakeCm or 0) * (tonumber(t.HitShake) or 1) * e
  if c.Displace.Enabled then U.try("react.displace", R.displace, ctx, mesh, cm) end
  if (c.Shake or {}).Enabled then U.try("react.shake", R.shake, ctx, mesh, shakeCm, shakeFrames or 6) end
end

function R.stats() return string.format("displaces=%d shakes=%d", R.displaces, R.shakes) end

return R
