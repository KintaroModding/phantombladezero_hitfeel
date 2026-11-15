-- PBZ HitFeel: performance numbers for the log. A "perf" line every Diagnostics.PerfEverySec seconds of play that had
-- fighting in it, and whenever the mod goes off or on (Ctrl+F7, the panel's switch, its 10 s vanilla trial): the frame
-- rate while fighting (the 3 s after any hit or parry of yours) and while calm, how slow the slowest 1% of frames
-- were, the mod's own time on the game thread (a frame, a hit, the largest parts), its Lua memory, its effects (how
-- many at once, how long each lasted, how many its budget ended) and how many of others' blows it left alone. The same
-- fight with the mod on and then off shows the mod's share of a drop in frame rate. Off, its hooks still look at each
-- hit, so "off" is close to the game alone but not quite.
-- Also the upkeep that runs on the clock: the effect budget's sweep, and every few seconds each module's prune of
-- what it keeps per enemy, so nothing the mod keeps grows with the length of a session.
local P = { name = "perf" }
local S, U

local FIGHT_SEC = 3
-- Frame times are counted in 0.5 ms steps up to 200 ms; slower frames count as 200.
local BUCKET_MS, BUCKETS = 0.5, 400
-- A window shorter than this, or with less fighting, is not written.
local MIN_MS, MIN_FIGHT_MS = 5000, 2000

local function group() return { n = 0, ms = 0, work = 0, hist = {} } end

local function newWindow()
  return { on = S.cfg.Enabled == true, ms = 0, fight = group(), calm = group(), hits = 0, others = 0, crowd = 0, features = {},
    spawned = 0, maxAlive = 0, gone = 0, lifeMs = 0, lifeMax = 0, cut = 0, aged = 0 }
end

function P.init(state)
  S, U = state, state.U
  P.w = newWindow()
  U.cost.by = {}
  P.lastCost = U.cost.ms
  U.onFrame = function(dt, t)
    if S.perf then U.try("perf", S.perf.frame, dt, t) end
  end
end

-- Mod off, a reload: the window so far is written.
function P.release() P.close() end

-- From the hit bus, for every hit and parry you are in, mod on or off.
function P.fight(ctx)
  P.fightAt = ctx.time
  if P.w then P.w.hits = P.w.hits + 1 end
end

-- From the hit bus: a hit or clash between others, left alone.
function P.other()
  if P.w then P.w.others = P.w.others + 1 end
end

-- From the hit bus: one of your hits past Hit.MaxFullPerFrame in its frame, given its hit stop only.
function P.crowd()
  if P.w then P.w.crowd = P.w.crowd + 1 end
end

-- From the hit bus: one feature's handling of one hit, in ms.
function P.feature(name, ms)
  local w = P.w
  if w then w.features[name] = (w.features[name] or 0) + ms end
end

-- From hf_vfx: one of our effects started (`alive` now playing), or ended: finished, "cut" by the budget, or "aged"
-- past Vfx.KillAfterMs.
function P.spawned(alive)
  local w = P.w
  if not w then return end
  w.spawned = w.spawned + 1
  if alive > w.maxAlive then w.maxAlive = alive end
end

function P.gone(sec, how)
  local w = P.w
  if not w then return end
  w.gone, w.lifeMs = w.gone + 1, w.lifeMs + sec * 1000
  if sec * 1000 > w.lifeMax then w.lifeMax = sec * 1000 end
  if how == "cut" then w.cut = w.cut + 1 elseif how == "aged" then w.aged = w.aged + 1 end
end

-- Every frame, from the clock (U.onFrame): its length in ms and the mod's time (U.now; nil before there is a world).
function P.frame(dt, t)
  if U.frame % 10 == 0 and S.vfx and S.vfx.sweep then U.try("vfx.sweep", S.vfx.sweep, t) end
  if U.frame % 600 == 0 and t then
    if S.hit and S.hit.prune then U.try("hit.prune", S.hit.prune, t) end
    for _, m in ipairs(S.features or {}) do
      if m.prune then U.try(m.name .. ".prune", m.prune, t) end
    end
  end
  local cost = U.cost.ms
  local work = cost - (P.lastCost or cost)
  P.lastCost = cost
  local d = S.cfg.Diagnostics or {}
  if not d.Perf then return end
  local w = P.w
  if (S.cfg.Enabled == true) ~= w.on then
    P.close()
    w = P.w
  end
  -- (No time: no player yet. Over a second: a loading screen.)
  if not dt or dt <= 0 or dt > 1000 then return end
  local g = (P.fightAt and t and t - P.fightAt <= FIGHT_SEC) and w.fight or w.calm
  g.n, g.ms, g.work = g.n + 1, g.ms + dt, g.work + work
  local b = math.min(BUCKETS, math.floor(dt / BUCKET_MS) + 1)
  g.hist[b] = (g.hist[b] or 0) + 1
  w.ms = w.ms + dt
  if w.ms >= (tonumber(d.PerfEverySec) or 60) * 1000 then P.close() end
end

local function fps(g) return g.ms > 0 and g.n * 1000 / g.ms or 0 end

-- The frame time the slowest `share` of frames reach (the bucket's upper end).
local function slowest(g, share)
  local need, seen = math.max(1, math.floor(g.n * share + 0.5)), 0
  for b = BUCKETS, 1, -1 do
    seen = seen + (g.hist[b] or 0)
    if seen >= need then return b * BUCKET_MS end
  end
  return 0
end

-- The `n` largest entries of a name -> ms table, each divided by `per`, as "name 0.12".
local function largest(t, n, per, prefix)
  local list = {}
  for k, v in pairs(t) do list[#list + 1] = { (k:gsub(prefix or "^$", "")), v } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = string.format("%s %.2f", list[i][1], list[i][2] / per) end
  return table.concat(out, ", ")
end

function P.close()
  local w, by = P.w, U.cost.by
  P.w, U.cost.by = newWindow(), {}
  if not w or w.ms < MIN_MS or w.fight.ms < MIN_FIGHT_MS then return end
  local f, c = w.fight, w.calm
  local frames = f.n + c.n
  local parts = { string.format("perf (mod %s, %.0f s): fighting %.0f s at %.0f fps, slowest 1%% of frames %.1f ms",
    w.on and "on" or "off", w.ms / 1000, f.ms / 1000, fps(f), slowest(f, 0.01)) }
  if c.n > 0 then
    parts[#parts + 1] = string.format("; calm %.0f s at %.0f fps, slowest 1%% %.1f ms", c.ms / 1000, fps(c), slowest(c, 0.01))
  end
  parts[#parts + 1] = string.format(" | the mod's own time: %.2f ms a frame fighting, %.2f calm", f.work / math.max(1, f.n),
    c.work / math.max(1, c.n))
  if w.hits > 0 then
    -- What fighting cost beyond the calm frames' share, spread over the hits.
    local extra = c.n > 0 and (f.work - c.work / c.n * f.n) or f.work
    parts[#parts + 1] = string.format("; %d hits and parries, about %.1f ms each", w.hits, math.max(0, extra) / w.hits)
    if next(w.features) then parts[#parts + 1] = " (handling one: " .. largest(w.features, 4, w.hits) .. ")" end
  end
  parts[#parts + 1] = "; most of it, ms a frame: " .. largest(by, 4, math.max(1, frames), "^hook ")
  parts[#parts + 1] = string.format("; Lua memory %.1f MB", collectgarbage("count") / 1024)
  if w.spawned > 0 or w.gone > 0 then
    parts[#parts + 1] = string.format(" | its effects: %d started, at most %d at once, %.1f s each (longest %.1f s), %d ended by the budget%s",
      w.spawned, w.maxAlive, w.gone > 0 and w.lifeMs / w.gone / 1000 or 0, w.lifeMax / 1000, w.cut,
      w.aged > 0 and string.format(", %d past Vfx.KillAfterMs", w.aged) or "")
  end
  if w.crowd > 0 then
    parts[#parts + 1] = string.format(" | %d hits in a crowd given their hit stop only (Hit.MaxFullPerFrame)", w.crowd)
  end
  if w.others > 0 then
    parts[#parts + 1] = string.format(" | %d blows and clashes not yours, left alone", w.others)
  end
  U.log("%s", table.concat(parts))
end

function P.stats()
  return string.format("modMs=%.0f window=%.0fs", U.cost.ms, P.w and P.w.ms / 1000 or 0)
end

return P
