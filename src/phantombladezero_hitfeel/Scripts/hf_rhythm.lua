-- PBZ HitFeel: rhythm. Hits need contrast to read: a string of quick light hits that each land as hard as a heavy one
-- turns into a buzz, and the heavy one no longer stands out. Each of your hits on an enemy takes its place in a
-- string (hits less than Rhythm.ChainGapMs apart). Quick light hits after the first get gradually less (freeze,
-- shake, push, flash and buzz all scale by ctx.rhythm.emph), and the accents get more: a heavy or stronger hit, or a
-- middle hit after a string of quick ones (the finisher). Only accents get the screen impact. An accent closes its
-- string, so the next hit starts a new phrase at full strength. Since v0.7 a heavy hit right after another is no
-- accent and steps down, and a density fatigue lightens every hit of a dense string a little.
local Rh = { name = "rhythm", strings = 0, accents = 0, chain = 0, last = -1, dchain = 0, lastDeflect = -1, repeats = 0,
  heavyRun = 0, heavyRepeats = 0, load = 0 }
local S, U, C

function Rh.init(state)
  S, U, C = state, state.U, state.C
end

local LIGHT = { VeryLight = true, Light = true }
local HEAVY = { Heavy = true, UltraHeavy = true, Break = true }

-- The panel's contrast: 0 = every hit as its strength says (no rhythm), 1 = as configured, 2 = twice the contrast.
local function contrast() return math.max(0, tonumber((S.cfg.Tuning or {}).Rhythm) or 1) end

-- Density fatigue: a load of recent hits, each adding its FatigueWeight and the whole halving every
-- FatigueHalfLifeMs; a hit lands at 1 - Fatigue x load (accents feel half of it), not below FatigueFloor. The panel's
-- contrast scales it like the rest of the rhythm (0 = none).
local function fatigue(c, t, now, accent, k)
  local hl = math.max(0.05, (tonumber(c.FatigueHalfLifeMs) or 600) / 1000)
  if Rh.loadAt then Rh.load = Rh.load * 0.5 ^ ((now - Rh.loadAt) / hl) end
  Rh.loadAt = now
  local f, scale = (tonumber(c.Fatigue) or 0) * k, 1
  if f > 0 then scale = math.max(c.FatigueFloor or 0.7, 1 - f * Rh.load * (accent and 0.5 or 1)) end
  Rh.load = Rh.load + (C.tier(c.FatigueWeight, t) or 0.25)
  return math.min(1, scale)
end

-- Called once per lookup of your hit on an enemy, before its freeze is decided (the freeze is rewritten in the same
-- frame). Lookups in one frame (a swing through two enemies) share their place in the string.
function Rh.mark(info)
  local c = S.cfg.Rhythm or {}
  if not c.Enabled then return end
  local now = info.time
  if Rh.lastMark and now - Rh.last < 0.005 then
    info.rhythm = Rh.lastMark
    return
  end
  local inString = Rh.last >= 0 and now - Rh.last <= (c.ChainGapMs or 400) / 1000
  if inString then
    Rh.chain = Rh.chain + 1
  else
    Rh.chain = 1
    Rh.strings = Rh.strings + 1
    Rh.heavyRun = 0
  end
  Rh.last = now
  local t, k = info.tierName, contrast()
  local r = { chain = Rh.chain, emph = 1 }
  if HEAVY[t] and inString and Rh.heavyRun > 0 then
    -- A heavy hit right after another (the chain's rapid heavy blows): every one of them used to be a full accent,
    -- so the string had no contrast left. No accent; one step lighter each time, not below HeavyRepeatFloor.
    Rh.heavyRun = Rh.heavyRun + 1
    local step = math.max(c.HeavyRepeatFloor or 0.7, (c.HeavyRepeatDecay or 0.85) ^ (Rh.heavyRun - 2))
    r.emph, r.heavyRepeat = math.max(0.2, 1 - k * (1 - step)), Rh.heavyRun
    Rh.heavyRepeats = Rh.heavyRepeats + 1
    Rh.chain = 0
    if Rh.heavyRepeats == 1 then U.log("rhythm: heavy hit %d of a quick string, no accent, x%.2f", Rh.heavyRun, r.emph) end
  elseif HEAVY[t] or (t == "Middle" and Rh.chain > (c.FinisherAfter or 3)) then
    r.accent = true
    r.emph = 1 + k * ((c.AccentEmph or 1.3) - 1)
    Rh.accents = Rh.accents + 1
    Rh.chain = 0
    Rh.heavyRun = HEAVY[t] and 1 or 0
    if Rh.accents == 1 then U.log("rhythm: first accent, a %s hit as hit %d of its string, x%.2f", tostring(t), r.chain, r.emph) end
  else
    Rh.heavyRun = 0
    if LIGHT[t] then
      local d = c.LightDecay or {}
      r.emph = math.max(0.2, 1 - k * (1 - (d[math.min(Rh.chain, #d)] or 1)))
      if r.chain == #d and not Rh.decayLogged then
        Rh.decayLogged = true
        U.log("rhythm: light hit %d of a quick string at x%.2f", r.chain, r.emph)
      end
    end
  end
  r.fatigue = fatigue(c, t, now, r.accent, k)
  r.emph = r.emph * r.fatigue
  if r.fatigue < 0.9 and not Rh.fatigueLogged then
    Rh.fatigueLogged = true
    U.log("rhythm: a dense string, this hit at x%.2f of its emphasis (Rhythm.Fatigue)", r.fatigue)
  end
  info.rhythm, Rh.lastMark = r, r
end

-- Clashes form strings too (an enemy's combo into your guard, a flurry into a shield, ClashGapMs apart). Only the
-- first of a string stops you; v0.5.7 stopped you on every one of them, the sudden stutter in a string of blocks.
-- A perfect deflect always does.
function Rh.markDeflect(info)
  local c = S.cfg.Rhythm or {}
  if not c.Enabled then return end
  local now = info.time
  if Rh.lastDeflectMark and now - Rh.lastDeflect < 0.005 then
    info.rhythm = Rh.lastDeflectMark
    return
  end
  if Rh.lastDeflect >= 0 and now - Rh.lastDeflect <= (c.ClashGapMs or 600) / 1000 then
    Rh.dchain = Rh.dchain + 1
  else
    Rh.dchain = 1
  end
  Rh.lastDeflect = now
  local r = { chain = Rh.dchain, repeated = Rh.dchain > 1 }
  if r.repeated then Rh.repeats = Rh.repeats + 1 end
  info.rhythm, Rh.lastDeflectMark = r, r
end

function Rh.onHit() end

function Rh.stats()
  return string.format("strings=%d accents=%d heavyRepeats=%d clashRepeats=%d load=%.2f", Rh.strings, Rh.accents,
    Rh.heavyRepeats, Rh.repeats, Rh.load)
end

return Rh
