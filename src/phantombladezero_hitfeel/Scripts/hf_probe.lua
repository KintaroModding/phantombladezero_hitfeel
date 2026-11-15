-- PBZ HitFeel: read-only probe. Writes the reflection data, loaded assets and runtime values the mod relies on,
-- plus the first hits in full, to logs/probe_*.txt, so later versions can target exact names instead of guesses.
-- It never hooks functions blindly: v0.1.0 did, and reading the unwritten return value of a native
-- pre-hook crashed the game on the first attack. Observers below run after the call and read whitelisted inputs.
local P = { effectDumps = 0, victimDumped = {}, shakeLogs = 0 }
local S, U

local REFLECT = { "Hitreact", "HitReact", "HitReaction", "HitEffect", "Slomo", "FreezeFrame", "PhysicsHit",
  "PhysicalAnimation", "SoundFXSubsystem", "MusicSubsystem", "AkGameplayStatics", "GameUserSettings", "SettingsLocal",
  "ForceFeedback", "TPCCamera", "CameraShakeManager", "PBZPlayerController", "PBZPlayerCameraManager",
  "WeaponData", "AudioVolumeType", "FreezeFrameMode", "ParticleAttachOwner", "NiagaraFunctionLibrary", "WwiseMotion",
  "Deflect", "CameraModifier_CameraShake", "ActiveCameraShakeInfo" }
local TYPE_CLASSES = { Class = true, BlueprintGeneratedClass = true, ScriptStruct = true, UserDefinedStruct = true,
  Enum = true, UserDefinedEnum = true }
local ASSET_CAPS = { AkRtpc = 600, AkAudioEvent = 900, NiagaraSystem = 900, ParticleSystem = 300,
  ForceFeedbackEffect = 300, PhysicsHitAnimation = 300, CurveFloat = 300, CameraShakeClass = 300 }
local ASSET_FILTERS = {
  AkAudioEvent = { "hit", "impact", "flesh", "blood", "cut", "slash", "blade", "sword", "vib", "motion", "rumble",
    "haptic", "heavy", "clash", "attack", "swing", "whoosh", "deflect" },
  NiagaraSystem = { "hit", "slash", "blood", "spark", "trail", "cut", "blade", "sword", "impact", "flash", "swing",
    "line", "dao" },
  ParticleSystem = { "hit", "slash", "blood", "spark", "trail", "cut", "blade", "sword", "impact", "flash" },
  CurveFloat = { "hit", "physic", "alpha", "blend", "slomo", "react" },
}
local SLASH_HINTS = { "bloodslash", "slash", "bladetrail", "blade_trail", "swordtrail", "daoguang", "delayblade",
  "swordhit", "flashlight" }
local SIGNATURES = {
  "/Script/AkAudio.AkGameplayStatics:SetRTPCValue", "/Script/AkAudio.AkGameplayStatics:GetRTPCValue",
  "/Script/AkAudio.AkGameplayStatics:PostEventAtLocation",
  "/Script/Niagara.NiagaraFunctionLibrary:SpawnSystemAtLocation", "/Script/Niagara.NiagaraFunctionLibrary:SpawnSystemAttached",
  "/Script/Engine.GameplayStatics:SpawnEmitterAtLocation",
  "/Script/Engine.PlayerCameraManager:StartCameraShake", "/Script/Engine.PlayerController:PlayDynamicForceFeedback",
  "/Script/Engine.SceneComponent:K2_SetRelativeLocation",
  "/Script/AdvancedThirdPersonCamera.ATPCCameraComponent:SetAdditiveParameter_Distance",
  "/Script/AdvancedThirdPersonCamera.ATPCCameraComponent:SetAdditiveParameter_Rotation",
}
-- Class defaults worth reading for deflect tuning (perfect vs. normal slow-down, shakes, sounds).
local CDOS = { "/PBZDeflectSystem/BP_DeflectHitreactAttackSource.Default__BP_DeflectHitreactAttackSource_C" }

function P.init(state)
  S, U = state, state.U
end

local function writeFile(name, lines)
  local f = io.open(U.logDir .. "/" .. name, "w")
  if not f then return end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

local function paramsStr(descs)
  if not descs then return "<not found>" end
  local out = {}
  for _, d in ipairs(descs) do out[#out + 1] = d.name .. ": " .. U.typeDesc(d) end
  return table.concat(out, ", ")
end

local function tblStr(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
  return "{" .. table.concat(out, ", ") .. "}"
end

local function chainStr(o) return table.concat(U.classChain(o), " < ") end

-- Dumps whitelisted hook parameters while the call frame is still alive.
local function dumpArgs(args, descs, wanted, depth, L)
  for i = 1, args.n do
    local d = descs[i]
    if d and wanted[d.name] then
      local ok, v = pcall(function() return args[i]:get() end)
      if ok then U.dumpValue(v, d, depth, "  " .. d.name, L) end
    end
  end
end

function P.actorDetails(a, L)
  L[#L + 1] = "  actor " .. U.fullName(a) .. "  (" .. chainStr(a) .. ")"
  local root = U.try("probe.root", function() return a.RootComponent end)
  local comps = U.valid(root) and U.attachTree(root, 64) or {}
  for _, c in ipairs(comps) do L[#L + 1] = "    comp " .. U.fname(c) .. " : " .. chainStr(c) end
  local mesh = U.try("probe.mesh", function() return a.Mesh end)
  if U.valid(mesh) then
    local n = U.try("probe.nbones", function() return mesh:GetNumBones() end) or 0
    local names = {}
    for i = 0, math.min(n, 220) - 1 do
      local s = U.try("probe.bone", function() return mesh:GetBoneName(i):ToString() end)
      if s then names[#names + 1] = s end
    end
    L[#L + 1] = string.format("    mesh %s bones=%d: %s", U.fullName(mesh), n, table.concat(names, ", "))
    local sim = U.try("probe.sim", function() return mesh.BodyInstance.bSimulatePhysics end)
    L[#L + 1] = "    mesh.BodyInstance.bSimulatePhysics = " .. tostring(sim)
  end
end

-- Written once when the blade socket is not found: every component searched, with the sockets it does have.
function P.bladeTree(comps)
  local L = { "PBZHitFeel blade search " .. os.date("%Y-%m-%d %H:%M:%S"), "sockets tried: " .. table.concat(S.cfg.Hit.BladeSockets or {}, ", ") }
  for _, c in ipairs(comps) do
    local names = U.try("probe.sockets", function()
      local out = {}
      local arr = c:GetAllSocketNames()
      -- An entry is an FName, or a wrapper around one (no ToString of its own): v0.7.0 logged five errors here.
      local function str(n)
        if type(n) == "string" then return n end
        local ok, s = pcall(function() return n:ToString() end)
        if not ok then ok, s = pcall(function() return n:get():ToString() end) end
        return ok and tostring(s) or tostring(n)
      end
      if type(arr) == "table" then
        for _, n in ipairs(arr) do out[#out + 1] = str(n) end
      elseif arr then
        arr:ForEach(function(_, e) out[#out + 1] = str(e:get()) end)
      end
      return out
    end) or {}
    local owner = U.try("probe.owner", function() return U.fname(c:GetOwner()) end) or "?"
    L[#L + 1] = string.format("  %s (%s) owner=%s sockets=[%s]", U.fname(c), chainStr(c), owner, table.concat(names, ", "))
  end
  writeFile("probe_blade.txt", L)
end

local function addAsset(assets, counts, kind, obj)
  counts[kind] = (counts[kind] or 0) + 1
  local list = assets[kind] or {}
  assets[kind] = list
  if #list < ASSET_CAPS[kind] then list[#list + 1] = obj end
end

function P.scan()
  local t0 = os.clock()
  local classes, assets, counts = {}, {}, {}
  ForEachUObject(function(obj)
    local ok, cname = pcall(function() return obj:GetClass():GetFName():ToString() end)
    if not ok then return end
    if TYPE_CLASSES[cname] then
      local n = U.fname(obj)
      if n:sub(1, 9) ~= "Default__" then
        if #classes < 500 and U.matchesAny(n, REFLECT) then classes[#classes + 1] = obj end
        if cname == "BlueprintGeneratedClass" and n:lower():find("shake", 1, true) then
          addAsset(assets, counts, "CameraShakeClass", obj)
        end
      end
    elseif ASSET_CAPS[cname] then
      local filt = ASSET_FILTERS[cname]
      if not filt or U.matchesAny(U.fname(obj), filt) then addAsset(assets, counts, cname, obj) end
    end
  end)

  table.sort(classes, function(a, b) return U.fullName(a) < U.fullName(b) end)
  local L = { "PBZHitFeel reflection dump " .. os.date("%Y-%m-%d %H:%M:%S") }
  for _, cls in ipairs(classes) do
    local kind = U.className(cls)
    L[#L + 1] = "== " .. U.fullName(cls) .. "  (" .. table.concat(U.superChain(cls), " < ") .. ")"
    if kind == "Enum" or kind == "UserDefinedEnum" then
      pcall(function()
        cls:ForEachName(function(name, value)
          L[#L + 1] = "  " .. (type(name) == "string" and name or name:ToString()) .. " = " .. tostring(value)
        end)
      end)
    else
      for _, f in ipairs(U.funcs(cls)) do
        local flags = 0
        pcall(function() flags = f:GetFunctionFlags() end)
        L[#L + 1] = string.format("  fn %s(%s) flags=0x%08X", U.fname(f), paramsStr(U.fields(f)), math.tointeger(flags) or 0)
      end
      for _, d in ipairs(U.fields(cls)) do L[#L + 1] = "  prop " .. d.name .. ": " .. U.typeDesc(d) end
    end
  end
  writeFile("probe_reflection.txt", L)

  local A = { "PBZHitFeel loaded assets " .. os.date("%Y-%m-%d %H:%M:%S") }
  local kinds = {}
  for k in pairs(assets) do kinds[#kinds + 1] = k end
  table.sort(kinds)
  for _, k in ipairs(kinds) do
    local names = {}
    for _, o in ipairs(assets[k]) do names[#names + 1] = U.fullName(o) end
    table.sort(names)
    A[#A + 1] = string.format("== %s (%d matched, %d listed)", k, counts[k], #names)
    for _, n in ipairs(names) do A[#A + 1] = "  " .. n end
  end
  writeFile("probe_assets.txt", A)

  -- Kept as paths, never as objects: the game unloads assets later, and asking a freed object for its name is a
  -- native crash (v0.3.0's Ctrl+F6 crash). Paths are looked up again when used.
  S.rtpcPaths, S.slashCandidatePaths = {}, {}
  for _, o in ipairs(assets.AkRtpc or {}) do S.rtpcPaths[#S.rtpcPaths + 1] = (U.fullName(o):gsub("^%S+%s+", "")) end
  for _, o in ipairs(assets.NiagaraSystem or {}) do
    if U.matchesAny(U.fname(o), SLASH_HINTS) then S.slashCandidatePaths[#S.slashCandidatePaths + 1] = (U.fullName(o):gsub("^%S+%s+", "")) end
  end
  table.sort(S.slashCandidatePaths)
  U.log("probe scan: %d classes, assets %s, %d slash candidates, %.1f s", #classes, tblStr(counts), #S.slashCandidatePaths, os.clock() - t0)
  S.scanned = true
end

-- StartSlomoData calls the hit bus sees (first 200): ID, frames, multiplier, owner, and what the mod wrote.
function P.onSlomo(rec)
  P.slomoLogged = (P.slomoLogged or 0) + 1
  if P.slomoLogged > 200 then return end
  U.write("probe_observe.txt", string.format("%.3f slomo id=%s frames=%s mult=%s call=%s owner=%s%s",
    rec.time, tostring(rec.id), tostring(rec.frames), rec.mult and string.format("%.2f", rec.mult) or "nil",
    tostring(rec.callIndex or "clash"), rec.owner and U.fname(rec.owner) or "-",
    rec.rewritten and (" -> rewritten to " .. tostring(rec.rewritten) .. " frames") or ""))
end

function P.values()
  local L = { "PBZHitFeel runtime values " .. os.date("%Y-%m-%d %H:%M:%S") }
  local function add(s) L[#L + 1] = s end
  add("== UE4SS EngineTickAvailable=" .. tostring(EngineTickAvailable) .. " ProcessEventAvailable=" .. tostring(ProcessEventAvailable))
  add(string.format("== frame time %.2f ms (%d frames counted)", U.frameMs, U.frame))
  local pc = U.pc()
  if pc then
    add("== PlayerController " .. U.fullName(pc) .. "  (" .. chainStr(pc) .. ")")
    for _, n in ipairs({ "bForceFeedbackEnabled", "ForceFeedbackScale" }) do
      local ok, v = pcall(function() return pc[n] end)
      add("  " .. n .. " = " .. tostring(ok and v or "<err>"))
    end
  end
  local pcm = U.pcm()
  if pcm then
    local ok, fov = pcall(function() return pcm:GetFOVAngle() end)
    add("== PlayerCameraManager GetFOVAngle() = " .. tostring(ok and fov or "<err>"))
    local ok2, sc = pcall(function() return pcm.CameraShakeScale end)
    add("  CameraShakeScale = " .. tostring(ok2 and sc or "<err>"))
  end
  if S.hit then add("== active camera shakes now: " .. table.concat(S.hit.activeShakes(), ", ")) end
  local comp = S.camera and S.camera.atpc and U.try("probe.atpcget", S.camera.atpc)
  if U.valid(comp) then
    local d = U.try("probe.atpc", function() return comp:GetCameraDistance() end)
    add(string.format("== ATPCCameraComponent %s distance=%s", U.fullName(comp), tostring(d)))
  end
  if S.knockback then U.try("probe.knockback", S.knockback.describe, L) end
  for _, path in ipairs(CDOS) do
    local o = StaticFindObject(path)
    if U.valid(o) then
      add("== " .. path)
      U.dumpObject(o, 2, "  ", L, "Object", nil)
    else
      add("== " .. path .. " not loaded")
    end
  end
  local snd = FindFirstOf("PBZSoundFXSubsystem")
  if U.valid(snd) then
    add("== PBZSoundFXSubsystem")
    U.dumpObject(snd, 1, "  ", L, "Object", { "motion", "volume", "clash", "mix" })
  end
  local g = U.cdo("/Script/AkAudio.Default__AkGameplayStatics")
  add("== GetRTPCValue of loaded AkRtpc assets (global)")
  for _, path in ipairs(S.rtpcPaths or {}) do
    local r = StaticFindObject(path)
    if U.valid(r) and not U.fname(r):find("^Default__") then
      local out, typ = {}, {}
      local ok = pcall(function()
        U.callNamed(g, "/Script/AkAudio.AkGameplayStatics:GetRTPCValue",
          { RTPCValue = r, PlayingID = 0, InputValueType = 1, Value = out, OutputValueType = typ })
      end)
      add(string.format("  %s: ok=%s value=%s type=%s", U.fname(r), tostring(ok), tblStr(out), tblStr(typ)))
    end
  end
  for _, fp in ipairs(SIGNATURES) do add("== sig " .. fp .. "(" .. paramsStr(U.fnParams(fp)) .. ")") end
  local p = U.player()
  if p then
    add("== player pawn")
    P.actorDetails(p, L)
  end
  writeFile("probe_values.txt", L)
end

-- Effect-chooser call: full parameter dump for the first real hits, while the frame is alive.
function P.onEffect(info, args, descs)
  if not S.cfg.Probe.Enabled or not S.cfg.Probe.Dumps or P.effectDumps >= S.cfg.Probe.MaxHitDumps then return end
  P.effectDumps = P.effectDumps + 1
  local L = { string.format("==== effect #%d t=%.3f tier=%s weapon=%s tags=%s", P.effectDumps, info.time,
    info.tierName, tostring(info.weapon), table.concat(info.tags, "|")) }
  dumpArgs(args, descs, { AttackType = true, HitStrength = true, BodyMaterial = true, ParticleData = true,
    SlomoData = true, CameraShake = true, HitSound = true }, 5, L)
  U.write("probe_hits.txt", table.concat(L, "\n"))
end

function P.onHit(ctx)
  local function nm(o) return U.valid(o) and U.fname(o) or "-" end
  local ids = {}
  for _, r in ipairs(ctx.slomos or {}) do
    ids[#ids + 1] = string.format("%s:%s@%s", tostring(r.id), tostring(r.frames), r.mult and string.format("%.2f", r.mult) or "?")
  end
  local extra = ""
  if ctx.kind == "deflect" then
    extra = string.format(" source=%s clashMult=%s strength=%s by=%s freezeTier=%s counter=%s lookupShakes=[%s] shakes=[%s]",
      tostring(ctx.blockSource or "clash"), ctx.clashMult and string.format("%.2f", ctx.clashMult) or "-", tostring(ctx.strengthTier),
      tostring(ctx.classifiedBy), tostring(ctx.freezeTier), tostring(ctx.counterFlags), table.concat(ctx.lookupShakes or {}, ","),
      table.concat(ctx.shakes or {}, ","))
  elseif ctx.byPlayer and ctx.shakeLevel and P.shakeLogs < 5 then
    -- Shows whether the upgraded vanilla shake is what the game actually plays.
    P.shakeLogs = P.shakeLogs + 1
    extra = " playing=[" .. table.concat(S.hit and S.hit.activeShakes() or {}, ",") .. "]"
  end
  U.write("probe_hitlog.txt", string.format(
    "%.3f #%d %s%s tier=%s lvl=%d special=%s mat=%s weapon=%s byPlayer=%s victim=%s method=%s impact=%s@%s sweep=%s shake=%s->%s freeze=%s dup=%s slomos=[%s] tags=%s%s",
    ctx.time or 0, ctx.index or 0, tostring(ctx.kind), ctx.kind == "deflect" and ("(" .. tostring(ctx.tierName) .. ")") or "",
    tostring(ctx.tierName), ctx.level or -1, tostring(ctx.special), tostring(ctx.material), tostring(ctx.weapon),
    tostring(ctx.byPlayer), nm(ctx.victim), tostring(ctx.method),
    ctx.impact and string.format("(%.0f,%.0f,%.0f)%s", ctx.impact.X, ctx.impact.Y, ctx.impact.Z, ctx.impactEstimated and "~" or "") or "-",
    tostring(ctx.hitBone),
    ctx.sweep and string.format("(%.2f,%.2f,%.2f)", ctx.sweep.X, ctx.sweep.Y, ctx.sweep.Z) or "-",
    tostring(ctx.vanillaShakeLevel), tostring(ctx.shakeLevel), tostring(ctx.freezeApplied), tostring(ctx.duplicate),
    table.concat(ids, " "), table.concat(ctx.tags or {}, "|"), extra))
  if not S.cfg.Probe.Enabled or not U.valid(ctx.victim) then return end
  local cname = U.className(ctx.victim)
  if P.victimDumped[cname] then return end
  P.victimDumped[cname] = true
  U.try("probe.materials", P.materials, ctx.victim, cname)
  if not S.cfg.Probe.Dumps then return end
  local D = { "==== victim class " .. cname .. " (first hit)" }
  P.actorDetails(ctx.victim, D)
  U.write("probe_victims.txt", table.concat(D, "\n"))
end

-- The scalar parameters on the first enemy materials (once per enemy class): looking for one a hit flash can drive.
function P.materials(victim, cname)
  P.materialLogs = (P.materialLogs or 0) + 1
  if P.materialLogs > 6 then return end
  local mesh = U.try("probe.mmesh", function() return victim.Mesh end)
  if not U.valid(mesh) then return end
  local parts = {}
  for i = 0, 3 do
    local m = U.try("probe.mat", function() return mesh:GetMaterial(i) end)
    if not U.valid(m) then break end
    local names = {}
    pcall(function()
      m.ScalarParameterValues:ForEach(function(_, e)
        if #names < 40 then names[#names + 1] = e:get().ParameterInfo.Name:ToString() end
      end)
    end)
    parts[#parts + 1] = U.fname(m) .. "[" .. table.concat(names, ",") .. "]"
  end
  U.log("materials of %s: %s", cname, table.concat(parts, " "))
end

function P.writeSummary()
  local H = S.hit
  local L = { string.format("PBZHitFeel %s summary %s", U.version, os.date("%Y-%m-%d %H:%M:%S")),
    string.format("enabled=%s effects=%d ignoredTicks=%d hits=%d deflects=%d slomoCalls=%d scanned=%s blade=%s",
      tostring(S.cfg.Enabled), H.effects, H.ignored, H.hits, H.deflects, H.slomos, tostring(S.scanned),
      H.blade and H.blade.name or "-") }
  for path in pairs(S.hooked) do L[#L + 1] = "hooked " .. path end
  for _, m in ipairs(S.features or {}) do
    L[#L + 1] = "feature " .. m.name .. ": " .. (m.stats and U.try("stats." .. m.name, m.stats) or "")
  end
  for tag, n in pairs(U.errors) do L[#L + 1] = string.format("errors %5d  %s", n, tag) end
  writeFile("probe_summary.txt", L)
end

-- The summary is rewritten every minute. The full object scan (ForEachUObject) is off unless Probe.Scan is set:
-- walking every object while the game destroys some (v0.3.1: just after Ctrl+F6 previews) crashed in UE4SS.dll.
-- Its results are already in hand; Ctrl+F9 still writes the runtime values.
-- Both are session loops; the scan runs once a session.
function P.schedule()
  if S.cfg.Probe.Scan and not S.probeScanned then
    U.loop("probe.scan", function()
      if not U.player() then return false end
      S.probeScanned = true
      U.log("player found; probe scan in %d s (expect a short hitch)", S.cfg.Probe.ScanDelaySec)
      ExecuteInGameThreadWithDelay(S.cfg.Probe.ScanDelaySec * 1000, function() U.try("probe.scan", S.probe.scan) end)
      return true
    end, 2000)
  end
  U.loop("probe.summary", function()
    U.try("probe.summary", S.probe.writeSummary)
    return false
  end, 60000)
end

return P
