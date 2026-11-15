-- PBZ HitFeel: the kernel, the one script that is never reloaded. It starts the mod (hf_boot, which loads every other
-- script) and, when asked (Ctrl+F8, or an update installed from the panel), loads a fresh copy of every script and
-- swaps it in while the game runs. The new copy is loaded in full before anything of the running one is touched; if it
-- does not load, or fails while starting, the running scripts carry on or come back, so a broken file never leaves the
-- mod half replaced. What outlives a reload: the state table (RT.S: the hooks, the panel, the preloaded assets, the
-- counters), the session loops (RT.loops) and what hf_util hands to its new copy (the open logs, the mod's time). The
-- old copies of hf_util and hf_config then answer with the new ones, for the hooks and delayed actions that still hold
-- them. Kept small on purpose: a change to this file only takes effect when the game starts again.
local KERNEL = 1

local RT = { kernel = KERNEL, gen = 0, loops = {} }
_G.PBZHitFeel_RT = RT

local function moduleNames()
  local out = {}
  for name in pairs(package.loaded) do
    if type(name) == "string" and name:find("^hf_") then out[#out + 1] = name end
  end
  return out
end

local function putBack(old)
  for _, n in ipairs(moduleNames()) do package.loaded[n] = nil end
  for n, m in pairs(old) do package.loaded[n] = m end
end

local function say(fmt, ...)
  local U = package.loaded.hf_util
  if type(U) == "table" and U.log then return U.log(fmt, ...) end
  print(string.format("[PBZHitFeel] " .. fmt .. "\n", ...))
end

-- Loads hf_boot, and with it every script, afresh; the copies running until now are handed to hf_util's new copy
-- while it loads (RT.handover). On failure the running copies are put back.
local function loadFresh()
  local old = {}
  for _, n in ipairs(moduleNames()) do old[n], package.loaded[n] = package.loaded[n], nil end
  RT.handover = old
  local ok, boot = pcall(require, "hf_boot")
  RT.handover = nil
  if ok and type(boot) == "table" and type(boot.start) == "function" then return boot, old end
  putBack(old)
  return nil, old, ok and "hf_boot is not a module" or tostring(boot)
end

-- An old copy of a shared module, still held by hooks and delayed actions, answers with the new one.
local function forward(old, new)
  if type(old) ~= "table" or type(new) ~= "table" or old == new then return end
  for k in pairs(old) do old[k] = nil end
  setmetatable(old, { __index = new, __newindex = new })
end

-- Swaps in a fresh copy of the scripts. True, or false and why; RT.last says how it went.
function RT.reload(why)
  local running = RT.boot
  local boot, old, err = loadFresh()
  if not boot then
    RT.last = { ok = false, why = why, err = err }
    say("reload (%s): the new scripts did not load, so the running ones carry on: %s", tostring(why), tostring(err))
    return false, err
  end
  if (tonumber(boot.KERNEL) or 1) > KERNEL then
    putBack(old)
    err = "they need a newer main.lua, which only takes over when the game starts again"
    RT.last = { ok = false, why = why, err = err, restart = true, version = boot.VERSION }
    say("reload (%s): %s", tostring(why), err)
    return false, err
  end
  if running and running.stop then pcall(running.stop, why) end
  local ok, e = pcall(boot.start, RT, why, old)
  if ok then
    forward(old.hf_util, package.loaded.hf_util)
    forward(old.hf_config, package.loaded.hf_config)
    RT.boot, RT.gen = boot, RT.gen + 1
    RT.last = { ok = true, why = why, version = boot.VERSION }
    return true
  end
  -- The new copy failed while starting: it stops, and the running one starts again on the same state.
  pcall(boot.stop, "failed start")
  local failed = {}
  for _, n in ipairs(moduleNames()) do failed[n] = package.loaded[n] end
  putBack(old)
  local back = running ~= nil and pcall(running.start, RT, "back after a failed reload", failed)
  RT.last = { ok = false, why = why, err = tostring(e), back = back }
  say("reload (%s): the new scripts failed while starting (%s); %s", tostring(why), tostring(e),
    back and "the running ones are back" or "the running ones did not start again either")
  return false, e
end

-- A reload asked for from inside the mod (a hotkey, the panel, the updater) runs at the start of the next frame,
-- outside the code that asked for it.
function RT.request(why)
  if RT.pending then return end
  RT.pending = why or "request"
  local function go()
    local w = RT.pending
    RT.pending = nil
    local ok, err = pcall(RT.reload, w)
    if not ok then say("reload (%s): %s", tostring(w), tostring(err)) end
  end
  if EngineTickAvailable and type(ExecuteInGameThreadAfterFrames) == "function" then
    ExecuteInGameThreadAfterFrames(1, go)
  else
    ExecuteInGameThreadWithDelay(16, go)
  end
end

local boot, _, err = loadFresh()
if not boot then error("PBZHitFeel could not load its scripts: " .. tostring(err)) end
RT.boot = boot
boot.start(RT, nil, {})
