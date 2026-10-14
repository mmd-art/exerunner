#!/usr/bin/env python3
"""Keep this developer checkout and generated apps out of macOS search."""
import argparse
import ctypes
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
UTF8 = 0x08000100


def metadata_api():
    cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    md = ctypes.CDLL("/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Metadata")
    cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
    cf.CFStringCreateWithCString.restype = ctypes.c_void_p
    cf.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long, ctypes.c_uint32]
    cf.CFStringGetCString.restype = ctypes.c_bool
    cf.CFArrayGetCount.argtypes = [ctypes.c_void_p]
    cf.CFArrayGetCount.restype = ctypes.c_long
    cf.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
    cf.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None
    md._MDCopyExclusionList.argtypes = []
    md._MDCopyExclusionList.restype = ctypes.c_void_p
    # The installed Spotlight settings extension calls this with a CFString path,
    # a 0/1 exclusion flag, and checks the returned 32-bit error code.
    md._MDSetExclusion.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    md._MDSetExclusion.restype = ctypes.c_int32
    return cf, md


def exclusion_paths(cf, md):
    items = md._MDCopyExclusionList()
    if not items:
        raise RuntimeError("Cannot read Spotlight Search Privacy; allow access to macOS metadata services.")
    paths = []
    try:
        for index in range(cf.CFArrayGetCount(items)):
            item = cf.CFArrayGetValueAtIndex(items, index)
            buffer = ctypes.create_string_buffer(32768)
            if not cf.CFStringGetCString(item, buffer, len(buffer), UTF8):
                raise RuntimeError("Cannot decode a Spotlight exclusion path.")
            paths.append(buffer.value.decode("utf-8"))
    finally:
        cf.CFRelease(items)
    return paths


def exclude_project():
    cf, md = metadata_api()
    project = str(ROOT)
    paths = exclusion_paths(cf, md)
    if project in paths:
        return {"project": project, "excluded": True, "changed": False}
    value = cf.CFStringCreateWithCString(None, project.encode("utf-8"), UTF8)
    if not value:
        raise RuntimeError("Cannot encode the project path.")
    try:
        status = md._MDSetExclusion(value, 1)
    finally:
        cf.CFRelease(value)
    if status != 0:
        raise RuntimeError(f"Cannot exclude this checkout from Spotlight (error {status}).")
    if project not in exclusion_paths(cf, md):
        raise RuntimeError("Spotlight did not retain this checkout's exclusion.")
    return {"project": project, "excluded": True, "changed": True}


def unregister_build(path):
    app = Path(path).resolve()
    try:
        app.relative_to(ROOT / "build")
    except ValueError:
        raise RuntimeError("Only generated apps under this checkout's build directory may be unregistered.")
    if app.name != "ExeRunner.app":
        raise RuntimeError("Expected a generated ExeRunner.app bundle.")
    attempt = subprocess.run([LSREGISTER, "-u", str(app)], text=True, capture_output=True)
    # LaunchServices may report fnfErr for an already-unregistered new build.
    # Accept only that case, and only after the catalogue check below proves absence.
    if attempt.returncode and "-10814" not in attempt.stdout + attempt.stderr:
        raise RuntimeError(f"Cannot unregister generated app: {attempt.stdout}{attempt.stderr}")
    dump = subprocess.run([LSREGISTER, "-dump"], check=True, text=True, capture_output=True)
    if "bundle id:" not in dump.stdout:
        raise RuntimeError("Cannot verify LaunchServices; allow access to macOS application services.")
    registered = re.findall(r"^path:\s+(.*?)\s+\(0x[0-9a-f]+\)\s*$", dump.stdout, re.MULTILINE)
    if str(app) in registered:
        raise RuntimeError(f"The generated app is still registered: {app}")
    return {"app": str(app), "registered": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("exclude-project")
    unregister = commands.add_parser("unregister-build")
    unregister.add_argument("app")
    args = parser.parse_args()
    if sys.platform != "darwin":
        raise RuntimeError("This helper requires macOS.")
    result = exclude_project() if args.command == "exclude-project" else unregister_build(args.app)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Search privacy: {error}", file=sys.stderr)
        sys.exit(1)
