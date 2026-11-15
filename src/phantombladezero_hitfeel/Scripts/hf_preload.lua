-- PBZ HitFeel: loads everything the mod uses when a map loads (a new player pawn appears), a couple of assets per
-- frame while the level settles, so nothing is loaded in the middle of a fight. Each asset is held the moment it is
-- found or loaded, by a hidden widget with one collapsed Image per asset (the asset as its brush resource): an asset
-- nothing references is freed by the engine's next garbage collection, and a Lua value does not count. 0.5.0 held
-- them all at the end of the pass, so one loaded a few frames earlier had been freed by then (the game collects
-- right after loading a save), and writing it into a brush crashed UE4SS natively on "Continue". The same pass
-- finds the blades, warms the function signatures, prepares the knockbacks, reads the level's post-process and starts
-- building the tuning panel (hidden), one of these a frame: v0.5.8 did them all in the pass's last frame, 136 ms,
-- logged as a hitch just after loading. A second pass later catches combat data that loaded after the map.
local P = { name = "preload" }
local S, U, C

function P.init(state)
  S, U, C = state, state.U, state.C
  S.preloadState = S.preloadState or {}
end

function P.onHit() end

local function construct(clsName, outer, name)
  local cls = StaticFindObject("/Script/UMG." .. clsName)
  if not U.valid(cls) then error("UMG class not found: " .. clsName) end
  local o = name and StaticConstructObject(cls, outer, name) or StaticConstructObject(cls, outer)
  if not U.valid(o) then error("could not construct " .. clsName) end
  return o
end

-- The holder for this pass: a collapsed widget, in the viewport from the start (its Slate widget keeps it alive),
-- whose canvas takes one image per asset. One per controller: a new map gets a new one and the old one goes with the
-- old world. On a respawn under the same controller the previous holder stays until this pass holds everything, so
-- its assets stay referenced in between.
local function newKeeper(pc)
  local st = S.preloadState
  if st.keeper and st.keeperOwner == U.addr(pc) and U.valid(st.keeper) then
    st.retired = st.retired or {}
    st.retired[#st.retired + 1] = st.keeper
  end
  st.keeper, st.keeperTree, st.keeperCanvas = nil, nil, nil
  local widget = construct("UserWidget", pc, S.env and S.env.widgetName("Keeper"))
  local tree = construct("WidgetTree", widget)
  widget.WidgetTree = tree
  local canvas = construct("CanvasPanel", tree)
  tree.RootWidget = canvas
  widget:AddToViewport(-1000)
  widget:SetVisibility(1)
  st.keeper, st.keeperTree, st.keeperCanvas, st.keeperOwner = widget, tree, canvas, U.addr(pc)
end

local function retireOld()
  local st = S.preloadState
  for _, old in ipairs(st.retired or {}) do
    if U.valid(old) then pcall(function() old:RemoveFromParent() end) end
  end
  st.retired = nil
end

-- Gives `o` a reference from the holder. Only for an object found or loaded in this same frame: it is alive now,
-- so the read-back that checks the hold is safe. The engine's setter first, the brush field if the setter is missing.
local function hold(o)
  local st = S.preloadState
  if not U.valid(o) or not U.valid(st.keeperTree) or not U.valid(st.keeperCanvas) then return false end
  local img = construct("Image", st.keeperTree)
  pcall(function() img:SetBrushResourceObject(o) end)
  local held = U.try("preload.check", function() return U.same(img.Brush.ResourceObject, o) end)
  if not held then
    pcall(function() img.Brush.ResourceObject = o end)
    held = U.try("preload.check2", function() return U.same(img.Brush.ResourceObject, o) end)
  end
  pcall(function() img:SetVisibility(1) end)
  st.keeperCanvas:AddChildToCanvas(img)
  return held == true
end

local function assetPaths()
  local out = {}
  for _, m in ipairs(S.features or {}) do
    if m.assetPaths then U.try(m.name .. ".paths", m.assetPaths, out) end
  end
  if S.hit and S.hit.assetPaths then U.try("hit.paths", S.hit.assetPaths, out) end
  local seen, list = {}, {}
  for _, p in ipairs(out) do
    if not seen[p] then
      seen[p] = true
      list[#list + 1] = p
    end
  end
  return list
end

-- Function signatures the features call by parameter name, read once here instead of on the first hit.
local function warmSignatures()
  local n = 0
  for _, m in ipairs(S.features or {}) do
    for _, v in pairs(m) do
      if type(v) == "string" and v:find("^/Script/[%w_]+%.[%w_]+:[%w_]+$") then
        if U.fnParams(v) then n = n + 1 end
      end
    end
  end
  return n
end

-- One pass: assets a few per frame, each held in the frame it is found or loaded (no object is kept for a later
-- frame), then the rest of the preparation, one piece a frame.
function P.run(reason)
  local st = S.preloadState
  if st.running or not (S.cfg.Preload or {}).Enabled then return end
  st.running = true
  local list = assetPaths()
  local loaded, held, missing, i, frames, work, worst = 0, 0, {}, 0, 0, 0, 0
  local per = math.max(1, (S.cfg.Preload or {}).PerFrame or 2)
  local sigs, times, t = 0, {}, 0
  local tail = {
    { "retire", retireOld },
    { "blades", function()
      local player = U.player()
      if player and S.hit then U.try("preload.blades", S.hit.findBlades, player, true) end
    end },
    { "signatures", function() sigs = U.try("preload.sigs", warmSignatures) or 0 end },
    { "knockbacks", function() if S.knockback then U.try("preload.knockback", S.knockback.discover) end end },
    { "post-process", function() if S.screen then U.try("preload.screen", S.screen.discover) end end },
    { "panel", function() if S.hud and S.hud.prebuild then U.try("preload.hud", S.hud.prebuild) end end },
  }
  local function step()
    local t0 = os.clock()
    frames = frames + 1
    if frames == 1 then
      local pc = U.pc()
      if not pc then error("no player controller") end
      -- (Once a session, before this run builds any: widgets an earlier run of the scripts left behind.)
      if S.env then
        local own = {}
        for _, w in ipairs({ st.keeper, S.hudState and S.hudState.widget, S.overlayState and S.overlayState.widget }) do
          if w then own[#own + 1] = w end
        end
        U.try("env.sweep", S.env.sweep, own)
      end
      newKeeper(pc)
    elseif not U.valid(st.keeper) then
      error("the holder widget is gone (the map changed during the pass)")
    end
    for _ = 1, per do
      i = i + 1
      local p = list[i]
      if not p then break end
      local o = StaticFindObject(p)
      if not U.valid(o) then o = U.try("preload.load", LoadAsset, p) end
      if U.valid(o) then
        loaded = loaded + 1
        if U.try("preload.hold", hold, o) then held = held + 1 end
      else
        missing[#missing + 1] = p
      end
    end
    if i < #list or t < #tail then
      -- The assets first; then one piece of the rest a frame (the panel builds itself over the next frames).
      if i >= #list then
        t = t + 1
        local t1 = os.clock()
        U.try("preload." .. tail[t][1], tail[t][2])
        times[#times + 1] = string.format("%s %.0f", tail[t][1], (os.clock() - t1) * 1000)
      end
      local dt = os.clock() - t0
      work, worst = work + dt, math.max(worst, dt)
      if t < #tail then return false end
    end
    U.log("preload (%s): %d assets loaded and %d held over %d frames, %d function signatures; %.0f ms of work, at most %.0f ms in one frame (then, one a frame, in ms: %s)%s",
      reason, loaded, held, frames, sigs, work * 1000, worst * 1000, table.concat(times, ", "),
      #missing > 0 and ("; not found: " .. table.concat(missing, ", ")) or "")
    st.running = false
    return true
  end
  -- An error ends the pass (U.everyFrame logs it); the next map load can run again.
  U.everyFrame("preload", function()
    local ok, done = pcall(step)
    if not ok then
      st.running = false
      error(done)
    end
    return done
  end)
end

-- Watches for a new player pawn (a map load, or a respawn into a new level) twice a second; a session loop.
function P.start()
  U.loop("preload.watch", function()
    local st, pre = S.preloadState, S.preload
    if not pre then return false end
    local player = U.player()
    local key = player and U.addr(player)
    if not key or key == st.pawn then return false end
    st.pawn = key
    local c = S.cfg.Preload or {}
    ExecuteInGameThreadWithDelay(c.DelayMs or 1500, function() U.try("preload.run", S.preload.run, "map loaded") end)
    if (c.SecondPassSec or 0) > 0 then
      ExecuteInGameThreadWithDelay(math.floor(c.SecondPassSec * 1000), function()
        if S.knockback then U.try("preload.knockback2", S.knockback.discover) end
      end)
    end
    return false
  end, 500)
end

function P.stats()
  local st = S.preloadState
  return string.format("keeper=%s running=%s", tostring(st.keeper ~= nil), tostring(st.running == true))
end

return P
