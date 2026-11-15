"""Raises the version of the mod by one step: the second number (1.0 -> 1.1, 1.9 -> 1.10).

The version is in mod.json ("version": "<major>.<minor>"). Some mods also write it into their log line, so the script
also changes that line when its file exists. Hit Feel (this project's copy of the template script): the line
`B.HITFEEL_VERSION = "<major>.<minor>"` in src/<folder>/Scripts/hf_boot.lua; its main.lua is PBZHitFeel's kernel and has
no version line. The rest of each file keeps its layout and its line ends (the mod's files are CRLF).

Usage:
    python scripts/bump_version.py           # 1.0 -> 1.1
    python scripts/bump_version.py --major   # 1.4 -> 2.0, only when the user says so
    python scripts/bump_version.py --show    # print the version
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_JSON = ROOT / "mod.json"
VERSION = re.compile(r"^(\d+)\.(\d+)$")
JSON_VERSION = re.compile(r'("version"\s*:\s*")([^"]*)(")')
# (file below src/<folder>, its version line, how the error names the line)
SCRIPTS = [
    (Path("Scripts") / "hf_boot.lua", re.compile(r'^(B\.HITFEEL_VERSION = ")([^"]*)(")', re.MULTILINE),
     'B.HITFEEL_VERSION = "<major>.<minor>"'),
]


def main() -> None:
    text = MOD_JSON.read_text(encoding="utf-8")
    mod = json.loads(text)
    current = mod["version"]
    match = VERSION.match(current)
    if not match:
        sys.exit(f'mod.json: version "{current}" is not <major>.<minor>')
    found = []
    for relative, pattern, shown in SCRIPTS:
        path = ROOT / "src" / mod["folder"] / relative
        if not path.is_file():
            continue
        with open(path, encoding="utf-8", newline="") as f:  # newline="": the CRLF line ends stay as they are
            script = f.read()
        script_match = pattern.search(script)
        if script_match is None:
            sys.exit(f"{path}: no line '{shown}'")
        if script_match.group(2) != current:
            sys.exit(f"Versions differ: mod.json {current}, {relative.name} {script_match.group(2)}. Make them equal first.")
        found.append((path, pattern, script))

    if "--show" in sys.argv:
        print(current)
        return

    major, minor = int(match.group(1)), int(match.group(2))
    new = f"{major + 1}.0" if "--major" in sys.argv else f"{major}.{minor + 1}"
    MOD_JSON.write_text(JSON_VERSION.sub(lambda m: m.group(1) + new + m.group(3), text, count=1),
                        encoding="utf-8", newline="\n")
    for path, pattern, script in found:
        with open(path, "w", encoding="utf-8", newline="") as f:  # writes the line ends that were read
            f.write(pattern.sub(lambda m: m.group(1) + new + m.group(3), script, count=1))
    print(f"Version {current} -> {new}")


if __name__ == "__main__":
    main()
