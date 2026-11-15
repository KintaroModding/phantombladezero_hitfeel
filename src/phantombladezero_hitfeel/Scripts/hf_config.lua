-- PBZ HitFeel: built-in defaults, merged under the user's config.lua (mod root).
local C = {}

local SHAKE = "/PBZCombatAsset/Config/HitReact/CameraShake/"
local COMMON = "/PBZVFXPack/VFX/BattleFX/Common/"
local DEFLECT_SFX = "/Game/Wwise/Events/SFX/Combat/Special/Hero_Special/Hun/Common/PingDao/"
local IMPACT_SFX = "/Game/Wwise/Events/SFX_Impact/PingDao/Player/"

local function shake(name) return SHAKE .. name .. "." .. name .. "_C" end
local function asset(dir, name) return dir .. name .. "." .. name end

-- Frame counts are 60 fps frames (1 frame = 16.7 ms); the mod converts them to the game's actual frame rate.
C.DEFAULTS = {
  Enabled = true,

  Freeze = {
    Enabled = true,
    Method = "slomo",
    Fallback = "symmetric",
    Scale = 0.04,
    Frames = { VeryLight = 4, Light = 6, Middle = 7, Heavy = 9, UltraHeavy = 11, Break = 12, Default = 6 },
    SymmetricFrames = { VeryLight = 3, Light = 4, Middle = 5, Heavy = 7, UltraHeavy = 8, Break = 9, Default = 4 },
    SymmetricScale = 0.12,
    -- Knockback hits keep vanilla's hold: a longer freeze on a knocked-back enemy is the likely source of the
    -- occasional overly long knockback.
    ExtendKnockback = false,
    -- The enemy-only hold bends the enemy's timing (fighting games freeze both sides, so frame data stays): the game's
    -- slomo makes the held time up afterwards, running the enemy above 1.0 (up to about 1.36x in the v0.7.0 log), so
    -- a longer hold means a longer stretch of the enemy moving faster than normal, and an attack starting then comes
    -- out faster than the player has learned. What the holds add over vanilla (time lost, in 60 fps frames) is capped
    -- per enemy over the last second, and an enemy whose super armor the hit does not break keeps vanilla's slow-down
    -- (hf_freeze F.armored). 0 / false = off.
    MaxExtraFramesPerSec = 12,
    EndureGuard = true,
  },

  Audio = {
    Enabled = true,
    MinLevel = 1,
    DuckDb = 8,
    DuckFactor = 0.4,
    AttackMs = 10,
    HoldMs = 150,
    HeavyExtraHoldMs = 120,
    ReleaseMs = 280,
    RtpcAssets = { "/Game/Wwise/Game_Parameters/Mus/Mus_BattleVolumeModifier.Mus_BattleVolumeModifier" },
  },

  DualLayer = {
    Enabled = true,
    EveryN = 2,
    AlwaysAtLevel = 3,
    EventPathByTier = "/Game/Wwise/Events/SFX/Combat/Special/Hero_Special/Hun/Common/ShouJi/SFX_Combat_Hit_SlashTangBlade_Meat_{tier}.SFX_Combat_Hit_SlashTangBlade_Meat_{tier}",
    EventPath = "",
  },

  Camera = {
    Enabled = true,
    VanillaShakeUpgrade = { VeryLight = 1, Light = 1, Middle = 2, Heavy = 2, UltraHeavy = 1, Break = 0, Default = 1 },
    -- Hits the game gives no shake (dual-blade very light and light) get the one-hand blade's vanilla level for that
    -- strength, not upgraded further. Tiers left out get none.
    FillEmptyShake = true,
    FillShakeLevel = { VeryLight = 0, Light = 1 },
    ExtraShakeClassPath = shake("CameraShake_PunchHit_Level2"),
    ExtraShakeScale = { VeryLight = 0, Light = 0.2, Middle = 0.35, Heavy = 0.5, UltraHeavy = 0.6, Break = 0.7, Default = 0.25 },
    ExtraShakeOnlyWhenVanillaHasNone = false,
    Punch = {
      PushCm = { VeryLight = 0, Light = 4, Middle = 8, Heavy = 14, UltraHeavy = 18, Break = 22, Default = 4 },
      KickDeg = { VeryLight = 0, Light = 0.3, Middle = 0.5, Heavy = 0.9, UltraHeavy = 1.1, Break = 1.3, Default = 0.3 },
      RefDistanceCm = 300,
      InMs = 25,
      HoldMs = 40,
      OutMs = 170,
    },
    MinIntervalMs = 60,
  },

  -- Screen impact (hf_screen): the camera's vignette added on top for a moment, the edges darkening while the middle
  -- stays as it is, plus chromatic fringe at the edges (Fringe per 1.0 of vignette). Hit = accents of your hits only
  -- (hf_rhythm), by strength; Deflect = the clash tiers you defend (the game darkens the screen itself on a perfect
  -- one); Receive = blows that get through to you.
  Screen = {
    Enabled = true,
    Hit = { Middle = 0.30, Heavy = 0.35, UltraHeavy = 0.45, Break = 0.55, Default = 0 },
    Deflect = { Perfect = 0, Guard = 0.35, Blocked = 0, Default = 0 },
    Receive = { Middle = 0.30, Heavy = 0.45, UltraHeavy = 0.55, Break = 0.60, Default = 0 },
    Fringe = 2.0,
    AttackMs = 30,
    HoldMs = 50,
    ReleaseMs = 260,
    MaxVignette = 1.0,
    -- Pulses closer than MinGapMs kept the edges dark through a quick string of heavy blows (the chain's rapid heavy
    -- hits, an enemy combo landing on you; the user found it uncomfortable). Within the gap only a pulse StrongerBy
    -- times the last one gets through. 0 = no gap.
    MinGapMs = 1200,
    StrongerBy = 1.25,
  },

  -- Rhythm (hf_rhythm): hits less than ChainGapMs apart form a string. Light hits (VeryLight, Light) in it scale by
  -- LightDecay for their place (the 4th and later by the last); a Heavy or stronger hit, or a Middle hit after more
  -- than FinisherAfter hits of its string, is an accent, scaled by AccentEmph, and closes the string. The scale goes to
  -- the freeze, the shake and push, the hit flash, the camera's extra shake and punch, and the buzz.
  Rhythm = {
    Enabled = true,
    ChainGapMs = 400,
    LightDecay = { 1.0, 0.85, 0.7, 0.6 },
    FinisherAfter = 3,
    AccentEmph = 1.3,
    -- Heavy hits in a quick string (the chain's rapid heavy blows): the first is the accent; the next ones lose it
    -- and step down by HeavyRepeatDecay a hit, not below HeavyRepeatFloor, until a pause. Every heavy hit used to be
    -- a full accent, so a string of them had no contrast left.
    HeavyRepeatDecay = 0.85,
    HeavyRepeatFloor = 0.7,
    -- Density fatigue: each hit adds its FatigueWeight to a load that halves every FatigueHalfLifeMs, and a hit lands
    -- at 1 - Fatigue x load (accents feel half of it), not below FatigueFloor. Keeps a long string from piling every
    -- channel up. 0 = off.
    Fatigue = 0.35,
    FatigueHalfLifeMs = 600,
    FatigueFloor = 0.7,
    FatigueWeight = { VeryLight = 0.15, Light = 0.2, Middle = 0.3, Heavy = 0.4, UltraHeavy = 0.5, Break = 0.6, Default = 0.25 },
    -- Clashes ClashGapMs apart form a string; only the first of a string stops you (a perfect one each time, the
    -- later ones by Deflect.RepeatPerfectScale).
    ClashGapMs = 600,
  },

  -- The killing blow (hf_kill). The hit carries no HP, so the enemy's health is read from its ability system's
  -- attribute sets (the first GameplayAttributeData named like HealthNames, not a Max one) CheckAfterFrames after your
  -- hit; at or below DeadAtOrBelow it died from that hit and gets an accent of its own: Screen vignette, the ShakeClass
  -- shake and a camera punch, a buzz. The first checks log the attributes and the health they read. (v0.7.0 looked
  -- for a death tag, and this build cannot list an ability system's tags.)
  Kill = {
    Enabled = true,
    CheckAfterFrames = 3,
    HealthNames = { "Health", "HP", "Hp", "Life" },
    DeadAtOrBelow = 0,
    -- When the enemy's health is already at zero at its own slomo call (the damage lands first), the killing blow holds
    -- it this long (60 fps frames, times the panel's "hit stop length"), past the armor guard and the cap. 0 = off.
    HoldFrames = 16,
    Screen = 0.5,
    ShakeClass = shake("CameraShake_PunchHit_Level4"),
    ShakeScale = 1.0,
    PushCm = 20,
    KickDeg = 1.2,
    Rumble = { Body = 1.0, BodyMs = 180, Edge = 0.8, EdgeMs = 90 },
    LogChecks = 12,
  },

  -- A frame that takes HitchMs or more (and four times the usual) is logged with what the mod did just before it;
  -- 0 = off. At most MaxHitchLogs lines a session, then every 50th. Perf: a "perf" line every PerfEverySec seconds of
  -- play with fighting in it and whenever the mod goes off or on (hf_perf): the frame rate fighting and calm, the
  -- mod's own time on the game thread, its effects.
  Diagnostics = {
    HitchMs = 70,
    MaxHitchLogs = 30,
    Perf = true,
    PerfEverySec = 60,
    -- Lines of the weapons' attach sockets and visibility, logged when they change (hf_hit); 0 = none.
    WeaponLogs = 30,
  },

  Vfx = {
    Enabled = true,
    -- Our hit effects (the contact effect, the blade's hit trail, the extra impact) in this color, through the effect's
    -- own color parameter; one without keeps its colors (hitfeel.log says which, the first time each plays). Materials
    -- would go through the color parameters of its materials, but in this game build a Niagara component lists no
    -- materials (v0.6.1 in game: "the component lists none" for every candidate), so it is off.
    Tint = { Enabled = true, Color = { R = 0.30, G = 0.0, B = 0.008, A = 1 }, Materials = false },
    -- Our effects sort over the game's own translucent ones (blood mist, smoke) at the same depth; 0 = engine order.
    SortPriority = 10,
    -- Our effects are kept out of the engine's effect culling (Niagara scalability: how many of one effect may play at
    -- once, distance, time off screen). Skill effects allow few at a time: with it off, the ink blade showed on the
    -- first hit of a quick string and on none after it.
    NeverCull = true,
    -- With the engine's budget off for them, the mod keeps one: at most MaxAlive of its effects play at once (one more
    -- ends the oldest, one already fading first), and none lasts past KillAfterMs. 0 = no limit.
    MaxAlive = 12,
    KillAfterMs = 6000,
    -- The blade's hit trail at most once per blade in this many ms (one swing striking two enemies hangs one). The hit
    -- effect at the contact has no such gap since v0.6.3: every hit gets one.
    MinIntervalMs = 30,
    MaxLifeMs = 1500,
    -- A hit effect from the game's own set for enemies that do not bleed is skipped on an enemy the game already
    -- gives that set (the YuCong boss): this compares the asset folder with the effects the game is playing.
    SkipWhenGameUsesSameSet = true,
    -- A hit trail on the blade that hit. Off since v0.5.4: the blade's own swing trail stays as the game made it, and
    -- the hit is marked where it lands instead (Slash below).
    AirTrail = {
      Enabled = false,
      MinLevel = 1,
      UseWeaponTrail = false,
      AtTip = true,
      ByWeapon = {
        Default = COMMON .. "Doll/NS_DollHitTrail_00{n}.NS_DollHitTrail_00{n}",
      },
      Ms = { VeryLight = 90, Light = 110, Middle = 140, Heavy = 170, UltraHeavy = 200, Break = 220, Default = 120 },
      -- "{n}" in an effect path is replaced by the hit's strength, like the game's own hit effects (_001 lightest);
      -- "{n:1,3,5}" is a set with only those numbers, and the nearest one is used.
      TierNumber = { VeryLight = 1, Light = 2, Middle = 3, Heavy = 4, UltraHeavy = 5, Break = 5, Default = 2 },
      -- Hit trails (the game's blood trail and its non-blood counterpart) are authored for the blade socket, where
      -- the game attaches them on a hit; swing trails go where the game attaches the weapon's own trail.
      HitTrailKeywords = { "HitTrail", "BloodTrail" },
    },
    -- An extra impact at the contact point: the game's own non-blood hit effect, by strength. Off since v0.5.4: it is
    -- one of the Slash candidates now. "" = a copy of this weapon's vanilla hit effect instead.
    HitVfx = {
      Enabled = false,
      AssetPath = COMMON .. "Doll/NS_DollHit_00{n}.NS_DollHit_00{n}",
      UseSweep = true,
      RotationOffset = { Pitch = 0, Yaw = 0, Roll = 0 },
      Scale = { VeryLight = 1, Light = 1, Middle = 1, Heavy = 1, UltraHeavy = 1, Break = 1, Default = 1 },
    },
    -- The hit effect where the blow lands: a slash line or an air slash at the contact point. Its long axis runs along
    -- the swing (the blade tip's motion into the hit) and its face turns to the camera. Ctrl+F6 steps through the
    -- candidates (kept in slash_choice.txt); the Ctrl+F5 panel's hit-effect page sets each one's step, scale and
    -- angle (kept in slash_tuning.lua, over Effects below). The game's effects have one size per file and a heavier
    -- hit plays a bigger file; scale barely changes sprite effects, so size goes by "{n}" sets and the step.
    Slash = {
      Enabled = true,
      MinLevel = 1,
      -- The effect used until one is picked with Ctrl+F6 or the panel (and again once slash_choice.txt is deleted): the
      -- ink blade, at the size and angle the author plays with (Effects below). v0.6.2 started on the first candidate,
      -- a QTE effect that fills the screen with purple flames.
      Default = asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiMoShang/", "NS_Hun_HeiMoShang_DelayBlade_101"),
      Candidates = {
        asset("/PBZVFXPack/VFX/BattleFX/ZuoShang/", "NS_ZuoShang_LaSwordHit_QTE_601"),
        asset("/PBZVFXPack/VFX/BattleFX/ZuoShang/", "NS_ZuoShang_PhantomSwordHit_002"),
        asset("/PBZVFXPack/VFX/BattleFX/WanJun/", "NS_WanJun_CAHit_201"),
        asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiShang/", "NS_Weapon_Tang_BladeBullet_001"),
        asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiShang/", "NS_Weapon_Tang_MeshBlade_301"),
        asset("/PBZVFXPack/VFX/BattleFX/HuaShan/", "NS_HuaShan_FlashLight_301"),
        asset("/PBZVFXPack/VFX/BattleFX/LeiTing/", "NS_LightningHit_201"),
        asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiMoShang/", "NS_Hun_HeiMoShang_DelayBlade_101"),
        asset("/PBZVFXPack/VFX/BattleFX/ChiYingGuRen/", "NS_ChiYingGuRen_MaskBlade_002_Main"),
        asset("/PBZVFXPack/VFX/BattleFX/MBoss/", "NS_MBoss_Blade_001"),
        COMMON .. "Doll/NS_DollHit_00{n}.NS_DollHit_00{n}",
        asset(COMMON .. "Blood_V2/", "NS_BloodSlash_004"),
        COMMON .. "HitEffect/NS_MetalDoll_Hit_10{n:1,3,5}.NS_MetalDoll_Hit_10{n:1,3,5}",
      },
      -- Each effect's own settings: Step (versions lighter, negative, or heavier within a "{n}" set), Scale x, Angle
      -- (degrees, turned in the screen plane), Roll (about the swing), Pitch. The DelayBlade is a skill-sized
      -- effect: at 1.0 it stood 2-3 times the enemy's height; its values are the author's own from the panel.
      Effects = {
        [asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiMoShang/", "NS_Hun_HeiMoShang_DelayBlade_101")] = { Scale = 0.15, Angle = 0, Roll = 90, Pitch = 15 },
      },
      -- By strength, times the effect's own size.
      Scale = { VeryLight = 0.8, Light = 0.9, Middle = 1.0, Heavy = 1.15, UltraHeavy = 1.25, Break = 1.35, Default = 1.0 },
      -- Drawn toward the camera out of the struck body's capsule (BodyMarginCm beyond it): at least TowardCameraCm,
      -- at most MaxTowardCameraCm.
      TowardCameraCm = 20,
      MaxTowardCameraCm = 120,
      BodyMarginCm = 12,
      PreviewDistanceCm = 180,
      MaxMs = 900,
    },
    -- An air trail on the blade through every swing (the tip faster than StartCmPerSec relative to you for two frames
    -- starts it; StopFrames frames under StopCmPerSec end it, MaxMs at the latest). Path is the light doll hit trail;
    -- the hit trail (AirTrail) stays an extra on hits.
    SwingTrail = {
      Enabled = true,
      Path = COMMON .. "Doll/NS_DollHitTrail_002.NS_DollHitTrail_002",
      StartCmPerSec = 700,
      StopCmPerSec = 350,
      StopFrames = 4,
      MinMs = 120,
      MaxMs = 900,
      GapMs = 60,
    },
  },

  React = {
    Enabled = true,
    Displace = {
      Enabled = true,
      Cm = { VeryLight = 0.5, Light = 1.0, Middle = 2.0, Heavy = 3.5, UltraHeavy = 4.5, Break = 5.0, Default = 1.0 },
      Frames = 6,
    },
    -- The model shakes side to side (across the hit) while the enemy is held, fading out: the fighting-game hit shake.
    -- Hz is how often it changes side; the length follows the freeze.
    Shake = {
      Enabled = true,
      Cm = { VeryLight = 1.0, Light = 1.5, Middle = 2.0, Heavy = 3.0, UltraHeavy = 3.5, Break = 4.0, Default = 1.5 },
      Frames = { VeryLight = 4, Light = 6, Middle = 7, Heavy = 9, UltraHeavy = 11, Break = 12, Default = 6 },
      Hz = 30,
    },
    -- Hit Feel: PBZHitFeel's Jiggle (physics on the bones near the hit) is removed; see hf_react.lua.
  },

  Rumble = {
    Enabled = true,
    Scale = 1.0,
    ForceEnableUEForceFeedback = false,
    Profiles = {
      VeryLight  = { Body = 0.15, BodyMs = 45,  Edge = 0.50, EdgeMs = 40 },
      Light      = { Body = 0.35, BodyMs = 65,  Edge = 0.65, EdgeMs = 45 },
      Middle     = { Body = 0.55, BodyMs = 90,  Edge = 0.75, EdgeMs = 55 },
      Heavy      = { Body = 0.80, BodyMs = 120, Edge = 0.85, EdgeMs = 65 },
      UltraHeavy = { Body = 0.95, BodyMs = 150, Edge = 0.90, EdgeMs = 70 },
      Break      = { Body = 1.00, BodyMs = 180, Edge = 0.95, EdgeMs = 75 },
      Default    = { Body = 0.35, BodyMs = 65,  Edge = 0.65, EdgeMs = 45 },
    },
  },

  -- Tiers: Perfect / Guard when the player deflects, Blocked when an enemy blocks the player's attack (a deflect
  -- lookup on the player's side, or a player hit on a Shield material). Blocked is a clang, not a hit: metal sound,
  -- sparks and a crisp buzz, no push on the enemy.
  Deflect = {
    Enabled = true,
    -- Which deflects get the perfect set (hf_hit H.deflectTier). "game": the game said so, through its own perfect
    -- deflect choosers (BP_DeflectEffectPlayer_Chooser_Perfect / _PerfectFinal) or its deflect frame's result, within
    -- PerfectWindowMs before the clash. "mult": the old guess, the clash slow-down below PerfectBelowMult; the logs
    -- showed it follows the stopped attack's strength (0.7 / 0.5 / 0.3), so heavy attacks and a boss's whole flurry
    -- counted as perfect. "all_perfect" / "all_guard". An "auto" kept from older settings means "game".
    Classify = "game",
    PerfectBelowMult = 0.4,
    PerfectWindowMs = 250,
    -- A normal guard weighs what it stopped: its freeze, camera shake and buzz scale by the attack's strength.
    GuardByStrength = { Light = 0.8, Middle = 1.0, Heavy = 1.3 },
    -- Perfect deflects in a quick string (a flurry): the first holds both sides in full, the later ones by
    -- RepeatPerfectScale; the game's final perfect deflect (PerfectFinal) by FinalEmph, always.
    RepeatPerfectScale = 0.5,
    FinalEmph = 1.3,
    OnEnemyDeflect = true,
    FreezeScale = 0.04,
    EnemyFreeze = { Perfect = 14, Guard = 8, Blocked = 3 },
    PlayerFreeze = { Perfect = 8, Guard = 3, Blocked = 3 },
    EnemyPushCm = { Perfect = 5, Guard = 2.5, Blocked = 0 },
    EnemyShakeCm = { Perfect = 2.5, Guard = 1.5, Blocked = 0 },   -- the hit shake on the enemy, for its freeze
    PushCm = { Perfect = 24, Guard = 0, Blocked = 0 },
    KickDeg = { Perfect = 1.4, Guard = 0, Blocked = 0.25 },
    ShakeClass = {
      Perfect = shake("CameraShake_PunchHit_Level4"),
      Guard = shake("CameraShake_PunchHit_Level2"),
      Blocked = shake("CameraShake_PunchHit_Level1"),
    },
    ShakeScale = { Perfect = 1.0, Guard = 0.9, Blocked = 0.6 },
    Vfx = {
      Perfect = asset(COMMON, "NS_PinDaoPerfect_005"),
      Guard = asset(COMMON, "NS_PinDao_004"),
      Blocked = asset(COMMON, "NS_PinDao_004"),
    },
    -- A second layer. Guard had none until v0.5.6; the user asked for its sparks half again as strong, and the
    -- game's lighter clash spark on top of the main one is about that.
    Vfx2 = {
      Perfect = asset(COMMON, "NS_PinDaoFinal_006"),
      Guard = asset(COMMON, "NS_PinDao_003"),
      Blocked = asset(COMMON, "NS_PinDao_003"),
    },
    VfxScale = { Perfect = 1.6, Guard = 1.25, Blocked = 0.9 },
    -- Copies of the two layers (hf_vfx V.sparkCopies). The user found v0.5.6's two-layer guard about the same and
    -- asked for half again: 1.5 plays the main layer twice. A perfect deflect plays its main layer only (0.5) since
    -- v0.6.6: with the finishing burst on top the user found it too much.
    SparkAmount = { Perfect = 0.5, Guard = 1.5, Blocked = 1 },
    SparkTowardCameraCm = 15,
    -- The extra clash layer below (Sound, ShieldSound): a switch, and its own volume 0-1 (the game's clash sound is
    -- untouched). Players found deflects louder than vanilla.
    SoundEnabled = true,
    SoundVolume = 1.0,
    Sound = {
      Perfect = asset(DEFLECT_SFX, "SFX_Combat_Deflect_HuoLiuXing_BladeDefault_Heavy_Perfect"),
      Guard = asset(IMPACT_SFX, "SFX_Combat_Deflect_SlashTangBlade_BladeDefault_{tier}"),
      Blocked = asset(IMPACT_SFX, "SFX_Combat_Deflect_SlashTangBlade_BladeDefault_{tier}"),
    },
    ShieldSound = asset("/Game/Wwise/Events/SFX_Impact/ShouJi/MHP/", "SFX_Combat_Hit_SlashDefault_ShieldIron_{tier}"),
    DuckHoldMs = { Perfect = 380, Guard = 200, Blocked = 100 },
    Rumble = {
      Perfect = { Body = 1.00, BodyMs = 150, Edge = 1.00, EdgeMs = 90 },
      Guard   = { Body = 0.85, BodyMs = 120, Edge = 0.60, EdgeMs = 60 },
      Blocked = { Body = 0.20, BodyMs = 40,  Edge = 0.90, EdgeMs = 60 },
    },
  },

  Hit = {
    DedupeMs = 40,
    MaxVictimDistanceCm = 600,
    ReadSlomoOwner = true,
    -- Of the enemies your hits strike in one frame (a swing through a crowd, an area skill), how many get the whole
    -- feedback, in the order struck; the rest keep only their hit stop. 0 = no cap.
    MaxFullPerFrame = 3,
    -- A weapon hanging from a socket whose name holds one of these (any case) is put away: no swing trail, and it is
    -- no hit's blade. So is a hidden one. In game: Pt_DoubleBlade_R_Back_Socket and the like on the back, weapon_r_Socket,
    -- weapon_l_Socket and WEAPON_R in the hands.
    SheathedSockets = { "Back" },
    BlockMaterials = { "Shield" },
    BladeSockets = { "BladeBloodStart", "BladeStart", "Blade_Start", "BladeBloodEnd", "BladeEnd", "Blade_End" },
    BladeTipSockets = { "BladeBloodEnd", "BladeEnd", "Blade_End", "BladeTip", "WeaponTip", "Tip" },
    WeaponKeywords = {
      DW = { "Dual", "Double", "Shuang", "Snake" },
      ["2H"] = { "ZhanMa", "Great", "BrutalAxe", "Axe" },
      ["1H"] = { "TangBlade", "Blade", "Sword", "Jian" },
    },
  },

  -- Hit flash: the enemy that was hit glows white at the rim for a few frames, fading back. Character materials have
  -- a fresnel rim the game drives itself (the ZhanMa emergency shield sets these two parameters on the player); the
  -- names are confirmed from that ability's defaults at runtime when it can be found (UseGameNames).
  Flash = {
    Enabled = true,
    StrengthParam = "Fresnel_Strength",
    ColorParam = "Fresnel_Color",
    UseGameNames = true,
    -- Black-red since v0.5.9 (the user's choice): a rim of deep red. The rim adds light, so a dark color needs about
    -- twice the strength of white to read.
    Color = { R = 0.55, G = 0.015, B = 0.03, A = 1 },
    -- v0.5.4: 0.6 of v0.5.3's, the level the user set in the panel ("more see-through").
    Strength = { VeryLight = 0.72, Light = 1.08, Middle = 1.44, Heavy = 2.16, UltraHeavy = 2.52, Break = 2.88, Default = 1.08 },
    Frames = { VeryLight = 3, Light = 4, Middle = 5, Heavy = 6, UltraHeavy = 7, Break = 8, Default = 4 },
    HoldFrames = 1,
    Parts = true,      -- also the skeletal meshes attached to the body (clothes, hair)
    CreateMids = true, -- give a material slot a dynamic instance when it has none (the engine does the same)
    KeepSec = 10,      -- a body's material instances are looked up again after this long (between, they are reused)
  },

  -- On the receiving end. Guard: an enemy's blow on your held guard (the game's non-perfect deflect). Hit: a blow
  -- that gets through. The camera is knocked back and tips up, your model is pushed back a few cm and springs back
  -- (only the model: control and hit boxes are untouched), a heavier buzz; a hit also flashes your rim red and raises
  -- the game's own being-hit shake. Damage-over-time ticks get nothing.
  Receive = {
    Enabled = true,
    Guard = { RecoilCm = 10, KickDeg = 0.7, FlinchCm = 2.5, FlinchFrames = 6 },  -- its buzz is Deflect.Rumble.Guard
    Hit = {
      RecoilCm = { VeryLight = 6, Light = 8, Middle = 12, Heavy = 18, UltraHeavy = 22, Break = 26, Default = 10 },
      KickDeg = { VeryLight = 0.4, Light = 0.6, Middle = 0.9, Heavy = 1.3, UltraHeavy = 1.5, Break = 1.7, Default = 0.7 },
      FlinchCm = { VeryLight = 1.5, Light = 2, Middle = 3.5, Heavy = 5, UltraHeavy = 5.5, Break = 6, Default = 2.5 },
      FlinchFrames = 8,
      ShakeUpgrade = 1,  -- the game's own CameraShake_PlayerHit level, raised this many (4 at most)
      Flash = { Color = { R = 1, G = 0.12, B = 0.06, A = 1 },
        Strength = { VeryLight = 0.30, Light = 0.42, Middle = 0.60, Heavy = 0.84, UltraHeavy = 0.96, Break = 1.08, Default = 0.48 },
        Frames = 6 },
      Rumble = {
        VeryLight = { Body = 0.35, BodyMs = 70, Edge = 0.2, EdgeMs = 40 },
        Light = { Body = 0.5, BodyMs = 90, Edge = 0.3, EdgeMs = 45 },
        Middle = { Body = 0.7, BodyMs = 120, Edge = 0.4, EdgeMs = 55 },
        Heavy = { Body = 0.95, BodyMs = 170, Edge = 0.5, EdgeMs = 70 },
        Default = { Body = 0.6, BodyMs = 100, Edge = 0.35, EdgeMs = 50 },
      },
    },
  },

  -- Your guard (hf_guard): Sha-Chi (the game's Shachi attribute) drains while you guard and on every blocked blow, and
  -- when it runs out the guard breaks. Low: in a fight, below Below of its range the screen's edges darken toward
  -- red (Edge at Full and under), and below PulseBelow they beat (PulseHz from there to empty, PulseAdd on top);
  -- CombatSec after Sha-Chi last fell they fade, InMs / OutMs being how fast they follow. Strain: a block on a guard
  -- below Below lands heavier, up to Max times at empty, and flicks the edge by up to Tick. Break: the game's guard
  -- break on you flashes the edge (Edge, held HoldMs, ebbing over FadeMs with Beats beats), knocks the camera back
  -- and gives a heavy double rumble. Attributes: where Sha-Chi is read (the first name found).
  Guard = {
    Enabled = true,
    PollFrames = 3,
    Low = { Enabled = true, Below = 0.5, Full = 0.12, Edge = 0.45, PulseBelow = 0.3, PulseAdd = 0.22,
      PulseHz = { 0.9, 1.7 }, CombatSec = 4, InMs = 120, OutMs = 700 },
    Strain = { Below = 0.5, Max = 1.6, Tick = 0.25 },
    Break = { Enabled = true, Edge = 0.9, HoldMs = 140, FadeMs = 1500, Beats = 2, RecoilCm = 30, KickDeg = 2.2,
      Rumble = { Body = 1.0, BodyMs = 260, Edge = 0.8, EdgeMs = 110, ThenBody = 0.45, ThenMs = 220, GapMs = 170 } },
    Attributes = { Value = { "Shachi" }, Max = { "Shachi_Max" }, Min = { "Shachi_Min" } },
  },

  -- Whole-feature multipliers, mainly for the HUD (Ctrl+F5).
  Tuning = {
    Freeze = 1, DeflectFreeze = 1, PlayerDeflectFreeze = 1, Push = 1, HitShake = 1, Flash = 1, Receive = 1,
    -- Sparks is an amount, played as copies of the clash spark layers (see V.sparkCopies), not a scale.
    AirTrail = 1, HitVfx = 1, Slash = 1, Sparks = 1, Shake = 1, Punch = 1, Screen = 1, Rhythm = 1, Guard = 1,
  },

  -- Load everything the mod uses when a map loads, and keep it loaded, so nothing loads (and hitches) mid-fight.
  Preload = {
    Enabled = true,
    DelayMs = 1500,
    PerFrame = 2,
    SecondPassSec = 30,
  },

  -- The panel: 520 x 800 (1080p units) at X, Y; the Ctrl+F6 notice at ToastX, ToastY. Preset: the feel preset
  -- picked in the panel (nil = Custom), written to tuning.lua. TrialSec: how long its "vanilla for 10 s" button turns the mod
  -- off. Language: "auto" (the game's language), "zh", "en", "ja" or "ko"; the panel's list writes it to tuning.lua.
  -- EscCloses: Esc closes the panel as Ctrl+F5 does. BuildMsPerFrame: how much of a frame building the panel may take
  -- after a map load.
  Hud = {
    Enabled = true,
    X = 40,
    Y = 70,
    ToastX = 40,
    ToastY = 30,
    RefreshMs = 250,
    ToastMs = 2500,
    TrialSec = 10,
    Language = "auto",
    EscCloses = true,
    BuildMsPerFrame = 4,
  },

  -- Hotkeys (all with Ctrl) are read from the player controller on the game thread once a frame; false = UE4SS's
  -- RegisterKeyBind, whose callbacks run on UE4SS's own thread (the v0.5.4 crash). The panel's arrows repeat while
  -- the mouse holds them.
  Keys = {
    ReadOnGameThread = true,
    RepeatDelayMs = 450,
    RepeatMs = 110,
    -- The hotkeys: a modifier ("Ctrl", "Alt", "Shift" or "None") and each key by the engine's name ("F5", "F1"-"F12",
    -- "Insert", "Home", "PageUp", "K", "NumPadFive" ...), to move off another mod's keys.
    Modifier = "Ctrl",
    Panel = "F5",
    Effect = "F6",
    Toggle = "F7",
    Reload = "F8",
    Probe = "F9",
  },

  Probe = {
    Enabled = true,
    Scan = false,
    Dumps = false,
    MaxHitDumps = 30,
    ScanDelaySec = 12,
  },
}

-- Values changed in the HUD, saved as "Path.To.Key" = value and applied over config.lua.
C.TUNING_FILE = "tuning.lua"
-- Never kept in tuning.lua: the panel's master switch is for comparing on and off within one session, like
-- Ctrl+F7. v0.5.1 saved it, so a session that ended switched off started the next one switched off.
C.SESSION_ONLY = { Enabled = true }

local function setPath(cfg, path, value)
  local t = cfg
  local parts = {}
  for p in path:gmatch("[^%.]+") do parts[#parts + 1] = p end
  for i = 1, #parts - 1 do
    if type(t[parts[i]]) ~= "table" then return false end
    t = t[parts[i]]
  end
  t[parts[#parts]] = value
  return true
end
C.setPath = setPath

function C.getPath(cfg, path)
  local t = cfg
  for p in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[p]
  end
  return t
end

function C.loadTuning(U)
  local ok, t = pcall(dofile, U.root .. "/" .. C.TUNING_FILE)
  if not (ok and type(t) == "table") then return {} end
  local dropped = {}
  for k in pairs(C.SESSION_ONLY) do
    if t[k] ~= nil then
      dropped[#dropped + 1] = k .. " = " .. tostring(t[k])
      t[k] = nil
    end
  end
  if #dropped > 0 then
    table.sort(dropped)
    U.log("%s: ignored %s (it only lasts one session) and removed it from the file", C.TUNING_FILE, table.concat(dropped, ", "))
    C.saveTuning(U, t)
  end
  return t
end

-- A path -> value table written as a Lua file in the mod folder (tuning.lua, and the panel's saved custom set).
function C.saveOverrides(U, file, overrides, header)
  local keys = {}
  for k in pairs(overrides) do
    if not C.SESSION_ONLY[k] then keys[#keys + 1] = k end
  end
  table.sort(keys)
  local lines = { "-- " .. header, "return {" }
  for _, k in ipairs(keys) do
    local v = overrides[k]
    local s = type(v) == "string" and string.format("%q", v) or tostring(v)
    lines[#lines + 1] = string.format("  [%q] = %s,", k, s)
  end
  lines[#lines + 1] = "}"
  local f = io.open(U.root .. "/" .. file, "w")
  if not f then return false end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  return true
end

function C.readOverrides(U, file)
  local ok, t = pcall(dofile, U.root .. "/" .. file)
  return ok and type(t) == "table" and t or {}
end

function C.saveTuning(U, overrides)
  return C.saveOverrides(U, C.TUNING_FILE, overrides,
    "PBZHitFeel: values changed in the Ctrl+F5 panel. They override config.lua; delete this file to go back.")
end

local function merge(base, over)
  if type(base) ~= "table" or type(over) ~= "table" then return over end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over) do
    if type(v) == "table" and type(base[k]) == "table" and #v == 0 then
      out[k] = merge(base[k], v)
    else
      out[k] = v
    end
  end
  return out
end

function C.load(U)
  local path = U.root .. "/config.lua"
  local ok, user = pcall(dofile, path)
  local cfg
  if not ok then
    U.log("config.lua not loaded (%s); using defaults", tostring(user))
    cfg = merge(C.DEFAULTS, {})
  elseif type(user) ~= "table" then
    U.log("config.lua did not return a table; using defaults")
    cfg = merge(C.DEFAULTS, {})
  else
    cfg = merge(C.DEFAULTS, user)
  end
  local n = 0
  for k, v in pairs(C.loadTuning(U)) do
    if type(k) == "string" and setPath(cfg, k, v) then n = n + 1 end
  end
  if n > 0 then U.log("%d value(s) from %s applied over config.lua", n, C.TUNING_FILE) end
  return cfg
end

-- config.lua over the defaults without tuning.lua: what the HUD's Ctrl+Home goes back to.
function C.loadBase(U)
  local ok, user = pcall(dofile, U.root .. "/config.lua")
  if ok and type(user) == "table" then return merge(C.DEFAULTS, user) end
  return merge(C.DEFAULTS, {})
end

-- Lookup in a per-tier table with Default fallback.
function C.tier(tbl, tierName)
  if type(tbl) ~= "table" then return tbl end
  local v = tbl[tierName]
  if v == nil then v = tbl.Default end
  return v
end

return C
