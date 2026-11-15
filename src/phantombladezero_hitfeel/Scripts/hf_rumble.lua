-- PBZ HitFeel: controller rumble on confirmed hits, in two layers. On XInput pads UE maps the
-- Large channels to the low-frequency (left) motor and the Small channels to the high-frequency (right) one.
local R = { name = "rumble", uuid = 731000, played = 0 }
local S, U, C

R.PLAY_DYN = "/Script/Engine.PlayerController:PlayDynamicForceFeedback"

function R.init(state)
  S, U, C = state, state.U, state.C
end

function R.play(intensity, ms, large, small)
  if not intensity or intensity <= 0 or not ms or ms <= 0 then return end
  local pc = U.pc()
  if not pc then return end
  R.uuid = R.uuid + 1
  U.callNamed(pc, R.PLAY_DYN, {
    Intensity = math.min(1, intensity),
    Duration = ms / 1000,
    bAffectsLeftLarge = large, bAffectsLeftSmall = small,
    bAffectsRightLarge = large, bAffectsRightSmall = small,
    Action = 0,
    LatentInfo = { Linkage = 0, UUID = R.uuid, ExecutionFunction = FName("None"), CallbackTarget = pc },
  })
  R.played = R.played + 1
end

local function checkController()
  if R.checked then return end
  local pc = U.pc()
  if not pc then return end
  R.checked = true
  local en = U.try("rumble.flag", function() return pc.bForceFeedbackEnabled end)
  local scale = U.try("rumble.scale", function() return pc.ForceFeedbackScale end)
  U.log("rumble: bForceFeedbackEnabled=%s ForceFeedbackScale=%s", tostring(en), tostring(scale))
  if en == false and S.cfg.Rumble.ForceEnableUEForceFeedback then
    pc.bForceFeedbackEnabled = true
    U.log("rumble: UE force feedback was off; enabled because ForceEnableUEForceFeedback = true")
  end
end

function R.onHit(ctx)
  local c = S.cfg.Rumble
  if not c.Enabled or not ctx.byPlayer then return end
  checkController()
  local p = C.tier(ctx.kind == "deflect" and S.cfg.Deflect.Rumble or c.Profiles, ctx.tierName)
  if not p then return end
  local e = U.emph(ctx)
  U.try("rumble.body", R.play, math.min(1, (p.Body or 0) * c.Scale * e), p.BodyMs or 0, true, false)
  U.try("rumble.edge", R.play, math.min(1, (p.Edge or 0) * c.Scale * e), p.EdgeMs or 0, false, true)
end

-- Confirmation buzz for the hotkeys: one pulse = on/reloaded, two = off.
function R.pulse(times)
  for i = 0, times - 1 do
    ExecuteInGameThreadWithDelay(i * 180 + 1, function() U.try("rumble.pulse", R.play, 0.5, 80, true, true) end)
  end
end

function R.stats() return string.format("played=%d", R.played) end

return R
