# PBZHitFeel - Hit Feel Overhaul

Adds weight to every hit: enemy-only hit stop, rim flash, camera shakes, slash effects, rumble and sound. Based on PBZHitFeel by MoonlightSakura (MIT).

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod for Phantom Blade Zero (Unreal Engine 5.7), tested with game
version `CL-302256_JKS-17280` (Steam build 26367565) and UE4SS `v4.0.0`. This README is for developers; what the mod
does and how to install it are in [openmods.md](openmods.md), the mod page on [openmods](https://openmods.nexus).

PBZHitFeel is made by MoonlightSakura
([Nexus Mods profile](https://www.nexusmods.com/profile/MoonlightSakura?gameId=10614),
[original mod page](https://www.nexusmods.com/phantombladezero/mods/473),
[bilibili](https://space.bilibili.com/en/666977)). This project took over its version 0.7.3 so that the mod manager
(UE MM) can include it. The first commit holds the original files unchanged, so `git diff` against it shows every
change of this build.

## How it works

`Scripts\main.lua` is the kernel: it loads `hf_boot.lua`, which loads every other script, and on a reload (Ctrl+F8)
it loads a fresh copy of all scripts but itself and swaps it in while the game runs. The hit bus (`hf_hit.lua`) hooks:

- `BP_HitEffectPlayer_Chooser_C:GetEffectData` and the three `BP_DeflectEffectPlayer_Chooser_*` (post hooks): every hit
  and deflect lookup with its tags and the game's effect assets; the outputs (camera shake, slow-motion data) can be
  changed there;
- `RuntimeSlomoDataHelper:StartSlomoData` (native, pre hook): the hit stop, rewritten so that only the struck enemy
  stops;
- `BP_DeflectHitreactAttackSource_C:GetHitStrength` and `GAA_DeflectFrame_C:Process Deflect Frame` for deflects.

The feature modules (`hf_freeze`, `hf_react`, `hf_flash`, `hf_camera`, `hf_screen`, `hf_vfx`, `hf_rumble`,
`hf_audio`, `hf_receive`, `hf_kill`, `hf_guard`, `hf_knockback`, `hf_rhythm`, ...) act on each hit. `hf_hud.lua` is the
Ctrl+F5 panel (UMG widgets with the art in `ui\`), `hf_lang.lua` its texts (Chinese is the key, English, Japanese and
Korean the translations), `hf_config.lua` the defaults under `config.lua`.

Changes against PBZHitFeel 0.7.3 (each one a commit):

- 1.0: the physics jiggle removed (`hf_react.lua`: `SetAllBodiesBelowSimulatePhysics` and the blend and impulse calls
  on the bones near the hit); its settings, panel rows and texts removed. A player's crash in the game's animation
  code under a montage ability task points to it.
- 1.1: the in-game updater removed (`hf_update.lua`: a Nexus check with `curl.exe`, an install with `tar.exe` over the
  mod folder); its panel section and settings removed.
- 1.2: the comments and the manual in English.
- `hf_boot.lua` `B.HITFEEL_VERSION` names this build in the log; `VERSION` stays PBZHitFeel's 0.7.3.

## Deploy and test

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1     # copy the mod folder into the game's ue4ss\Mods
python tests\test_main.py                                 # offline test (needs lupa)
```

`deploy.ps1` copies `src\phantombladezero_hitfeel\` to `<game folder>\platform\steam\ue4ss\Mods\phantombladezero_hitfeel\`.
The game folder is `$env:UE5_GAMES_DIR\PBZ`; `-GameDir` or `-ModsDir` override it. The mod writes its own files into
its folder (`tuning.lua`, `tuning_custom.lua`, `slash_choice.txt`, `slash_tuning.lua`, `logs\`), so the script
mirrors only `Scripts\` and `ui\` and copies the rest without removing anything. An existing `config.lua` in the game
stays (the tester's settings); `-ResetConfig` copies the shipped one. The mod writes its lines into
`ue4ss\UE4SS.log` with the tag `[PBZHitFeel]`, and its own log into `logs\hitfeel.log` and `logs\recent.txt`.

`tests\test_main.py` runs with Lua 5.4 ([lupa](https://pypi.org/project/lupa/)): every script compiles, `config.lua`
and a player's `tuning.lua` load as the mod loads them, every panel row has its English, Japanese and Korean text,
nothing of the jiggle or the updater is left, no script starts a program or opens a web page, comments and documents
are English, and the versions match.

Versioning: every change raises the second number (1.0 -> 1.1) in `mod.json` and in `B.HITFEEL_VERSION`:
`python scripts\bump_version.py`.

## Line ends

The mod's files keep their bytes as PBZHitFeel has them: its Lua files are LF, its `README.md`, `logs\README.txt` and
`hf_lang.lua` CRLF. `.gitattributes` turns line-end conversion off for `src\`.

## Project layout

```
src/phantombladezero_hitfeel/   The UE4SS mod folder: Scripts/ (main.lua and the hf_*.lua modules), config.lua,
                                ui/ (panel art), logs/, README.md, LICENSE (MoonlightSakura's), enabled.txt
tests/test_main.py              Offline test with lupa
docs/                           Cover and screenshots
scripts/                        bump_version.py, check_openmods.py, publish.ps1
deploy.ps1                      Copies the mod folder into the game's ue4ss\Mods
mod.json                        Name, version, game, engine and UE4SS version
```

## License

MIT, see [LICENSE](LICENSE): MoonlightSakura for PBZHitFeel (code and panel art), Kintaro for the changes.
