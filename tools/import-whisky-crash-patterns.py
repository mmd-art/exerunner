#!/usr/bin/env python3
"""Converts frankea/Whisky's crash signatures (WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/
patterns.json, GPL-3.0-or-later) into compat/crash-patterns.json.

Changes on the way:
- remediation ids become this app's remedies (see REMEDIES);
- the DirectX and .NET library patterns capture the DLL name, so the app can name the component
  that provides it;
- gpu-device-lost-dxvk loses its prefilter, which hid two of its three alternatives;
- one pattern of our own: wine's "failed to start" message.

usage: tools/import-whisky-crash-patterns.py <whisky checkout> [output]
"""
import json
import sys
from pathlib import Path

REMEDIES = {
    "install-vcredist": ["install-missing-dll"],
    "install-dotnet": ["install-missing-dll"],
    "install-dx-redist": ["install-missing-dll"],
    "switch-backend": ["switch-graphics"],
    "disable-dxr": ["raytracing-off"],
    "reinstall-prefix": ["info:prefix"],
    "network-info": ["info:network"],
    "anticheat-info": ["info:anticheat"],
    "steam-download-fix": ["info:steam-download"],
}

CAPTURE = {
    "dll-load-d3dcompiler": r"err:.*(d3dcompiler_\d+\.dll).*(?:not found|could not be loaded)",
    "dll-load-d3dx9": r"err:.*(d3dx9_\d+\.dll).*(?:not found|could not be loaded)",
    "dll-load-xinput": r"err:.*(xinput\d+_\d+\.dll).*(?:not found|could not be loaded)",
    "dll-load-xaudio2": r"err:.*(xaudio2_\d+\.dll).*(?:not found|could not be loaded)",
    "dotnet-clr-missing": r"err:.*(mscoree\.dll|mscorlib\.dll|fusion\.dll).*(?:not found|could not be loaded)",
}

OWN = [{
    "id": "wine-failed-to-start",
    "category": "prefixFilesystem",
    "severity": "error",
    "confidence": 0.8,
    "prefilter": "failed to start",
    "regex": r"wine: failed to start (.+): ([0-9a-f]+)",
    "remedies": ["info:path"],
}]


def main():
    whisky = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "compat/crash-patterns.json"
    source = json.loads((whisky / "WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/patterns.json").read_text())
    patterns = []
    for p in source["patterns"]:
        remedies = []
        for action in p.get("remediationActionIds") or []:
            for remedy in REMEDIES[action]:
                if remedy not in remedies:
                    remedies.append(remedy)
        if p["category"] == "coreCrashFatal":
            remedies.append("logging-crash")
        prefilter = p.get("substringPrefilter")
        if p["id"] == "gpu-device-lost-dxvk":
            prefilter = None
        patterns.append({
            "id": p["id"],
            "category": p["category"],
            "severity": p["severity"],
            "confidence": p["confidence"],
            "prefilter": prefilter,
            "regex": CAPTURE.get(p["id"], p["regex"]),
            "remedies": remedies,
        })
    patterns += OWN
    doc = {
        "source": "frankea/Whisky WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/patterns.json "
                  "(GPL-3.0-or-later), converted by tools/import-whisky-crash-patterns.py",
        "patterns": patterns,
    }
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(patterns)} patterns -> {out}")


if __name__ == "__main__":
    main()
