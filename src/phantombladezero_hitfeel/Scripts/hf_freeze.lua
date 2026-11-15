-- PBZ HitFeel: hitstop through the game's own slomo system. Every hit starts the lookup's SlomoData twice
-- (StartSlomoData): attacker first, then the side that was hit, and vanilla then writes CustomTimeDilation every
-- frame (which is why v0.2's direct writes lost).
-- "slomo": the victim's call of the player's hits is rewritten before it runs, so vanilla holds only the enemy, with
--   its own curve and recovery. The first rewrites are checked by sampling the enemy's dilation; if none of them
--   reached the game, Freeze.Fallback takes over.
-- "symmetric": the lookup's SlomoData output is lengthened instead (the write pbz_hit_enhance uses), so both sides
--   hold; kept short for the player.
-- "dilation": v0.2's per-frame CustomTimeDilation writes.
-- Deflects: the lookups after a clash carry empty slomo data. Their output is filled in, so both sides hold for the
-- player's length; with "slomo" working the per-side calls then give the enemy its own, longer length.
local F = { name = "freeze", rewrites = 0, gedWrites = 0, deflectWrites = 0, checks = {}, active = {}, applied = 0,
  overridden = 0 }
local S, U, C

function F.init(state)
  S, U, C = state, state.U, state.C
  F.method = S.cfg.Freeze.Method or "slomo"
  -- A verdict from earlier in the session survives Ctrl+F8 reloads.
  if S.freezeVerdict == false and F.method == "slomo" then F.method = S.cfg.Freeze.Fallback or "none" end
end

-- HUD multipliers (Tuning.*), 1.0 when absent.
local function mult(key) return tonumber((S.cfg.Tuning or {})[key]) or 1 end

-- `emph`: the hit's place in the rhythm (hf_rhythm): quick light hits in a string hold shorter, accents longer.
local function frames(tbl, tier, key, emph)
  return U.gameFrames((C.tier(tbl, tier) or 0) * (key and mult(key) or 1) * (emph or 1))
end

-- Some hits carry no vanilla slomo at all (0 frames, multiplier 0: dual-wield taps); a minimum with that 0 would
-- stop the enemy dead, so only a real vanilla value is kept when it is lower.
local function holdScale(scale, vf, vm)
  local s = (vf or 0) > 0 and math.min(scale, vm or scale) or scale
  return math.max(0.01, s)
end

-- Samples the enemy's dilation after a rewrite; two low values early on mean vanilla is holding it for us.
function F.verify(owner, nf, nm, vf, vm)
  if F.checking or #F.checks >= 3 or S.freezeVerdict ~= nil then return end
  F.checking = true
  local seen, k, total = {}, 0, nf + 24
  -- Where the enemy is each frame: if it slides on while held, some of the game's hit movement ignores the freeze.
  local start, heldAt = U.actorLoc(owner), nil
  U.everyFrame("freeze.verify", function()
    k = k + 1
    if not U.valid(owner) then
      F.checking = false
      return true
    end
    seen[#seen + 1] = tonumber(owner.CustomTimeDilation) or -1
    if k == nf then heldAt = U.actorLoc(owner) end
    if k < total then return false end
    local finish = U.actorLoc(owner)
    if start and heldAt and finish then
      F.lastMove = string.format("enemy moved %.0f cm while held, %.0f cm in the next %d frames",
        U.len(U.flat(U.sub(heldAt, start))), U.len(U.flat(U.sub(finish, heldAt))), total - nf)
    end
    F.checking = false
    -- Halfway between our multiplier and vanilla's: the game's slomo curve lifts ours (0.05 -> 0.16 over 8 frames
    -- in game), so a fixed 0.12 called one held rewrite "not held".
    local thr, low = math.max(nm * 2, (nm + vm) / 2), 0
    for i = 1, math.min(#seen, nf + 2) do
      if seen[i] >= 0 and seen[i] <= thr then low = low + 1 end
    end
    local held = low >= math.min(2, nf)
    F.checks[#F.checks + 1] = held
    local vals = {}
    for i, x in ipairs(seen) do vals[i] = string.format("%.2f", x) end
    U.log("freeze check %d: enemy %d frames x%.2f (vanilla %d x%.2f, %.1f ms/frame) -> %s; %s; dilation per frame: %s",
      #F.checks, nf, nm, vf, vm, U.frameMs, held and "held" or "not held", F.lastMove or "-", table.concat(vals, " "))
    if held then
      S.freezeVerdict = true
      U.log("freeze: the slomo rewrite works; only the enemy is held, by the game's own slomo")
    elseif #F.checks >= 3 then
      S.freezeVerdict = false
      F.method = S.cfg.Freeze.Fallback or "none"
      U.log("freeze: the slomo rewrite never reached the game; using Freeze.Fallback = %s", F.method)
    end
    return true
  end)
end

-- The enemy-only hold bends the enemy's timing (fighting games freeze both sides, so frame data stays): the game's
-- slomo makes the held time up afterwards above 1.0 (up to about 1.36x in the v0.7.0 log), so the longer the hold,
-- the longer the enemy then moves faster than normal. What the holds add over vanilla, the time the enemy loses, is
-- capped per enemy over the last second (Freeze.MaxExtraFramesPerSec, 60 fps frames). Returns the frames to hold (fewer when the
-- rest of the second's allowance is short), or nil to leave vanilla's call as it is. An accent keeps its full hold,
-- the punctuation of the string, and its cost comes out of the hits that follow.
function F.cap(owner, nf, nm, vf, vm, accent)
  local cap = (tonumber(S.cfg.Freeze.MaxExtraFramesPerSec) or 0) / 60
  local key = U.addr(owner)
  if cap <= 0 or not key then return nf end
  local now, fs = U.now(), (U.frameMs or 16.7) / 1000
  F.spent = F.spent or {}
  local kept, used = {}, 0
  for _, e in ipairs(F.spent[key] or {}) do
    if now - e.t < 1 then
      kept[#kept + 1] = e
      used = used + e.lost
    end
  end
  F.spent[key] = kept
  local base = vf * (1 - math.min(1, vm)) * fs
  local want = nf * (1 - nm) * fs - base
  if want <= 0 then return nf end
  local left = cap - used
  if accent then
    kept[#kept + 1] = { t = now, lost = want }
    return nf
  end
  if left <= 0 then
    F.capped = (F.capped or 0) + 1
    if F.capped == 1 then U.log("freeze: an enemy's extra hold for the last second is used up; vanilla's slow-down for this hit") end
    return nil
  end
  if want > left then
    nf, want = math.max(vf, math.floor((left + base) / ((1 - nm) * fs))), left
    F.capped = (F.capped or 0) + 1
  end
  kept[#kept + 1] = { t = now, lost = want }
  return nf
end

-- An enemy not held in the last second has nothing left in its allowance (and its address may come back as another
-- enemy's). hf_perf calls this every few seconds.
function F.prune(now)
  for key, list in pairs(F.spent or {}) do
    local last = list[#list]
    if not last or now - last.t >= 1 then F.spent[key] = nil end
  end
end

F.UTILS = "/Script/PBZCombatAsset.Default__PBZHitreactUtils"
F.ENDURE = "/Script/PBZCombatAsset.PBZHitreactUtils:GetEndureLevel"
F.BREAK_ASC = "/Script/PBZCombatAsset.PBZHitreactUtils:GetAbilitySystemBreakEndureLevel"
F.BREAK_OWNER = "/Script/PBZCombatAsset.PBZHitreactUtils:GetOwnerBreakEndureLevel"

local function level(fn, named)
  local utils = U.cdo(F.UTILS)
  if not utils then return nil end
  local ok, v = pcall(U.callNamed, utils, fn, named)
  return ok and type(v) == "number" and v or nil
end

-- Whether the hit leaves the enemy's super armor standing: its endure level above the break-endure level your
-- attack brings (PBZHitreactUtils, through the ability systems). Such an enemy is mid-attack and not staggered, and
-- holding it would push its swing later than the player has learned. The first readings are logged. A reading that
-- says "armored" on the first hit of every one of five different enemies is taken for a wrong one (most enemies
-- stagger on a first hit), and the guard turns itself off.
function F.armored(owner)
  if not S.cfg.Freeze.EndureGuard or F.endureOff then return false end
  local easc, pasc = U.asc(owner), U.asc(U.player())
  local endure = easc and level(F.ENDURE, { AbilitySystem = easc })
  local b1 = pasc and level(F.BREAK_ASC, { AbilitySystem = pasc })
  local b2 = level(F.BREAK_OWNER, { OwnerActor = U.player() })
  if not endure or not (b1 or b2) then
    if not F.endureWarned then
      F.endureWarned = true
      U.log("freeze: super armor cannot be read here (ability system %s, endure %s, break %s/%s); every hit is held",
        tostring(easc ~= nil), tostring(endure), tostring(b1), tostring(b2))
    end
    return false
  end
  local brk = math.max(b1 or 0, b2 or 0)
  local armored = endure > brk
  F.endureChecks = (F.endureChecks or 0) + 1
  if F.endureChecks <= 10 then
    U.log("freeze: super armor check %d: %s endure %d, your break %s/%s -> %s", F.endureChecks, U.fname(owner), endure,
      tostring(b1), tostring(b2), armored and "armored, vanilla hold" or "staggered")
  end
  local key = U.addr(owner)
  F.firstHits = F.firstHits or {}
  -- (Five enemies settle it either way, so no more are kept.)
  if key and F.firstHits[key] == nil and not F.firstHitsDone then
    F.firstHits[key] = armored
    local n, all = 0, true
    for _, a in pairs(F.firstHits) do
      n = n + 1
      all = all and a
    end
    if n >= 5 and all then
      F.endureOff = true
      U.log("freeze: the super armor check said armored on the first hit of 5 different enemies; taken for a wrong reading and turned off")
      return false
    end
    F.firstHitsDone = n >= 5
  end
  if armored then F.armoredHits = (F.armoredHits or 0) + 1 end
  return armored
end

-- Whether a deflect lookup (a clash, or a blow on a shield) gets its slomo write: never one you are not in (others
-- parry each other anywhere on the map). Not known yet at this lookup: with "slomo" the calls that follow name both
-- sides and are written then; the other methods have only this write, so they keep the old guess that it is yours.
local function deflectWrite(fd)
  if fd.mine ~= nil then return fd.mine end
  return F.method ~= "slomo"
end

-- GetEffectData output, after the lookup ran (blueprint hook): sd is its SlomoData.
function F.onEffect(info, sd)
  local c = S.cfg.Freeze
  if not c.Enabled then return end
  if info.deflect then
    -- Deflect lookups, and player hits that land on a shield: a short stop for both sides.
    local d = S.cfg.Deflect
    local fd = info.deflect
    if not d.Enabled or (fd.playerAttacked and not d.OnEnemyDeflect) or not deflectWrite(fd) then return end
    -- A quick repeat in a string of clashes leaves the lookup as the game made it; the enemy's own call still holds.
    if fd.tier ~= "Perfect" and info.rhythm and info.rhythm.repeated then return end
    local n = frames(d.PlayerFreeze, fd.tier, "PlayerDeflectFreeze", S.hit.deflectWeight(fd.tier, fd.strengthTier, info.rhythm, fd.final))
    if n <= 0 then return end
    sd.Frames, sd.Multiplier = n, math.max(0.01, d.FreezeScale)
    F.deflectWrites = F.deflectWrites + 1
    info.freezeApplied = string.format("both %d x%.2f", n, d.FreezeScale)
    return
  end
  -- (This write is all "symmetric" has, before any call names the attacker: a hit known by its shake alone is taken
  -- for yours, though it may be two others' blow, and its rhythm is not known yet.)
  if F.method ~= "symmetric" or not info.likelyPlayer then return end
  local vf, vm = info.vanillaFrames or 0, info.vanillaMult or 1
  local nf, nm = math.max(frames(c.SymmetricFrames, info.tierName, "Freeze", U.emph(info)), vf), holdScale(c.SymmetricScale, vf, vm)
  if nf == vf and nm == vm then return end
  sd.Frames, sd.Multiplier = nf, nm
  F.gedWrites = F.gedWrites + 1
  info.freezeApplied = string.format("both %d x%.2f (vanilla %d x%.2f)", nf, nm, vf, vm)
end

-- StartSlomoData before it runs: rec is this call, ged the lookup it follows, sd its SlomoData.
function F.onSlomoCall(rec, ged, sd)
  local c = S.cfg.Freeze
  if not c.Enabled or not rec.owner or F.method ~= "slomo" then return end
  if ged.deflect then
    local d = S.cfg.Deflect
    local fd = ged.deflect
    if not d.Enabled or (fd.playerAttacked and not d.OnEnemyDeflect) or not fd.mine then return end
    local repeated = fd.tier ~= "Perfect" and ged.rhythm and ged.rhythm.repeated
    if rec.isPlayer and repeated then
      ged.freezeApplied = "enemy only (a quick repeat: only the first clash of a string stops you)"
      return
    end
    local w = S.hit.deflectWeight(fd.tier, fd.strengthTier, ged.rhythm, fd.final)
    local n = rec.isPlayer and frames(d.PlayerFreeze, fd.tier, "PlayerDeflectFreeze", w) or frames(d.EnemyFreeze, fd.tier, "DeflectFreeze", w)
    if n <= 0 then return end
    sd.Frames, sd.Multiplier = n, math.max(0.01, d.FreezeScale)
    rec.rewritten = n
    return
  end
  if not ged.attackerIsPlayer or ged.onPlayer or rec.isPlayer or (rec.callIndex or 0) < 2 then return end
  if ged.special == "Knockback" and not c.ExtendKnockback then return end
  -- The killing blow (hf_kill: this hit took the enemy's health to zero) holds longer, Kill.HoldFrames, past the armor
  -- guard and the cap: none of the enemy's timing is left to keep.
  local killing = S.kill and U.try("freeze.kill", S.kill.atLookup, rec.owner)
  if not killing and U.try("freeze.armor", F.armored, rec.owner) then
    ged.freezeApplied = "vanilla (its super armor held: its attack keeps its timing)"
    return
  end
  local vf, vm = rec.frames or 0, rec.mult or 1
  local nf, nm = math.max(frames(c.Frames, ged.tierName, "Freeze", U.emph(ged)), vf), holdScale(c.Scale, vf, vm)
  if killing then nf = math.max(nf, frames({ Default = S.cfg.Kill.HoldFrames or 0 }, "Default", "Freeze")) end
  if nf == vf and nm == vm then return end
  if not killing then
    nf = F.cap(rec.owner, nf, nm, vf, vm, ged.rhythm and ged.rhythm.accent)
    if not nf then
      ged.freezeApplied = "vanilla (this enemy's extra hold for the last second is used up)"
      return
    end
  end
  sd.Frames, sd.Multiplier = nf, nm
  F.rewrites = F.rewrites + 1
  rec.rewritten = nf
  ged.freezeApplied = string.format("%s %d x%.2f (vanilla %d x%.2f)", killing and "killing blow" or "enemy", nf, nm, vf, vm)
  -- Light and middle hits slow by 0.4 / 0.2 in vanilla, far from a freeze, so they show whether the rewrite held.
  if S.freezeVerdict == nil and vm >= 0.15 then F.verify(rec.owner, nf, nm, vf, vm) end
  F.watchMove(rec.owner, nf, ged.tierName)
end

-- For the first hits: how far the enemy travels while held and right after, into probe_knockback.txt. A slide while
-- held means some of the game's hit movement does not respect the freeze.
function F.watchMove(owner, nf, tier)
  F.watched = (F.watched or 0) + 1
  if F.watched > 12 or not U.valid(owner) then return end
  local start, heldAt, k = U.actorLoc(owner), nil, 0
  if not start then return end
  U.everyFrame("freeze.move", function()
    k = k + 1
    if not U.valid(owner) then return true end
    if k == nf then heldAt = U.actorLoc(owner) end
    if k < nf + 30 then return false end
    local finish = U.actorLoc(owner)
    if heldAt and finish then
      U.write("probe_knockback.txt", string.format("%s held %s %d frames: moved %.0f cm while held, %.0f cm in the next 30 frames",
        os.date("%H:%M:%S"), tostring(tier), nf, U.len(U.flat(U.sub(heldAt, start))), U.len(U.flat(U.sub(finish, heldAt)))))
    end
    return true
  end)
end

-- ------------------------------------------------------------------ "dilation" (v0.2 method)

local function finish(key, st)
  if U.valid(st.actor) then
    local cur = st.actor.CustomTimeDilation
    if type(cur) == "number" and math.abs(cur - st.scale) < 1e-3 then st.actor.CustomTimeDilation = 1.0 end
  end
  if F.active[key] == st then F.active[key] = nil end
end

-- Holds `actor` at `scale` for `frames` (60 fps frames, run as real time); a new hold extends a running one.
function F.hold(actor, frames60, scale)
  if not U.valid(actor) or not frames60 or frames60 <= 0 then return end
  local key = U.addr(actor)
  if not key then return end
  local untilT = U.now() + frames60 / 60
  local st = F.active[key]
  if st then
    st.untilT = math.max(st.untilT, untilT)
    st.scale = math.min(st.scale, scale)
    actor.CustomTimeDilation = st.scale
    return
  end
  st = { actor = actor, scale = scale, untilT = untilT }
  F.active[key] = st
  actor.CustomTimeDilation = scale
  F.applied = F.applied + 1
  U.everyFrame("freeze.step", function()
    if st.cancelled or not U.valid(st.actor) then
      if F.active[key] == st then F.active[key] = nil end
      return true
    end
    if U.now() >= st.untilT then
      finish(key, st)
      return true
    end
    local cur = st.actor.CustomTimeDilation
    if type(cur) == "number" and math.abs(cur - st.scale) > 1e-3 then F.overridden = F.overridden + 1 end
    st.actor.CustomTimeDilation = st.scale
    return false
  end)
end

function F.release()
  for key, st in pairs(F.active) do
    st.cancelled = true
    U.try("freeze.release", finish, key, st)
  end
  F.active = {}
end

function F.onHit(ctx)
  local c = S.cfg.Freeze
  if not c.Enabled or not ctx.byPlayer or F.method ~= "dilation" then return end
  if ctx.kind == "deflect" then
    local d = S.cfg.Deflect
    F.hold(ctx.victim, C.tier(d.EnemyFreeze, ctx.tierName), d.FreezeScale)
    F.hold(ctx.player, C.tier(d.PlayerFreeze, ctx.tierName), d.FreezeScale)
    return
  end
  F.hold(ctx.victim, C.tier(c.Frames, ctx.tierName), c.Scale)
end

function F.stats()
  local n = 0
  for _ in pairs(F.active) do n = n + 1 end
  return string.format("method=%s verdict=%s enemyRewrites=%d lookupWrites=%d deflectWrites=%d checks=%d dilationHolds=%d active=%d %.1fms/frame",
    tostring(F.method), tostring(S.freezeVerdict), F.rewrites, F.gedWrites, F.deflectWrites, #F.checks, F.applied, n, U.frameMs)
end

return F
