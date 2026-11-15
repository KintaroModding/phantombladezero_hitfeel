-- PBZ HitFeel: camera. The vanilla attack shake is raised in the hit bus; here: a directional punch shake on top,
-- the deflect shakes, and a short push-in plus kick through the third-person camera's own additive layers
-- (ATPC SetAdditiveParameter_Distance / _Rotation, under this mod's names, blended in and back out).
-- PBZPlayerCameraManager has no callable SetFOV in this build, so v0.2's FOV punch is gone, and ATPC has no FOV
-- layer either. The push-in is as small as the game's own camera moves (v0.5.5: 6-12 cm pushes while the distance to
-- the player changed by -7, +20 and -15 cm); the screen-level accent is hf_screen's vignette pulse. Your hits scale
-- by their place in the rhythm (ctx.rhythm.emph).
local Cam = { name = "camera", last = -1, shakes = 0, punches = 0, captured = {}, punchChecks = 0 }
local S, U, C

Cam.START_SHAKE = "/Script/Engine.PlayerCameraManager:StartCameraShake"
Cam.ADD_DISTANCE = "/Script/AdvancedThirdPersonCamera.ATPCCameraComponent:SetAdditiveParameter_Distance"
Cam.ADD_ROTATION = "/Script/AdvancedThirdPersonCamera.ATPCCameraComponent:SetAdditiveParameter_Rotation"
local PUSH_NAME, KICK_NAME = "PBZHitFeel_Push", "PBZHitFeel_Kick"

function Cam.init(state)
  S, U, C = state, state.U, state.C
end

-- Vanilla shake classes found in the effect data; their presence also tells us vanilla will shake.
function Cam.capture(ctx)
  if ctx.shakeLevel then Cam.upgrades = (Cam.upgrades or 0) + 1 end
  for _, o in ipairs(ctx.objects) do
    if o.kind == "class" and U.chainHas(o.chain, "CameraShakeBase") then
      ctx.vanillaShake = ctx.vanillaShake or o
      Cam.captured.any = o.obj
    end
  end
end

function Cam.loadClass(path)
  if not path or path == "" then return nil end
  Cam.classes = Cam.classes or {}
  local cls = Cam.classes[path]
  if U.valid(cls) then return cls end
  cls = StaticFindObject(path)
  if not U.valid(cls) then
    U.note("loaded %s", tostring(path):match("([^%./]+)$") or tostring(path))
    cls = U.try("camera.load", LoadAsset, path)
  end
  Cam.classes[path] = cls
  return U.valid(cls) and cls or nil
end

local function playShake(pcm, cls, scale, yaw)
  U.callNamed(pcm, Cam.START_SHAKE, { ShakeClass = cls, Scale = scale, PlaySpace = yaw and 2 or 0,
    UserPlaySpaceRot = { Pitch = 0, Yaw = yaw or 0, Roll = 0 } })
  Cam.shakes = Cam.shakes + 1
end

-- The player's ATPC camera component ("NBCamera" on the pawn), asked from the pawn rather than found by a scan.
function Cam.atpc()
  local player = U.player()
  if not player then return nil end
  if U.valid(Cam.comp) and U.same(Cam.compOwner, player) then return Cam.comp end
  local cls = StaticFindObject("/Script/AdvancedThirdPersonCamera.ATPCCameraComponent")
  if not U.valid(cls) then return nil end
  local comp = U.try("camera.find", function() return player:GetComponentByClass(cls) end)
  Cam.comp, Cam.compOwner = U.valid(comp) and comp or nil, player
  return Cam.comp
end
local atpc = Cam.atpc

-- ATPC's GetCameraDistance does not include additive layers (v0.3 checks read 375 -> 375), so the check measures
-- the rendered camera's distance to the player instead.
local function camToPlayer()
  local pcm, p = U.pcm(), U.player()
  if not pcm or not p then return nil end
  local cl = U.try("camera.loc", function() return U.copyv(pcm:GetCameraLocation()) end)
  local pl = U.actorLoc(p)
  return cl and pl and U.len(U.sub(cl, pl)) or nil
end

local function setLayers(comp, push, kick, blendS)
  if push then U.callNamed(comp, Cam.ADD_DISTANCE, { AdditiveName = FName(PUSH_NAME), Distance = push, BlendTime = blendS }) end
  if kick then U.callNamed(comp, Cam.ADD_ROTATION, { AdditiveName = FName(KICK_NAME), RotationOffset = kick, BlendTime = blendS }) end
end

-- Push-in (cm, negative distance = closer) and a kick along the swing (degrees). Rapid hits extend the hold.
-- With `recoil` (the world direction the blow pushes the player) it is the other way round: the camera is knocked
-- back by cm, tips up, and swings to the side the blow comes from.
function Cam.punch(cm, kickDeg, ctx, p, recoil)
  cm, kickDeg = cm or 0, kickDeg or 0
  if (cm <= 0 and kickDeg <= 0) or Cam.punchBroken then return end
  local comp = atpc()
  if not comp then
    if not Cam.punchWarned then
      U.log("camera: no ATPC camera component found; push-in and kick are off")
      Cam.punchWarned = true
    end
    return
  end
  local kick
  if kickDeg > 0 then
    -- Screen-side of the swing: its component along the camera's right axis decides the sign.
    local side = 1
    local pcm = U.pcm()
    local sweep = recoil or (ctx and (ctx.sweep or ctx.right))
    if pcm and sweep then
      local rot = U.try("camera.rot", function() return U.copyr(pcm:GetCameraRotation()) end)
      if rot then
        local y = math.rad(rot.Yaw)
        local rx, ry = -math.sin(y), math.cos(y)
        side = (sweep.X * rx + sweep.Y * ry) >= 0 and 1 or -1
      end
    end
    kick = { Pitch = (recoil and 0.45 or -0.45) * kickDeg, Yaw = 0.6 * kickDeg * side, Roll = 0.5 * kickDeg * side }
  end
  -- The same push reads smaller the farther back the camera sits (3.5-4.8 m in the v0.4 logs, where 4 cm was 1% of
  -- the distance): PushCm is meant at RefDistanceCm and grows with the distance, up to twice.
  local ref = tonumber(p.RefDistanceCm) or 0
  local before = cm > 0 and camToPlayer() or nil
  if cm > 0 and ref > 0 and before and before > ref then cm = cm * math.min(before / ref, 2) end
  local check = Cam.punchChecks < 3 and cm > 0 and not recoil
  local inS, outS = (p.InMs or 25) / 1000, (p.OutMs or 160) / 1000
  setLayers(comp, cm > 0 and (recoil and cm or -cm) or nil, kick, inS)
  Cam.punches = Cam.punches + 1
  Cam.active = comp
  Cam.handle = Cam.handle or MakeActionHandle()
  RetriggerableExecuteInGameThreadWithDelay(Cam.handle, math.floor((p.InMs or 25) + (p.HoldMs or 40)), function()
    U.try("camera.unpunch", function()
      if U.valid(comp) then setLayers(comp, 0, { Pitch = 0, Yaw = 0, Roll = 0 }, outS) end
      Cam.active = nil
    end)
  end)
  if check then
    Cam.punchChecks = Cam.punchChecks + 1
    local n = Cam.punchChecks
    U.afterFrames(math.max(2, U.gameFrames(3)), function()
      local after = camToPlayer()
      U.log("camera punch check %d: camera to player %s -> %s cm for a %.0f cm push-in", n, tostring(before and math.floor(before)),
        tostring(after and math.floor(after)), cm)
    end)
  end
end

function Cam.release()
  if U.valid(Cam.active) then
    U.try("camera.release", setLayers, Cam.active, 0, { Pitch = 0, Yaw = 0, Roll = 0 }, 0.1)
  end
  Cam.active = nil
end

-- HUD multipliers (Tuning.*), 1.0 when absent.
local function mult(key) return tonumber((S.cfg.Tuning or {})[key]) or 1 end

-- A clash's weight (hf_hit H.deflectWeight, as its emphasis) scales its shake and punch.
local function deflect(ctx, pcm)
  local d = S.cfg.Deflect
  local e = U.emph(ctx)
  local cls = Cam.loadClass(C.tier(d.ShakeClass, ctx.tierName))
  local scale = (C.tier(d.ShakeScale, ctx.tierName) or 1) * mult("Shake") * e
  if cls and scale > 0 then U.try("camera.deflect", playShake, pcm, cls, scale, nil) end
  local p = S.cfg.Camera.Punch or {}
  U.try("camera.punch", Cam.punch, (C.tier(d.PushCm, ctx.tierName) or 0) * mult("Punch") * e,
    (C.tier(d.KickDeg, ctx.tierName) or 0) * mult("Punch") * e, ctx, p)
end

-- A killing blow (hf_kill): a shake of its own and a punch along the last swing.
function Cam.kill(ctx, k)
  if not S.cfg.Camera.Enabled then return end
  local pcm = U.pcm()
  if not pcm then return end
  local cls = Cam.loadClass(k.ShakeClass)
  local scale = (k.ShakeScale or 1) * mult("Shake")
  if cls and scale > 0 then U.try("camera.kill", playShake, pcm, cls, scale, nil) end
  U.try("camera.punch", Cam.punch, (k.PushCm or 0) * mult("Punch"), (k.KickDeg or 0) * mult("Punch"), ctx,
    S.cfg.Camera.Punch or {})
end

function Cam.onHit(ctx)
  local c = S.cfg.Camera
  if not c.Enabled or not ctx.byPlayer then return end
  local pcm = U.pcm()
  if not pcm then return end
  if not Cam.scaleLogged then
    Cam.scaleLogged = true
    U.log("camera: game shake setting CameraShakeScale = %s", tostring(U.try("camera.scale", function() return pcm.CameraShakeScale end)))
  end
  if ctx.kind == "deflect" then return deflect(ctx, pcm) end
  if Cam.last >= 0 and (ctx.time - Cam.last) * 1000 < c.MinIntervalMs then return end
  Cam.last = ctx.time

  local e = U.emph(ctx)
  local scale = (C.tier(c.ExtraShakeScale, ctx.tierName) or 0) * mult("Shake") * e
  if scale > 0 and (not c.ExtraShakeOnlyWhenVanillaHasNone or not ctx.vanillaShakeLevel) then
    local cls = Cam.loadClass(c.ExtraShakeClassPath)
    if not cls and U.valid(Cam.captured.any) then cls = Cam.captured.any end
    if cls then
      local yaw = ctx.dirVec and U.yawDeg(ctx.dirVec) or 0
      U.try("camera.shake", playShake, pcm, cls, scale, yaw)
    end
  end
  local p = c.Punch or {}
  U.try("camera.punch", Cam.punch, (C.tier(p.PushCm, ctx.tierName) or 0) * mult("Punch") * e,
    (C.tier(p.KickDeg, ctx.tierName) or 0) * mult("Punch") * e, ctx, p)
end

-- Every shake class this module may play, for the preloader; plus the vanilla attack shakes the hit bus upgrades to.
function Cam.assetPaths(out)
  local function add(p) if type(p) == "string" and p ~= "" then out[#out + 1] = p end end
  add(S.cfg.Camera.ExtraShakeClassPath)
  for _, p in pairs(S.cfg.Deflect.ShakeClass or {}) do add(p) end
  if S.hit then
    for lvl = 0, 4 do add(string.format(S.hit.SHAKE_FMT, lvl, lvl)) end
    if (S.cfg.Receive or {}).Enabled and S.hit.HIT_SHAKE_FMT then
      for lvl = 2, 4 do add(string.format(S.hit.HIT_SHAKE_FMT, lvl, lvl)) end
    end
  end
end

function Cam.stats()
  return string.format("extraShakes=%d punches=%d vanillaShakeUpgrades=%d atpc=%s", Cam.shakes, Cam.punches,
    Cam.upgrades or 0, tostring(U.valid(Cam.comp)))
end

return Cam
