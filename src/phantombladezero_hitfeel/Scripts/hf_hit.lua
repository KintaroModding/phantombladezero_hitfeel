-- PBZ HitFeel: hit bus.
-- GetEffectData (blueprint, hooked after it runs) reports every hit and deflect lookup with its tags and the vanilla
-- effect assets; its outputs (camera shake, slomo data) can still be changed there. StartSlomoData (native, hooked
-- before it runs) follows each lookup twice in the same frame, attacker first, then the side that was hit
-- (RuntimeData.Owner), with the lookup's SlomoData. A clash starts its own slomo pair before its deflect lookups.
-- Events are grouped by frame (the world's real time is constant within one) and dispatched one frame later.
-- Lessons from v0.1: the game calls its sound/camera/rumble helpers natively, so hooks never see them; a native
-- pre-hook must not read return values or pure outputs (garbage pointer -> native crash); after a native call
-- UE4SS shifts the arguments by one. So: whitelisted inputs only, native hooks act before the call, and every
-- value is copied out inside the callback because hook parameters die with the call frame.
local H = { listeners = {}, hits = 0, deflects = 0, effects = 0, ignored = 0, slomos = 0, pending = {},
  recentSlomos = {}, lastByVictim = {}, lightHits = 0 }
local S, U, C

H.GED_PATH = "/PBZCombatAsset/Prototypes/Hitreact/BP_HitEffectPlayer_Chooser.BP_HitEffectPlayer_Chooser_C:GetEffectData"
H.SLOMO_PATH = "/Script/SGameCombatSystem.RuntimeSlomoDataHelper:StartSlomoData"
-- The game's own perfect deflect: its perfect choosers (siblings of the hit chooser under
-- BP_HitEffectPlayer_ChooserBase_C, so the GetEffectData hook above never sees them) and the deflect frame's result.
local HITREACT = "/PBZCombatAsset/Prototypes/Hitreact/"
H.PERFECT_CLASS = HITREACT .. "BP_DeflectEffectPlayer_Chooser_Perfect.BP_DeflectEffectPlayer_Chooser_Perfect_C"
H.PERFECT_FINAL_CLASS = HITREACT .. "BP_DeflectEffectPlayer_Chooser_PerfectFinal.BP_DeflectEffectPlayer_Chooser_PerfectFinal_C"
H.DEFLECT_FRAME_CLASS = "/PBZDeflectSystem/Actions/GAA_DeflectFrame.GAA_DeflectFrame_C"
H.PERFECT_PATH = H.PERFECT_CLASS .. ":GetEffectData"
H.PERFECT_FINAL_PATH = H.PERFECT_FINAL_CLASS .. ":GetEffectData"
H.DEFLECT_FRAME_PATH = H.DEFLECT_FRAME_CLASS .. ":Process Deflect Frame"
H.SHAKE_FMT = "/PBZCombatAsset/Config/HitReact/CameraShake/CameraShake_PlayerAttack_Level%d.CameraShake_PlayerAttack_Level%d_C"

local TAG_READ = { AttackType = true, HitStrength = true, BodyMaterial = true }
local ASSET_READ = { ParticleData = true, SlomoData = true, CameraShake = true, HitSound = true }
local SLOMO_READ = { RuntimeData = true, SlomoID = true, SlomoData = true }
local ASSET_PARAMS = { "ParticleData", "CameraShake", "HitSound" }

local LEVELS = { VeryLight = 1, Light = 2, Middle = 3, Heavy = 4, UltraHeavy = 5, Break = 5, Default = 2 }
local BUMP = { VeryLight = "Light", Light = "Middle", Middle = "Heavy", Heavy = "UltraHeavy", UltraHeavy = "Break",
  Break = "Break", Default = "Middle" }
local STRONG_INCOME = { Break = true, Launchback = true }
H.LEVELS = LEVELS

function H.init(state)
  S, U, C = state, state.U, state.C
end

function H.subscribe(name, fn)
  H.listeners[#H.listeners + 1] = { name = name, fn = fn }
end

function H.paramDescs(fnPath)
  local fn = StaticFindObject(fnPath)
  if not U.valid(fn) then return nil end
  return U.fields(fn)
end

local function sameFrame(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-4 end
H.sameFrame = sameFrame

local function objEntry(path, obj, isClass)
  return { path = path, obj = obj, kind = isClass and "class" or "object",
    chain = isClass and U.superChain(obj) or U.classChain(obj) }
end

local function collect(info, v, d, path)
  U.walk(v, d, 4, path, function(kind, p, val)
    if (kind == "object" or kind == "class") and U.valid(val) then
      info.objects[#info.objects + 1] = objEntry(p, val, kind == "class")
    end
  end)
end

-- Tags seen in this build: HitReact.AttackType.Physical.Slash.TangBlade.Player,
-- Hitreact.Strength.Income.Normal.{VeryLight..Heavy}, ...Normal.Knockback.Middle, ...Deflect.{Attacker,Defender},
-- Hitreact.Material.{Meat,PlayerMeat,Shield.Iron}. Burning and other status ticks come through as
-- Hitreact.AttackType.Energy with Income.None or Income.StatusInfliction.*, several times a second.
local function classify(info)
  local hs = info.strengthTag or ""
  local normal = hs:match("^Hitreact%.Strength%.Income%.Normal%.([%a%.]+)$")
  if normal then
    info.normal = true
    local special, tier = normal:match("^(%a+)%.(%a+)$")
    if special then info.special, normal = special, tier end
    info.tierName = LEVELS[normal] and normal or "Default"
  end
  info.deflectSide = hs:match("^Hitreact%.Strength%.Income%.Deflect%.(%a+)$")
  -- A guard broken (Sha-Chi gone): Income.Break.Deflect, with no attack type, on the side whose guard broke.
  info.guardBreak = hs:find("^Hitreact%.Strength%.Income%.Break%.Deflect") ~= nil
  local income = hs:match("^Hitreact%.Strength%.Income%.(%a+)")
  if income and income ~= "Normal" and income ~= "Deflect" then info.special = income end
  info.tierName = info.tierName or "Default"
  if STRONG_INCOME[info.special or ""] then
    info.tierName, info.strong = "Break", true
  elseif info.special == "Knockback" then
    info.tierName = BUMP[info.tierName]
  end
  info.level = LEVELS[info.tierName] or 2
  info.material = (info.materialTag or ""):match("^Hitreact%.Material%.([%w%.]+)$")
  info.onPlayer = info.material ~= nil and info.material:find("^Player") ~= nil
  info.relevant = info.normal == true or info.strong == true or info.deflectSide ~= nil

  local kw = S.cfg.Hit.WeaponKeywords or {}
  local at = info.attackTag or ""
  for _, cat in ipairs({ "DW", "2H", "1H" }) do
    if not info.weapon and U.matchesAny(at, kw[cat] or {}) then info.weapon = cat end
  end
end

-- Before the slomo calls name the attacker: the player's attacks carry a ".Player" attack tag or a
-- CameraShake_PlayerAttack shake (AHua and ShachiHook attacks only the latter). Only the tag is sure: the game's
-- tables give NPCs' blows on each other PlayerAttack shakes too (bandits on dolls, one sect on another, anywhere on
-- the map), so a hit known by its shake alone waits for the attacker's slomo call (claim) before it counts as yours.
local function playerHint(info)
  if info.onPlayer or info.deflectSide then return false end
  info.playerTag = (info.attackTag or ""):find("%.Player$") ~= nil
  if info.playerTag then return true end
  return info.vanillaShakeLevel ~= nil
end

-- ------------------------------------------------------------------ player blade

-- The vanilla blood trail attaches to the blade socket "BladeBloodStart"; its position gives the contact point,
-- and its motion between two frames gives the swing direction. The weapons hang off the character mesh, so the
-- search walks AttachChildren from the player's root, plus the root of every child actor. The player carries
-- several weapons at once (the 2H axe, the 1H blade, the dual blades), so every blade is kept and the one nearest
-- the hands is taken per hit.
local HANDS = { "hand_r", "hand_l" }

local function firstSocket(comp, names)
  for _, sock in ipairs(names or {}) do
    local fn = FName(sock)
    local ok, has = pcall(function() return comp:DoesSocketExist(fn) end)
    if ok and has then return fn, sock end
  end
end

-- Every component under the actor with a blade socket; also the components walked, for the probe.
local function scanBlades(actor)
  local roots = {}
  local function addRoot(a)
    local r = U.try("hit.root", function() return a.RootComponent end)
    if U.valid(r) then roots[#roots + 1] = r end
  end
  addRoot(actor)
  for _, a in ipairs(U.arrayObjects(U.try("hit.children", function() return actor.Children end), 32)) do addRoot(a) end
  local seen, comps = {}, {}
  for _, r in ipairs(roots) do
    for _, c in ipairs(U.attachTree(r, 96)) do
      local key = U.addr(c)
      if key and not seen[key] then
        seen[key] = true
        comps[#comps + 1] = c
      end
    end
  end
  local list = {}
  for _, comp in ipairs(comps) do
    local fn, name = firstSocket(comp, S.cfg.Hit.BladeSockets)
    if fn then
      local tip, tipName = firstSocket(comp, S.cfg.Hit.BladeTipSockets)
      if tipName == name then tip, tipName = nil, nil end
      list[#list + 1] = { comp = comp, key = U.addr(comp), socket = fn, name = name, tip = tip, tipName = tipName }
    end
  end
  return list, comps
end

-- Blades of any character, cached for 10 s per actor; entries older than a minute are dropped.
H.bladeCaches = H.bladeCaches or {}

local function allValid(list)
  for _, b in ipairs(list) do
    if not U.valid(b.comp) then return false end
  end
  return true
end

-- A cached list is reused only while all its components are alive: a pawn spawned after a death or a map load can
-- get the old one's address. `fresh` (the map-load pass) always rescans.
local function bladesOf(actor, fresh)
  local key = U.addr(actor)
  if not key then return {} end
  local now = U.now()
  local c = H.bladeCaches[key]
  if c and not fresh and (now - c.time) < 10 and allValid(c.list) then return c.list, nil, true end
  for k, old in pairs(H.bladeCaches) do
    if now - old.time > 60 then H.bladeCaches[k] = nil end
  end
  local list, comps = scanBlades(actor)
  H.bladeCaches[key] = { time = now, list = list }
  return list, comps, false
end

function H.findBlades(player, fresh)
  local list, comps, cached = bladesOf(player, fresh)
  if cached then return list end
  if #list ~= (H.bladeCount or -1) then
    H.bladeCount = #list
    local names = {}
    for _, b in ipairs(list) do names[#names + 1] = b.name .. (b.tipName and ("-" .. b.tipName) or "") .. " on " .. U.fullName(b.comp) end
    if #list > 0 then
      U.log("blade sockets: %s", table.concat(names, "; "))
    else
      U.log("blade socket not found on %d components under the player; hit points are estimated (probe_blade.txt lists them)", #comps)
      if S.probe then U.try("probe.blade", S.probe.bladeTree, comps) end
    end
  end
  return list
end

-- Blade tips, sampled every frame: the swing direction at a hit is how the tip moved into it. (Measured after the
-- hit it was mostly lost: the game slows the attacker for a few frames on every hit, so the tip hardly moves.) Only
-- the cached blade list is used here, never a rescan; the samples live in S so they outlive a reload, and the loop
-- (a session loop: a reload starts it again in place of the old one) always calls the current module.
function H.trackTips()
  S.tips = S.tips or {}
  U.loop("hit.tips", function()
    if S.hit and S.hit.sampleTips then S.hit.sampleTips() end
    return false
  end)
end

-- The blade's weapon for the log: "BP_Weapon_Hun_DoubleBlade_R_C_2147477127" out of the component's full name.
function H.weaponName(b)
  if not b.label then b.label = U.fullName(b.comp):match("([^%.:]+)%.[^%.:]*$") or b.name end
  return b.label
end

-- Which weapons are in use. In a real fight (2026-11-05: the dual blades and the wooden sword) a weapon in your hands
-- hung from weapon_r_Socket, weapon_l_Socket or WEAPON_R, a put-away one from Pt_DoubleBlade_R_Back_Socket,
-- Pt_DoubleBlade_L_Back_Socket or Pt_TangBlade_Back_Socket; the one not in use was hidden, and in some moves all of
-- them were. (The blade socket's distance to a hand told nothing: in hand 75-113 cm, on the back 20-59 cm.) So a
-- weapon counts while it is shown and its socket names none of Hit.SheathedSockets; one that cannot be read counts.
-- Looked at every 10 frames (H.sampleTips). Only those are sampled for the swing trails, and only they give a hit its
-- blade and contact point.
H.bladeUse = H.bladeUse or {}

-- The socket the weapon hangs from on you, and where that is ("weapon_r_Socket on CharacterMesh0"). The component
-- that hangs it there is found once by walking up from the blade, then read directly while its parent stays the same.
-- Plain pcalls: a build that lacks one of these reads nothing, and the weapon counts.
local function attachOf(b, player)
  local link = b.link
  if link and U.valid(link.comp) then
    local ok, parent = pcall(function() return link.comp.AttachParent end)
    if ok and parent ~= nil and U.addr(parent) == link.parent then
      local _, s = pcall(function() return link.comp.AttachSocketName:ToString() end)
      s = type(s) == "string" and s or nil
      return s, tostring(s or "?") .. " on " .. link.parentName
    end
  end
  b.link = nil
  local cur = b.comp
  for _ = 1, 6 do
    local ok, parent = pcall(function() return cur.AttachParent end)
    if not (ok and U.valid(parent)) then return nil, "not attached" end
    local _, owner = pcall(function() return parent:GetOwner() end)
    if U.same(owner, player) then
      local _, s = pcall(function() return cur.AttachSocketName:ToString() end)
      s = type(s) == "string" and s or nil
      b.link = { comp = cur, parent = U.addr(parent), parentName = U.fname(parent) }
      return s, tostring(s or "?") .. " on " .. b.link.parentName
    end
    cur = parent
  end
  return nil, "?"
end

local function shown(b)
  if b.owner == nil then
    local ok, o = pcall(function() return b.comp:GetOwner() end)
    b.owner = ok and U.valid(o) and o or false
  end
  local _, vis = pcall(function() return b.comp:IsVisible() end)
  local _, hid = pcall(function() return b.comp.bHiddenInGame end)
  local ahid = b.owner and select(2, pcall(function() return b.owner.bHidden end))
  return not (vis == false or hid == true or ahid == true)
end

local function putAway(socket)
  local s = tostring(socket or ""):lower()
  for _, w in ipairs(S.cfg.Hit.SheathedSockets or {}) do
    if s:find(tostring(w):lower(), 1, true) then return true end
  end
  return false
end

-- Logged when it changes, the first Diagnostics.WeaponLogs times a session (the count in S: a reload must not start
-- it over).
local function refreshUse(player, list)
  local use, parts = {}, {}
  for _, b in ipairs(list) do
    local key = b.key or U.addr(b.comp)
    if key and U.valid(b.comp) then
      local socket, where = attachOf(b, player)
      local vis = shown(b)
      use[key] = vis and not putAway(socket)
      parts[#parts + 1] = string.format("%s at %s, %s%s", H.weaponName(b), where, vis and "shown" or "hidden", use[key] and "" or " (left out)")
    end
  end
  H.bladeUse = use
  local sig = table.concat(parts, "; ")
  if sig ~= S.weaponSig and (S.weaponLogs or 0) < (tonumber((S.cfg.Diagnostics or {}).WeaponLogs) or 30) then
    S.weaponSig, S.weaponLogs = sig, (S.weaponLogs or 0) + 1
    U.log("weapons (%d): %s", S.weaponLogs, sig)
  end
end

-- True unless the last look found the blade hidden or put away.
function H.inUse(b)
  local key = b.key or U.addr(b.comp)
  return not key or H.bladeUse[key] ~= false
end

function H.sampleTips()
  -- (Mod off: nothing reads them, and the swing trails were ended when it went off.)
  if not S.cfg.Enabled then return end
  local player = U.player()
  local c = player and H.bladeCaches[U.addr(player) or 0]
  if not c then
    -- No list yet (a new pawn the map-load pass has not reached): looked up at most every 2 s.
    local now = os.clock()
    if not player or now < (H.bladeRetryAt or 0) then return end
    H.bladeRetryAt = now + 2
    U.try("hit.tipblades", H.findBlades, player)
    c = H.bladeCaches[U.addr(player) or 0]
    if not c then return end
  end
  -- Which weapons are in use: every 10 frames, and at once for a new list.
  if c ~= H.useFor or U.frame - (H.useFrame or 0) >= 10 or U.frame < (H.useFrame or 0) then
    H.useFor, H.useFrame = c, U.frame
    U.try("hit.inuse", refreshUse, player, c.list)
  end
  local blades = {}
  for _, b in ipairs(c.list) do
    local key = b.key or U.addr(b.comp)
    if key and H.bladeUse[key] ~= false and U.valid(b.comp) then
      blades[#blades + 1] = b
      local t = U.try("hit.tip", function() return U.copyv(b.comp:GetSocketLocation(b.tip or b.socket)) end)
      if t then
        local e = S.tips[key] or {}
        S.tips[key] = e
        -- (Not sampled in the last frame, put away or hidden: no speed from that old sample.)
        if e.frame and U.frame - e.frame > 1 then e.last = nil end
        e.prev, e.last, e.frame = e.last, t, U.frame
      end
    end
  end
  -- The same samples tell when a swing starts and ends (the swing trail). (The frame's time from the clock, which runs
  -- first: U.now() asks the engine, some six calls, every frame.)
  if S.vfx and S.vfx.swingStep then U.try("vfx.swing", S.vfx.swingStep, player, blades, U.frameNow or U.now()) end
end

-- How a blade's tip moved into the frame of a hit (cm), from the last sample; the one before when the last was
-- taken this frame already.
local function tipMotion(b, tipNow)
  local e = S.tips and S.tips[b.key or U.addr(b.comp) or 0]
  if not e or not e.last or not tipNow then return nil end
  local mv = U.sub(tipNow, e.last)
  if U.len(mv) < 1 and e.prev then mv = U.sub(tipNow, e.prev) end
  return U.len(mv) >= 1 and mv or nil
end

-- The blade in use: of the weapons in use (H.inUse: shown, not put away), the one whose socket is nearest a hand; none
-- in a move that hides them all. (Before v0.7.3 every carried weapon was a candidate, and the ones on your back are
-- nearer a hand than the blade socket of one in it.)
function H.activeBlade(player)
  local list = {}
  for _, b in ipairs(H.findBlades(player)) do
    if H.inUse(b) then list[#list + 1] = b end
  end
  local hands = {}
  local mesh = U.try("hit.pmesh", function() return player.Mesh end)
  if #list > 1 and U.valid(mesh) then
    for _, h in ipairs(HANDS) do
      local fn = FName(h)
      local ok, has = pcall(function() return mesh:DoesSocketExist(fn) end)
      if ok and has then
        local p = U.try("hit.hand", function() return U.copyv(mesh:GetSocketLocation(fn)) end)
        if p then hands[#hands + 1] = p end
      end
    end
  end
  local best, bestD
  for _, b in ipairs(list) do
    if U.valid(b.comp) then
      local p = U.try("hit.blade", function() return U.copyv(b.comp:GetSocketLocation(b.socket)) end)
      if p then
        local d = 0
        if #hands > 0 then
          d = math.huge
          for _, h in ipairs(hands) do d = math.min(d, U.len(U.sub(p, h))) end
        end
        if not bestD or d < bestD then best, bestD, b.point = b, d, p end
      end
    end
  end
  return best
end

function H.bladePoint()
  local player = U.player()
  if not player then return nil end
  local b = H.activeBlade(player)
  H.blade = b
  return b and b.point or nil
end

-- The weapon's own swing trail, if one is playing on it now: an active Niagara system with "trail" in its name
-- attached under the weapon mesh (our own spawns excluded). Reused as the hit's air trail, so it fits the weapon.
-- The previous hit's hit trail also hangs on the blade for a while and is skipped: the blood one, and the non-blood
-- one the game uses on doll-like enemies (v0.5.2 took that one for the weapon's trail on the YuCong boss and doubled
-- it). Where the game attached the swing trail (socket and offset on the weapon mesh) is kept too, so ours sits the
-- same way: weapon trails are authored for their own attach point.
local function isHitTrail(name)
  if name:find("blood", 1, true) then return true end
  for _, k in ipairs(S.cfg.Vfx.AirTrail.HitTrailKeywords or {}) do
    if name:find(k:lower(), 1, true) then return true end
  end
  return false
end

local function ownTrail(b)
  for _, c in ipairs(U.attachTree(b.comp, 16)) do
    if not (S.ourEffects or {})[U.addr(c) or 0] and U.chainHas(U.classChain(c), "NiagaraComponent") then
      local asset = U.try("hit.trailasset", function() return c.Asset end)
      local active = U.try("hit.trailactive", function() return c:IsActive() end)
      local name = U.valid(asset) and U.fname(asset):lower() or ""
      if active and name:find("trail", 1, true) and not isHitTrail(name) then
        local parent = U.try("hit.trailparent", function() return c.AttachParent end)
        if U.same(parent, b.comp) then
          local sock = U.try("hit.trailsocket", function() return c.AttachSocketName:ToString() end)
          local loc = U.try("hit.trailloc", function() return U.copyv(c.RelativeLocation) end)
          local rot = U.try("hit.trailrot", function() return U.copyr(c.RelativeRotation) end)
          if sock then b.trailAt = { socket = FName(sock), socketName = sock, loc = loc, rot = rot } end
        end
        return (U.fullName(asset):gsub("^%S+%s+", ""))
      end
    end
  end
end

-- One blade as a segment, now: socket to tip, or the socket extended away from the weapon's origin when there is no
-- tip socket.
local function segmentOf(b)
  local a = U.try("hit.seg.a", function() return U.copyv(b.comp:GetSocketLocation(b.socket)) end)
  if not a then return nil end
  local t = b.tip and U.try("hit.seg.b", function() return U.copyv(b.comp:GetSocketLocation(b.tip)) end)
  if not t then
    local o = U.try("hit.seg.o", function() return U.copyv(b.comp:K2_GetComponentLocation()) end)
    if o and U.len(U.sub(a, o)) > 1 then t = U.add(a, U.mul(U.sub(a, o), 0.6)) end
  end
  return a, t or a
end

-- The weapon's own trail is looked for only when something would use it: as the hit trail (UseWeaponTrail), or for
-- where it hangs, for a trail of ours that is not a hit trail (hit trails go on the blade socket, hf_vfx placement).
-- The search walks everything attached to each blade, a few dozen engine calls a blade on every hit.
local function hitTrailPath(p)
  for _, k in ipairs(S.cfg.Vfx.AirTrail.HitTrailKeywords or {}) do
    if tostring(p):find(k, 1, true) then return true end
  end
  return false
end

local function wantsOwnTrail(b)
  local v = S.cfg.Vfx
  if v.AirTrail.UseWeaponTrail then return true end
  if b.trailAt then return false end
  if v.SwingTrail and v.SwingTrail.Enabled and v.SwingTrail.Path and not hitTrailPath(v.SwingTrail.Path) then return true end
  if v.AirTrail.Enabled then
    for _, p in pairs(v.AirTrail.ByWeapon or {}) do
      if not hitTrailPath(p) then return true end
    end
  end
  return false
end

-- Every blade of the player as a segment, sampled in the frame of the hit.
-- (Only the weapons in use, H.inUse: a hidden or put-away one gave contact points too.)
function H.bladeSegments(player)
  local out = {}
  for _, b in ipairs(H.findBlades(player)) do
    if U.valid(b.comp) and H.inUse(b) then
      local a, t = segmentOf(b)
      if a then
        if wantsOwnTrail(b) then b.ownTrail = U.try("hit.owntrail", ownTrail, b) or b.ownTrail end
        out[#out + 1] = { blade = b, a = a, b = t, motion = tipMotion(b, b.tip and t or a) }
      end
    end
  end
  return out
end

local BODY_BONES = { "Head", "neck_01", "spine_05", "spine_04", "spine_03", "spine_02", "spine_01", "pelvis",
  "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r" }
H.boneCache = H.boneCache or {}

local function bodyBones(mesh)
  local key = U.addr(mesh)
  local c = key and H.boneCache[key]
  if c then
    c.frame = U.frame
    return c.list
  end
  local list = {}
  for _, n in ipairs(BODY_BONES) do
    local fn = FName(n)
    local ok, has = pcall(function() return mesh:DoesSocketExist(fn) end)
    if ok and has then list[#list + 1] = fn end
  end
  if key then H.boneCache[key] = { list = list, frame = U.frame } end
  return list
end

local function closestOnSegment(a, b, p)
  local ab = U.sub(b, a)
  local l2 = ab.X * ab.X + ab.Y * ab.Y + ab.Z * ab.Z
  if l2 < 1e-6 then return a end
  local t = ((p.X - a.X) * ab.X + (p.Y - a.Y) * ab.Y + (p.Z - a.Z) * ab.Z) / l2
  t = math.max(0, math.min(1, t))
  return U.add(a, U.mul(ab, t))
end

-- Where blade and body met: the body bone nearest any blade segment, and the point a third of the way from the
-- blade to that bone (just inside the body's surface). Done in the frame of the hit, while blade and body are
-- still where they touched. Returns impact, segment, bone name.
function H.contact(victim, segs)
  if not segs or #segs == 0 then return nil end
  local mesh = U.try("hit.vmesh", function() return victim.Mesh end)
  if not U.valid(mesh) then return nil end
  local best
  for _, bone in ipairs(bodyBones(mesh)) do
    local p = U.try("hit.bone", function() return U.copyv(mesh:GetSocketLocation(bone)) end)
    if p then
      for _, s in ipairs(segs) do
        local q = closestOnSegment(s.a, s.b, p)
        local d = U.len(U.sub(p, q))
        if not best or d < best.d then best = { d = d, p = p, q = q, seg = s, bone = bone } end
      end
    end
  end
  if not best or best.d > 250 then return nil end
  return U.add(best.q, U.mul(U.sub(best.p, best.q), 0.35)), best.seg, best.bone:ToString()
end

local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function clamp01(x) return math.max(0, math.min(1, x)) end

-- Closest points of segments p1-q1 and p2-q2 (Ericson, Real-Time Collision Detection 5.1.9).
local function closestBetween(p1, q1, p2, q2)
  local d1, d2, r = U.sub(q1, p1), U.sub(q2, p2), U.sub(p1, p2)
  local a, e, f = dot(d1, d1), dot(d2, d2), dot(d2, r)
  local s, t
  if a <= 1e-6 and e <= 1e-6 then return p1, p2 end
  if a <= 1e-6 then
    s, t = 0, clamp01(f / e)
  else
    local c = dot(d1, r)
    if e <= 1e-6 then
      s, t = clamp01(-c / a), 0
    else
      local b = dot(d1, d2)
      local denom = a * e - b * b
      s = denom > 1e-6 and clamp01((b * f - c * e) / denom) or 0
      t = (b * s + f) / e
      if t < 0 then
        s, t = clamp01(-c / a), 0
      elseif t > 1 then
        s, t = clamp01((b - c) / a), 1
      end
    end
  end
  return U.add(p1, U.mul(d1, s)), U.add(p2, U.mul(d2, t))
end

-- Where the blades met in a clash: the closest approach of the player's blade and the opponent's, when the
-- opponent's weapon has blade sockets too; else the point of the player's blade nearest the opponent's chest. (The
-- blade socket alone sits at the hilt, in the player's hand.) Returns the point and how it was found.
function H.clashPoint(b, opponent, vl, hh)
  if not b or not U.valid(b.comp) then return nil end
  local a1, b1 = segmentOf(b)
  if not a1 then return nil end
  local best
  for _, ob in ipairs((bladesOf(opponent))) do
    if U.valid(ob.comp) then
      local a2, b2 = segmentOf(ob)
      if a2 then
        local p, q = closestBetween(a1, b1, a2, b2)
        local d = U.len(U.sub(p, q))
        if d < 80 and (not best or d < best.d) then best = { d = d, at = U.mul(U.add(p, q), 0.5) } end
      end
    end
  end
  if best then return best.at, "blades" end
  return closestOnSegment(a1, b1, U.add(vl, U.v3(0, 0, hh * 0.35))), "chest"
end

-- ------------------------------------------------------------------ camera shakes

function H.shakeClass(level)
  H.shakeCache = H.shakeCache or {}
  local c = H.shakeCache[level]
  if U.valid(c) then return c end
  local path = string.format(H.SHAKE_FMT, level, level)
  c = StaticFindObject(path)
  if not U.valid(c) then
    U.note("loaded CameraShake_PlayerAttack_Level%d", level)
    c = U.try("hit.loadshake", LoadAsset, path)
  end
  H.shakeCache[level] = c
  return U.valid(c) and c or nil
end

local function readShake(info, args, index)
  local i = index.CameraShake
  if not i then return end
  local cur = args[i]:get()
  if not U.valid(cur) then
    info.noVanillaShake = true
    return
  end
  local name = U.fname(cur)
  info.vanillaShakeLevel = tonumber(name:match("^CameraShake_PlayerAttack_Level(%d)_C$"))
  info.vanillaHitShakeLevel = tonumber(name:match("^CameraShake_PlayerHit_Level(%d)_C$"))
end

H.HIT_SHAKE_FMT = "/PBZCombatAsset/Config/HitReact/CameraShake/CameraShake_PlayerHit_Level%d.CameraShake_PlayerHit_Level%d_C"

-- A blow on the player: the game's own being-hit shake (levels 1-4), raised by Receive.Hit.ShakeUpgrade.
local function boostPlayerHit(info, args, index)
  local r, i, lvl = S.cfg.Receive, index.CameraShake, info.vanillaHitShakeLevel
  if not r or not r.Enabled or not S.cfg.Camera.Enabled or not i or not lvl then return end
  local target = math.min(4, lvl + (tonumber((r.Hit or {}).ShakeUpgrade) or 0))
  if target <= lvl then return end
  local path = string.format(H.HIT_SHAKE_FMT, target, target)
  local cls = StaticFindObject(path)
  if not U.valid(cls) then
    U.note("loaded CameraShake_PlayerHit_Level%d", target)
    cls = U.try("hit.loadhitshake", LoadAsset, path)
  end
  if not U.valid(cls) then return end
  args[i]:set(cls)
  info.hitShakeLevel = target
  if not H.hitShakeLogged then
    H.hitShakeLogged = true
    U.log("receive: the game's being-hit shake CameraShake_PlayerHit_Level%d is raised to %d", lvl, target)
  end
end

-- Raises the vanilla attack camera shake before the game plays it. A hit the game gives no shake at all (the dual
-- blades' very light and light hits) gets the level the game gives the one-hand blade for that strength; a slot
-- holding some other shake (a kick's, say) is left alone.
local function boostVanilla(info, args, index)
  local c, i = S.cfg.Camera, index.CameraShake
  if not c.Enabled or not i then return end
  local lvl, target = info.vanillaShakeLevel, nil
  if lvl then
    local up = C.tier(c.VanillaShakeUpgrade, info.tierName) or 0
    if up <= 0 then return end
    target = math.min(4, lvl + up)
    if target == lvl then return end
  elseif info.noVanillaShake and c.FillEmptyShake then
    target = tonumber(C.tier(c.FillShakeLevel, info.tierName))
    if not target or target < 0 then return end
    target = math.min(4, math.floor(target))
  else
    return
  end
  local cls = H.shakeClass(target)
  if cls then
    args[i]:set(cls)
    info.shakeLevel = target
    if not lvl and not H.fillLogged then
      H.fillLogged = true
      U.log("camera: a %s hit with no vanilla shake now plays CameraShake_PlayerAttack_Level%d (Camera.FillShakeLevel)",
        tostring(info.tierName), target)
    end
  end
end

-- Class names of the camera shakes playing now, from the engine's shake modifier. (v0.3 also walked PBZ's shake
-- manager map through FindAllOf on every deflect; it never returned anything, and FindAllOf on a timer and map
-- iteration are both known ways to crash UE4SS, so it is gone.)
function H.activeShakes()
  local names = {}
  local pcm = U.pcm()
  if pcm then
    pcall(function()
      local mod = pcm.CachedCameraShakeMod
      if not U.valid(mod) then return end
      mod.ActiveShakes:ForEach(function(_, e)
        local inst = e:get().ShakeInstance
        if U.valid(inst) then names[#names + 1] = U.className(inst) end
      end)
    end)
  end
  return names
end

-- ------------------------------------------------------------------ deflects

-- The game's own clash slomo pair, started before the deflect lookups of the same frame.
local function noteClash(rec)
  local cl = H.clash
  if not (cl and sameFrame(cl.time, rec.time)) then
    cl = { time = rec.time, mult = rec.mult, frames = rec.frames, owners = {} }
    H.clash = cl
  end
  if rec.owner then cl.owners[#cl.owners + 1] = rec.owner end
end

-- "game", "mult", "all_perfect" or "all_guard"; an "auto" kept from older settings is "game".
local function classifyMode()
  local m = S.cfg.Deflect.Classify or "game"
  return m == "auto" and "game" or m
end

-- The game's word on a perfect deflect for the clash at `t`: a signal from PerfectWindowMs before (the deflect frame
-- comes about 90 ms ahead of the clash lookups) to a little after (the choosers may pick their effects after the
-- lookups), not yet taken by another clash.
local function perfectSignal(t)
  local sig = H.perfect
  if not sig or (sig.taken and not sameFrame(sig.taken, t)) then return nil end
  local dt = t - sig.time
  if dt > (S.cfg.Deflect.PerfectWindowMs or 250) / 1000 or dt < -0.1 then return nil end
  sig.taken = t
  return sig
end

-- Once, when a parry is sorted before any of the game's perfect signals could be hooked.
local function warnUnhooked()
  if H.unhookedWarned then return end
  for _, p in ipairs({ H.PERFECT_PATH, H.PERFECT_FINAL_PATH, H.DEFLECT_FRAME_PATH }) do
    if S.hooked[p] then return end
  end
  H.unhookedWarned = true
  U.log("deflect: none of the game's perfect-deflect signals is hooked yet, so this parry counts as a normal one (Deflect.Classify = \"mult\" brings back the old guess)")
end

-- A perfect deflect from the game: its perfect choosers picking the clash effects (PerfectFinal: the final one of a
-- string), or its deflect frame reporting a perfect result. A clash this frame already sorted as a guard (its lookups
-- came first) turns perfect before its slomo calls run.
local function notePerfect(final, from)
  local t = U.now()
  local sig = H.perfect
  if not (sig and sameFrame(sig.time, t)) then
    sig = { time = t }
    H.perfect = sig
  end
  sig.final = sig.final or final
  if not (sig.from or ""):find(from, 1, true) then sig.from = sig.from and (sig.from .. "+" .. from) or from end
  H.perfects = (H.perfects or 0) + 1
  local fd = H.frameDeflect
  -- (The choosers pick effects for every clash: two others' perfect deflect is theirs, and is used up with it.)
  if fd and sameFrame(fd.time, t) and fd.mine == false then sig.taken = t end
  if fd and sameFrame(fd.time, t) and fd.mine ~= false and not fd.playerAttacked and fd.tier == "Guard" and classifyMode() == "game" then
    fd.perfect, fd.tier, fd.final, fd.by, sig.taken = true, "Perfect", sig.final, sig.from, t
  end
  if H.perfects <= 4 then U.log("deflect: the game's %s said perfect%s", from, final and " (the final one)" or "") end
end

function H.onPerfectChooser() notePerfect(false, "perfect chooser") end
function H.onPerfectFinalChooser() notePerfect(true, "perfect-final chooser") end

local FRAME_READ = { Result = true }
-- GAA_DeflectFrame:Process Deflect Frame (blueprint, after it runs): the deflect's result tag, on the first beat. Each
-- new result name is logged once; one naming Perfect (not a perfect dodge) is the game's perfect deflect.
function H.onDeflectFrame(Context, ...)
  local args = table.pack(...)
  H.frameDescs = H.frameDescs or H.paramDescs(H.DEFLECT_FRAME_PATH) or {}
  local tag = U.tagName(U.readParams(args, H.frameDescs, FRAME_READ).Result)
  if not tag then return end
  H.frameResults = H.frameResults or {}
  if not H.frameResults[tag] then
    H.frameResults[tag] = true
    U.log("deflect: deflect frame result %s", tag)
  end
  if tag:find("Perfect", 1, true) and not tag:find("Dodge", 1, true) then notePerfect(false, "deflect frame") end
end

-- How hard a clash lands, for its freeze and the rest: a guard weighs the attack it stopped (GuardByStrength), a
-- perfect deflect repeated in a flurry less (RepeatPerfectScale), the game's final one more (FinalEmph).
function H.deflectWeight(tier, strengthTier, rhythm, final)
  local d = S.cfg.Deflect
  if tier == "Guard" then return C.tier(d.GuardByStrength, strengthTier or "Middle") or 1 end
  if tier ~= "Perfect" then return 1 end
  if final then return d.FinalEmph or 1.3 end
  return rhythm and rhythm.repeated and (d.RepeatPerfectScale or 0.5) or 1
end

-- Assets the hooks above need loaded (and held, hf_preload) before the first perfect deflect: the game may load the
-- perfect choosers only when one happens.
-- With the game's shake classes the hit lookups may swap in (your attacks' levels 0-4, being hit 1-4): one not yet
-- loaded was a load from disk in the middle of a fight, on the frame of the hit.
function H.assetPaths(out)
  for _, p in ipairs({ H.PERFECT_CLASS, H.PERFECT_FINAL_CLASS, H.DEFLECT_FRAME_CLASS }) do out[#out + 1] = p end
  for lvl = 0, 4 do out[#out + 1] = string.format(H.SHAKE_FMT, lvl, lvl) end
  for lvl = 1, 4 do out[#out + 1] = string.format(H.HIT_SHAKE_FMT, lvl, lvl) end
end

-- The clash slow-down follows the strength of the attack that was stopped: 0.7 light, 0.5 middle, 0.3 heavy.
local function strengthOfMult(mult)
  if not mult then return "Middle" end
  if mult >= 0.6 then return "Light" end
  if mult >= 0.4 then return "Middle" end
  return "Heavy"
end

local TIER_STRENGTH = { VeryLight = "Light", Light = "Light", Middle = "Middle", Heavy = "Heavy", UltraHeavy = "Heavy",
  Break = "Heavy", Default = "Middle" }

-- Whether you are in this clash: a lookup on your side (your material), or one of the game's clash pair started on
-- you. NPCs parry each other too (rival sects, bandits and dolls), anywhere on the map, and up to v0.7.0 each of those
-- parries was taken for yours: your camera kicked and the sparks went off beside you. false: the pair's owners are
-- known and you are not one of them; nil: nothing tells yet. A later lookup or slomo call of the frame can still
-- make it true (H.onStartSlomo).
local function clashIsMine(info, cl)
  if info.onPlayer then return true end
  if not (cl and sameFrame(cl.time, info.time) and #cl.owners > 0) then return nil end
  local player = U.player()
  if not player then return nil end
  for _, o in ipairs(cl.owners) do
    if U.same(o, player) then return true end
  end
  return false
end

-- Perfect / Guard / Blocked for this frame's deflect. Decided at the first deflect lookup, in time for the slomo
-- writes that follow it, and kept for the frame. Each lookup is "X hit Y" with Y's material, so Attacker with
-- PlayerMeat (or Defender with Meat) means an enemy blocked the player's attack.
function H.deflectTier(info)
  local fd = H.frameDeflect
  if fd and sameFrame(fd.time, info.time) then
    if info.onPlayer then fd.mine = true end
    return fd
  end
  local d = S.cfg.Deflect
  fd = { time = info.time }
  H.frameDeflect = fd
  fd.playerAttacked = (info.deflectSide == "Attacker") == (info.onPlayer == true)
  local cl = H.clash
  if cl and sameFrame(cl.time, info.time) then fd.mult = cl.mult end
  fd.mine = clashIsMine(info, cl)
  fd.strengthTier = strengthOfMult(fd.mult)
  if fd.mine ~= false then fd.lookupShakes = H.activeShakes() end
  if fd.playerAttacked then
    fd.tier, fd.by = "Blocked", "side"
    return fd
  end
  local mode = classifyMode()
  if mode == "all_perfect" or mode == "all_guard" then
    fd.perfect, fd.by = mode == "all_perfect", "config"
  elseif mode == "mult" then
    fd.perfect = fd.mult ~= nil and fd.mult < (d.PerfectBelowMult or 0.4)
    fd.by = fd.mult and "mult" or "default"
  else
    local sig
    if fd.mine == false then
      -- Two others' clash: only a signal of this very frame can be theirs, and it is used up here.
      sig = H.perfect
      if sig and sameFrame(sig.time, info.time) and not sig.taken then sig.taken = info.time else sig = nil end
    else
      sig = perfectSignal(info.time)
      if not sig then warnUnhooked() end
    end
    fd.perfect, fd.final, fd.by = sig ~= nil, sig and sig.final, sig and sig.from or "game"
  end
  fd.tier = fd.perfect and "Perfect" or "Guard"
  return fd
end

-- A player hit that lands on a shield (Hitreact.Material.Shield.*) is a block too. Yours for sure with the ".Player"
-- tag; known by its shake alone, once your slomo call comes first (claim).
local function shieldBlock(info)
  if not info.normal or not info.likelyPlayer then return end
  if not U.matchesAny(info.material or "", S.cfg.Hit.BlockMaterials or {}) then return end
  info.blockHit = true
  info.deflect = { time = info.time, tier = "Blocked", by = "material", playerAttacked = true,
    strengthTier = TIER_STRENGTH[info.tierName] or "Middle", mine = info.surePlayer or nil }
end

-- A lookup known to be yours: the blade point before the hit (for the swing), the blade segments (for the contact,
-- found in the struck side's slomo call) and its place in the rhythm (for its hold). Done at the lookup when that is
-- sure, else at the slomo call that names you, still before the struck side's call decides the hold. NPCs' blows on
-- each other used to take a place in your rhythm too, and in a crowded fight their density fatigue lightened your
-- own hits.
-- (The blade is read once a frame: one swing through a crowd claims a lookup for each enemy, all in the same frame,
-- and each read was some thirty engine calls.)
local function claim(info)
  if info.claimed then return end
  info.claimed = true
  local now = H.bladeFrame
  if not (now and sameFrame(now.time, info.time)) then
    now = { time = info.time, point = H.bladePoint() }
    H.bladeFrame = now
  end
  info.blade = now.point
  if not info.deflectSide then
    if now.segs == nil then
      local player = U.player()
      now.segs = player and U.try("hit.segs", H.bladeSegments, player) or false
    end
    info.segs = now.segs or nil
  end
  if not (S.cfg.Enabled and S.rhythm) then return end
  if info.deflect then
    U.try("hit.rhythm", S.rhythm.markDeflect, info)
    info.deflect.rhythm = info.deflect.rhythm or info.rhythm
  elseif not info.onPlayer then
    U.try("hit.rhythm", S.rhythm.mark, info)
  end
end

-- BP_DeflectHitreactAttackSource:GetHitStrength (blueprint, after it runs): its Counter / "Is Source Attacker" flags,
-- logged with each deflect to tell perfect deflects apart in a later version. Read only.
function H.onDeflectSource(Context)
  local src = Context:get()
  if not U.valid(src) then return end
  local counter = U.try("hit.counter", function() return src["Counter"] end)
  local attacker = U.try("hit.srcatt", function() return src["Is Source Attacker"] end)
  local t = U.now()
  local cur = H.deflectSources
  if not (cur and sameFrame(cur.time, t)) then
    cur = { time = t, flags = {} }
    H.deflectSources = cur
  end
  cur.flags[#cur.flags + 1] = string.format("%s/%s", counter and "C" or "-", attacker and "A" or "D")
end

-- ------------------------------------------------------------------ hooks

function H.addEvent(info)
  H.pending[#H.pending + 1] = { info = info, time = info.time }
  if not H.flushQueued then
    H.flushQueued = true
    U.afterFrames(1, function()
      H.flushQueued = false
      U.try("hit.flush", H.flush)
    end, "hit dispatch")
  end
end

local function gedDescs()
  if not H.gedDescsCache then
    H.gedDescsCache = H.paramDescs(H.GED_PATH) or {}
    H.gedIndex = {}
    local names = {}
    for i, d in ipairs(H.gedDescsCache) do
      H.gedIndex[d.name] = i
      names[i] = d.name .. ":" .. U.typeDesc(d)
    end
    U.log("GetEffectData params: %s", table.concat(names, ", "))
  end
  return H.gedDescsCache, H.gedIndex
end

function H.onGetEffectData(Context, ...)
  local args = table.pack(...)
  local descs, index = gedDescs()
  local tags = U.readParams(args, descs, TAG_READ)
  local info = { objects = {}, time = U.now(), tags = {}, calls = 0 }
  info.attackTag, info.strengthTag, info.materialTag = U.tagName(tags.AttackType), U.tagName(tags.HitStrength), U.tagName(tags.BodyMaterial)
  for _, t in ipairs({ info.attackTag, info.strengthTag, info.materialTag }) do info.tags[#info.tags + 1] = t end
  classify(info)
  H.effects = H.effects + 1
  H.lastGed = info
  if not info.relevant then
    H.ignored = H.ignored + 1
    return
  end
  local vals = U.readParams(args, descs, ASSET_READ)
  for _, name in ipairs(ASSET_PARAMS) do
    local i = index[name]
    if i and vals[name] ~= nil then collect(info, vals[name], descs[i], name) end
  end
  if vals.SlomoData ~= nil then
    pcall(function() info.vanillaFrames, info.vanillaMult = vals.SlomoData.Frames, vals.SlomoData.Multiplier end)
  end
  U.try("hit.shake", readShake, info, args, index)
  info.likelyPlayer = playerHint(info)
  -- (Without owner reads nothing names the attacker later, so the shake is taken at its word, as before v0.7.1.)
  info.surePlayer = info.likelyPlayer and (info.playerTag or not S.cfg.Hit.ReadSlomoOwner)
  if info.deflectSide then
    info.deflect = H.deflectTier(info)
    if info.deflect.mine then claim(info) end
  else
    shieldBlock(info)
    if info.surePlayer then claim(info) end
  end
  if S.cfg.Enabled then
    -- (The shake must be decided here, before the calls name the attacker. One upgraded on two others' hit should
    -- not play: the game's helper is handed both sides and this slot is its PlayerAttack one. Not checked in game.)
    if info.likelyPlayer and not info.blockHit then U.try("hit.boost", boostVanilla, info, args, index) end
    if info.onPlayer and not info.deflectSide then U.try("hit.boosthit", boostPlayerHit, info, args, index) end
    if S.freeze and vals.SlomoData ~= nil then U.try("freeze.effect", S.freeze.onEffect, info, vals.SlomoData) end
  end
  if S.probe then U.try("probe.effect", S.probe.onEffect, info, args, descs) end
  H.addEvent(info)
end

-- One swing through a crowd (or a skill's area) strikes many enemies in one frame. Past the first
-- Hit.MaxFullPerFrame of them, in the order struck, a hit gets its hit stop only: no contact point here, and nothing
-- more at its dispatch. Each of those hits was a few hundred engine calls, all in one frame.
local function crowded(rec)
  local cap = tonumber(S.cfg.Hit.MaxFullPerFrame) or 3
  local key = cap > 0 and U.addr(rec.owner)
  if not key then return false end
  local f = H.struck
  if not (f and sameFrame(f.time, rec.time)) then
    f = { time = rec.time, n = 0, order = {} }
    H.struck = f
  end
  if not f.order[key] then
    f.n = f.n + 1
    f.order[key] = f.n
  end
  return f.order[key] > cap
end

function H.onStartSlomo(Context, ...)
  local args = table.pack(...)
  H.slomoDescsCache = H.slomoDescsCache or H.paramDescs(H.SLOMO_PATH) or {}
  local p = U.readParams(args, H.slomoDescsCache, SLOMO_READ)
  local rec = { time = U.now() }
  if p.SlomoID ~= nil then
    local ok, s = pcall(function() return p.SlomoID:ToString() end)
    rec.id = ok and s or nil
  end
  if p.SlomoData ~= nil then
    pcall(function()
      rec.frames, rec.mult = p.SlomoData.Frames, p.SlomoData.Multiplier
      rec.useDuration = p.SlomoData.UseSlomoDuration
    end)
  end
  if S.cfg.Hit.ReadSlomoOwner and p.RuntimeData ~= nil then
    local ok, o = pcall(function() return p.RuntimeData.Owner end)
    if ok and U.valid(o) then rec.owner = o end
  end
  H.slomos = H.slomos + 1
  local player = U.player()
  rec.isPlayer = rec.owner ~= nil and player ~= nil and U.same(rec.owner, player)
  local ged = H.lastGed
  if ged and sameFrame(ged.time, rec.time) then
    ged.calls = ged.calls + 1
    rec.callIndex = ged.calls
    if ged.calls == 1 and rec.owner then
      ged.attackerIsPlayer = rec.isPlayer
      if rec.isPlayer and ged.relevant and not ged.deflectSide then claim(ged) end
    end
    -- A clash or a shield block with one of its calls on you is yours.
    if rec.isPlayer and ged.deflect and not ged.deflect.mine then
      ged.deflect.mine = true
      claim(ged)
    end
    if ged.calls >= 2 and rec.owner and not rec.isPlayer then
      ged.victims = ged.victims or {}
      ged.victims[#ged.victims + 1] = rec.owner
      local mine = ged.attackerIsPlayer or (ged.attackerIsPlayer == nil and ged.likelyPlayer)
      if mine and #ged.victims == 1 and not ged.deflectSide and not ged.blockHit then ged.crowd = crowded(rec) end
      -- Contact point now, in the frame of the hit; one frame later the blade has already swung on.
      if ged.segs and not ged.impact and mine and not ged.crowd then
        local impact, seg, bone = U.try("hit.contact", H.contact, rec.owner, ged.segs)
        if impact then ged.impact, ged.hitSeg, ged.hitBone = impact, seg, bone end
      end
    end
    if S.cfg.Enabled and S.freeze and ged.relevant and p.SlomoData ~= nil then
      U.try("freeze.slomo", S.freeze.onSlomoCall, rec, ged, p.SlomoData)
    end
    rec.ignored = not ged.relevant
  elseif rec.id == "Hitreact" and (rec.frames or 0) > 0 then
    noteClash(rec)
  end
  local list = H.recentSlomos
  list[#list + 1] = rec
  if #list > 64 then table.remove(list, 1) end
  if S.probe and not rec.ignored then U.try("probe.slomo", S.probe.onSlomo, rec) end
end

-- ------------------------------------------------------------------ dispatch

local function slomosAt(t)
  local out = {}
  for _, r in ipairs(H.recentSlomos) do
    if sameFrame(r.time, t) then out[#out + 1] = r end
  end
  return out
end

local function nearestEnemy(player, maxDist)
  local pl = U.actorLoc(player)
  if not pl then return nil end
  local fwd = U.try("hit.fwd", function() return U.copyv(player:GetActorForwardVector()) end) or U.v3(1, 0, 0)
  local best, bestScore
  for _, c in ipairs(FindAllOf("Character") or {}) do
    if U.valid(c) and not U.same(c, player) then
      local l = U.actorLoc(c)
      if l then
        local dx, dy, dz = l.X - pl.X, l.Y - pl.Y, l.Z - pl.Z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist < maxDist then
          local dot = (dx * fwd.X + dy * fwd.Y) / math.max(dist, 1)
          local score = dist * (1.6 - dot)
          if dot > -0.2 and (not bestScore or score < bestScore) then best, bestScore = c, score end
        end
      end
    end
  end
  return best
end

local function otherOwner(slomos, player)
  for _, r in ipairs(slomos) do
    if r.owner and not U.same(r.owner, player) and U.valid(r.owner) then return r.owner end
  end
end
H.otherOwner = otherOwner

-- Contact point: from the hit frame when known, else the point of the victim's capsule nearest the blade, else an
-- estimate in front of the victim. A clash happens at the blade itself.
local function geometry(ctx, target, bladeBefore, info)
  local vl = U.actorLoc(target)
  if not vl then return end
  local pl = U.actorLoc(ctx.player)
  local dir = pl and U.norm(U.flat(U.sub(vl, pl))) or U.v3(1, 0, 0)
  ctx.dirVec, ctx.right, ctx.victimLoc = dir, U.v3(-dir.Y, dir.X, 0), vl
  -- Contact found in the frame of the hit (blade segments against body bones): use it, and take the swing direction
  -- from how that blade's tip moved into the hit; failing that, from how far it has moved since.
  local seg = info and info.hitSeg
  if info and info.impact then
    ctx.impact, ctx.hitBone = info.impact, info.hitBone
    if seg and U.valid(seg.blade.comp) then
      H.blade, ctx.blade = seg.blade, seg.blade
      local b = seg.blade
      if seg.motion then
        ctx.sweep, ctx.sweepFrom = U.norm(seg.motion), "into"
      else
        local now = U.try("hit.tipnow", function() return U.copyv(b.comp:GetSocketLocation(b.tip or b.socket)) end)
        local mv = now and U.sub(now, b.tip and seg.b or seg.a)
        if mv and U.len(mv) > 2 then ctx.sweep, ctx.sweepFrom = U.norm(mv), "after" end
      end
    end
    return
  end
  local hh, r = U.capsule(target)
  local blade = H.bladePoint()
  if blade and U.len(U.sub(blade, vl)) < hh + r + 150 then
    if ctx.kind == "deflect" then
      local at, how = U.try("hit.clash", H.clashPoint, H.blade, target, vl, hh)
      ctx.impact, ctx.hitBone = at or blade, how or "hilt"
    else
      local z = math.max(vl.Z - (hh - r), math.min(vl.Z + (hh - r), blade.Z))
      local center = U.v3(vl.X, vl.Y, z)
      local d = U.sub(blade, center)
      local len = U.len(d)
      ctx.impact = len < 1 and center or U.add(center, U.mul(d, r / len))
    end
    if bladeBefore then
      local mv = U.sub(blade, bladeBefore)
      if U.len(mv) > 2 then ctx.sweep = U.norm(mv) end
    end
  elseif ctx.kind == "deflect" and pl then
    local dist = U.len(U.flat(U.sub(vl, pl)))
    ctx.impact = U.add(pl, U.add(U.mul(dir, math.min(dist * 0.5, 90)), U.v3(0, 0, hh * 0.45)))
    ctx.impactEstimated = true
  else
    ctx.impact = U.add(U.sub(vl, U.mul(dir, r * 0.9)), U.v3(0, 0, hh * 0.35))
    ctx.impactEstimated = true
  end
end

-- ctx.ours: you are in it (your hit, a blow on you, your clash). Others' fights reach only the probe and the captures.
local function run(ctx)
  if S.probe then U.try("probe.hit", S.probe.onHit, ctx) end
  -- Your fighting, for the perf log, mod on or off; others' blows only counted.
  if S.perf then
    if ctx.ours then S.perf.fight(ctx) else S.perf.other() end
  end
  -- Captures read vanilla assets even while the mod is toggled off, so they are ready when it comes back on.
  if S.capture then U.try("capture", S.capture, ctx) end
  if not S.cfg.Enabled or ctx.duplicate or not ctx.ours then return end
  -- (The crash trail, logs/recent.txt. The material, not the victim's class: that would be three engine calls a hit.)
  U.crumb("%s %s on %s%s", ctx.kind, tostring(ctx.tierName), ctx.playerVictim and "you" or tostring(ctx.material or "?"),
    ctx.light and " (crowd: hit stop only)" or "")
  if ctx.light then
    H.lightHits = H.lightHits + 1
    if S.perf then S.perf.crowd() end
    return
  end
  local perf = S.perf
  for _, l in ipairs(H.listeners) do
    local t0 = os.clock()
    U.try(l.name, l.fn, ctx)
    if perf then perf.feature(l.name, (os.clock() - t0) * 1000) end
  end
end

local function dispatchHit(ev, player)
  local info = ev.info
  local ctx = { kind = "hit", time = ev.time, player = player, tags = info.tags, objects = info.objects }
  for _, k in ipairs({ "tierName", "level", "special", "material", "weapon", "attackTag", "vanillaFrames",
    "vanillaMult", "shakeLevel", "vanillaShakeLevel", "freezeApplied", "rhythm", "guardBreak" }) do
    ctx[k] = info[k]
  end
  ctx.slomos = slomosAt(ev.time)
  local byPlayer = info.attackerIsPlayer
  if byPlayer == nil then byPlayer = info.likelyPlayer end
  if info.onPlayer or not byPlayer then
    ctx.byPlayer, ctx.playerVictim, ctx.ours = false, info.onPlayer, info.onPlayer == true
    ctx.method = info.onPlayer and "player-hit" or "not-player-attack"
    return run(ctx)
  end
  ctx.ours = true
  for _, v in ipairs(info.victims or {}) do
    if U.valid(v) and not U.same(v, player) then
      ctx.victim, ctx.method = v, "slomo-owner"
      break
    end
  end
  if not ctx.victim then
    ctx.victim = otherOwner(ctx.slomos, player)
    ctx.method = ctx.victim and "slomo-frame" or nil
  end
  if not ctx.victim then
    ctx.victim = nearestEnemy(player, S.cfg.Hit.MaxVictimDistanceCm)
    ctx.method = ctx.victim and "nearest" or "none"
  end
  ctx.attacker = player
  ctx.byPlayer = ctx.victim ~= nil
  if ctx.byPlayer then
    local key = U.addr(ctx.victim)
    local last = key and H.lastByVictim[key]
    if last and (ctx.time - last.time) * 1000 < S.cfg.Hit.DedupeMs and ctx.level <= last.level then
      ctx.duplicate = true
    elseif key then
      H.lastByVictim[key] = { time = ctx.time, level = ctx.level }
    end
    -- Past the first Hit.MaxFullPerFrame enemies struck in this frame (crowded, at the slomo call): its hit stop only,
    -- already set at its slomo calls.
    if info.crowd and not ctx.duplicate then
      ctx.light = true
      if not H.crowdLogged then
        H.crowdLogged = true
        local cap = tonumber(S.cfg.Hit.MaxFullPerFrame) or 3
        U.log("crowd: more than %d enemies struck in one frame; the first %d get the whole feedback, the rest their hit stop only (Hit.MaxFullPerFrame)",
          cap, cap)
      end
    end
    if not ctx.light then geometry(ctx, ctx.victim, info.blade, info) end
  end
  H.hits = H.hits + 1
  ctx.index = H.hits
  run(ctx)
end

local function dispatchDeflect(list, player)
  local d = S.cfg.Deflect
  local first = list[1].info
  local fd = first.deflect or H.deflectTier(first)
  local t = list[1].time
  local blade
  for _, ev in ipairs(list) do blade = blade or ev.info.blade end
  local slomos = slomosAt(t)
  local ctx = { kind = "deflect", time = t, player = player, slomos = slomos, objects = {}, tags = {},
    playerDefended = not fd.playerAttacked, playerDeflected = fd.playerAttacked, clashMult = fd.mult,
    strengthTier = fd.strengthTier, classifiedBy = fd.by, freezeTier = fd.tier, freezeApplied = first.freezeApplied,
    lookupShakes = fd.lookupShakes, blockSource = first.blockHit and "shield" or nil }
  for _, ev in ipairs(list) do
    for _, tg in ipairs(ev.info.tags) do ctx.tags[#ctx.tags + 1] = tg end
  end
  if fd.mine ~= true then
    -- No lookup on your side and no slomo call on you: two others parried each other, wherever on the map.
    H.othersClashes = (H.othersClashes or 0) + 1
    if H.othersClashes == 1 then
      local names, cl = {}, H.clash
      for _, o in ipairs(cl and sameFrame(cl.time, t) and cl.owners or {}) do
        if U.valid(o) then names[#names + 1] = U.className(o) end
      end
      U.log("deflect: a clash without you (%s); others' fights get no feedback (logged once)",
        #names > 0 and table.concat(names, " and ") or "its sides unknown")
    end
    ctx.method, ctx.byPlayer, ctx.playerDefended, ctx.playerDeflected = "others", false, false, false
    return run(ctx)
  end
  ctx.ours = true
  local src = H.deflectSources
  if src and sameFrame(src.time, t) then ctx.counterFlags = table.concat(src.flags, ",") end
  ctx.shakes = H.activeShakes()
  -- The game's perfect signal can come after the lookups: one frame on, it still turns a guard perfect for everything
  -- but the freeze, which was decided at the lookups.
  local tier = fd.tier
  if tier == "Guard" and not fd.playerAttacked and classifyMode() == "game" then
    local sig = perfectSignal(t)
    if sig then tier, ctx.classifiedBy, fd.final = "Perfect", sig.from, sig.final end
  end
  ctx.tierName, ctx.perfect = tier, tier == "Perfect"
  ctx.final = ctx.perfect and fd.final or nil
  ctx.level = tier == "Perfect" and 5 or (tier == "Guard" and 3 or 2)
  -- How hard it lands (H.deflectWeight), for the features that scale by a hit's emphasis. (A clash known as yours only
  -- at its second lookup has its place in the rhythm there: fd keeps it.)
  local rhythm = first.rhythm or fd.rhythm
  ctx.rhythm = { emph = H.deflectWeight(tier, ctx.strengthTier, rhythm, ctx.final), repeated = rhythm and rhythm.repeated }
  if ctx.perfect and classifyMode() == "game" then
    H.perfectClashes = (H.perfectClashes or 0) + 1
    if H.perfectClashes <= 3 then
      U.log("deflect: perfect, by the game's %s%s", tostring(ctx.classifiedBy), ctx.final and ", the final one" or "")
    end
  end
  if fd.playerAttacked and not d.OnEnemyDeflect then
    ctx.method = "enemy-deflect-off"
    return run(ctx)
  end
  local cl = H.clash
  if cl and sameFrame(cl.time, t) then
    for _, o in ipairs(cl.owners) do
      if U.valid(o) and not U.same(o, player) then
        ctx.victim = o
        break
      end
    end
  end
  for _, v in ipairs(first.victims or {}) do
    if not ctx.victim and U.valid(v) and not U.same(v, player) then ctx.victim = v end
  end
  ctx.victim = ctx.victim or otherOwner(slomos, player) or nearestEnemy(player, S.cfg.Hit.MaxVictimDistanceCm)
  ctx.method = ctx.victim and "deflect" or "none"
  ctx.attacker = player
  ctx.byPlayer = ctx.victim ~= nil
  if ctx.byPlayer then geometry(ctx, ctx.victim, blade) end
  H.deflects = H.deflects + 1
  ctx.index = H.hits + H.deflects
  run(ctx)
end

function H.flush()
  local events = H.pending
  H.pending = {}
  local player = U.player()
  if not player then return end
  local deflects = {}
  for _, ev in ipairs(events) do
    if ev.info.deflectSide then
      deflects[#deflects + 1] = ev
    elseif ev.info.blockHit then
      -- Yours when your slomo call came first; with no owner read at all, by its shake as before.
      local fd = ev.info.deflect
      if fd.mine == nil and ev.info.attackerIsPlayer == nil then fd.mine = ev.info.likelyPlayer end
      if S.cfg.Deflect.Enabled and fd.mine then U.try("hit.block", dispatchDeflect, { ev }, player) end
    else
      U.try("hit.dispatch", dispatchHit, ev, player)
    end
  end
  if #deflects > 0 and S.cfg.Deflect.Enabled then U.try("hit.deflect", dispatchDeflect, deflects, player) end
end

-- What is kept per enemy or blade, by address, goes once it is no longer used: nothing else removes it, and a freed
-- object's address comes back as a new one. (The blade lists prune themselves at each scan.) hf_perf calls this
-- every few seconds; `now` is U.now().
function H.prune(now)
  local keep = (S.cfg.Hit.DedupeMs or 0) / 1000 + 1
  for k, last in pairs(H.lastByVictim) do
    if now - last.time > keep then H.lastByVictim[k] = nil end
  end
  for k, c in pairs(H.boneCache) do
    if U.frame - c.frame > 1800 then H.boneCache[k] = nil end
  end
  for k, e in pairs(S.tips or {}) do
    if U.frame - (e.frame or 0) > 600 then S.tips[k] = nil end
  end
end

-- ------------------------------------------------------------------ registration

local NOOP = function() end
H.DEFLECT_SRC_PATH = "/PBZDeflectSystem/BP_DeflectHitreactAttackSource.BP_DeflectHitreactAttackSource_C:GetHitStrength"
local HANDLERS = { [H.GED_PATH] = "onGetEffectData", [H.SLOMO_PATH] = "onStartSlomo",
  [H.DEFLECT_SRC_PATH] = "onDeflectSource", [H.PERFECT_PATH] = "onPerfectChooser",
  [H.PERFECT_FINAL_PATH] = "onPerfectFinalChooser", [H.DEFLECT_FRAME_PATH] = "onDeflectFrame" }
-- Optional hooks, tried alongside the two the mod needs until they exist.
local OPTIONAL = { H.DEFLECT_SRC_PATH, H.PERFECT_PATH, H.PERFECT_FINAL_PATH, H.DEFLECT_FRAME_PATH }
local function allOptional()
  for _, p in ipairs(OPTIONAL) do
    if not S.hooked[p] then return false end
  end
  return true
end

-- Blueprint functions: one callback, after the call. Native functions: the callback goes before the call.
-- Callbacks reach the current module through S.hit, so Ctrl+F8 can swap in reloaded code under the same hooks.
local function hook(path, native)
  if S.hooked[path] then return true end
  if not U.valid(StaticFindObject(path)) then return false end
  local name = HANDLERS[path]
  local tag = "hook " .. name
  local cb = function(Context, ...)
    local h = S.hit
    if not (h and h[name]) then return end
    U.costBegin()
    U.try(tag, h[name], Context, ...)
    U.costEnd(tag)
  end
  local ok, a, b
  if native then
    ok, a, b = pcall(RegisterHook, path, cb, NOOP)
  else
    ok, a, b = pcall(RegisterHook, path, cb)
  end
  if ok then
    S.hooked[path] = { a, b }
    U.log("hooked %s", path)
  else
    U.log("RegisterHook failed for %s: %s", path, tostring(a))
  end
  return ok
end

-- True once the two hooks the mod needs exist; the optional ones (the deflect-source observer, the game's perfect
-- deflect signals) are tried alongside.
local function tryRegister()
  local slomo = hook(H.SLOMO_PATH, true)
  local ged = hook(H.GED_PATH, false)
  for _, p in ipairs(OPTIONAL) do hook(p, false) end
  return slomo and ged
end

-- The chooser and deflect blueprints load with gameplay (the perfect choosers maybe only with the first perfect
-- deflect, so the preloader loads them too), so keep retrying once a second until the needed hooks exist, then for
-- up to an hour for the optional ones. A hook stays registered for the session (S.hooked) and calls the current
-- module; a reload restarts the retries with the new copy's list of hooks.
function H.start()
  H.trackTips()
  if tryRegister() and allOptional() then
    U.stopLoop("hit.register")
    return
  end
  local tries = 0
  U.loop("hit.register", function()
    tries = tries + 1
    local needed = U.try("hit.register", tryRegister)
    return needed and (allOptional() or tries > 3600)
  end, 1000)
end

return H
