-- PBZ HitFeel: shared helpers (logging, safe calls, UObject and reflection utilities, scheduling, vector math).
-- Reloaded like every script but main.lua (the kernel): a fresh copy takes over the running one's open logs, frame
-- clock, mod time and counts as it loads (U.handover, at the end of this file), and the old copy then answers with
-- the new one's functions, so nothing that kept a reference to it (a hook, a delayed action) is left behind.
local UEH = require("UEHelpers")
-- The kernel's table (main.lua): the session loops and, during a reload, the copy of this file that is running.
local RT = rawget(_G, "PBZHitFeel_RT")

local U = {}

local function dirOf(path) return path:match("^(.*)[/\\][^/\\]*$") end
local src = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):gsub("\\", "/")
U.scriptsDir = dirOf(src) or "."
U.root = dirOf(U.scriptsDir) or "."
U.logDir = U.root .. "/logs"
U.modName = "PBZHitFeel"
U.version = "?"
U.maxLines = 30000

-- ---------------------------------------------------------------- logging

-- The open log files, their line counts and the ones not yet flushed. A reload hands them on: opening a log again
-- would start it over, empty, in the middle of a session.
local logs = { files = {}, counts = {}, dirty = {} }

-- Keeps the previous session's file as *.prev.txt so one restart does not lose it.
function U.open(name)
  local f = logs.files[name]
  if f ~= nil then return f end
  local path = U.logDir .. "/" .. name
  local prev = path:gsub("%.(%w+)$", ".prev.%1")
  os.remove(prev)
  os.rename(path, prev)
  f = io.open(path, "w")
  logs.files[name] = f or false
  logs.counts[name] = 0
  return f
end

-- The main log goes to disk at once (it is what is left after a crash); the probe files every couple of seconds
-- (U.flushLogs from the clock): a flush per line was a disk write on the game thread with every hit.
function U.write(name, text)
  local f = U.open(name)
  if not f or logs.counts[name] > U.maxLines then return end
  f:write(text, "\n")
  logs.counts[name] = logs.counts[name] + 1
  if name == "hitfeel.log" then f:flush() else logs.dirty[name] = f end
end

function U.flushLogs()
  for name, f in pairs(logs.dirty) do
    pcall(f.flush, f)
    logs.dirty[name] = nil
  end
end

function U.log(fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  if not ok then msg = tostring(fmt) end
  print(string.format("[%s] %s\n", U.modName, msg))
  U.write("hitfeel.log", os.date("%H:%M:%S ") .. msg)
end

U.errors = {}

-- pcall wrapper: logs the first few errors per tag, then every 200th.
function U.try(tag, fn, ...)
  local res = table.pack(pcall(fn, ...))
  if not res[1] then
    local n = (U.errors[tag] or 0) + 1
    U.errors[tag] = n
    if n <= 5 or n % 200 == 0 then U.log("ERROR [%s] #%d: %s", tag, n, tostring(res[2])) end
    return nil
  end
  return table.unpack(res, 2, res.n)
end

-- ---------------------------------------------------------------- the mod's own time
-- The mod's time on the game thread, for the perf log (hf_perf): the frame loops, the scheduled callbacks and the hook
-- callbacks are timed with os.clock, by source. Its steps are whole milliseconds on Windows, so one call mostly reads
-- 0 or 1 ms; summed over thousands of calls the total comes out right. A timing inside another counts once, for the
-- outer one.
U.cost = { ms = 0, depth = 0, by = {} }

function U.costBegin()
  local c = U.cost
  c.depth = c.depth + 1
  if c.depth == 1 then c.t0 = os.clock() end
end

function U.costEnd(src)
  local c = U.cost
  c.depth = c.depth - 1
  if c.depth > 0 then return end
  c.depth = 0
  local ms = (os.clock() - c.t0) * 1000
  c.ms = c.ms + ms
  c.by[src] = (c.by[src] or 0) + ms
end

-- ---------------------------------------------------------------- scheduling (game thread)

-- Frame-based scheduling when UE4SS has the EngineTick hook and its frame functions (hf_env sets U.frameApi from what
-- the running UE4SS has), otherwise ~60 Hz timers.
local function frames()
  if U.frameApi ~= nil then return U.frameApi end
  return EngineTickAvailable == true
end

-- `src` names it in the perf log.
function U.afterFrames(n, fn, src)
  local function run()
    U.costBegin()
    local ok, err = pcall(fn)
    U.costEnd(src or "callbacks")
    if not ok then error(err, 0) end
  end
  if frames() then return ExecuteInGameThreadAfterFrames(math.max(1, n), run) end
  return ExecuteInGameThreadWithDelay(math.max(1, n) * 16, run)
end

-- Loops that run for the whole session (the clock, the hotkeys, the blade tips, the hook retries, the preloader's
-- watch), one per name, kept by the kernel: starting one under a name already running ends the old one first, so a
-- reload never leaves two of them, or one running old code. fn returns true to end it. With `everyMs` it runs on a
-- timer instead of every frame.
local loops = RT and RT.loops or {}
if RT then RT.loops = loops end

local function startLoop(name, step, everyMs)
  U.stopLoop(name)
  if everyMs then
    loops[name] = LoopInGameThreadWithDelay(everyMs, step)
  elseif frames() then
    loops[name] = LoopInGameThreadAfterFrames(1, step)
  else
    loops[name] = LoopInGameThreadWithDelay(16, step)
  end
  return loops[name]
end

function U.loop(name, fn, everyMs)
  local function step()
    U.costBegin()
    local ok, done = pcall(fn)
    U.costEnd(name)
    if not ok then
      U.try(name, error, done)
      done = true
    end
    if done and loops[name] then U.stopLoop(name) end
  end
  return startLoop(name, step, everyMs)
end

function U.stopLoop(name)
  local h = loops[name]
  loops[name] = nil
  if h then pcall(CancelDelayedAction, h) end
end

function U.looping(name) return loops[name] ~= nil end

-- Calls fn once per frame until it returns true.
function U.everyFrame(tag, fn)
  local st = {}
  local function step()
    U.costBegin()
    local ok, done = pcall(fn)
    U.costEnd(tag)
    if not ok then
      U.try(tag, error, done)
      done = true
    end
    if done then CancelDelayedAction(st.handle) end
  end
  if frames() then
    st.handle = LoopInGameThreadAfterFrames(1, step)
  else
    st.handle = LoopInGameThreadWithDelay(16, step)
  end
  return st.handle
end

-- Frame clock. The game's slomo counts frames, not time (3 frames are 33 ms at 90 fps), so frame counts from
-- config.lua (60 fps frames) are converted with the measured frame time.
U.frame, U.frameMs = 0, 1000 / 60

-- ---------------------------------------------------------------- hitches
-- What the mod did in the last frames (asset loads, first spawns, physics switches, scans), so that a frame which
-- took far longer than usual can be told apart: one of ours, or the game's own (loading, garbage collection,
-- shaders) when no note is there. U.hitchMs (from config) is the threshold; 0 = off.
U.notes, U.hitches = {}, 0

function U.note(fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  local n = U.notes
  n[#n + 1] = { frame = U.frame, what = ok and msg or tostring(fmt) }
  if #n > 24 then table.remove(n, 1) end
  U.crumb("%s", ok and msg or tostring(fmt))
end

-- The mod's last actions (your hits and clashes with the struck material, the effects it spawned, kills, guard breaks,
-- loads, reloads, updates) in logs/recent.txt, each line written and flushed as it happens: after a native crash the
-- file ends with what the mod did last, which UE4SS.log does not show (most of these are not logged). A short line is
-- one small write, with the file kept open. Every 400 lines it starts over from the last 40; the previous session's
-- file is kept as recent.prev.txt (U.open).
local crumbs = { list = {}, lines = 0 }
function U.crumb(fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  local line = string.format("%s f%d %s", os.date("%H:%M:%S"), U.frame, ok and msg or tostring(fmt))
  local l = crumbs.list
  l[#l + 1] = line
  if #l > 40 then table.remove(l, 1) end
  local f = U.open("recent.txt")
  if not f then return end
  if crumbs.lines == 0 or crumbs.lines >= 400 then
    if crumbs.lines > 0 then
      pcall(f.close, f)
      f = io.open(U.logDir .. "/recent.txt", "w")
      logs.files["recent.txt"] = f or false
      if not f then return end
    end
    f:write("PBZHitFeel ", tostring(U.version), ": the mod's last actions, newest last (f = frame)\n")
    for i = 1, #l - 1 do f:write(l[i], "\n") end
    crumbs.lines = #l - 1
  end
  f:write(line, "\n")
  f:flush()
  crumbs.lines = crumbs.lines + 1
end

-- `mine`: the mod's own code in that frame, ms (U.cost, os.clock in 1 ms steps), when known.
function U.hitch(ms, mine)
  U.hitches = U.hitches + 1
  if U.hitches > (U.maxHitchLogs or 30) and U.hitches % 50 ~= 0 then return end
  local recent = {}
  for _, e in ipairs(U.notes) do
    if e.frame >= U.frame - 2 then recent[#recent + 1] = e.what end
  end
  U.log("hitch #%d: one frame took %.0f ms (usual %.1f ms%s); the mod just before: %s", U.hitches, ms, U.frameMs,
    mine and string.format("; the mod's own code %.0f ms of it", mine) or "",
    #recent > 0 and table.concat(recent, "; ") or "nothing of note (the game's own: loading, garbage collection, shaders)")
end

-- U.onFrame(dt, t), set by hf_perf, gets every frame's length in ms (nil when unknown) and the mod's time (U.now).
-- A session loop: started again by a reload, it replaces the old copy's.
function U.startClock()
  local last, lastCost
  local function tick()
    U.frame = U.frame + 1
    local t = U.realTime()
    local dt
    -- (The mod's own time since the last tick: all it did in the frame that just ended.)
    local mine = lastCost and U.cost.ms - lastCost or nil
    lastCost = U.cost.ms
    if t and last and t > last then
      dt = (t - last) * 1000
      if dt > 2 and dt < 100 then U.frameMs = U.frameMs + (dt - U.frameMs) * 0.05 end
      if (U.hitchMs or 0) > 0 and dt >= U.hitchMs and dt >= U.frameMs * 4 and dt < 5000 then U.hitch(dt, mine) end
    end
    last = t
    -- (The frame's time, for loops that run every frame: U.now() asks the engine each time.)
    U.frameNow = t and U.timeline(t) or os.clock()
    if U.onFrame then U.onFrame(dt, t and U.frameNow) end
    if U.frame % 120 == 0 then U.flushLogs() end
  end
  local function step()
    -- Nothing else runs between frames: a timing left open by an error elsewhere ends here.
    U.cost.depth = 0
    U.costBegin()
    local ok, err = pcall(tick)
    U.costEnd("clock")
    if not ok then U.try("clock", error, err) end
  end
  startLoop("clock", step)
end

-- 60 fps frames to frames at the current frame rate (at least 1 for any positive count).
function U.gameFrames(frames60)
  if type(frames60) ~= "number" or frames60 <= 0 then return 0 end
  return math.max(1, math.floor(frames60 * (1000 / 60) / U.frameMs + 0.5))
end

-- ---------------------------------------------------------------- objects

function U.valid(o)
  if o == nil then return false end
  local ok, v = pcall(function() return o:IsValid() end)
  return ok and v == true
end

function U.fullName(o)
  local ok, s = pcall(function() return o:GetFullName() end)
  return ok and s or "?"
end

function U.fname(o)
  local ok, s = pcall(function() return o:GetFName():ToString() end)
  return ok and s or "?"
end

function U.className(o)
  local ok, s = pcall(function() return o:GetClass():GetFName():ToString() end)
  return ok and s or "?"
end

function U.addr(o)
  local ok, a = pcall(function() return o:GetAddress() end)
  return ok and a or nil
end

function U.same(a, b)
  local x, y = U.addr(a), U.addr(b)
  return x ~= nil and x == y
end

local chainCache = {}

-- Names of a UStruct/UClass and all of its supers. Only a chain read whole is kept for its class: one that came out
-- empty, has a name that could not be read or broke off is read again next time. (Up to v0.7.1 any chain was kept, so
-- one bad read stood for that class for the rest of the session.)
function U.superChain(cls)
  local key = U.addr(cls)
  if key and chainCache[key] then return chainCache[key] end
  local names, c, guard, whole = {}, cls, 0, true
  while U.valid(c) and guard < 48 do
    local n = U.fname(c)
    if n == "?" then
      whole = false
      break
    end
    names[#names + 1] = n
    local ok, s = pcall(function() return c:GetSuperStruct() end)
    if not ok then
      whole = false
      break
    end
    c, guard = s, guard + 1
  end
  if key and whole and #names > 0 and guard < 48 then chainCache[key] = names end
  return names
end

function U.classChain(o)
  local ok, c = pcall(function() return o:GetClass() end)
  if not ok then return {} end
  return U.superChain(c)
end

function U.chainHas(chain, name)
  for _, n in ipairs(chain) do
    if n == name then return true end
  end
  return false
end

function U.isA(o, name) return U.chainHas(U.classChain(o), name) end

local cdoCache = {}

function U.cdo(path)
  local o = cdoCache[path]
  if U.valid(o) then return o end
  o = StaticFindObject(path)
  if U.valid(o) then
    cdoCache[path] = o
    return o
  end
  return nil
end

-- The player controller, found once and reused while it stays valid: UEHelpers.GetPlayerController() runs FindAllOf
-- over every object on each call, and the per-frame code (clock, hotkeys, blade tips, model shake) asks several times
-- a frame. While there is none (loading), it is looked for at most twice a second. Its class is checked once a frame
-- (a freed controller's address can come back as another object), IsValid on every ask; the pawn is read once a frame
-- the same way. (An ask was five engine calls, and the clock, the hotkeys, the blade tips and every hook asked.)
local pcCache, pcRetryAt, pcFrame = nil, 0, -1
local pawnCache, pawnFrame = nil, -1

function U.pc()
  if pcCache then
    if U.valid(pcCache) and (pcFrame == U.frame or U.isA(pcCache, "PlayerController")) then
      pcFrame = U.frame
      return pcCache
    end
    pcCache, pawnCache = nil, nil
  end
  local t = os.clock()
  if t < pcRetryAt then return nil end
  pcRetryAt = t + 0.5
  local ok, pc = pcall(UEH.GetPlayerController)
  if ok and U.valid(pc) then
    pcCache, pcFrame = pc, U.frame
    return pc
  end
  return nil
end

function U.player()
  if pawnCache and pawnFrame == U.frame and U.valid(pawnCache) then return pawnCache end
  pawnCache = nil
  local pc = U.pc()
  if not pc then return nil end
  local ok, p = pcall(function() return pc.Pawn end)
  if ok and U.valid(p) then
    pawnCache, pawnFrame = p, U.frame
    return p
  end
  return nil
end

function U.pcm()
  local pc = U.pc()
  if not pc then return nil end
  local ok, m = pcall(function() return pc.PlayerCameraManager end)
  if ok and U.valid(m) then return m end
  return nil
end

function U.engine()
  local ok, e = pcall(UEH.GetEngine)
  if ok and U.valid(e) then return e end
  return nil
end

-- The world's real (undilated) seconds, nil before a player exists. Constant within one frame.
function U.realTime()
  local gs, p = U.cdo("/Script/Engine.Default__GameplayStatics"), U.player()
  if gs and p then
    local ok, t = pcall(function() return gs:GetRealTimeSeconds(p) end)
    if ok and type(t) == "number" then return t end
  end
  return nil
end

-- Real (undilated) seconds, so cooldowns are not stretched by our own freeze.
-- The mod's time. The world's real time is the same for every call within a frame (the hit bus groups events by it),
-- but it starts again at 0 in every new world (another map, a save loaded), and times kept from the old world then
-- lay in the future. Until the new world's clock caught up (as long as the old one had lasted): an enemy given an old
-- one's address had its hits taken for repeats, the camera's and the screen's gaps and the trails' spacing never ran
-- out, the hold allowance stayed used up, and every hit got the rhythm's last mark from before the load. So the mod's
-- time runs on across worlds: a new one starts a minute after the old one ended, past every gap kept from it. (The
-- v0.7.0 log had two of these resets in one evening.) A reload hands the offset on, or every time kept would jump.
local world = { base = 0, last = nil }
function U.timeline(t)
  if world.last and t < world.last - 0.5 then world.base = world.base + world.last - t + 60 end
  world.last = t
  return t + world.base
end

function U.now()
  local t = U.realTime()
  return t and U.timeline(t) or os.clock()
end

-- How strongly this hit lands in its rhythm (hf_rhythm): below 1 for quick light hits deep in a string, above 1 for
-- accents, 1 for everything else.
function U.emph(ctx)
  return ctx and ctx.rhythm and ctx.rhythm.emph or 1
end

-- Valid objects held in a reflected array (e.g. Actor.Children, SceneComponent.AttachChildren).
function U.arrayObjects(arr, limit)
  local out = {}
  if arr == nil then return out end
  pcall(function()
    arr:ForEach(function(_, e)
      if #out >= (limit or 64) then return true end
      local v = e:get()
      if U.valid(v) then out[#out + 1] = v end
    end)
  end)
  return out
end

-- Scene components attached below `root`, breadth first, read from the reflected AttachChildren arrays
-- (K2_GetComponentsByClass returns nothing iterable in this build). Includes weapons attached to the mesh.
function U.attachTree(root, limit)
  limit = limit or 96
  local out, queue, seen, head = {}, { root }, {}, 1
  while queue[head] ~= nil and #out < limit do
    local c = queue[head]
    head = head + 1
    local key = U.addr(c)
    if key and not seen[key] and U.valid(c) then
      seen[key] = true
      out[#out + 1] = c
      local kids = U.try("util.attach", function() return c.AttachChildren end)
      for _, k in ipairs(U.arrayObjects(kids, 64)) do queue[#queue + 1] = k end
    end
  end
  return out
end

-- Reads the first readable numeric property, then the first numeric getter.
function U.readNumber(obj, propNames, fnNames)
  for _, n in ipairs(propNames or {}) do
    local ok, v = pcall(function() return obj[n] end)
    if ok and type(v) == "number" then return v, n end
  end
  for _, n in ipairs(fnNames or {}) do
    local ok, v = pcall(function() return obj[n](obj) end)
    if ok and type(v) == "number" then return v, n .. "()" end
  end
  return nil
end

-- ---------------------------------------------------------------- reflection

function U.propName(p)
  local ok, s = pcall(function() return p:GetFName():ToString() end)
  return ok and s or "?"
end

function U.propType(p)
  local ok, s = pcall(function() return p:GetClass():GetFName():ToString() end)
  return ok and s or "?"
end

function U.structOf(p)
  local ok, s = pcall(function() return p:GetStruct() end)
  if ok and U.valid(s) then return s end
end

function U.objClassOf(p)
  local ok, c = pcall(function() return p:GetPropertyClass() end)
  if ok and U.valid(c) then return c end
end

function U.innerOf(p)
  local ok, i = pcall(function() return p:GetInner() end)
  if ok and i then return i end
end

function U.enumOf(p)
  local ok, e = pcall(function() return p:GetEnum() end)
  if ok and U.valid(e) then return e end
end

function U.props(struct)
  local list = {}
  pcall(function()
    struct:ForEachProperty(function(p)
      list[#list + 1] = p
    end)
  end)
  return list
end

function U.funcs(cls)
  local list = {}
  pcall(function()
    cls:ForEachFunction(function(f)
      list[#list + 1] = f
    end)
  end)
  return list
end

-- Field descriptor: name, type and the nested type info the walker needs.
function U.desc(p)
  local d = { prop = p, name = U.propName(p), type = U.propType(p) }
  if d.type == "StructProperty" then
    d.struct = U.structOf(p)
    d.sname = d.struct and U.fname(d.struct) or "?"
  elseif d.type == "ArrayProperty" then
    local i = U.innerOf(p)
    d.inner = i and U.desc(i)
  elseif d.type == "EnumProperty" or d.type == "ByteProperty" then
    local e = U.enumOf(p)
    d.enum = e and U.fname(e)
  elseif d.type:find("ObjectProperty") or d.type:find("ClassProperty") then
    local c = U.objClassOf(p)
    d.cname = c and U.fname(c)
  end
  return d
end

local fieldCache = {}

-- Own fields of a struct/class (no supers), cached by address.
function U.fields(struct)
  local key = U.addr(struct)
  if key and fieldCache[key] then return fieldCache[key] end
  local list = {}
  for _, p in ipairs(U.props(struct)) do list[#list + 1] = U.desc(p) end
  if key then fieldCache[key] = list end
  return list
end

function U.typeDesc(d)
  if d.sname then return d.type .. "<" .. d.sname .. ">" end
  if d.inner then return d.type .. "<" .. U.typeDesc(d.inner) .. ">" end
  if d.enum then return d.type .. "<" .. d.enum .. ">" end
  if d.cname then return d.type .. "<" .. d.cname .. ">" end
  return d.type
end

local fnMeta = {}

-- Parameter descriptors of a native UFunction, cached by path.
function U.fnParams(fnPath)
  local m = fnMeta[fnPath]
  if m ~= nil then return m or nil end
  local fn = StaticFindObject(fnPath)
  if not U.valid(fn) then
    fnMeta[fnPath] = false
    return nil
  end
  m = U.fields(fn)
  fnMeta[fnPath] = m
  return m
end

local function defaultArg(t)
  if t == "StructProperty" or t == "ArrayProperty" then return {} end
  if t == "BoolProperty" then return false end
  if t == "NameProperty" then return FName("None") end
  if t == "StrProperty" then return "" end
  if t:find("Object") or t:find("Class") or t:find("Interface") then return nil end
  return 0
end

-- Calls a UFunction with arguments given by parameter name, so signature differences between
-- engine/plugin versions (extra or reordered params) do not shift positional arguments.
-- Names match case-insensitively: this build has e.g. `duration` and `orientation` in lower case.
function U.callNamed(target, fnPath, named)
  local meta = U.fnParams(fnPath)
  if not meta then error("function not found: " .. fnPath) end
  local lower = {}
  for k, v in pairs(named) do lower[k:lower()] = v end
  local fnName = fnPath:match(":([^:]+)$")
  local args, n = {}, 0
  for _, d in ipairs(meta) do
    if d.name == "ReturnValue" then break end
    n = n + 1
    local v = lower[d.name:lower()]
    if v == nil then v = defaultArg(d.type) end
    args[n] = v
  end
  return target[fnName](target, table.unpack(args, 1, n))
end

-- Reads only the named hook parameters. Native pre-hooks hand over return values and pure out
-- parameters before the engine has written them; turning such garbage into a UObject crashes UE4SS
-- natively (pcall cannot catch it), so every hook in this mod reads through an explicit whitelist.
function U.readParams(args, descs, wanted)
  local out = {}
  for i = 1, args.n do
    local d = descs[i]
    if d and wanted[d.name] then
      local ok, v = pcall(function() return args[i]:get() end)
      if ok then out[d.name] = v end
    end
  end
  return out
end

function U.tagName(tag)
  local ok, s = pcall(function() return tag.TagName:ToString() end)
  return ok and s or nil
end

function U.containerTags(c)
  local out = {}
  pcall(function()
    c.GameplayTags:ForEach(function(_, elem)
      local s = U.tagName(elem:get())
      if s then out[#out + 1] = s end
    end)
  end)
  return out
end

U.ASC_LIB = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
U.GET_ASC = "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:GetAbilitySystemComponent"

-- An actor's ability system (the game keeps endure levels and character state tags there), or nil.
function U.asc(actor)
  if not U.valid(actor) then return nil end
  local lib = U.cdo(U.ASC_LIB)
  if not lib then return nil end
  local ok, asc = pcall(U.callNamed, lib, U.GET_ASC, { Actor = actor })
  return ok and U.valid(asc) and asc or nil
end

-- The gameplay tags an actor's ability system owns, as names; nil and why when they cannot be read.
function U.ownedTags(actor)
  local asc = U.asc(actor)
  if not asc then return nil, "no ability system" end
  for _, fn in ipairs({ "GetOwnedGameplayTags", "K2_GetOwnedGameplayTags" }) do
    local ok, c = pcall(function() return asc[fn](asc) end)
    if ok and c ~= nil then return U.containerTags(c) end
  end
  return nil, "GetOwnedGameplayTags cannot be called"
end

local VECTOR_STRUCTS = { Vector = true, Vector3d = true, Vector3f = true, Vector_NetQuantize = true,
  Vector_NetQuantize10 = true, Vector_NetQuantize100 = true, Vector_NetQuantizeNormal = true }

-- Walks a reflected value (descriptor d) and reports leaves to visit(kind, path, value, d, extra).
function U.walk(v, d, depth, path, visit)
  local t = d.type
  if t == "StructProperty" then
    local sname = d.sname or "?"
    if sname == "GameplayTag" then return visit("tag", path, U.tagName(v), d) end
    if sname == "GameplayTagContainer" then return visit("tags", path, U.containerTags(v), d) end
    if VECTOR_STRUCTS[sname] then return visit("vector", path, U.copyv(v), d, sname) end
    if sname == "Rotator" or sname == "Rotator3d" then return visit("rotator", path, U.copyr(v), d) end
    visit("struct", path, v, d, sname)
    if depth <= 0 or not d.struct then return end
    for _, fd in ipairs(U.fields(d.struct)) do
      local ok, fv = pcall(function() return v[fd.name] end)
      if ok then
        U.walk(fv, fd, depth - 1, path .. "." .. fd.name, visit)
      else
        visit("error", path .. "." .. fd.name, nil, fd)
      end
    end
  elseif t == "ArrayProperty" then
    local n = 0
    pcall(function() n = v:GetArrayNum() end)
    visit("array", path, n, d, d.inner and U.typeDesc(d.inner) or "?")
    if depth <= 0 or not d.inner or n == 0 then return end
    local count = 0
    pcall(function()
      v:ForEach(function(i, elem)
        count = count + 1
        if count > 8 then return true end
        U.walk(elem:get(), d.inner, depth - 1, path .. "[" .. tostring(i) .. "]", visit)
      end)
    end)
  elseif t == "ObjectProperty" or t == "ClassProperty" or t == "WeakObjectProperty" or t == "LazyObjectProperty" then
    local o = v
    if t == "WeakObjectProperty" or t == "LazyObjectProperty" then pcall(function() o = v:Get() end) end
    visit(t == "ClassProperty" and "class" or "object", path, o, d)
  elseif t == "SoftObjectProperty" or t == "SoftClassProperty" then
    visit("soft", path, v, d)
  elseif t == "NameProperty" or t == "StrProperty" or t == "TextProperty" then
    local ok, s = pcall(function() return v:ToString() end)
    visit("string", path, ok and s or tostring(v), d)
  elseif t == "BoolProperty" then
    visit("bool", path, v, d)
  elseif t == "EnumProperty" or t == "ByteProperty" then
    visit("enum", path, v, d, d.enum)
  elseif t:find("Delegate") or t == "MapProperty" or t == "SetProperty" then
    visit("skip", path, nil, d, t)
  else
    visit("number", path, v, d)
  end
end

local function objStr(o)
  if o == nil then return "nil" end
  if not U.valid(o) then return "None" end
  return U.fullName(o)
end

-- Text dump of a reflected value, one line per leaf.
function U.dumpValue(v, d, depth, prefix, lines)
  U.walk(v, d, depth, prefix, function(kind, path, val, _, extra)
    local s
    if kind == "tag" then
      s = "Tag(" .. tostring(val) .. ")"
    elseif kind == "tags" then
      s = "Tags[" .. table.concat(val or {}, ", ") .. "]"
    elseif kind == "vector" then
      s = val and string.format("(%.1f, %.1f, %.1f)", val.X, val.Y, val.Z) or "?"
    elseif kind == "rotator" then
      s = val and string.format("(P%.1f Y%.1f R%.1f)", val.Pitch, val.Yaw, val.Roll) or "?"
    elseif kind == "struct" then
      s = "{" .. tostring(extra) .. "}"
    elseif kind == "array" then
      s = "Array[" .. tostring(val) .. "] of " .. tostring(extra)
    elseif kind == "object" or kind == "class" then
      s = objStr(val)
    elseif kind == "soft" then
      local ok, str = pcall(function() return val:ToString() end)
      s = "Soft(" .. (ok and tostring(str) or tostring(val)) .. ")"
    elseif kind == "enum" then
      s = tostring(val) .. (extra and (" <" .. extra .. ">") or "")
    elseif kind == "skip" then
      s = "<" .. tostring(extra) .. ">"
    elseif kind == "error" then
      s = "<read error>"
    else
      s = tostring(val)
    end
    lines[#lines + 1] = path .. " = " .. s
  end)
  return lines
end

-- Property values of an object including inherited ones, stopping at the given base class.
function U.dumpObject(o, depth, prefix, lines, stopAt, filter)
  local chain = {}
  pcall(function()
    local c, guard = o:GetClass(), 0
    while U.valid(c) and guard < 32 do
      local n = U.fname(c)
      if n == (stopAt or "Object") then break end
      chain[#chain + 1] = c
      c, guard = c:GetSuperStruct(), guard + 1
    end
  end)
  for _, c in ipairs(chain) do
    for _, fd in ipairs(U.fields(c)) do
      if not filter or U.matchesAny(fd.name, filter) then
        local ok, v = pcall(function() return o[fd.name] end)
        if ok then
          U.dumpValue(v, fd, depth, prefix .. fd.name, lines)
        else
          lines[#lines + 1] = prefix .. fd.name .. " = <read error>"
        end
      end
    end
  end
  return lines
end

-- ---------------------------------------------------------------- vectors

function U.v3(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end

function U.copyv(s)
  if s == nil then return nil end
  local ok, r = pcall(function() return { X = s.X, Y = s.Y, Z = s.Z } end)
  return ok and r or nil
end

function U.copyr(s)
  if s == nil then return nil end
  local ok, r = pcall(function() return { Pitch = s.Pitch, Yaw = s.Yaw, Roll = s.Roll } end)
  return ok and r or nil
end

function U.add(a, b) return U.v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
function U.sub(a, b) return U.v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
function U.mul(a, s) return U.v3(a.X * s, a.Y * s, a.Z * s) end
function U.len(a) return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
function U.flat(a) return U.v3(a.X, a.Y, 0) end

function U.norm(a)
  local l = U.len(a)
  if l < 1e-6 then return U.v3(1, 0, 0) end
  return U.mul(a, 1 / l)
end

function U.yawDeg(a) return math.deg(math.atan(a.Y, a.X)) end

function U.actorLoc(a)
  local ok, l = pcall(function() return a:K2_GetActorLocation() end)
  if ok then return U.copyv(l) end
end

function U.actorYaw(a)
  local ok, y = pcall(function() return a:K2_GetActorRotation().Yaw end)
  if ok and type(y) == "number" then return y end
  return 0
end

-- Scaled capsule half height and radius in cm, with mannequin-sized defaults.
function U.capsule(a)
  local hh, r = 90, 34
  pcall(function()
    local c = a.CapsuleComponent
    if U.valid(c) then
      hh = c:GetScaledCapsuleHalfHeight()
      r = c:GetScaledCapsuleRadius()
    end
  end)
  return hh, r
end

-- World direction to the actor's local frame (yaw only), as used by component relative offsets.
function U.toLocal(actor, w)
  local yaw = math.rad(-U.actorYaw(actor))
  local c, s = math.cos(yaw), math.sin(yaw)
  return U.v3(c * w.X - s * w.Y, s * w.X + c * w.Y, w.Z)
end

function U.matchesAny(s, patterns)
  local low = tostring(s):lower()
  for _, pat in ipairs(patterns) do
    if low:find(pat:lower(), 1, true) then return true end
  end
  return false
end

-- The hotkeys as the player set them (Keys in config.lua; hf_boot fills U.keyLabels): texts are written with the
-- defaults ("Ctrl+F5" ...), and what is shown says the keys in use.
U.keyLabels = {}
function U.keys(s)
  if type(s) ~= "string" or next(U.keyLabels) == nil then return s end
  return (s:gsub("Ctrl%+F[5-9]", function(k) return U.keyLabels[k] or k end))
end

-- ---------------------------------------------------------------- files

function U.readFile(path, mode)
  local f = io.open(path, mode or "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function U.writeFile(path, data, mode)
  local f = io.open(path, mode or "wb")
  if not f then return false end
  local ok = f:write(data) ~= nil
  f:close()
  return ok
end

function U.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

-- ---------------------------------------------------------------- reloads

-- What a reload hands from the running copy of this file to the fresh one: the open logs, the mod's time across
-- worlds, the frame clock's measures, the hitch notes, the error counts and the perf sums. (The caches of class
-- chains, functions and the controller are not handed on: the new copy finds those again.)
function U.handover()
  return { logs = logs, world = world, frame = U.frame, frameMs = U.frameMs, hitches = U.hitches, notes = U.notes,
    errors = U.errors, cost = U.cost, crumbs = crumbs }
end

local function adopt(prev)
  if type(prev) ~= "table" or type(prev.handover) ~= "function" then return end
  local ok, h = pcall(prev.handover)
  if not ok or type(h) ~= "table" then return end
  logs, world, crumbs = h.logs or logs, h.world or world, h.crumbs or crumbs
  -- (A copy from before the trail was written line by line keeps no count: its file is not open yet.)
  crumbs.list, crumbs.lines = crumbs.list or {}, crumbs.lines or 0
  U.frame, U.frameMs = h.frame or U.frame, h.frameMs or U.frameMs
  U.hitches, U.notes, U.errors, U.cost = h.hitches or U.hitches, h.notes or U.notes, h.errors or U.errors, h.cost or U.cost
end
adopt(RT and RT.handover and RT.handover.hf_util)

return U
