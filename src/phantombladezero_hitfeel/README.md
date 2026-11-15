# PBZHitFeel - Hit Feel Overhaul (based on PBZHitFeel 0.7.3)

This is PBZHitFeel 0.7.3 by MoonlightSakura with two changes by Kintaro: the physics jiggle is removed (it is
linked to a game crash), and so is the in-game updater (updates come as new releases on GitHub). The rest of this
manual is the original's; what it says about the jiggle and the updater no longer applies. The original came with
a Chinese manual too; this build ships this English one.

A UE4SS Lua mod that adds weight to every hit without slowing your own character. Only the enemy you hit stops for
a moment; everything else is camera, effects, the enemy's model, rumble and audio. Your own character pauses only on
deflects, and only on the first clash of a quick string of them.

## What it does

- **Hit stop on the enemy only**: the enemy you hit freezes for 4–12 frames (by strength), through the game's own
  slomo system, so the hold and the recovery are the game's. You never stop on normal hits.
- **Rhythm**: quick light hits in a string land a little lighter each time; heavy hits and the middle hit that ends a
  string are accents (stronger hold, shake, flash and rumble). Only accents get the screen impact.
- **Hit flash**: a short dark-red rim-light flash on the enemy you hit (the game's own Fresnel parameters, restored
  after).
- **Hit shake and push**: the enemy's model shakes sideways and is pushed a few cm while it is held (model only; hit
  boxes, AI and animations are untouched).
- **Camera**: the game's attack shakes raised a level, a fill shake on light hits the game leaves still, a short
  directional punch shake.
- **Screen impact**: on accents, a held guard and blows that get through, the edges of the screen darken for a moment
  (the camera's own vignette plus a touch of chromatic fringe); the middle of the screen never flashes. At most one
  every 1.2 s, so a quick string of heavy blows does not keep the edges dark.
- **Hit effect**: a slash or air-slash effect where the blow lands, aligned with the actual swing and facing the
  camera, moved along your line of sight out of the struck body so the body does not hide it, and drawn over the
  game's own blood mist and smoke. Every hit gets one: the engine is kept from culling them in quick strings. The
  default is the dark-red ink blade (the 8th); Ctrl+F6 cycles 13 candidates (previewed in front of you). Tinted dark
  red when the effect has a color parameter of its own; the log and the panel say which effects do.
- **Swing air trail**: an air trail follows the blade through every swing (detected from how fast the blade's tip
  moves relative to you); the hit trail is an extra layer on hits.
- **Deflects**: clash sparks where the blades meet, a clang layer (switch it off or turn it down on the panel's Sound
  tab; the game's own clash sound stays), a short stop for both sides, rumble.
- **Being hit**: camera recoil, your model pushed back, a red rim flash, the game's being-hit shake raised a level.
- **Sha-Chi and guard breaks** (v0.7.3): Sha-Chi drains while you guard and on every blocked blow, and when it runs
  out your guard breaks. In a fight, once it is below half, the screen's edges darken toward red, more the lower it
  gets, and below 30% they beat like a pulse, quicker as it nears empty; they fade when Sha-Chi comes back or the
  fight goes quiet. Blocks on a weak guard land heavier (up to 1.6x at empty). The break itself: the edges flash dark
  red and ebb with two beats, the camera staggers back, and the controller gives a heavy double thump. The edge is an
  image under the game's own HUD, so the health and Sha-Chi bars stay sharp. Nothing changes the game's guard.
- **Audio**: battle music ducks for a moment on hits; dual blades get a layer of the one-hand blade's hit sound.
- **Knockback ease-out**: knockback starts faster and ends slower, same distance.

## Requirements

- Phantom Blade Zero on Steam. Tested with build 26266538 and with build 26367565 (the November 4 update); both
  work. At startup, a `game:` line near the top of `logs/hitfeel.log` names the build you are running.
- UE4SS for Phantom Blade Zero ([KintaroModding/ue4ss](https://github.com/KintaroModding/ue4ss/releases), the build for UE 5.7;
  tested with v3.0.1-1195-g1ceefac8), installed so
  that `dwmapi.dll` and the `ue4ss` folder sit next to `PBZ.exe` in `<game>\platform\steam\`.

## Install

Extract the archive into `<game>\platform\steam\` (the folder with `PBZ.exe`). You get
`ue4ss\Mods\PBZHitFeel\`. The included `enabled.txt` turns the mod on; no need to edit `mods.txt`.

To uninstall, delete `ue4ss\Mods\PBZHitFeel`. To remove UE4SS as well, delete `dwmapi.dll` and the `ue4ss` folder
next to `PBZ.exe`.

## Hotkeys

| Key | Action |
|---|---|
| Ctrl+F5 | Open or close the tuning panel |
| Ctrl+F7 | Mod on/off for this session (rumble: one pulse = on, two = off) |
| Ctrl+F6 | Next hit effect, previewed in front of you |
| Ctrl+F8 | Reload config.lua and the scripts |
| Ctrl+F9 | Write probe data to `logs/` |
| Esc | Close the tuning panel (set `Hud.EscCloses = false` in `config.lua` to leave Esc to the game) |

Hotkeys are read on the game thread from the player controller, so they work in game, not in the game's own menus.

## Tuning panel (Ctrl+F5)

Used with the mouse. Ctrl+F5 shows the panel and the cursor; click the controls. Esc, Ctrl+F5 or the X closes it and
gives the mouse and the controls back to the game. While it is open, clicks only reach the panel, the camera does not
follow the mouse, your character ignores the keyboard, and the game keeps running (open it somewhere safe). The Esc
that closes the panel never reaches the game, so the game's own menu does not open with it.

**Languages**: Chinese, English, Japanese and Korean, picked from the list next to the title. By default
(`Hud.Language = "auto"`) the panel follows the game's language (Chinese, Japanese or Korean; English for anything
else). The choice is saved, and the on-screen notices follow it too.

Feel presets (Vanilla / Subtle / Intense / Custom; the one in use is dark red), five tabs (Main, Action, Camera,
Sound, Advanced) and a description on every row. Switches toggle on a click; numbers step with the arrows (hold to
repeat); the mouse wheel scrolls. A changed row is marked `*`, and hovering it shows a reset mark. "Vanilla for 10 s"
turns the mod off for 10 seconds and closes the panel so you can fight in vanilla; the mod comes back on by itself.
Changes apply at once and are saved to `tuning.lua` in the mod folder; picking a preset keeps your own set in
`tuning_custom.lua`, and Custom brings it back.

Everything is also in `config.lua`, commented in Chinese.

## Compatibility

- Changes nothing on disk outside the mod folder; everything is done in memory while the game runs. Saves are not
  touched.
- **Do not combine with other hitstop mods** (for example pbz_hit_enhance): both rewrite the same hit lookup. If you
  want to, turn off the hit stop (Hitstop) in one of them.
- Other UE4SS mods that bind Ctrl+F5–F9 will clash with the hotkeys.
- Mods that raise the game's sound levels (for example one that raises the hit and perfect-defense sounds by 8 dB)
  work alongside, but the sound adds up: this mod ducks the music on hits and layers a clash sound on parries. If it
  gets loud, turn "Parry sound volume" down or "Music dip" off on the Sound tab.
- While the panel is open it shows the cursor, sets the input mode and turns your character's input off, and puts
  all three back when it closes. Another mod's mouse menu open at the same time would fight over the input mode.
- A game update that renames hit-effect assets only disables the affected effect (logged in `logs/hitfeel.log`).

## Logs

`logs/hitfeel.log` records what the mod found and did. A frame that takes much longer than usual is logged as
`hitch` together with the mod's own time in that frame (`the mod's own code … ms of it`, v0.7.3) and what the mod did
just before it, so a stutter can be traced to the mod or to the game: a frame of a few hundred ms with 0-1 ms of the
mod's and nothing before it is the game's own. A hit
effect the engine stopped anyway is logged as `the engine stopped hit effect`. Every minute of fighting, and whenever
the mod is switched off or on, a `perf` line gives the frame rate and the mod's own cost (see below).

`logs/recent.txt` (v0.7.3) lists the mod's recent actions, one a line: your hits and clashes (on what material, and
whether a crowd left one with its hit stop only), the effects it spawned, kills, guard breaks, what it loaded from
disk, reloads and updates. Each line is written as it happens, so after a crash the file ends with the mod's last
action. The previous session's is kept as `recent.prev.txt`.

## If the frame rate drops

The game's own frame rate drops in fights anyway, so first tell how much of a drop is this mod's:

1. In the same fight, switch the mod off with Ctrl+F7 (two rumble pulses), fight a while, then switch it back on
   (one pulse); or use the panel's "Vanilla for 10 s". With frame generation on, the counter shows generated frames:
   turn it off for the comparison.
2. `logs/hitfeel.log` has a `perf` line for each stretch, in this form (the numbers are only an example):
   `perf (mod on, 60 s): fighting 23 s at 64 fps, slowest 1% of frames 28.0 ms; calm 37 s at 81 fps … | the mod's own time: 0.40 ms a frame fighting, 0.15 calm; 41 hits and parries, about 1.4 ms each …; Lua memory 3.2 MB | its effects: 63 started, at most 8 at once, 1.6 s each … | 17 blows and clashes not yours, left alone`
   - `fighting … fps` and `calm … fps`: the frame rate within 3 s after any of your hits, parries or blows taken, and
     otherwise; `slowest 1%` is how long the slowest 1% of frames took (higher feels choppier).
   - `the mod's own time`: the mod's Lua on the game thread, per frame and per hit, then its largest parts. At 80 fps a
     frame is 12.5 ms.
   - `Lua memory`: the mod's own Lua memory. What it keeps per enemy is pruned every few seconds, so this does not grow
     with the length of a session. The game's own memory is not in it, and is far larger.
   - `its effects`: how many of the mod's effects played at once, how long each lasted, how many the effect budget
     (`Vfx.MaxAlive`) ended.
   - `hits in a crowd given their hit stop only`: hits past `Hit.MaxFullPerFrame` enemies struck in one frame (v0.7.3).
   - `not yours, left alone`: how many blows and clashes between NPCs the mod saw and ignored.
3. Compare `fighting … fps` on the `mod on` and `mod off` lines. (Off, its hooks still look at each hit, so it costs a
   little more than not having it installed. For that comparison, move the `ue4ss\Mods\PBZHitFeel` folder out and
   watch the game's or the GPU driver's frame counter in the same fight.)

Send the `hitfeel.log` with the `perf` lines, and say which GPU, resolution and quality settings you use.

## If the game will not start or looks wrong

The mod puts nothing on screen and leaves input alone until you are in a level (the panel and the hidden widget that
holds its assets are built there). With several mods installed, narrow it down:

1. Turn off this mod only: move the whole `ue4ss\Mods\PBZHitFeel` folder somewhere else (the desktop, say). If that
   fixes it, please send the two logs below (its log is in the folder you moved).
2. Turn off every UE4SS mod: rename `platform\steam\dwmapi.dll` (e.g. to `dwmapi.dll.off`). If it still happens,
   UE4SS mods are not the cause: check pak mods in `~mods` or `LogicMods`, ReShade, `Engine.ini` tweaks, or verify the
   game files in Steam.
3. The first start after a game update recompiles shaders; give it time.

When reporting, attach `ue4ss\UE4SS.log` and `ue4ss\Mods\PBZHitFeel\logs\hitfeel.log`, and say whether you play on
Steam or WeGame and which other mods you use.

If the game crashes with a UE4SS `Fatal Error` window, do not start it again first (`UE4SS.log` is rewritten at every
launch). Send these, and say what you were doing and which version of the mod you use (the `PBZHitFeel 0.… loading`
line in `UE4SS.log`):

- `ue4ss\UE4SS.log`
- the `ue4ss\crash_*.dmp` the window names
- `ue4ss\Mods\PBZHitFeel\logs\recent.txt` (v0.7.3 and later): the mod's last few dozen actions before the crash. If
  you have started the game again since, the crashed session's is `recent.prev.txt`.

## Alongside other loaders and storefronts (v0.7.3)

- **PBZModLoader** (Nexus mod 113, a JavaScript/TypeScript mod loader): **install it alongside if you like, but it
  cannot run this mod.** PBZHitFeel is a UE4SS Lua mod and needs UE4SS.
  - The two leave each other alone: UE4SS uses `dwmapi.dll`, PBZModLoader `version.dll` by default (or hid, winmm,
    dsound, dxgi.dll). Its published source patches the game's script start, three PuerTS log functions and five
    script checks; UE4SS hooks the engine's ProcessEvent and friends. Different files, different code; its author
    says the two coexist too.
  - Hotkeys: it holds Alt+F5 for its hot reload, this mod uses Ctrl+F5. If you move this mod's keys to Alt, avoid
    Alt+F5.
  - Do not put PBZHitFeel into `ProjectPBZ\PBZModLoader\mods`; it goes into `ue4ss\Mods` as always.
  - JavaScript mods that also change hit stop, the camera or hit reactions stack with this mod; switch one side's off
    if it is too much.
  - The `env:` line near the top of `hitfeel.log` names the loaders and proxy DLLs it found.
- **Either UE4SS package works**: KintaroModding's and Vercadi's Phantom Blade Zero packages both use `dwmapi.dll`;
  install one. If the UE4SS in use lacks a function this mod calls, the log says which; the ones it can do without
  get a stand-in, and without a required one (`RegisterHook`, say) the mod does not start and says why.
- **WeGame and Epic**: both UE4SS packages are tested on Steam only. This mod finds everything by name, so where UE4SS
  runs, it most likely runs too; install beside that storefront's `PBZ.exe` (e.g. `platform\wegame\`).
- **Hotkeys** can be moved in `config.lua` (`Keys`: `Modifier` "Ctrl", "Alt", "Shift" or "None", and `Panel`,
  `Effect`, `Toggle`, `Reload`, `Probe` by engine key name); the panel and notices name the keys in use.
- **UE4SS's own hot reload** (Ctrl+R with `EnableHotReloadSystem = 1`) drops the old Lua state but not its widgets;
  at the next map this mod takes down what an earlier run of its scripts left (panel, red edge, preload holder) and
  gives back the input an open panel held.
- **Vortex**: "Install the download" also looks in `%APPDATA%\Vortex\downloads\phantombladezero`.
- **Title screen all red, buttons reading `CONFIRM {ButtonText}`**: PBZModLoader users reported it and fixed it by
  removing `ProjectPBZ\Content\Paks\~mods` (pak mods). This mod draws nothing before you are in a level.

## Updates

PBZHitFeel's in-game updater is not in Hit Feel: it asked Nexus Mods for the original PBZHitFeel and installed
it over this mod's folder, which would bring back what Hit Feel removed. Hit Feel's updates are new releases on
GitHub (a mod manager such as UE MM installs them). By hand: copy the new files over the folder. Your own
settings files (`tuning.lua`, `tuning_custom.lua`, `slash_choice.txt`, `slash_tuning.lua`) are not in a release,
so they stay. Ctrl+F8 makes changed scripts take over without a restart.

## Changes in v0.7.3

- **In-game updates**: the panel's Advanced tab can check Nexus for a newer version, open its download page and
  install the downloaded zip, which takes over without a restart; a version that keeps failing rolls itself back, and
  you can roll back by hand. See "Updating in game".
- **Hot reload of every script**: `main.lua` is now a small kernel that never changes, and every other script (also
  `hf_util` and `hf_config`, which Ctrl+F8 used to leave alone) can be swapped while the game runs. The new scripts
  load in full before anything is replaced; if they do not load or fail while starting, the running ones carry on.
  The log, the mod's time, the hooks, the panel and the preloaded assets carry over; no hook is registered twice and
  no per-frame loop is left running twice.
- **Sha-Chi and guard breaks**: dark-red screen edges as Sha-Chi drains, a pulse near empty, heavier blocks on a weak
  guard, and its own moment when your guard breaks (red flash, camera stagger, heavy double rumble).
- The release zip now has `logs\` and `update\` folders (each with a README), so `hitfeel.log` is finally written on
  players' PCs; until v0.7.2 there was none, and the same lines were only in `ue4ss\UE4SS.log`.
- **Stability and performance**, after a player crashed several times in the Xiao Xue boss fight with mobs around (on
  v0.7.0, whose crash on hits v0.7.2 fixed):
  - Crowds: when one frame's hits strike several enemies, the first 3 (in the order struck) get the whole feedback
    and the rest their hit stop only (`Hit.MaxFullPerFrame`, 0 = no cap). In the offline test one swing through 6
    enemies cost about 30% fewer engine calls in its frame; the blade is read once a frame, and enemies past the cap
    get no contact point.
  - The kill check remembers where each enemy's health lives and reads only that value; it used to walk the enemy's
    ability system three times a hit, about a dozen engine calls each. The entry goes when the enemy does.
  - The game's camera shake classes (your attacks' levels 0-4, being hit 1-4) are preloaded with the map. A level not
    yet loaded used to come from disk on the frame of a hit: in a real session the first blow taken stalled one frame
    for 106 ms, the same frame that first raised the being-hit shake (and first flashed your body's 43 materials).
    Anything still loaded from disk at a hit is named in the `hitch` line.
  - The work done every frame (reading the hotkeys, sampling the blade tips) uses the frame's time instead of asking
    the engine for it each time: 25.6 engine calls an idle frame before, 19.6 now (offline test). Measured in game
    on the author's PC (six one-minute `perf` lines, before this change): the mod takes 0.48-0.60 ms a frame in fights
    and 0.35-0.40 ms otherwise; fights ran 1-8 fps below calm (one stretch 2 fps above), which includes the game's
    own cost of a fight. The two largest per-frame parts are the blade tips (about 0.2 ms) and the hotkeys (about
    0.1 ms).
  - Swing trails go only on the weapons in use: shown, and not hanging from a back socket (a socket whose name holds
    `Back`, `Hit.SheathedSockets`). Every weapon you carried used to count, and one put away or hidden on your back
    swung round with each turn and roll and got a trail too: in the author's `recent.txt`, 3 of about 20 swings
    started 3 trails in the same frame (the dual blades and the wooden sword hidden on the back); 100-490 effects a
    minute, nearly all ended early by the 12-effect budget. A weapon put away or hidden in the middle of a swing (some
    moves hide them all) has its trail ended at once.
  - Parry sparks, and a hit's place and swing direction when no blade-to-body contact is found, used the blade
    nearest a hand. In game the blade socket of a weapon in hand is 75-113 cm from the hands and that of one on the
    back 20-59 cm, so it was often the one on your back. Now the blade is picked among the weapons in use, and the
    blade-to-body contact also uses only those.
  - Which weapon is in use was measured in game. A first try by the distance to a hand flipped within a second and
    was taken back; a session logging each weapon's attach socket and visibility then showed the dual blades in the
    hands at `weapon_r_Socket` and `weapon_l_Socket` and the wooden sword at `WEAPON_R`, put away at
    `Pt_DoubleBlade_R_Back_Socket`, `Pt_TangBlade_Back_Socket` and the like, the one not in use hidden. The log's
    `weapons` lines (at most 30 a session, `Diagnostics.WeaponLogs`) give each weapon's socket, whether it is shown and
    whether it is left out; the first 10 swing trails name their weapon.
  - A `hitch` line now gives the mod's own time in that frame.
  - New `logs\recent.txt`, the crash trail (see "Logs").
  - New offline tests: one swing through 6 enemies (no hit stop lost, the whole feedback for the first 3, fewer engine
    calls), enemies freed by the game in the middle of the flash and the knock, after the kill accent started, and 6
    at once (none touched again: in game that is a crash), their entries all gone a minute later, and `recent.txt`'s
    content and turnover. Both scenarios pass.
- **The automatic update check is off by default**: the mod asks Nexus only when you click "Check for updates", so no
  console window flashes at the game's start.
- **Compatibility**: checked against PBZModLoader's source (they coexist; see "Alongside other loaders"). Hotkeys can
  be moved in config.lua; an `env:` log line names the storefront, the UE4SS version and other loaders; missing UE4SS
  functions get stand-ins or a clear message; widgets left by UE4SS restarting its mods are taken down; the updater
  also looks in Vortex's downloads.
- New offline tests: the edge from full Sha-Chi to 10% and its pulse, the guard break, fading when Sha-Chi comes back
  or the fight ends, three reloads mid-fight (no extra loops, no hook registered twice, the log kept), and the whole
  update path (check, download page, install and takeover, the 30 s watch, rollback by hand and by itself, a broken
  zip, a version that fails to start, a zip that is not newer, no zip, no network, files replaced by hand). Both
  scenarios pass. The two real jobs (the Nexus check, the unpacking) were also run on Windows, in a folder whose path
  has spaces and Chinese characters.

## Changes in v0.7.2

Fixes a crash on hits and parries (a UE4SS `Fatal Error` window, and a `crash_*.dmp` in the `ue4ss` folder). Every
version released on Nexus has it.

- A player's crash dump shows the game crashing inside `SpawnEmitterAtLocation`, the spawner for old-style (Cascade)
  particle systems: the engine read the template it was given as a particle system and hit an invalid address. The
  mod calls it in one place only, and until now every effect asset whose class did not read as Niagara went there
  unchecked. The dump holds only the thread stacks, so which asset it was, and why its class did not read as
  Niagara, cannot be seen; all three places below are changed, and the log says so if it happens again.
- Before an effect is spawned, what it is gets checked: Niagara systems play as before, particle systems (the game's
  own hit effects may be one) go to `SpawnEmitterAtLocation`, the blade takes Niagara only, and anything else is not
  spawned. `hitfeel.log` then writes `vfx: not spawning …` with the class it read (the first 5 times).
- A kept effect asset is checked again before each use: after the engine frees an asset, another object can get its
  memory address, and the asset is then found again.
- A class's chain of parent classes that was not read whole (empty, a name that could not be read, an error halfway)
  is no longer kept; it is read again next time. Before, one bad read stood for that class for the whole session.
- New offline tests: a class that cannot be read the first time, a kept effect whose address another object took, a
  particle system, and a blade effect that is not Niagara. The test's `SpawnEmitterAtLocation` counts anything but a
  particle system as a crash; the v0.7.1 scripts crash there 4 times.

## Changes in v0.7.1

Fixes found while looking into player reports ("two factions fight somewhere I cannot see and my screen shakes",
"after a while the frame rate drops"). v0.6.5 has the first two problems too.

- Only fights you are in get feedback. NPCs parry each other too (rival sects, thieves and dolls), and every one of
  those parries used to be taken for yours, wherever on the map it happened: your camera and controller shook, sparks
  went off beside you, the screen edges pulsed and a clang played; their slow-down got a hold added; and their perfect
  parry could turn your next normal parry into a perfect one. They are now left alone, and the first one writes
  `a clash without you` to `hitfeel.log`. NPCs' blows on each other also counted in your hit rhythm and density fade,
  which made your own hits lighter in a crowded fight; a blow now counts only once the game names you as its attacker
  (a ".Player" attack tag, or the attacker's slomo call).
- Feedback no longer goes quiet after loading a save or changing maps. The game's world clock starts again at 0 in
  every new world, so the times the mod had kept lay in the future. For as long as the previous world had lasted, the
  camera's and the screen's impact gaps and the hit trails' spacing never ran out, an enemy that got an old enemy's
  memory address had its hits taken for repeats (no feedback at all), and every hit kept the rhythm's last mark from
  before the load. The play log showed two such resets in one evening. The mod now keeps its own continuous time.
- What the mod keeps per enemy (the duplicate check, bone lists, kill state, hold allowance, the flash's materials)
  is pruned every few seconds and no longer grows with the length of a session. In the offline test, 150 different
  enemies struck once each leave nothing behind a minute later.
- The `perf` line adds the mod's Lua memory and how many NPC blows and clashes it left alone.

## Changes in v0.7.0

A pass along the usual hit-feel principles: feedback should tell the truth, have contrast, and not pile up.

- Perfect parries now come from the game's own judgment: its perfect-deflect effect choosers
  (`BP_DeflectEffectPlayer_Chooser_Perfect` and `…_PerfectFinal`) and its deflect frame's result. The v0.6 guess (the
  clash slow-down below 0.4, or a level-3 deflect shake) actually followed the strength of the attack you stopped:
  heavy attacks and every parry against a boss counted as perfect, and each one held both sides for long. The first
  lines of `logs/hitfeel.log` say when the game's signal arrives (`deflect frame result …`, `deflect: perfect, by …`).
  If they never appear on perfect parries, every parry gets the normal set; `Deflect.Classify = "mult"` brings the
  old guess back.
  - A normal guard weighs the attack it stopped (light 0.8, middle 1, heavy 1.3), so a heavy block still lands hard.
  - Later perfect parries in a quick string hold for half as long (no stutter through a boss flurry); the game's
    final perfect parry of a string holds 1.3 times as long.
  - The panel's "Perfect parry check" offers Game's call (default), By slow-mo (the old guess), All perfect, All normal.
- The enemy-only hold now has two guards, so it bends an enemy's timing less (fighting games freeze both sides for
  this reason). The game's slomo makes the held time up afterwards, running the enemy faster than normal (up to about
  1.36x in the logs), so the longer the hold, the longer an attack starting then comes out faster than you have
  learned:
  - At most 12 extra frames per enemy in any one second (accents keep theirs, but use up the allowance).
  - An enemy whose super armor your hit does not break (it is mid-attack) keeps vanilla's slow-down, so its swing
    lands when you expect it.
- Quick heavy strings: only the first heavy hit is an accent; the next ones step down until a pause.
- Density fade: the denser the hits, the lighter each one lands, up to 30% (accents feel half of it). "Density fade"
  on the Action tab; 0 = off.
- Kill accent: the killing blow gets a camera shake and punch, a screen pulse and rumble of its own, and holds the
  enemy 16 frames longer when the damage is in before the enemy's slomo starts. The game hands the hit no HP, so the
  mod reads the enemy's health from its ability system's attribute sets (`BasicAttributeSet.Health` in build
  26367565); the first checks log the attributes and the health they read (`kill: … attributes`, `kill check …`). In
  testing, two of the first three kills were held longer; on the third the health was still 197 when the slomo began.
- Performance (after a player reported frame drops in fights):
  - The mod's effects are kept out of the engine's effect budget so that every hit gets one (since v0.6.3), which also
    left them without a limit: a dense string could pile them up. The mod now keeps its own budget: at most 12 play at
    once, one more ends the oldest (one already fading first), and none lasts past 6 s (`Vfx.MaxAlive`,
    `Vfx.KillAfterMs`).
  - Less work per frame and per hit: the player controller and pawn are checked once a frame (the clock, the hotkeys,
    the blade-tip samples and every hook each looked them up before); the hit flash remembers each enemy's materials
    instead of walking all its parts and material slots on every hit (a few hundred engine calls on a ten-material
    enemy); the weapon's own trail is looked for only when something uses it. In the offline test, engine calls fell
    from 41 to 23 an idle frame and from about 600 to about 400 a middle hit.
  - New `perf` lines in `logs/hitfeel.log` (see "If the frame rate drops").
- What was going to be v0.6.6 (never released on its own):
- Added: a switch and a volume for the parry sound ("Parry sound" and "Parry sound volume" on the panel's Sound tab;
  `Deflect.SoundEnabled` and `Deflect.SoundVolume` in `config.lua`). On every parry, blocked attack and hit on a
  shield, the mod plays one more of the game's clash sounds on top of the game's own, and some players found that
  louder than vanilla. That layer can now be switched off or turned down; the game's own clash sound is unchanged.
  Turned down, the layer plays on its own Wwise sound component, set to that volume.
- Perfect parries play half the sparks by default (`Deflect.SparkAmount.Perfect` 1 -> 0.5): one perfect-clash burst,
  without the finishing burst on top. "Perfect parry sparks" on the Advanced tab brings it back (1).
- The screen impact no longer pulses on every hit of a quick string: two are at least 1.2 s apart
  (`Screen.MinGapMs`), and within that only one at least 1.25 times as strong darkens the edges again; a weaker one
  no longer stretches the darkening in progress. In a quick string of heavy blows (the chain, for instance) the edges
  used to darken again on every accent and stay dark. "Screen impact gap" on the Camera tab; 0 = no gap.

## Changes in v0.6.5

- Fixed: opening and closing the tuning panel on the title screen, or in another game menu that shows its own cursor
  without pausing, switched input to the game alone and hid the cursor, so that menu took no more clicks. While a
  game menu has the cursor (paused, or its cursor already on), the panel now leaves input and the cursor alone.

## Changes in v0.6.4

- Works with the November 4 update (Steam build 26367565) and still with build 26266538. A full fight on the new
  build ran every feature with no errors, and every engine and game name the mod uses is still in the new PBZ.exe.
- `logs/hitfeel.log` names the game build at startup and says when it is one this version was not tested on.

## Changes in v0.6.3

- Fixed: the default hit effect filled the screen with purple flames. With no effect picked, v0.6.2 used the first
  candidate, a QTE effect. The default is now the ink blade (the 8th) at the author's own size and angle. An effect
  you already picked or tuned is kept.
- Fixed: the hit effect sometimes did not show. The engine let the ink blade (a skill effect) play only once at a
  time, so in a quick string only the first hit showed it; the mod now keeps its effects out of the engine's culling
  (`Vfx.NeverCull`). A 30 ms gap shared by all hits also dropped a stronger hit that came right after a light one; it
  now only spaces the hit trails on one blade.

## License and credits

- PBZHitFeel (code and panel art) is released under the MIT License, copyright (c) 2026 MoonlightSakura; see
  `LICENSE`. You may modify it, redistribute it or use it in your own mods; keep the copyright notice and `LICENSE`.
- The hook on the game's hit-effect lookup, the hit tag names and the way the slomo frames are rewritten follow
  pbz_hit_enhance (MIT); the code is this mod's own.
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT) by the UE4SS team, not included; the PBZ build by KintaroModding.
- No game assets are included: every effect, sound and shake is the game's own, used at runtime.
