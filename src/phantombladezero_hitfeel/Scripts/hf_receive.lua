-- PBZ HitFeel: the receiving end. An enemy's blow on your held guard (the game's non-perfect deflect, "Guard") and a
-- blow that gets through to you. The camera is knocked back, tips up and swings to the side the blow comes from; your
-- model is pushed back a few cm and springs back (only the model: control and hit boxes are untouched). A blow that
-- gets through also flashes your rim red, darkens the screen's edges (hf_screen) and buzzes heavier. The guard's own
-- buzz, shake and screen impact stay under Deflect and hf_screen, and the game's being-hit shake is raised in hf_hit
-- (it has to be written into the effect lookup).
local Rc = { name = "receive", guards = 0, hits = 0 }
local S, U, C

function Rc.init(state)
  S, U, C = state, state.U, state.C
end

local function mult() return tonumber((S.cfg.Tuning or {}).Receive) or 1 end

-- The direction the blow pushes the player: from the attacker to the player, level.
local function blowDir(player, attacker)
  local pl, al = U.actorLoc(player), attacker and U.actorLoc(attacker)
  if not pl or not al then return nil end
  local d = U.v3(pl.X - al.X, pl.Y - al.Y, 0)
  local l = U.len(d)
  return l > 1 and U.mul(d, 1 / l) or nil
end

local function knockBack(player, dir, recoilCm, kickDeg, flinchCm, flinchFrames)
  if S.camera and S.cfg.Camera.Enabled then
    U.try("receive.camera", S.camera.punch, recoilCm * mult(), kickDeg * mult(), nil, S.cfg.Camera.Punch or {}, dir)
  end
  if S.react and S.cfg.React.Enabled then
    U.try("receive.flinch", S.react.pushActor, player, dir, flinchCm * mult(), flinchFrames)
  end
end

local function guard(ctx, c)
  local dir = blowDir(ctx.player, ctx.victim)
  if not dir then return end
  -- (A guard low on Sha-Chi takes it harder: hf_guard's strain.)
  local k = ctx.guardStrain or 1
  knockBack(ctx.player, dir, (c.RecoilCm or 0) * k, (c.KickDeg or 0) * k, (c.FlinchCm or 0) * k, c.FlinchFrames or 6)
  Rc.guards = Rc.guards + 1
end

local function hit(ctx, c)
  -- An energy blow with no hit-stop of its own is a damage-over-time tick (burning and the like): nothing.
  if (ctx.vanillaFrames or 0) <= 0 and tostring(ctx.attackTag or ""):find("Energy", 1, true) then return end
  local player, t = ctx.player, ctx.tierName
  local attacker = S.hit and S.hit.otherOwner and S.hit.otherOwner(ctx.slomos or {}, player)
  local dir = blowDir(player, attacker)
  if dir then
    knockBack(player, dir, C.tier(c.RecoilCm, t) or 0, C.tier(c.KickDeg, t) or 0, C.tier(c.FlinchCm, t) or 0, c.FlinchFrames or 8)
  end
  local f = c.Flash
  if f and S.flash and (S.cfg.Flash or {}).Enabled then
    local s = (C.tier(f.Strength, t) or 0) * (tonumber((S.cfg.Tuning or {}).Flash) or 1)
    if s > 0 then U.try("receive.flash", S.flash.flash, player, s, U.gameFrames(f.Frames or 6), f.Color) end
  end
  if S.screen then U.try("receive.screen", S.screen.receive, t) end
  local r = C.tier(c.Rumble, t)
  if r and S.rumble and S.cfg.Rumble.Enabled then
    local sc = S.cfg.Rumble.Scale or 1
    U.try("receive.body", S.rumble.play, (r.Body or 0) * sc, r.BodyMs or 0, true, false)
    U.try("receive.edge", S.rumble.play, (r.Edge or 0) * sc, r.EdgeMs or 0, false, true)
  end
  Rc.hits = Rc.hits + 1
  if Rc.hits <= 2 then
    U.log("receive: a %s blow from %s, %s", tostring(t), attacker and U.fname(attacker) or "?", dir and "camera knocked back, model pushed" or "no attacker found")
  end
end

function Rc.onHit(ctx)
  local c = S.cfg.Receive
  if not c or not c.Enabled or not U.valid(ctx.player) then return end
  if ctx.kind == "deflect" and ctx.playerDefended and ctx.tierName == "Guard" and U.valid(ctx.victim) then
    U.try("receive.guard", guard, ctx, c.Guard or {})
  elseif ctx.kind == "hit" and ctx.playerVictim and not (ctx.guardBreak and S.guard and S.guard.breakCueOn()) then
    -- (A guard break has its own moment in hf_guard, unless that is switched off.)
    U.try("receive.hit", hit, ctx, c.Hit or {})
  end
end

function Rc.stats() return string.format("guards=%d hits=%d", Rc.guards, Rc.hits) end

return Rc
