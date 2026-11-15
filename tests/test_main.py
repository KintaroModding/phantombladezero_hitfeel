"""Offline test of the Hit Feel scripts with lupa (Lua 5.4).

The mod is PBZHitFeel 0.7.3 by MoonlightSakura: 25 scripts that need UE4SS and the running game for almost
everything they do. This test checks what runs without the game:

- every .lua file under src compiles;
- the shipped config.lua returns a table with the master switch;
- hf_config.lua merges config.lua and a player's tuning.lua the way the mod does at its start (C.load), also with
  a tuning.lua that names settings the mod does not have;
- every row of the tuning panel (the rows table in hf_hud.lua) has its text in English, Japanese and Korean
  (hf_lang.lua: a text a table lacks falls back to the Chinese and is noted in Lang.missing);
- Hit Feel's fix: no script turns physics on for a skeleton's bones (PBZHitFeel's jiggle), its settings are gone from
  the defaults and the panel, and a player's old tuning.lua that switched it on brings nothing back;
- the version in hf_boot.lua's log lines equals mod.json's.

Usage:
    python -I tests/test_main.py        (needs lupa: python -m pip install lupa)

Exit code: 0 = all checks passed, 1 = a check failed.
"""

import re
import shutil
import sys
import tempfile
from pathlib import Path

from lupa import lua54

sys.stdout.reconfigure(errors="backslashreplace")
ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "src" / "phantombladezero_hitfeel"
SCRIPTS = MOD / "Scripts"

FAILED = []


def check(ok, text):
    print(("ok    " if ok else "FAIL  ") + text)
    if not ok:
        FAILED.append(text)


def runtime():
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = ... .. '/?.lua;' .. package.path", str(SCRIPTS).replace("\\", "/"))
    return lua


def compiles():
    files = sorted(MOD.rglob("*.lua"))
    check(len(files) >= 25, f"{len(files)} Lua files found")
    lua = runtime()
    compile_text = lua.eval("function(text, name) local f, err = load(text, '=' .. name, 't'); return f ~= nil, err end")
    for path in files:
        ok, err = compile_text(path.read_text(encoding="utf-8"), path.name)
        check(ok, f"{path.relative_to(MOD)} compiles" + ("" if ok else f": {err}"))


def shipped_config():
    lua = runtime()
    cfg = lua.eval("function(path) return dofile(path) end")(str(MOD / "config.lua"))
    check(lua.eval("function(t) return type(t) == 'table' end")(cfg), "config.lua returns a table")
    check(cfg is not None and cfg["Enabled"] is True, "config.lua: Enabled = true")


# U as hf_config.lua uses it: the mod folder and the log.
U_STUB = """
return function(root)
  local U = { root = root, lines = {} }
  function U.log(fmt, ...) U.lines[#U.lines + 1] = string.format(fmt, ...) end
  return U
end
"""


def config_load():
    lua = runtime()
    make_u = lua.execute(U_STUB)
    C = lua.eval("function() return (require('hf_config')) end")()
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(MOD / "config.lua", Path(tmp) / "config.lua")
        root = tmp.replace("\\", "/")
        u = make_u(root)
        cfg = C.load(u)
        check(lua.eval("function(t) return type(t) == 'table' end")(cfg), "C.load without tuning.lua gives a table")
        check(cfg["Enabled"] is True and cfg["Freeze"]["Enabled"] is True, "C.load: config.lua's values are in it")
        # A tuning.lua as the panel writes it, with one known value, a path the mod does not have and a session-only
        # value.
        (Path(tmp) / "tuning.lua").write_text(
            '-- test\nreturn {\n  ["Tuning.Freeze"] = 0.5,\n  ["Nothing.Here.At.All"] = true,\n  ["Enabled"] = false,\n}\n',
            encoding="utf-8")
        u = make_u(root)
        cfg = C.load(u)
        check(abs(cfg["Tuning"]["Freeze"] - 0.5) < 1e-9, "C.load: a tuning.lua value is applied over config.lua")
        check(cfg["Nothing"] is None, "C.load: a tuning.lua path the mod does not have is left out")
        check(cfg["Enabled"] is True, "C.load: the session-only master switch from tuning.lua is ignored")
        lines = list(u.lines.values())
        check(any("1 value(s) from tuning.lua applied" in line for line in lines),
              "C.load logs how many tuning.lua values it applied")


def panel_texts():
    hud = (SCRIPTS / "hf_hud.lua").read_text(encoding="utf-8")
    # A panel row: { "label", "description", "Path.To.Key", "kind" ... }
    rows = re.findall(r'\{\s*"([^"]+)",\s*"([^"]+)",\s*"([A-Za-z]+(?:\.[A-Za-z]+)+)",\s*"(bool|num|choice|enum|key)"', hud)
    check(len(rows) >= 40, f"{len(rows)} panel rows found in hf_hud.lua")
    lua = runtime()
    lang = lua.eval("function() return (require('hf_lang')) end")()
    for code in ("en", "ja", "ko"):
        lang.code = code
        for label, description, _, _ in rows:
            lang.t(label)
            lang.t(description)
    missing = sorted(lang.missing.keys())
    check(not missing, "every panel row has its text in en, ja and ko" + (f": missing {missing[:6]}" if missing else ""))


PHYSICS_CALLS = ("SetAllBodiesBelowSimulatePhysics", "SetAllBodiesBelowPhysicsBlendWeight", "AddImpulseToAllBodiesBelow",
                 "SetAllBodiesSimulatePhysics", "SetSimulatePhysics", "AddImpulseAtLocation", "SetAllBodiesPhysicsBlendWeight")


def no_jiggle():
    for path in sorted(SCRIPTS.glob("*.lua")):
        # The code only: a comment may name a function (hf_react.lua explains the game's own SetSimulatePhysics).
        code = "\n".join(line.split("--", 1)[0] for line in path.read_text(encoding="utf-8").splitlines())
        found = [name for name in PHYSICS_CALLS if name in code]
        check(not found, f"{path.name} calls no physics function" + (f": {found}" if found else ""))
    react = (SCRIPTS / "hf_react.lua").read_text(encoding="utf-8")
    check("Jiggle" not in react.split("-- Hit Feel (Kintaro", 1)[0] and "c.Jiggle" not in react
          and "JiggleImpulse" not in react, "hf_react.lua reads no Jiggle setting")
    hud = (SCRIPTS / "hf_hud.lua").read_text(encoding="utf-8")
    check("Jiggle" not in hud, "hf_hud.lua: no Jiggle row, switch, scale or preset value")
    for name in ("config.lua",):
        text = (MOD / name).read_text(encoding="utf-8")
        code = "\n".join(line.split("--", 1)[0] for line in text.splitlines())
        check("Jiggle" not in code, f"{name}: no Jiggle setting (outside comments)")
    lua = runtime()
    C = lua.eval("function() return (require('hf_config')) end")()
    d = C.DEFAULTS
    check(d["React"]["Jiggle"] is None, "hf_config.lua: no React.Jiggle default")
    check(d["Deflect"]["JiggleImpulse"] is None, "hf_config.lua: no Deflect.JiggleImpulse default")
    check(d["Tuning"]["Jiggle"] is None, "hf_config.lua: no Tuning.Jiggle default")
    make_u = lua.execute(U_STUB)
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(MOD / "config.lua", Path(tmp) / "config.lua")
        # The tuning.lua of a player who switched the jiggle on in PBZHitFeel's panel.
        (Path(tmp) / "tuning.lua").write_text(
            '-- PBZHitFeel\nreturn {\n  ["React.Jiggle.Enabled"] = true,\n  ["Tuning.Jiggle"] = 2,\n}\n', encoding="utf-8")
        cfg = C.load(make_u(tmp.replace("\\", "/")))
        check(cfg["React"]["Jiggle"] is None, "an old tuning.lua with React.Jiggle.Enabled = true brings no Jiggle table back")
        check(cfg["React"]["Displace"]["Enabled"] is True and cfg["React"]["Shake"]["Enabled"] is True,
              "the push and the hit shake keep their settings")


def versions():
    boot = (SCRIPTS / "hf_boot.lua").read_text(encoding="utf-8")
    ours = re.search(r'^B\.HITFEEL_VERSION = "([^"]*)"', boot, re.MULTILINE)
    base = re.search(r'VERSION = "([^"]*)", KERNEL', boot)
    mod = re.search(r'"version"\s*:\s*"([^"]*)"', (ROOT / "mod.json").read_text(encoding="utf-8"))
    check(ours is not None and mod is not None and ours.group(1) == mod.group(1),
          f"hf_boot.lua HITFEEL_VERSION {ours and ours.group(1)} = mod.json {mod and mod.group(1)}")
    check(base is not None and base.group(1) == "0.7.3", "hf_boot.lua VERSION stays PBZHitFeel's 0.7.3")
    check(re.search(r'U\.log\("Hit Feel %s \(PBZHitFeel %s[^"]*\) loading[^"]*",\s*B\.HITFEEL_VERSION,\s*B\.VERSION,', boot)
          is not None, "the loading line names Hit Feel's version and PBZHitFeel's")
    check(re.search(r'U\.log\("Hit Feel %s \(PBZHitFeel %s\) ready:[^"]*",\s*B\.HITFEEL_VERSION, B\.VERSION,', boot)
          is not None, "the ready line names Hit Feel's version and PBZHitFeel's")


OUTSIDE_CALLS = ("os.execute", "io.popen", "LaunchURL", "curl", "tar.exe", "nexusmods", "http")


def no_updater():
    check(not (SCRIPTS / "hf_update.lua").exists(), "hf_update.lua (PBZHitFeel's in-game updater) is gone")
    check(not (MOD / "update").exists(), "the update folder is gone")
    for path in sorted(SCRIPTS.glob("*.lua")):
        code = "\n".join(line.split("--", 1)[0] for line in path.read_text(encoding="utf-8").splitlines())
        found = [name for name in OUTSIDE_CALLS if name in code]
        check(not found, f"{path.name} starts no program and opens no web page" + (f": {found}" if found else ""))
    boot = (SCRIPTS / "hf_boot.lua").read_text(encoding="utf-8")
    check('"hf_update"' not in boot and "S.update" not in boot, "hf_boot.lua loads and starts no updater")
    hud = (SCRIPTS / "hf_hud.lua").read_text(encoding="utf-8")
    check('"action", run =' not in hud and "Update.AutoCheck" not in hud, "the panel has no Updates rows")
    lua = runtime()
    C = lua.eval("function() return (require('hf_config')) end")()
    check(C.DEFAULTS["Update"] is None, "hf_config.lua: no Update settings")
    cfg = lua.eval("function(path) return dofile(path) end")(str(MOD / "config.lua"))
    check(cfg["Update"] is None, "config.lua: no Update settings")


CJK = re.compile(r"[　-鿿가-힯＀-￯]")


def english_only():
    """Comments and documents are English (the user, 2026-11-15). The panel's Chinese texts in code stay: Chinese is
    one of the panel's languages and the key of hf_lang.lua's tables."""
    for path in sorted(MOD.rglob("*.lua")):
        bad = [i for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
               if "--" in line and CJK.search(line.split("--", 1)[1])]
        check(not bad, f"{path.relative_to(MOD)}: comments in English" + (f" (Chinese on lines {bad[:8]})" if bad else ""))
    for name in ("README.md", "logs/README.txt", "LICENSE"):
        bad = [i for i, line in enumerate((MOD / name).read_text(encoding="utf-8").splitlines(), 1) if CJK.search(line)]
        check(not bad, f"{name} is English" + (f" (Chinese on lines {bad[:8]})" if bad else ""))
    check(not (MOD / "README_EN.md").exists(), "one README.md (the English manual), no README_EN.md")


def main():
    compiles()
    shipped_config()
    config_load()
    panel_texts()
    no_jiggle()
    no_updater()
    english_only()
    versions()
    print()
    if FAILED:
        print(f"{len(FAILED)} check(s) failed")
        sys.exit(1)
    print("All checks passed")


if __name__ == "__main__":
    main()
