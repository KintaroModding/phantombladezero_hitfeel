-- PBZHitFeel - Hit Feel Overhaul: settings (based on PBZHitFeel 0.7.3 by MoonlightSakura)
-- After a change, press Ctrl+F8 in the game: it takes effect at once (the scripts reload too, no game restart).
-- Ctrl+F7 switches the whole mod on and off for a comparison (the controller rumbles once = on, twice = off).
-- Ctrl+F5 opens the in-game tuning panel. Values changed there are saved in tuning.lua and override the same names
-- here; delete tuning.lua to go back to the values in this file.
-- Frame counts are always at 60 fps (1 frame = 16.7 ms); the mod converts them to your real frame rate, so times
-- stay the same at high frame rates.
-- Strength tiers come from the game's own hit tags: VeryLight / Light / Middle / Heavy / UltraHeavy /
-- Break (guard break, launch); a knockback raises the tier by one. Deflects: Perfect (perfect deflect) / Guard
-- (normal deflect) / Blocked (your attack blocked by the enemy). Default is used when no tier was recognized.
local SHAKE = "/PBZCombatAsset/Config/HitReact/CameraShake/"
local COMMON = "/PBZVFXPack/VFX/BattleFX/Common/"
local function shake(name) return SHAKE .. name .. "." .. name .. "_C" end
local function asset(dir, name) return dir .. name .. "." .. name end

return {
  Enabled = true,              -- Master switch. Ctrl+F7 and the panel's master switch only last one session; not saved

  -- Hit stop: only the enemy you hit stops; you do not. It rewrites the game's own hit slow-motion for the enemy's
  -- side, so the stop and the recovery are done by the game itself
  Freeze = {
    Enabled = true,
    Method = "slomo",          -- "slomo" stops only the enemy (default); "symmetric" stops both sides; "dilation" the old v0.2 way; "none" no hit stop
    Fallback = "symmetric",    -- The first hits in a game test the rewrite; if it did not reach the game, this way is used instead ("none" = no switch)
    Scale = 0.04,              -- The enemy's time scale during the stop; 0.04 = almost still. Never set it to 0
    Frames = { VeryLight = 4, Light = 6, Middle = 7, Heavy = 9, UltraHeavy = 11, Break = 12, Default = 6 },
    SymmetricFrames = { VeryLight = 3, Light = 4, Middle = 5, Heavy = 7, UltraHeavy = 8, Break = 9, Default = 4 }, -- Frames for both sides with "symmetric"; shorter than above, for the feel
    SymmetricScale = 0.12,
    -- Hits with a knockback (kicks, heavy blows that send someone flying) get no longer stop, as in the base game.
    -- A longer one lets the game's hit movement keep going during the stop, the most likely cause of "sometimes
    -- knocked very far". Switch it on in the Ctrl+F5 panel to compare
    ExtendKnockback = false,
    -- Stopping only the enemy changes its rhythm (fighting games stop both sides, so frame timings stay the same):
    -- the game's slow-motion later speeds the enemy up to catch up the stopped time (up to about 1.36x in the v0.7.0
    -- logs). The longer the stop, the longer the fast part after it, and the enemy then attacks faster than players
    -- know. So the extra stop this mod gives one enemy within the last second has a limit (at 60 fps, 0 = no limit);
    -- an enemy whose super armor was not broken (its armor level is above your blow's break level) keeps the game's
    -- own slow-motion, so its attack rhythm and your deflect timing stay the same
    MaxExtraFramesPerSec = 12,
    EndureGuard = true,
  },

  -- Deflects. Perfect (perfect deflect) and Guard (normal deflect): you deflect an enemy's attack. Blocked: your
  -- attack is blocked by the enemy (a blade clash, or a hit on a shield). Blocked is a short "clang", unlike a hit:
  -- a metal deflect sound, sparks, a crisp pulse of the small right motor, a very short stop for both sides, and the
  -- enemy is not pushed
  Deflect = {
    Enabled = true,
    -- Which deflects get the perfect feedback (only this mod's feedback; the game's judgement does not change):
    -- "game" = the game says it was perfect (its perfect deflect effect chooser, or the deflect frame's result, within
    -- PerfectWindowMs before the clash); "mult" = the old guess: the clash slow-motion factor below PerfectBelowMult.
    -- The logs show that this factor follows the strength of the blocked blow (0.7 / 0.5 / 0.3), so heavy blows and a
    -- boss's whole combo counted as perfect; "all_perfect" all perfect; "all_guard" all normal. An old "auto" counts
    -- as "game"
    Classify = "game",
    PerfectBelowMult = 0.4,
    PerfectWindowMs = 250,
    GuardByStrength = { Light = 0.8, Middle = 1.0, Heavy = 1.3 }, -- A normal deflect scales its stop, camera shake and rumble by the blocked blow's strength
    RepeatPerfectScale = 0.5,  -- In a string of clashes, perfect deflects from the second on stop this much shorter (the first as usual)
    FinalEmph = 1.3,           -- The game's "last perfect deflect" (PerfectFinal) stops this much longer
    OnEnemyDeflect = true,     -- Feedback also when the enemy blocks your attack (the Blocked tier)
    FreezeScale = 0.04,
    EnemyFreeze = { Perfect = 14, Guard = 8, Blocked = 3 },   -- Frames the enemy stops
    PlayerFreeze = { Perfect = 8, Guard = 3, Blocked = 3 },   -- Frames you stop (only on deflects; hits never stop you unless Freeze is "symmetric")
    EnemyPushCm = { Perfect = 5, Guard = 2.5, Blocked = 0 },  -- How many cm the enemy's model is pushed (the model only)
    EnemyShakeCm = { Perfect = 2.5, Guard = 1.5, Blocked = 0 },  -- How far the enemy shakes sideways while it is held (cm)
    PushCm = { Perfect = 24, Guard = 0, Blocked = 0 },       -- How many cm the camera pushes in at once (on a normal deflect the camera is knocked back instead, see Receive.Guard)
    KickDeg = { Perfect = 1.4, Guard = 0, Blocked = 0.25 }, -- How many degrees the camera swings along the blade
    ShakeClass = {                                            -- Extra camera shake (the game's own punch shakes, levels 0-4)
      Perfect = shake("CameraShake_PunchHit_Level4"),
      Guard = shake("CameraShake_PunchHit_Level2"),
      Blocked = shake("CameraShake_PunchHit_Level1"),
    },
    ShakeScale = { Perfect = 1.0, Guard = 0.9, Blocked = 0.6 },
    -- Clash sparks (the game's own): Vfx is the first layer, Vfx2 a second layer on top, empty = no second layer.
    -- Scaling (VfxScale) does little for these sparks; for more sparks, raise "clash spark amount" in the panel
    -- (more copies per layer)
    Vfx = {
      Perfect = asset(COMMON, "NS_PinDaoPerfect_005"),
      Guard = asset(COMMON, "NS_PinDao_004"),
      Blocked = asset(COMMON, "NS_PinDao_004"),
    },
    -- Normal deflects also get a second layer since v0.5.6 (the game's one-step-lighter clash sparks), about half more than v0.5.5's one layer
    Vfx2 = { Perfect = asset(COMMON, "NS_PinDaoFinal_006"), Guard = asset(COMMON, "NS_PinDao_003"), Blocked = asset(COMMON, "NS_PinDao_003") },
    VfxScale = { Perfect = 1.6, Guard = 1.25, Blocked = 0.9 },
    -- Spark amount: 0.5 = the first layer only, 1 = one copy of each layer, 1.5 = two copies of the first layer, 2 = two
    -- copies of both. Normal deflects 1.5 since v0.5.7 (half more than v0.5.6); perfect deflects 0.5 since v0.6.6: only
    -- the perfect sparks, without the final sparks on top (1 was too much)
    SparkAmount = { Perfect = 0.5, Guard = 1.5, Blocked = 1 },
    SparkTowardCameraCm = 15,  -- How many cm the sparks move toward the camera, so the two bodies do not hide them
    -- An extra clash sound layer (Sound and ShieldSound below). SoundEnabled = false leaves only the game's own clash
    -- sound; SoundVolume is this layer's volume, 0-1, 1 = as is; the game's own clash sound does not change. Also on
    -- the panel's Sound tab: turn it down or off when deflects sound louder than in the base game
    SoundEnabled = true,
    SoundVolume = 1.0,
    -- Which sound to add, empty = none. {tier} becomes the blocked blow's strength: Light / Middle / Heavy
    Sound = {
      Perfect = asset("/Game/Wwise/Events/SFX/Combat/Special/Hero_Special/Hun/Common/PingDao/", "SFX_Combat_Deflect_HuoLiuXing_BladeDefault_Heavy_Perfect"),
      Guard = asset("/Game/Wwise/Events/SFX_Impact/PingDao/Player/", "SFX_Combat_Deflect_SlashTangBlade_BladeDefault_{tier}"),
      Blocked = asset("/Game/Wwise/Events/SFX_Impact/PingDao/Player/", "SFX_Combat_Deflect_SlashTangBlade_BladeDefault_{tier}"),
    },
    ShieldSound = asset("/Game/Wwise/Events/SFX_Impact/ShouJi/MHP/", "SFX_Combat_Hit_SlashDefault_ShieldIron_{tier}"), -- Used for a hit on a shield
    DuckHoldMs = { Perfect = 380, Guard = 200, Blocked = 100 }, -- How long the battle music steps back
    Rumble = {
      Perfect = { Body = 1.00, BodyMs = 150, Edge = 1.00, EdgeMs = 90 },
      Guard   = { Body = 0.85, BodyMs = 120, Edge = 0.60, EdgeMs = 60 },
      Blocked = { Body = 0.20, BodyMs = 40,  Edge = 0.90, EdgeMs = 60 },  -- Mostly the small motor: a "ting" feel
    },
  },

  -- The battle music steps back on hits: measured in the default mix, the music raises everything below 630 Hz by
  -- 9-13 dB, exactly where the weight of a hit sound is
  Audio = {
    Enabled = true,
    MinLevel = 1,              -- From which tier it steps back (1 = from VeryLight)
    DuckDb = 8,                -- How many dB lower
    DuckFactor = 0.4,          -- Linear or percent parameters go down to this share of their value
    AttackMs = 10,             -- How long it takes to go down
    HoldMs = 150,              -- How long it stays down (quick hits extend it)
    HeavyExtraHoldMs = 120,    -- Extra hold for Heavy and above
    ReleaseMs = 280,           -- How long it takes to come back
    RtpcAssets = { "/Game/Wwise/Game_Parameters/Mus/Mus_BattleVolumeModifier.Mus_BattleVolumeModifier" },
  },

  -- A low-end hit layer for dual blades: measured, dual-blade hits are the weakest and have almost no low end; the
  -- layer is the one-hand blade's hit sound of the same tier (the most low end)
  DualLayer = {
    Enabled = true,
    EveryN = 2,                -- Add it every N hits
    AlwaysAtLevel = 3,         -- On every hit from Middle up
    EventPathByTier = "/Game/Wwise/Events/SFX/Combat/Special/Hero_Special/Hun/Common/ShouJi/SFX_Combat_Hit_SlashTangBlade_Meat_{tier}.SFX_Combat_Hit_SlashTangBlade_Meat_{tier}",
    EventPath = "",            -- Fill in to always use one fixed sound
  },

  -- Camera
  Camera = {
    Enabled = true,
    -- How many levels the base game's attack camera shakes go up (the game has levels 0-4, capped at 4). Lower a
    -- tier's value if it shakes too much
    VanillaShakeUpgrade = { VeryLight = 1, Light = 1, Middle = 2, Heavy = 2, UltraHeavy = 1, Break = 0, Default = 1 },
    -- Hits that do not shake at all in the base game (dual blades' VeryLight and Light) get the game's own attack
    -- shake. Levels as the one-hand blade's same tier: VeryLight level 0, Light level 1; these added shakes are not
    -- raised. Tiers not listed get none. Too much: set FillEmptyShake to false, or turn off "fill shake on light hits"
    -- in the Ctrl+F5 panel
    FillEmptyShake = true,
    FillShakeLevel = { VeryLight = 0, Light = 1 },
    ExtraShakeClassPath = shake("CameraShake_PunchHit_Level2"),  -- A short shake along the hit, on top of the base game's
    ExtraShakeScale = { VeryLight = 0, Light = 0.2, Middle = 0.35, Heavy = 0.5, UltraHeavy = 0.6, Break = 0.7, Default = 0.25 },
    ExtraShakeOnlyWhenVanillaHasNone = false,  -- true = only when the base game's hit has no shake
    Punch = {                  -- The camera pushes in and swings along the blade for a moment, then returns (through the game camera plugin's own additive layers)
      PushCm = { VeryLight = 0, Light = 4, Middle = 8, Heavy = 14, UltraHeavy = 18, Break = 22, Default = 4 },
      KickDeg = { VeryLight = 0, Light = 0.3, Middle = 0.5, Heavy = 0.9, UltraHeavy = 1.1, Break = 1.3, Default = 0.3 },
      RefDistanceCm = 300,     -- The push above is for a camera 3 m from you; a farther camera gets more (up to twice), so it looks the same. 0 = no change
      InMs = 25,               -- How long the push in takes
      HoldMs = 40,             -- How long it holds (quick hits extend it)
      OutMs = 170,             -- How long the return takes
    },
    MinIntervalMs = 60,
  },

  -- Screen impact: the edges of the screen darken for a moment and recover (a vignette); the middle stays as it is,
  -- with a touch of color fringe at the edges. Only on accents: your heavy hits, the hit that ends a string (see
  -- Rhythm below), normal deflects, and blows from Middle up that hit you. The numbers are how much darker the
  -- vignette gets (on top of the game's own), 0 = none. v0.5.6's full-screen flash lit up the middle of the screen
  -- too and was glaring even at 0.1, so this replaced it
  Screen = {
    Enabled = true,
    Hit = { Middle = 0.30, Heavy = 0.35, UltraHeavy = 0.45, Break = 0.55, Default = 0 },  -- A Middle hit is an accent only when it ends a string
    Deflect = { Perfect = 0, Guard = 0.35, Blocked = 0, Default = 0 },  -- The game darkens the screen on perfect deflects itself; nothing added here
    Receive = { Middle = 0.30, Heavy = 0.45, UltraHeavy = 0.55, Break = 0.60, Default = 0 },
    Fringe = 2.0,              -- Color fringe at the edges: how much per 1.0 of vignette, 0 = no fringe
    AttackMs = 30,             -- How long it takes to darken (ms)
    HoldMs = 50,               -- How long it holds
    ReleaseMs = 260,           -- How long it takes to recover
    MaxVignette = 1.0,         -- The darkest vignette (the engine's vignette, 0-1)
    MinGapMs = 1200,           -- The least time between two screen impacts (ms). Inside it, only one StrongerBy times stronger than the last darkens again,
    StrongerBy = 1.25,         -- so a quick string of heavy blows (chain hits, an enemy combo on you) does not keep the screen dark. 0 = no limit
  },

  -- Rhythm: hits less than ChainGapMs apart are one string. Light hits in a row (VeryLight, Light) land a little
  -- lighter each time: hits 1, 2, 3, 4 and later each by LightDecay. Heavy and above, or a Middle hit after
  -- FinisherAfter hits in a string, are accents: stronger by AccentEmph, and they end the string (the next hit starts a
  -- new one). It changes the stop length, the hit shake and push, the flash, the extra camera shake and push-in, and
  -- the rumble. Only accents get the screen impact. The panel's "rhythm contrast" sets the overall contrast, 0 = no
  -- rhythm: every hit by its strength alone
  Rhythm = {
    Enabled = true,
    ChainGapMs = 400,
    LightDecay = { 1.0, 0.85, 0.7, 0.6 },
    FinisherAfter = 3,
    AccentEmph = 1.3,
    -- Heavy hits in a row (chain hits, for example): the first is an accent, the next ones are not and each is
    -- multiplied by HeavyRepeatDecay, down to HeavyRepeatFloor; it resets after a pause
    HeavyRepeatDecay = 0.85,
    HeavyRepeatFloor = 0.7,
    -- Density: each hit adds FatigueWeight to a "load" that halves every FatigueHalfLifeMs ms; a hit lands at
    -- 1 - Fatigue x load (accents get half of that), at least FatigueFloor. The denser the hits, the lighter each one,
    -- so the feedback does not pile up. 0 = off
    Fatigue = 0.35,
    FatigueHalfLifeMs = 600,
    FatigueFloor = 0.7,
    FatigueWeight = { VeryLight = 0.15, Light = 0.2, Middle = 0.3, Heavy = 0.4, UltraHeavy = 0.5, Break = 0.6, Default = 0.25 },
    ClashGapMs = 600,          -- Clashes less than this apart are one string: only the first one stops you (perfect deflects stop you each time, from the second on shorter by RepeatPerfectScale)
  },

  -- Kill accent: the hit data has no health, so CheckAfterFrames frames after your hit the mod reads the enemy's
  -- health from its ability system's attribute sets (the attribute named in HealthNames, without Max); at
  -- DeadAtOrBelow or less, this hit killed it. The killing blow gets extra: the screen edges darken (Screen), a camera
  -- shake (ShakeClass), a push-in and swing, and rumble. The first LogChecks checks write the attribute names and
  -- the health into the log (v0.7.0 looked for a death tag, but this game version lists no tags)
  Kill = {
    Enabled = true,
    CheckAfterFrames = 3,
    HealthNames = { "Health", "HP", "Hp", "Life" },
    DeadAtOrBelow = 0,
    HoldFrames = 16,           -- The killing blow holds the enemy this much longer (at 60 fps, times the panel's "hit stop length"), past the super armor guard and the per-second limit.
                               -- Works only when the game takes the health before its slow-motion starts; the log's kill lines say so. 0 = off
    Screen = 0.5,
    ShakeClass = shake("CameraShake_PunchHit_Level4"),
    ShakeScale = 1.0,
    PushCm = 20,
    KickDeg = 1.2,
    Rumble = { Body = 1.0, BodyMs = 180, Edge = 0.8, EdgeMs = 90 },
    LogChecks = 12,
  },

  -- Hitch log: when a frame takes much longer than usual (over HitchMs ms and 4 times the usual), hitfeel.log gets a
  -- hitch line with what the mod did in the two frames before (loading assets, the first play of an effect, and so
  -- on); nothing there means it is the game's own hitch. 0 = no log.
  -- Performance log (Perf): while fighting every PerfEverySec seconds, and each time the mod is switched on or off,
  -- hitfeel.log gets a perf line: the frame rate fighting and calm, the slowest 1% of frames, the mod's own time per
  -- frame and per hit, how many of its effects play at once and how long each lasts. Switch the mod with Ctrl+F7 in
  -- the same fight to see how much of a frame rate drop is the mod's
  Diagnostics = {
    HitchMs = 70,
    MaxHitchLogs = 30,         -- At most this many lines per game session (after that one line every 50)
    Perf = true,
    PerfEverySec = 60,
    WeaponLogs = 30,           -- A weapons line in hitfeel.log when a weapon's socket or visibility changes, at most this many per game session; 0 = none
  },

  -- Effects
  Vfx = {
    Enabled = true,
    -- The engine may not cull this mod's effects by its effect budget. Skill effects (the ink blade is one) allow only
    -- one or two at a time: in v0.6.2 only the first hit of a string got its hit effect and the engine dropped the next
    -- ones, which was "the hit effect sometimes does not show". false = back to v0.6.2's way
    NeverCull = true,
    -- The engine's effect budget does not cover this mod's effects, so the mod keeps its own: at most MaxAlive at once
    -- (a new one ends the oldest first, those already fading out first), each at most KillAfterMs ms. 0 = no limit
    MaxAlive = 12,
    KillAfterMs = 6000,
    MinIntervalMs = 30,        -- Hit trail on the blade: one per blade within this many ms (one swing hitting two enemies adds one). Hit effects are not limited by it: every hit gets one
    MaxLifeMs = 1500,          -- The longest one of this mod's effects lives (ms) before it is turned off; some effects loop forever without this
    -- When the game already played the same effect set on this enemy (for example enemies that do not bleed, like
    -- YuCong, which get the doll hit effect in the base game), this mod does not play it again
    SkipWhenGameUsesSameSet = true,
    -- Tint hit effects dark red (the effect where the blade hits, the hit trail on the blade, the extra impact effect).
    -- Only effects that have a color parameter of their own take it; metal sparks and the doll hit trail do not.
    -- Materials = true tries to change the color on the effect's materials, but in v0.6.1 the game showed that this
    -- version's effect components let no material be changed, so it is off. The first time each effect plays,
    -- hitfeel.log says whether it can be tinted; so does the line under "hit effect" in the panel. For dark red, pick
    -- an effect that is dark red already with Ctrl+F6, such as the ink blade
    Tint = { Enabled = true, Color = { R = 0.30, G = 0.0, B = 0.008, A = 1 }, Materials = false },
    -- This mod's effects are drawn in front of the game's own translucent effects (blood mist, smoke); 0 = the
    -- engine's default depth order
    SortPriority = 10,
    -- Swing air trail: every swing carries an air trail on the blade for the whole swing. It starts when the blade tip
    -- moves faster than StartCmPerSec (cm/s) relative to your body in two frames in a row, and ends after StopFrames
    -- frames slower than StopCmPerSec, at most MaxMs ms. It uses the one-step-lighter doll hit trail; the trail on hits
    -- (AirTrail below) is an extra layer
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
    -- Hit trail: on a hit, one more trail on the blade that hit the enemy. Off by default since v0.5.4: the blade's
    -- own swing trail stays as it is, and Slash below puts an effect where the hit lands instead
    AirTrail = {
      Enabled = false,
      MinLevel = 1,
      UseWeaponTrail = false,  -- true = prefer the swing trail the weapon plays itself (v0.5.1's way)
      AtTip = true,            -- The swing trail sits at the blade tip (where the trail is widest); false = at the blade root. The hit trail always sits on the blade socket
      ByWeapon = {             -- Per weapon type: ["1H"] one hand, DW dual blades, ["2H"] two hands; Default for the rest
        Default = COMMON .. "Doll/NS_DollHitTrail_00{n}.NS_DollHitTrail_00{n}",
      },
      Ms = { VeryLight = 90, Light = 110, Middle = 140, Heavy = 170, UltraHeavy = 200, Break = 220, Default = 120 }, -- How long it stays (ms)
      -- {n} in a path becomes a number by the hit's strength (the game's own hit effects go from _001, the lightest,
      -- upward); hit effects can use it too. When only some tiers exist, write {n:1,3,5}: the nearest one is used
      TierNumber = { VeryLight = 1, Light = 2, Middle = 3, Heavy = 4, UltraHeavy = 5, Break = 5, Default = 2 },
      -- Effects with these words in the name are "hit trails": the game puts them on the blade socket on a hit, and so
      -- does this mod; the rest go where the weapon's own trail sits
      HitTrailKeywords = { "HitTrail", "BloodTrail" },
    },
    -- An extra hit impact effect (the one the game uses for enemies that do not bleed). Off by default since v0.5.4:
    -- it is one of the hit effect candidates below
    HitVfx = {
      Enabled = false,
      AssetPath = COMMON .. "Doll/NS_DollHit_00{n}.NS_DollHit_00{n}",  -- Empty = one more copy of the weapon's own hit effect (blood)
      UseSweep = true,         -- Turned along the swing (like the base game's blood slash); false = facing you
      RotationOffset = { Pitch = 0, Yaw = 0, Roll = 0 },  -- Turn it here when the direction is wrong (degrees)
      Scale = { VeryLight = 1, Light = 1, Middle = 1, Heavy = 1, UltraHeavy = 1, Break = 1, Default = 1 },  -- 0 = none for this tier
    },
    -- Hit effect: a blade-light line or an air slash where the hit lands. Its long side follows this swing's real
    -- direction (the blade tip's motion in the frame before the hit), its face turned to the camera. Ctrl+F6 steps
    -- through the candidates below (it shows the name on screen and previews it in front of you); the choice is
    -- saved in slash_choice.txt. Each effect's own strength step, scale and angle are on the Ctrl+F5 panel's
    -- "hit effect" page and saved in slash_tuning.lua.
    -- Size: the game's effects have one size per file; a heavy hit looks bigger because it is another file (_101
    -- light, _103 middle, _105 heavy), not a bigger scale. Scaling does little for particle effects such as sparks
    -- and flashes (at 0.01 in v0.5.4 they still looked the same), so effects with {n} change files by strength like
    -- the game does, and the panel's "strength step" moves them a few steps lighter or heavier
    Slash = {
      Enabled = true,
      MinLevel = 1,            -- From VeryLight on
      -- The default effect, while none was picked with Ctrl+F6 or the panel (deleting slash_choice.txt also goes back
      -- to it): the ink blade, at the size and angle the author uses (see Effects below). v0.6.2 used the first
      -- candidate by default, a QTE effect that filled the screen with purple fire on every hit at its own size
      Default = asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiMoShang/", "NS_Hun_HeiMoShang_DelayBlade_101"),
      Candidates = {
        asset("/PBZVFXPack/VFX/BattleFX/ZuoShang/", "NS_ZuoShang_LaSwordHit_QTE_601"),
        asset("/PBZVFXPack/VFX/BattleFX/ZuoShang/", "NS_ZuoShang_PhantomSwordHit_002"),
        asset("/PBZVFXPack/VFX/BattleFX/WanJun/", "NS_WanJun_CAHit_201"),
        asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiShang/", "NS_Weapon_Tang_BladeBullet_001"),   -- Blade wave (air slash)
        asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiShang/", "NS_Weapon_Tang_MeshBlade_301"),
        asset("/PBZVFXPack/VFX/BattleFX/HuaShan/", "NS_HuaShan_FlashLight_301"),
        asset("/PBZVFXPack/VFX/BattleFX/LeiTing/", "NS_LightningHit_201"),
        asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiMoShang/", "NS_Hun_HeiMoShang_DelayBlade_101"), -- Ink blade (a skill effect)
        asset("/PBZVFXPack/VFX/BattleFX/ChiYingGuRen/", "NS_ChiYingGuRen_MaskBlade_002_Main"),
        asset("/PBZVFXPack/VFX/BattleFX/MBoss/", "NS_MBoss_Blade_001"),
        COMMON .. "Doll/NS_DollHit_00{n}.NS_DollHit_00{n}",       -- The hit effect the game uses for enemies that do not bleed, 5 tiers by strength
        asset(COMMON .. "Blood_V2/", "NS_BloodSlash_004"),        -- The base game's blood slash (red)
        -- Metal sparks: the game has three files, light _101, middle _103, heavy _105; {n:1,3,5} = one of them by the hit's strength
        COMMON .. "HitEffect/NS_MetalDoll_Hit_10{n:1,3,5}.NS_MetalDoll_Hit_10{n:1,3,5}",
      },
      -- Each effect's own default strength step (Step, -1 = one step lighter), scale (Scale) and angle (Angle turns it
      -- in the screen plane, Roll around the swing direction, Pitch up and down, in degrees); panel values win
      Effects = {
        -- The ink blade is a skill effect, two or three enemies tall at 1.0. Scale 0.15, Roll 90 and Pitch 15 are what the author set in the panel
        [asset("/PBZVFXPack/VFX/BattleFX/Weapon/HeiMoShang/", "NS_Hun_HeiMoShang_DelayBlade_101")] = { Scale = 0.15, Angle = 0, Roll = 90, Pitch = 15 },
      },
      Scale = { VeryLight = 0.8, Light = 0.9, Middle = 1.0, Heavy = 1.15, UltraHeavy = 1.25, Break = 1.35, Default = 1.0 }, -- One more scale by strength
      -- Moved toward the camera until it is out of the struck enemy's body (BodyMarginCm cm past its collision capsule),
      -- so the body does not hide it; at least TowardCameraCm, at most MaxTowardCameraCm. Along the camera's view, so it
      -- stays at the same place on screen, only nearer
      TowardCameraCm = 20,
      MaxTowardCameraCm = 120,
      BodyMarginCm = 12,
      PreviewDistanceCm = 180, -- How far in front of you the Ctrl+F6 preview plays
      MaxMs = 900,             -- The longest it lives (ms)
    },
  },

  -- Hit reaction: only the model moves, not the collision capsule, the AI or the animation, so hit stun and hit
  -- detection do not change
  React = {
    Enabled = true,
    Displace = {               -- A small push: a few cm along the hit, then back (the base game has its own knockback; this only adds a jolt)
      Enabled = true,
      Cm = { VeryLight = 0.5, Light = 1.0, Middle = 2.0, Heavy = 3.5, UltraHeavy = 4.5, Break = 5.0, Default = 1.0 },
      Frames = 6,
    },
    Shake = {                  -- Hit shake: while the enemy is held, its model shakes quickly from side to side and fades (the fighting-game hit shake)
      Enabled = true,
      Cm = { VeryLight = 1.0, Light = 1.5, Middle = 2.0, Heavy = 3.0, UltraHeavy = 3.5, Break = 4.0, Default = 1.5 }, -- How far it shakes (cm)
      Frames = { VeryLight = 4, Light = 6, Middle = 7, Heavy = 9, UltraHeavy = 11, Break = 12, Default = 6 },        -- How long it shakes; as long as the hit stop
      Hz = 30,                 -- How many times a second it changes side
    },
    -- PBZHitFeel's physics jiggle (Jiggle) is removed in Hit Feel: it turned physics on for the bones of an enemy in
    -- the middle of its hit animation, and it is linked to a game crash
  },

  -- Controller rumble (Xbox/XInput): Body = the big left motor, low and heavy; Edge = the small right motor, high and
  -- crisp. Strength 0-1, times in ms
  Rumble = {
    Enabled = true,
    Scale = 1.0,               -- Overall strength
    ForceEnableUEForceFeedback = false,  -- Set to true only when the log shows bForceFeedbackEnabled=false and you feel no rumble
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

  -- Hit detection (usually no need to change)
  Hit = {
    DedupeMs = 40,             -- Repeated calls for the same enemy within 40 ms count once
    MaxVictimDistanceCm = 600, -- How far to look for the struck enemy
    ReadSlomoOwner = true,     -- Read who was hit from the game's hit slow-motion; on problems set to false to use "the nearest enemy in front" instead
    MaxFullPerFrame = 3,       -- When one frame hits several enemies (a sweep through a crowd, an area skill), the first ones get the full feedback, the rest only the hit stop; 0 = no limit
    SheathedSockets = { "Back" }, -- A weapon on a socket whose name has one of these words (any case) counts as sheathed: no swing trail, and not the blade that hits; hidden weapons do not count either. Measured: the back is Pt_DoubleBlade_R_Back_Socket and the like, the hands weapon_r_Socket, weapon_l_Socket, WEAPON_R
    BlockMaterials = { "Shield" }, -- A hit on these materials counts as "blocked by the enemy" (the Blocked tier), not as a hit
    BladeSockets = { "BladeBloodStart", "BladeStart", "Blade_Start", "BladeBloodEnd", "BladeEnd", "Blade_End" }, -- Sockets at the start of the blade
    BladeTipSockets = { "BladeBloodEnd", "BladeEnd", "Blade_End", "BladeTip", "WeaponTip", "Tip" }, -- Sockets at the blade tip (with the start they make the blade, used to find the hit point)
    WeaponKeywords = {         -- Weapon type by words in the attack tag
      DW = { "Dual", "Double", "Shuang", "Snake" },
      ["2H"] = { "ZhanMa", "Great", "BrutalAxe", "Axe" },
      ["1H"] = { "TangBlade", "Blade", "Sword", "Jian" },
    },
  },

  -- Knockback ease-out: the game's knockback is a constant force, so a launched body slides away at an even speed.
  -- This gives it a force curve that starts fast and ends slow, with the same average, so the distance is the same as
  -- in the base game: only a harder start and a slowing end. It works on enemies and on you
  Knockback = {
    Enabled = true,
    StartSpeed = 1.7,          -- The start speed as a multiple of the base game's (1 = the base game's even speed, 2 = the hardest); the end speed = 2 minus this
    Measure = true,            -- Writes how far each knockback slid to logs/probe_knockback.txt, to compare with the mod off (Ctrl+F7)
    MeasureMs = 600,
    MeasureCount = 40,
  },

  -- Hit flash: the struck enemy's outline flashes (dark red since v0.5.9) and fades within a few frames. The game's
  -- character materials have an outline light (fresnel) of their own; ZhanMa's emergency shield changes these two
  -- parameters to make you glow. Here the same two parameters change on the struck enemy and go back afterwards.
  -- In the game the parameter names are checked against the game's shield ability (UseGameNames)
  Flash = {
    Enabled = true,
    StrengthParam = "Fresnel_Strength",
    ColorParam = "Fresnel_Color",
    UseGameNames = true,
    Color = { R = 0.55, G = 0.015, B = 0.03, A = 1 },  -- Flash color: dark red since v0.5.9. White is { R = 1, G = 1, B = 1, A = 1 }
    -- Strength (lower is fainter). Since v0.5.7 it is 0.3 times v0.5.6's, the step set in the panel; quick light hits
    -- get less by the rhythm. The outline light adds light, and deep red is dark itself, so it needs twice the white
    -- strength to show
    Strength = { VeryLight = 0.72, Light = 1.08, Middle = 1.44, Heavy = 2.16, UltraHeavy = 2.52, Break = 2.88, Default = 1.08 },
    Frames = { VeryLight = 3, Light = 4, Middle = 5, Heavy = 6, UltraHeavy = 7, Break = 8, Default = 4 },   -- Frames to fade out
    HoldFrames = 1,            -- Frames the brightest moment holds before it fades
    Parts = true,              -- The other models on the body (clothes, hair, weapons) flash too
    CreateMids = true,         -- Creates a dynamic material instance for a material slot that has none yet (the engine does the same when it changes a parameter)
  },

  -- Feedback when you are hit. Guard: you hold your guard and block an enemy's blow (the game counts it as a normal
  -- deflect); Hit: it got through to you. The camera is knocked back a little and tips up, your model is pushed a few
  -- cm and springs back (the model only; control and hit detection do not change), and the controller rumbles hard;
  -- on a hit your outline also flashes red, and the game's own being-hit camera shake goes up one level. Damage over
  -- time such as burning does not count
  Receive = {
    Enabled = true,
    Guard = { RecoilCm = 10, KickDeg = 0.7, FlinchCm = 2.5, FlinchFrames = 6 },  -- Knocked back cm, tipped up degrees, model pushed cm; the rumble is in Deflect.Rumble.Guard
    Hit = {
      RecoilCm = { VeryLight = 6, Light = 8, Middle = 12, Heavy = 18, UltraHeavy = 22, Break = 26, Default = 10 },
      KickDeg = { VeryLight = 0.4, Light = 0.6, Middle = 0.9, Heavy = 1.3, UltraHeavy = 1.5, Break = 1.7, Default = 0.7 },
      FlinchCm = { VeryLight = 1.5, Light = 2, Middle = 3.5, Heavy = 5, UltraHeavy = 5.5, Break = 6, Default = 2.5 },
      FlinchFrames = 8,
      ShakeUpgrade = 1,        -- How many levels the game's own being-hit camera shake goes up (capped at 4)
      Flash = { Color = { R = 1, G = 0.12, B = 0.06, A = 1 },   -- The red flash on you
        Strength = { VeryLight = 0.30, Light = 0.42, Middle = 0.60, Heavy = 0.84, UltraHeavy = 0.96, Break = 1.08, Default = 0.48 },
        Frames = 6 },
      Rumble = {               -- Rumble when hit: mostly the big left motor, heavy
        VeryLight = { Body = 0.35, BodyMs = 70, Edge = 0.2, EdgeMs = 40 },
        Light = { Body = 0.5, BodyMs = 90, Edge = 0.3, EdgeMs = 45 },
        Middle = { Body = 0.7, BodyMs = 120, Edge = 0.4, EdgeMs = 55 },
        Heavy = { Body = 0.95, BodyMs = 170, Edge = 0.5, EdgeMs = 70 },
        Default = { Body = 0.6, BodyMs = 100, Edge = 0.35, EdgeMs = 50 },
      },
    },
  },

  -- Sha-Chi and guard breaks. Sha-Chi is the game's one resource for attack and defense: holding your guard drains
  -- it, each blocked blow drains more (also when the enemy blocks your attack), and when it runs out your guard
  -- breaks. This makes it something you feel in the fight, without changing the game's guard:
  -- Low Sha-Chi (Low): in a fight below half Sha-Chi, the screen edges slowly darken to dark red, deeper the lower it
  -- gets; below PulseBelow the edges beat like a heart, quicker as it nears empty. They fade when Sha-Chi comes back
  -- or after a few seconds without fighting (CombatSec).
  -- Heavier blocks (Strain): below half Sha-Chi every deflect's camera, rumble and sparks get stronger, up to Max
  -- times at empty, and the edges darken for a moment.
  -- Guard break (Break): the moment the game breaks your guard, the screen edges flash dark red and ebb with two
  -- beats; the camera is knocked back and tips up, and the controller gives two heavy pulses. This moment skips the
  -- usual being-hit feedback and stands alone
  Guard = {
    Enabled = true,
    PollFrames = 3,            -- Read Sha-Chi every this many frames
    Low = {
      Enabled = true,
      Below = 0.5,             -- Starts below this share of Sha-Chi
      Full = 0.12,             -- The edges are deepest (Edge) at this share
      Edge = 0.45,             -- The deepest edge strength (0-1)
      PulseBelow = 0.3,        -- The heartbeat starts below this share
      PulseAdd = 0.22,         -- The strength the heartbeat adds
      PulseHz = { 0.9, 1.7 },  -- Heartbeat rate: when it starts, and at empty Sha-Chi (beats a second)
      CombatSec = 4,           -- When Sha-Chi has not dropped for this many seconds, the fight counts as over and the edges fade
      InMs = 120,              -- How fast it darkens (ms)
      OutMs = 700,             -- How fast it fades (ms)
    },
    Strain = { Below = 0.5, Max = 1.6, Tick = 0.25 },  -- Below Below Sha-Chi deflects get stronger, Max times at empty; Tick is the strength of the edge flash
    Break = {
      Enabled = true,
      Edge = 0.9,              -- The edge strength at the moment of the guard break
      HoldMs = 140,            -- How long the deepest moment holds
      FadeMs = 1500,           -- How long until it has faded
      Beats = 2,               -- How many beats as it fades
      RecoilCm = 30,           -- How many cm the camera is knocked back
      KickDeg = 2.2,           -- How many degrees the camera tips up
      Rumble = { Body = 1.0, BodyMs = 260, Edge = 0.8, EdgeMs = 110, ThenBody = 0.45, ThenMs = 220, GapMs = 170 },  -- One heavy pulse, then one more after GapMs
    },
    Attributes = { Value = { "Shachi" }, Max = { "Shachi_Max" }, Min = { "Shachi_Min" } },  -- Sha-Chi's names among the game's attributes
  },

  -- Overall multipliers: one number for a whole kind of feedback, mainly for the Ctrl+F5 panel; 1 = no change
  Tuning = {
    Freeze = 1,                -- Hit stop length
    DeflectFreeze = 1,         -- The enemy's stop on deflects
    PlayerDeflectFreeze = 1,   -- Your own stop on deflects (0 = you never stop on deflects)
    Push = 1,                  -- How far the model is pushed
    HitShake = 1,              -- How far the struck enemy shakes
    Flash = 1,                 -- Hit flash strength
    Receive = 1,               -- Camera knock-back and model push when you are hit
    AirTrail = 1,              -- How long the hit trail stays on the blade
    HitVfx = 1,                -- Size of the extra hit impact effect
    Slash = 1,                 -- Hit effect scale (no longer on the panel: each effect's strength step and scale are on the panel's "hit effect" page)
    Sparks = 1,                -- Clash spark amount: 1 = one copy of each layer, 1.5 = two of the first layer, 2 = two of each, 0 = none
    Shake = 1,                 -- Extra camera shake
    Punch = 1,                 -- Camera push-in and swing
    Screen = 1,                -- Screen impact (vignette) strength
    Rhythm = 1,                -- Rhythm contrast: 0 = no light and heavy difference, 1 = default, 2 = double contrast
    Guard = 1,                 -- Low Sha-Chi and guard break cues: the red edge strength, the camera and rumble of a guard break
  },

  -- Preload: when a map loads, everything this mod uses (effects, sounds, shakes, the panel) is loaded and kept, so
  -- nothing stutters in a fight because it is used for the first time
  Preload = {
    Enabled = true,
    DelayMs = 1500,            -- How long after the map loads it starts (ms)
    PerFrame = 2,              -- Assets loaded per frame, spread out
    SecondPassSec = 30,        -- Seconds after the map loads to look for knockback data once more (some combat data loads late)
  },

  -- In-game tuning panel: Ctrl+F5 opens it, used with the mouse; Ctrl+F5 (or Esc) closes it. Chinese, English,
  -- Japanese and Korean
  Hud = {
    Enabled = true,
    X = 40,                    -- Where the panel's top left corner is on screen (pixels at 1080p; the panel is 520 x 800)
    Y = 70,
    ToastX = 40,               -- Where the Ctrl+F6 notice is while the panel is closed
    ToastY = 30,
    RefreshMs = 250,           -- How often the status section refreshes
    ToastMs = 2500,            -- How long the effect's name shows on screen when Ctrl+F6 changes the hit effect (ms)
    TrialSec = 10,             -- The panel's "vanilla for 10 s": how many seconds the mod is off (the panel closes, you fight a while, it comes back by itself)
    Language = "auto",         -- Panel language: "auto" follows the game's language, or "zh" Chinese / "en" English / "ja" Japanese / "ko" Korean. The list at the panel's top also changes it
    EscCloses = true,          -- Esc also closes the panel. Set to false when it clashes with the game's own menu; then only Ctrl+F5 opens and closes it
    BuildMsPerFrame = 4,       -- The panel is built over several frames after a map loads, at most this many ms a frame (building it at once stutters)
  },

  -- Hotkeys (by default all with Ctrl held). Since v0.5.5 the keys are read once a frame on the game thread. UE4SS's
  -- own key binds run on its own thread, at the same time as this mod's per-frame code on the same Lua data: that is
  -- how v0.5.4 crashed when Ctrl+left/right was held in the panel.
  -- When a key clashes with another mod's, change it here: Modifier is the key held with them, the five after it are
  -- the keys themselves (engine key names: "F1"-"F12", "Insert", "Home", "PageUp", a letter "K", the numpad
  -- "NumPadFive" and so on). The panel and the notices show the keys in use.
  -- With PBZModLoader installed do not use Alt+F5: it holds Alt+F5 for its own hot reload, and the game never gets it
  Keys = {
    ReadOnGameThread = true,   -- If a hotkey does nothing, set to false to use UE4SS's key binds again (the old way; holding keys in the panel may crash)
    RepeatDelayMs = 450,       -- How long the mouse holds a panel arrow before it repeats (ms)
    RepeatMs = 110,            -- Time between repeats (ms)
    Modifier = "Ctrl",         -- "Ctrl", "Alt", "Shift", or "None" (nothing held)
    Panel = "F5",              -- Open / close the tuning panel
    Effect = "F6",             -- Next hit effect
    Toggle = "F7",             -- Switch the whole mod on and off
    Reload = "F8",             -- Reload the settings and the scripts
    Probe = "F9",              -- Write the probe data once
  },

  -- Probe: the first 30 hit effects and slow-motion calls go to logs/, for tuning the next version. Read-only
  Probe = {
    Enabled = false,
    Scan = false,              -- One full scan of the reflection data and asset names after the game starts. In v0.3.1 it crashed together with the Ctrl+F6 preview; leave it off
    Dumps = false,             -- The full parameters of the first hits and the struck enemy's bone list go to logs/ (the first hit stutters once; keep it off)
    MaxHitDumps = 30,
    ScanDelaySec = 12,
  },
}
