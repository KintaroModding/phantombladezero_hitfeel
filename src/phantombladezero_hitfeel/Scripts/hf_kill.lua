-- PBZ HitFeel: the killing blow. Action games give the blow that ends an enemy the strongest feedback, the period at
-- the end of the sentence; until v0.7 the last hit landed like any other. The game hands the hit no damage or HP, so
-- the mod reads the struck enemy's health from its ability system's attribute sets (ASC.SpawnedAttributes: the first
-- GameplayAttributeData named like Kill.HealthNames, not a Max one) when the hit is dispatched and again
-- Kill.CheckAfterFrames later; at or below Kill.DeadAtOrBelow it died from that hit. (v0.7.0 read gameplay tags
-- instead, and this build cannot list an ability system's tags.) The first checks log what they read: the attribute
-- names once per attribute set class, then the health before and after.
local K = { name = "kill", kills = 0, checks = 0, dead = {}, setProps = {}, logged = {}, hp = {}, lookup = {}, held = {},
  touched = {}, healthAt = {} }
local S, U, C

function K.init(state)
  S, U, C = state, state.U, state.C
end

-- The GameplayAttributeData properties of an attribute set, its own class and its supers up to AttributeSet.
local function attributeNames(set)
  local out = {}
  local ok, cls = pcall(function() return set:GetClass() end)
  for _ = 1, 6 do
    if not ok or not U.valid(cls) or U.fname(cls) == "AttributeSet" then break end
    for _, p in ipairs(U.props(cls)) do
      local d = U.desc(p)
      if d.type == "StructProperty" and d.sname == "GameplayAttributeData" then out[#out + 1] = d.name end
    end
    ok, cls = pcall(function() return cls:GetSuperStruct() end)
  end
  return out
end

local function current(set, name)
  local ok, v = pcall(function() return set[name].CurrentValue end)
  return ok and type(v) == "number" and v or nil
end

-- The health attribute among `names`: an exact Kill.HealthNames entry first, then any name holding one (not Max).
local function pickHealth(names, wanted)
  for _, w in ipairs(wanted) do
    for _, n in ipairs(names) do
      if n == w then return n end
    end
  end
  for _, w in ipairs(wanted) do
    for _, n in ipairs(names) do
      if n:find(w, 1, true) and not n:find("Max", 1, true) then return n end
    end
  end
end

-- The enemy's health and where it was read ("Class.Attribute"), or nil and why. Where an enemy's health lives (its
-- attribute set and the name) is kept by address after the first read, so each later read is that one value: walking
-- the ability system was about a dozen engine calls, three times for every hit (its slomo call, the dispatch, the
-- check), on every enemy of a crowd. The kept set is checked before each use, and found again when it has gone.
function K.health(victim)
  local key = U.addr(victim)
  local at = key and K.healthAt[key]
  if at and U.valid(at.set) then
    local v = current(at.set, at.name)
    if v then return v, at.where end
  end
  local asc = U.asc(victim)
  if not asc then return nil, "no ability system" end
  local sets = U.arrayObjects(U.try("kill.sets", function() return asc.SpawnedAttributes end))
  if #sets == 0 then return nil, "no attribute sets" end
  local wanted = S.cfg.Kill.HealthNames or { "Health", "HP", "Hp" }
  for _, set in ipairs(sets) do
    local cls = U.className(set)
    local name = K.setProps[cls]
    if name == nil then
      local names = attributeNames(set)
      name = pickHealth(names, wanted) or false
      K.setProps[cls] = name
      if not K.logged[cls] and #names > 0 then
        K.logged[cls] = true
        local vals = {}
        for i, n in ipairs(names) do
          if i > 24 then break end
          local v = current(set, n)
          vals[#vals + 1] = v and string.format("%s=%.0f", n, v) or n
        end
        U.log("kill: %s attributes: %s; health read from %s", cls, table.concat(vals, " "), tostring(name or "none"))
      end
    end
    if name then
      local v = current(set, name)
      if v then
        -- (Touched too, so that the pruning forgets it with the enemy's other entries.)
        if key then K.healthAt[key], K.touched[key] = { set = set, name = name, where = cls .. "." .. name }, U.frame end
        return v, cls .. "." .. name
      end
    end
  end
  return nil, "no health attribute among " .. #sets .. " attribute set(s)"
end

-- At the struck enemy's own slomo call (hf_freeze, before it runs): true when this hit already took its health to zero,
-- so the killing blow can hold longer. Whether the damage has landed by then shows in the kill lines of the log.
function K.atLookup(owner)
  local k = S.cfg.Kill
  if not (k and k.Enabled) or (k.HoldFrames or 0) <= 0 then return false end
  local key = U.addr(owner)
  if not key then return false end
  local hp = K.health(owner)
  K.lookup[key], K.touched[key] = hp, U.frame
  local floor, prev = k.DeadAtOrBelow or 0, K.hp[key]
  local killing = hp ~= nil and hp <= floor and (prev == nil or prev > floor)
  K.held[key] = killing or nil
  return killing
end

local function accent(ctx, why)
  local k = S.cfg.Kill
  K.kills = K.kills + 1
  if K.kills <= 3 then U.log("kill: %s died from your hit (%s)", U.fname(ctx.victim), why) end
  U.crumb("kill %s", U.className(ctx.victim))
  if S.screen then U.try("kill.screen", S.screen.pulse, k.Screen or 0) end
  if S.camera and S.camera.kill then U.try("kill.camera", S.camera.kill, ctx, k) end
  local r = S.cfg.Rumble
  if S.rumble and r.Enabled then
    local p = k.Rumble or {}
    U.try("kill.body", S.rumble.play, math.min(1, (p.Body or 0) * r.Scale), p.BodyMs or 0, true, false)
    U.try("kill.edge", S.rumble.play, math.min(1, (p.Edge or 0) * r.Scale), p.EdgeMs or 0, false, true)
  end
end

-- An enemy seen dead keeps that for 10 s (a freed one's address can come back as a new enemy), and one whose health
-- was already at zero at an earlier check died from an earlier blow. The health at the lookup (K.atLookup) and when
-- the hit was dispatched (`before`) are only logged: the second session's log had the damage in by the dispatch.
local function check(ctx, before)
  local k, victim = S.cfg.Kill, ctx.victim
  local key, now = U.addr(victim), U.now()
  if not key or (K.dead[key] and now - K.dead[key] < 10) or not U.valid(victim) then return end
  local hp, where = K.health(victim)
  K.checks = K.checks + 1
  if not hp then
    if not K.warned then
      K.warned = true
      U.log("kill: the enemy's health cannot be read (%s); no kill accent", tostring(where))
    end
    return
  end
  local floor, prev = k.DeadAtOrBelow or 0, K.hp[key]
  K.hp[key], K.touched[key] = hp, U.frame
  local dead = hp <= floor and (prev == nil or prev > floor)
  local atLookup = K.lookup[key]
  if K.checks <= (k.LogChecks or 12) then
    U.log("kill check %d: %s health %s at the lookup, %s at the dispatch, %.0f %d frames later (%s)%s", K.checks,
      U.fname(victim), atLookup and string.format("%.0f", atLookup) or "?", before and string.format("%.0f", before) or "?",
      hp, k.CheckAfterFrames or 3, where, dead and " -> dead" or "")
  end
  if dead then
    K.dead[key] = now
    accent(ctx, string.format("health %.0f; %s", hp, K.held[key] and "held longer as the killing blow"
      or ("health at the lookup " .. (atLookup and string.format("%.0f", atLookup) or "?") .. ", so no longer hold")))
  end
  K.held[key] = nil
end

function K.onHit(ctx)
  local k = S.cfg.Kill
  if not (k and k.Enabled) or ctx.kind ~= "hit" or not ctx.byPlayer or not ctx.victim or ctx.duplicate then return end
  -- (The health at the dispatch is only for the first checks' log lines.)
  local before = K.checks < (k.LogChecks or 12) and U.try("kill.before", K.health, ctx.victim) or nil
  U.afterFrames(math.max(1, k.CheckAfterFrames or 3), function() U.try("kill.check", check, ctx, before) end)
end

-- An enemy not struck for about a minute is forgotten, and a dead mark goes after its 10 s: its address may come back
-- as a new enemy, which must start with no health on record. hf_perf calls this every few seconds.
function K.prune(now)
  for key, frame in pairs(K.touched) do
    if U.frame - frame > 3600 then
      K.touched[key], K.hp[key], K.lookup[key], K.held[key], K.healthAt[key] = nil, nil, nil, nil, nil
    end
  end
  -- (A health location whose attribute set is gone: its enemy was freed, and the address may come back as another.)
  for key, at in pairs(K.healthAt) do
    if not U.valid(at.set) then K.healthAt[key] = nil end
  end
  for key, at in pairs(K.dead) do
    if now - at >= 10 then K.dead[key] = nil end
  end
end

function K.stats() return string.format("checks=%d kills=%d", K.checks, K.kills) end

return K
