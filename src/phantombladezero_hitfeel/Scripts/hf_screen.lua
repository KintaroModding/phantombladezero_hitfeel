-- PBZ HitFeel: screen impact. A short pulse of the camera's own vignette (the edges darken, the middle stays as it
-- is) with a touch of chromatic fringe at the edges, only on accents: your heavy hits and finishers (hf_rhythm), a
-- held guard, and blows that get through to you. v0.5.6's full-screen flash was glaring even at 0.1: it lit the
-- middle of the screen, where you look.
-- The pulse writes the post-process settings of the camera the game renders through
-- (PBZPlayerCameraManager:GetCurrentActivateCameraComponent, a CineCameraComponent) and puts its values back when it
-- ends. Where that camera sets no vignette of its own, the pulse starts from the level's (read at map load from its
-- unbound post-process volumes), else from the engine's default.
local Sc = { name = "screen", pulses = 0, skipped = 0 }
local S, U, C

Sc.GET_CAMERA = "/Script/ProjectPBZ.PBZPlayerCameraManager:GetCurrentActivateCameraComponent"
local ENGINE_VIGNETTE, ENGINE_FRINGE = 0.4, 0

-- The pulse in progress lives in S.screenState, so a Ctrl+F8 reload mid-pulse still restores the camera.
function Sc.init(state)
  S, U, C = state, state.U, state.C
  S.screenState = S.screenState or {}
end

local function mult() return tonumber((S.cfg.Tuning or {}).Screen) or 1 end

-- The level's vignette and fringe: the highest-priority enabled unbound volume that overrides each. Map load only
-- (FindAllOf walks every object).
function Sc.discover()
  local st = S.screenState
  st.levelVignette, st.levelFringe = nil, nil
  local bestV, bestF, n = nil, nil, 0
  U.note("scan of post-process volumes")
  for _, v in ipairs(FindAllOf("PostProcessVolume") or {}) do
    local ok, x = pcall(function()
      local p = v.Settings
      return { unbound = v.bUnbound, enabled = v.bEnabled, pri = tonumber(v.Priority) or 0, w = tonumber(v.BlendWeight) or 1,
        ovV = p.bOverride_VignetteIntensity, vig = p.VignetteIntensity, ovF = p.bOverride_SceneFringeIntensity,
        fr = p.SceneFringeIntensity }
    end)
    if ok and x.unbound and x.enabled ~= false and x.w > 0 then
      n = n + 1
      if x.ovV and (not bestV or x.pri > bestV) then bestV, st.levelVignette = x.pri, tonumber(x.vig) end
      if x.ovF and (not bestF or x.pri > bestF) then bestF, st.levelFringe = x.pri, tonumber(x.fr) end
    end
  end
  U.log("screen: %d unbound post-process volume(s); level vignette %s, fringe %s", n,
    st.levelVignette and string.format("%.2f", st.levelVignette) or "not set (engine 0.4)",
    st.levelFringe and string.format("%.2f", st.levelFringe) or "not set (engine 0)")
end

local function camera()
  local pcm = U.pcm()
  if not pcm then return nil end
  local cam = U.try("screen.camera", function() return pcm:GetCurrentActivateCameraComponent() end)
  return U.valid(cam) and cam or nil
end

local function write(cam, vig, fr)
  local p = cam.PostProcessSettings
  p.bOverride_VignetteIntensity = true
  p.VignetteIntensity = vig
  if fr then
    p.bOverride_SceneFringeIntensity = true
    p.SceneFringeIntensity = fr
  end
end

-- Puts back what the camera had before the pulse, unless the game has written those settings since.
local function restore(st)
  local cam = st.cam
  st.cam, st.running = nil, false
  if not U.valid(cam) or not st.saved then return end
  U.try("screen.restore", function()
    local p, s = cam.PostProcessSettings, st.saved
    if math.abs((tonumber(p.VignetteIntensity) or 0) - (st.wroteV or -1)) < 1e-3 then
      p.VignetteIntensity, p.bOverride_VignetteIntensity = s.vig, s.ovV
    end
    if st.wroteF and math.abs((tonumber(p.SceneFringeIntensity) or 0) - st.wroteF) < 1e-3 then
      p.SceneFringeIntensity, p.bOverride_SceneFringeIntensity = s.fr, s.ovF
    end
  end)
end

-- Envelope 0..1 at `ms` into the pulse: a quick rise, a short hold, an eased fall.
local function envelope(c, ms)
  local a, h, r = c.AttackMs or 30, c.HoldMs or 50, c.ReleaseMs or 260
  if ms < a then return ms / a end
  if ms < a + h then return 1 end
  local x = (ms - a - h) / r
  if x >= 1 then return 0 end
  return (1 - x) * (1 - x)
end

local function step()
  local st, c = S.screenState, (S.cfg.Screen or {})
  if not st.running then return true end
  if not U.valid(st.cam) then
    st.cam, st.running = nil, false
    return true
  end
  local e = envelope(c, (U.now() - st.t0) * 1000)
  if e <= 0 then
    restore(st)
    return true
  end
  local vig = math.min(c.MaxVignette or 1, st.baseV + st.peak * e)
  local fr = (c.Fringe or 0) > 0 and st.baseF + st.peak * (c.Fringe or 0) * e or nil
  write(st.cam, vig, fr)
  st.wroteV, st.wroteF = vig, fr
  if not Sc.checked then
    Sc.checked = true
    local back = U.try("screen.check", function() return st.cam.PostProcessSettings.VignetteIntensity end)
    U.log("screen: vignette pulse on %s (blend weight %s): wrote %.2f, reads back %s; base %.2f (%s), fringe %s",
      U.fname(st.cam), tostring(st.weight), vig, tostring(back and string.format("%.2f", back)), st.baseV, st.baseFrom,
      fr and string.format("%.2f", fr) or "off")
  end
  return false
end

-- Whether a pulse of `peak` may start now. A quick string of heavy blows (the chain's rapid heavy hits, an enemy
-- combo landing on you) asked for one pulse after another, and the edges stayed dark through the whole string: within
-- Screen.MinGapMs of the last pulse only one StrongerBy times as strong gets through.
local function allowed(c, st, peak, now)
  local gap = (tonumber(c.MinGapMs) or 0) / 1000
  if gap <= 0 or not st.lastAt or now - st.lastAt >= gap then return true end
  return peak >= (st.lastPeak or 0) * (tonumber(c.StrongerBy) or 1.25)
end

-- A pulse of strength `peak` (vignette added at the top). A stronger pulse while one runs jumps straight to the new
-- peak and holds and fades from there (no dip back to the base); a weaker one leaves the pulse in progress to fade.
function Sc.pulse(peak)
  local c = S.cfg.Screen or {}
  if not c.Enabled or not peak or peak <= 0 then return end
  local st = S.screenState
  local cam = camera()
  if not cam then return end
  peak = peak * mult()
  if peak <= 0 then return end
  local now = U.now()
  if not allowed(c, st, peak, now) then
    Sc.skipped = Sc.skipped + 1
    if Sc.skipped == 1 then
      U.log("screen: a pulse %.0f ms after the last one skipped (Screen.MinGapMs %d)", (now - st.lastAt) * 1000,
        tonumber(c.MinGapMs) or 0)
    end
    return
  end
  if st.running and not U.same(st.cam, cam) then restore(st) end
  if st.running then
    local cur = st.peak * envelope(c, (now - st.t0) * 1000)
    if peak <= cur then return end
    st.peak, st.t0 = peak, now - (c.AttackMs or 30) / 1000
    st.lastAt, st.lastPeak = now, peak
    Sc.pulses = Sc.pulses + 1
    return
  end
  local saved = U.try("screen.save", function()
    local p = cam.PostProcessSettings
    return { ovV = p.bOverride_VignetteIntensity == true, vig = tonumber(p.VignetteIntensity) or ENGINE_VIGNETTE,
      ovF = p.bOverride_SceneFringeIntensity == true, fr = tonumber(p.SceneFringeIntensity) or ENGINE_FRINGE }
  end)
  if not saved then return end
  local w = U.try("screen.weight", function() return cam.PostProcessBlendWeight end)
  if type(w) == "number" and w <= 0 then
    if not Sc.weightLogged then
      Sc.weightLogged = true
      U.log("screen: the game's camera has post-process blend weight 0; no screen impact")
    end
    return
  end
  st.cam, st.saved, st.weight, st.running, st.peak, st.t0 = cam, saved, w, true, peak, now
  st.lastAt, st.lastPeak = now, peak
  if saved.ovV then
    st.baseV, st.baseFrom = saved.vig, "the camera's"
  elseif st.levelVignette then
    st.baseV, st.baseFrom = st.levelVignette, "the level's"
  else
    st.baseV, st.baseFrom = ENGINE_VIGNETTE, "engine default"
  end
  st.baseF = saved.ovF and saved.fr or st.levelFringe or ENGINE_FRINGE
  st.wroteV, st.wroteF = nil, nil
  Sc.pulses = Sc.pulses + 1
  U.everyFrame("screen.pulse", step)
end

-- Accents of your hits and a held guard; a blow on you comes from hf_receive (Sc.pulse with the Receive strength).
function Sc.onHit(ctx)
  local c = S.cfg.Screen or {}
  if not c.Enabled or not ctx.byPlayer then return end
  if ctx.kind == "deflect" then
    if ctx.playerDefended then Sc.pulse(C.tier(c.Deflect, ctx.tierName) or 0) end
  elseif ctx.rhythm and ctx.rhythm.accent then
    Sc.pulse(C.tier(c.Hit, ctx.tierName) or 0)
  end
end

function Sc.receive(tierName)
  local c = S.cfg.Screen or {}
  if c.Enabled then Sc.pulse(C.tier(c.Receive, tierName) or 0) end
end

function Sc.release()
  local st = S.screenState
  if st and st.running then restore(st) end
end

function Sc.stats()
  local st = S.screenState or {}
  return string.format("pulses=%d skipped=%d running=%s levelVignette=%s", Sc.pulses, Sc.skipped, tostring(st.running),
    tostring(st.levelVignette))
end

return Sc
