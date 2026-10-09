#!/usr/bin/env python3
"""Convert frankea/Whisky's game compatibility database into compat/games.json.

Source: WhiskyKit/Sources/WhiskyKit/GameDatabase/Resources/GameDB.json in
https://github.com/frankea/Whisky, GPL-3.0-or-later, (c) the Whisky contributors.
This project is GPL-3.0-or-later as well; see CREDITS.md.

What maps over: how to recognise a game (Steam app id, executable names), its rating and
anti-cheat, the graphics backend, environment variables, DLL overrides and winetricks verbs of
each variant, notes and known issues. Whisky-only switches (esync/msync choice, shader cache,
AVX toggle, Sequoia compatibility mode) are dropped: this engine always runs msync and always
advertises AVX.

usage: import-whisky-gamedb.py <GameDB.json> <whisky commit>   (writes JSON to stdout)
"""
import json
import sys

BACKENDS = {"d3dMetal": "automatic", "recommended": "automatic", "dxvk": "dxvk", "wined3d": "wine"}


def variant(v):
    settings = v.get("settings") or {}
    backend = BACKENDS.get(settings.get("graphicsBackend"), "automatic")
    env = dict(v.get("environmentVariables") or {})
    if settings.get("dxvkAsync") and backend == "dxvk":
        env.setdefault("DXVK_ASYNC", "1")
    return {
        "label": v.get("label") or v.get("id"),
        "whenToUse": v.get("whenToUse"),
        "graphics": backend,
        "environment": env,
        "dllOverrides": {o["dllName"]: o["mode"] for o in (v.get("dllOverrides") or [])},
        "winetricks": list(v.get("winetricksVerbs") or []),
    }


def convert(entry):
    variants = entry.get("variants") or []
    default = next((v for v in variants if v.get("isDefault")), variants[0] if variants else {})
    return {
        "id": entry["id"],
        "title": entry["title"],
        "aliases": entry.get("aliases") or [],
        "store": entry.get("store"),
        "steamAppID": entry.get("steamAppId"),
        "exeNames": entry.get("exeNames") or [],
        "rating": entry.get("rating", "unverified"),
        "antiCheat": entry.get("antiCheat"),
        "notes": entry.get("notes") or [],
        "issues": [
            {"severity": i.get("severity"), "text": i.get("description"), "workaround": i.get("workaround")}
            for i in entry.get("knownIssues") or []
        ],
        "recommended": variant(default),
        "alternatives": [variant(v) for v in variants if v is not default],
    }


def main():
    source, commit = sys.argv[1], sys.argv[2]
    with open(source, encoding="utf-8") as f:
        data = json.load(f)
    games = sorted((convert(e) for e in data["entries"]), key=lambda g: g["title"].lower())
    json.dump({
        "source": f"frankea/Whisky {commit}, WhiskyKit/Sources/WhiskyKit/GameDatabase/Resources/GameDB.json "
                  f"(version {data.get('version')}), GPL-3.0-or-later",
        "games": games,
    }, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
