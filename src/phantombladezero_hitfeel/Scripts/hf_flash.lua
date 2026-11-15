-- PBZ HitFeel: hit flash. The enemy that was hit glows white at the rim for a few frames and fades back.
-- Character materials in this game have a fresnel rim the game drives itself: the ZhanMa emergency shield
-- (GA_ZhanMa_PassiveBase) sets a strength and a colour parameter on the player's dynamic material instances
-- ("Fresnel_Strength", "Fresnel_Color" in PBZ.exe next to that class). The flash sets the same two on the hit enemy's
-- instances and restores the values it read first. Only parameters change: no overlay material (clearing one has
-- crash reports) and no material swap.
local F = { name = "flash", active = {}, flashes = 0, mids = 0, classes = {}, found = {}, walks = 0 }
local S, U, C

F.CREATE_MID = "/Script/Engine.PrimitiveComponent:CreateDynamicMaterialInstance"
-- Modules the ZhanMa ability class may live in; its defaults name the two parameters.
local ABILITY_MODULES = { "ProjectPBZ", "MagCombatAbilities", "LegoAbility", "SGameCombatSystem" }

function F.init(state)
  S, U, C = state, state.U, state.C
end

local function mult() return tonumber((S.cfg.Tuning or {}).Flash) or 1 end

-- The parameter names: the shield ability's own defaults when its class can be found (looked up once), else
-- config.lua's.
function F.names()
  local c = S.cfg.Flash
  if F.gameNames == nil then
    F.gameNames = false
    if c.UseGameNames then
      for _, m in ipairs(ABILITY_MODULES) do
        local cdo = StaticFindObject("/Script/" .. m .. ".Default__GA_ZhanMa_PassiveBase")
        if U.valid(cdo) then
          local sp = U.try("flash.sp", function() return cdo.ShieldFresnelStrengthParameter:ToString() end)
          local cp = U.try("flash.cp", function() return cdo.ShieldFresnelColorParameter:ToString() end)
          local sv = U.try("flash.sv", function() return cdo.ShieldFresnelStrength end)
          U.log("flash: the game's ZhanMa shield (/Script/%s) drives %s (up to %s) and %s", m, tostring(sp), tostring(sv), tostring(cp))
          if sp and cp and sp ~= "" and cp ~= "" and sp ~= "None" and cp ~= "None" then F.gameNames = { s = sp, c = cp } end
          break
        end
      end
      if not F.gameNames then
        U.log("flash: the shield ability's defaults were not found; using %s and %s from config.lua", c.StrengthParam, c.ColorParam)
      end
    end
  end
  if F.gameNames then return F.gameNames.s, F.gameNames.c end
  return c.StrengthParam, c.ColorParam
end

-- The body and, with Parts, the skinned meshes attached under it (clothes, hair).
local function parts(victim, c)
  local mesh = U.try("flash.mesh", function() return victim.Mesh end)
  if not U.valid(mesh) then return {} end
  if not c.Parts then return { mesh } end
  local out = {}
  for _, comp in ipairs(U.attachTree(mesh, 24)) do
    if U.chainHas(U.classChain(comp), "SkinnedMeshComponent") then out[#out + 1] = comp end
  end
  return out
end

-- The component's dynamic material instances; a slot without one gets one (CreateMids), as the engine itself does
-- when a parameter is set on a component's materials.
local function mids(comp, c)
  local out = {}
  local n = tonumber(U.try("flash.num", function() return comp:GetNumMaterials() end)) or 0
  for i = 0, math.min(n, 12) - 1 do
    local m = U.try("flash.mat", function() return comp:GetMaterial(i) end)
    if U.valid(m) and not U.isA(m, "MaterialInstanceDynamic") and c.CreateMids then
      m = U.try("flash.mid", U.callNamed, comp, F.CREATE_MID, { ElementIndex = i })
      if U.valid(m) then F.mids = F.mids + 1 end
    end
    if U.valid(m) and U.isA(m, "MaterialInstanceDynamic") then out[#out + 1] = m end
  end
  return out
end

-- The material instances of a struck body, kept for the next flash on it: finding them walks every part and slot of
-- the body, a few hundred engine calls on a ten-material enemy, and a combo strikes it every few frames. Found again
-- after Flash.KeepSec, or when one of them has gone.
local function instances(victim, key, c)
  local now = U.now()
  local f = F.found[key]
  if f and now - f.at < (c.KeepSec or 10) then
    local ok = true
    for _, mid in ipairs(f.list) do
      if not U.valid(mid) then
        ok = false
        break
      end
    end
    if ok then return f.list end
  end
  local list = {}
  for _, comp in ipairs(parts(victim, c)) do
    for _, mid in ipairs(mids(comp, c)) do list[#list + 1] = mid end
  end
  F.walks = F.walks + 1
  F.found[key] = { list = list, at = now }
  return list
end

-- Bodies not walked for a minute are forgotten (the next flash on one walks it again). hf_perf calls this every few
-- seconds.
function F.prune(now)
  for k, e in pairs(F.found) do
    if now - e.at > 60 then F.found[k] = nil end
  end
end

-- (Parameter names below are FNames, made once a flash.)
local function readColor(mid, name)
  local v = mid:K2_GetVectorParameterValue(name)
  return { R = v.R, G = v.G, B = v.B, A = v.A }
end

-- What a material instance shows now, read before the flash so it can be put back.
local function capture(mid, sF, cF)
  return {
    mid = mid,
    s0 = tonumber(U.try("flash.gets", function() return mid:K2_GetScalarParameterValue(sF) end)) or 0,
    c0 = U.try("flash.getc", readColor, mid, cF) or { R = 0, G = 0, B = 0, A = 0 },
  }
end

local function set(e, sF, cF, s, color)
  if not U.valid(e.mid) then return end
  e.mid:SetScalarParameterValue(sF, s)
  e.last = s
  if color then e.mid:SetVectorParameterValue(cF, color) end
end

-- Back to the values read first, unless the game has taken the parameter over meanwhile (a buff glow).
local function restore(e, sF, cF)
  if not U.valid(e.mid) then return end
  local now = tonumber(U.try("flash.now", function() return e.mid:K2_GetScalarParameterValue(sF) end))
  if now ~= nil and e.last ~= nil and math.abs(now - e.last) > 0.01 then return end
  e.mid:SetScalarParameterValue(sF, e.s0)
  e.mid:SetVectorParameterValue(cF, e.c0)
end

-- What was found on the first flash of each enemy class: shows whether the parameters exist (a material without
-- them reads back zero) and gives the resting values for tuning.
local function logClass(victim, list, sName, cName, peak)
  local cname = U.className(victim)
  if F.classes[cname] then return end
  F.classes[cname] = true
  local shown = {}
  for i, e in ipairs(list) do
    if i > 6 then break end
    shown[#shown + 1] = string.format("%s %s=%.2f %s=(%.2f,%.2f,%.2f,%.2f)", U.fname(e.mid), sName, e.s0, cName,
      e.c0.R or 0, e.c0.G or 0, e.c0.B or 0, e.c0.A or 0)
  end
  if #list == 0 then
    U.log("flash: %s has no material instance to flash", cname)
  else
    U.log("flash: %s, %d material(s), flashing to %.1f: %s", cname, #list, peak, table.concat(shown, "; "))
  end
end

-- `color` overrides config.lua's (the player's own red flash when a blow gets through).
function F.flash(victim, peak, frames, color)
  local c = S.cfg.Flash
  local key = U.addr(victim)
  if not key then return end
  local st = F.active[key]
  if not st then
    local sName, cName = F.names()
    local sF, cF = FName(sName), FName(cName)
    local list = {}
    for _, mid in ipairs(instances(victim, key, c)) do list[#list + 1] = capture(mid, sF, cF) end
    logClass(victim, list, sName, cName, peak)
    if #list == 0 then return end
    st = { victim = victim, list = list, sF = sF, cF = cF }
    F.active[key] = st
  end
  -- A hit during a flash restarts it from at least where it is.
  st.peak = math.max(peak, st.cur or 0)
  st.k, st.n, st.hold = 0, frames, U.gameFrames(c.HoldFrames or 1)
  color = color or c.Color or { R = 1, G = 1, B = 1, A = 1 }
  for _, e in ipairs(st.list) do U.try("flash.set", set, e, st.sF, st.cF, math.max(e.s0, st.peak), color) end
  st.cur = st.peak
  F.flashes = F.flashes + 1
  F.startLoop()
end

-- One frame of a flash: hold at full strength, then fade (ease-out) back to what was there. True when done.
function F.step(st)
  if not U.valid(st.victim) then return true end
  st.k = st.k + 1
  if st.k <= st.hold then return false end
  local t = (st.k - st.hold) / math.max(1, st.n)
  if t >= 1 then
    for _, e in ipairs(st.list) do U.try("flash.restore", restore, e, st.sF, st.cF) end
    st.cur = nil
    return true
  end
  local f = (1 - t) * (1 - t)
  for _, e in ipairs(st.list) do
    U.try("flash.fade", set, e, st.sF, st.cF, e.s0 + math.max(0, st.peak - e.s0) * f, nil)
  end
  st.cur = st.peak * f
  return false
end

function F.startLoop()
  if F.looping then return end
  F.looping = true
  U.everyFrame("flash.step", function()
    local any = false
    for key, st in pairs(F.active) do
      if F.step(st) then F.active[key] = nil else any = true end
    end
    if not any then F.looping = false end
    return not any
  end)
end

function F.release()
  for key, st in pairs(F.active) do
    for _, e in ipairs(st.list) do U.try("flash.release", restore, e, st.sF, st.cF) end
    F.active[key] = nil
  end
end

function F.onHit(ctx)
  local c = S.cfg.Flash
  if not c or not c.Enabled or ctx.kind ~= "hit" or not ctx.byPlayer or not U.valid(ctx.victim) then return end
  local peak = (C.tier(c.Strength, ctx.tierName) or 0) * mult() * U.emph(ctx)
  local frames = U.gameFrames(C.tier(c.Frames, ctx.tierName) or 4)
  if peak <= 0 or frames <= 0 then return end
  U.try("flash.flash", F.flash, ctx.victim, peak, frames)
end

function F.stats()
  local s, c = "?", "?"
  if F.gameNames then s, c = F.gameNames.s, F.gameNames.c elseif S and S.cfg.Flash then s, c = S.cfg.Flash.StrengthParam, S.cfg.Flash.ColorParam end
  return string.format("flashes=%d bodiesWalked=%d midsCreated=%d params=%s/%s", F.flashes, F.walks, F.mids, tostring(s), tostring(c))
end

return F
