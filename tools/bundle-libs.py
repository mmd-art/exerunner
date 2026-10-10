#!/usr/bin/env python3
"""Makes a copy of the engine run on a Mac without Homebrew.

Wine opens some libraries by name (freetype, gnutls, SDL2) and links others (GStreamer, FFmpeg).
On a development Mac they come from x86_64 Homebrew in /usr/local. This copies them into the
engine's lib/, with everything they need in turn, together with a set of GStreamer plugins and
the plugin scanner, and points every reference at the copies through @loader_path. Plugins whose
libraries are missing (Homebrew upgraded them and not the plugin) are left out and listed.

usage: tools/bundle-libs.py <engine dir>      e.g. engine/portable, a copy of engine/dist

Nothing under /usr/local is changed. The files that change here lose their signatures; the build
signs them again.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

HOMEBREW = ("/usr/local/", "/opt/homebrew/")

# what wine dlopens by name (configure's SONAME_ values); dbus and odbc stay out
DLOPENED = ["libfreetype.6.dylib", "libgnutls.30.dylib", "libSDL2-2.0.0.dylib"]

# GStreamer plugins winegstreamer needs for game video and audio: pipelines, conversion,
# containers (MP4, Matroska, AVI, ASF/WMV, Ogg, WAV, MPEG), decoders (FFmpeg's, VideoToolbox's,
# Vorbis, Theora, Opus, FLAC, MP3)
PLUGINS = [
    "coreelements", "app", "playback", "typefindfunctions", "videoconvertscale", "audioconvert", "audioresample",
    "volume", "autodetect", "isomp4", "matroska", "avi", "asf", "wavparse", "ogg", "vorbis", "theora", "opus",
    "opusparse", "flac", "audioparsers", "id3demux", "mpg123", "videoparsersbad", "mpegpsdemux", "mpegtsdemux",
    "applemedia",
]
PLUGIN_DIR = Path("/usr/local/lib/gstreamer-1.0")
# FFmpeg's decoders for GStreamer come from our own build (scripts/build-engine.sh media): Homebrew's
# gst-libav is linked against an older FFmpeg than it ships
MEDIA = Path(__file__).resolve().parent.parent / "engine/deps/media"
OWN_PLUGINS = [MEDIA / "lib/gstreamer-1.0/libgstlibav.dylib"]


def is_macho(path: Path) -> bool:
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
    except OSError:
        return False
    return magic in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xce\xfa\xed\xfe")


def linked(path: Path) -> list[str]:
    """Load commands of a Mach-O file: the libraries it links, without its own id"""
    out = subprocess.run(["otool", "-L", str(path)], capture_output=True, text=True, check=True).stdout.splitlines()[1:]
    own = subprocess.run(["otool", "-D", str(path)], capture_output=True, text=True).stdout.splitlines()[1:]
    own_id = own[0].strip() if own else None
    names = [line.strip().split(" (")[0] for line in out]
    return [n for n in names if n != own_id]


def rpaths(path: Path) -> list[str]:
    out = subprocess.run(["otool", "-l", str(path)], capture_output=True, text=True, check=True).stdout.splitlines()
    result = []
    for i, line in enumerate(out):
        if line.strip() == "cmd LC_RPATH":
            for follow in out[i + 1:i + 4]:
                if follow.strip().startswith("path "):
                    result.append(follow.strip()[5:].split(" (offset")[0])
    return result


def resolve(reference: str, loader: Path) -> Path | None:
    """Where a load command points on this Mac"""
    if reference.startswith("@loader_path/"):
        candidate = loader.resolve().parent / reference[len("@loader_path/"):]
        return candidate if candidate.exists() else None
    if reference.startswith("@rpath/"):
        name = reference[len("@rpath/"):]
        for base in [loader.resolve().parent, loader.resolve().parent.parent / "lib", Path("/usr/local/lib")]:
            if (base / name).exists():
                return base / name
        return None
    path = Path(reference)
    return path if path.exists() else None


def foreign(reference: str) -> bool:
    return (reference.startswith(HOMEBREW) or reference.startswith(str(MEDIA) + "/")
            or reference.startswith("@rpath/") or reference.startswith("@loader_path/"))


def main() -> None:
    engine = Path(sys.argv[1]).resolve()
    lib = engine / "lib"
    plugins_out = lib / "gstreamer-1.0"
    scanner_out = engine / "libexec" / "gstreamer-1.0" / "gst-plugin-scanner"

    # library name (as references spell it) -> its file on this Mac
    wanted: dict[str, Path] = {}
    missing: dict[str, set[str]] = {}

    def collect(path: Path, owner: str) -> bool:
        """Adds what `path` needs; False when something it needs is not on this Mac"""
        ok = True
        for reference in linked(path):
            if not foreign(reference):
                continue
            name = Path(reference).name
            if name in wanted:
                continue
            source = resolve(reference, path)
            if source is None:
                missing.setdefault(owner, set()).add(reference)
                ok = False
                continue
            if source.resolve().is_relative_to(engine):
                continue
            wanted[name] = source
            ok = collect(source, owner) and ok
        return ok

    for name in DLOPENED:
        source = Path("/usr/local/lib") / name
        if source.exists():
            wanted[name] = source
            collect(source, name)
        else:
            print(f"skip {name}: not installed")

    machos = [p for p in engine.rglob("*") if p.is_file() and not p.is_symlink() and is_macho(p)]
    for path in machos:
        collect(path, str(path.relative_to(engine)))

    plugins_out.mkdir(parents=True, exist_ok=True)
    plugin_files: list[Path] = []
    plugin_sources: dict[str, Path] = {}
    for plugin in PLUGINS:
        source = PLUGIN_DIR / f"libgst{plugin}.dylib"
        if not source.exists():
            print(f"skip plugin {plugin}: not installed")
            continue
        before = dict(wanted)
        if not collect(source, f"plugin {plugin}"):
            # a plugin Homebrew left behind its libraries would only fail to load
            for name in set(wanted) - set(before):
                del wanted[name]
            print(f"skip plugin {plugin}: needs {sorted(missing[f'plugin {plugin}'])}")
            continue
        target = plugins_out / source.name
        shutil.copy2(source.resolve(), target)
        plugin_files.append(target)
        plugin_sources[target.name] = source.resolve()

    for source in OWN_PLUGINS:
        if not source.exists():
            print(f"skip {source.name}: not built (scripts/build-engine.sh media)")
            continue
        collect(source, f"plugin {source.name}")
        target = plugins_out / source.name
        shutil.copy2(source.resolve(), target)
        plugin_files.append(target)
        plugin_sources[target.name] = source.resolve()

    scanner = next(Path("/usr/local/Cellar/gstreamer").glob("*/libexec/gstreamer-1.0/gst-plugin-scanner"), None)
    if scanner:
        collect(scanner, "gst-plugin-scanner")
        scanner_out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(scanner.resolve(), scanner_out)

    copied: list[Path] = []
    for name, source in sorted(wanted.items()):
        target = lib / name
        if not target.exists():
            shutil.copy2(source.resolve(), target)
            os.chmod(target, 0o755)
        copied.append(target)

    # every Mach-O in the engine now points at the copies
    def fix(path: Path) -> None:
        args: list[str] = []
        for reference in linked(path):
            if not foreign(reference):
                continue
            name = Path(reference).name
            if not (lib / name).exists():
                continue
            relative = os.path.relpath(lib / name, path.parent)
            args += ["-change", reference, f"@loader_path/{relative}"]
        for rpath in rpaths(path):
            if rpath.startswith(HOMEBREW) or rpath.startswith("@loader_path"):
                args += ["-delete_rpath", rpath]
        if path.parent == lib or path.parent == plugins_out:
            args += ["-id", f"@rpath/{path.name}"]
        if args:
            subprocess.run(["install_name_tool", *args, str(path)], check=True, capture_output=True)

    for path in machos + copied + plugin_files + ([scanner_out] if scanner else []):
        fix(path)

    leftovers = []
    for path in [p for p in engine.rglob("*") if p.is_file() and not p.is_symlink() and is_macho(p)]:
        for reference in linked(path) + rpaths(path):
            if reference.startswith(HOMEBREW) or reference.startswith(str(MEDIA)):
                leftovers.append(f"{path.relative_to(engine)} -> {reference}")
    size = sum(p.stat().st_size for p in copied + plugin_files) / 1e6
    print(f"bundled {len(copied)} libraries and {len(plugin_files)} plugins ({size:.0f} MB)")
    write_licenses(engine, {name: source for name, source in wanted.items()}, plugin_sources)
    if leftovers:
        print("still pointing at Homebrew:")
        print("\n".join(leftovers))
        sys.exit(1)


def write_licenses(engine: Path, libraries: dict[str, Path], plugins: dict[str, Path]) -> None:
    """LICENSES.md: which Homebrew formula and version each copied file comes from, with its
    licence, so whoever passes the engine on can name the sources"""
    import json
    formulas: dict[str, tuple[str, list[str]]] = {}
    sources = [(name, path.resolve()) for name, path in libraries.items()]
    sources += [(name, path) for name, path in plugins.items()]
    for name, real in sources:
        parts = real.parts
        if "Cellar" not in parts:
            continue
        i = parts.index("Cellar")
        formula, version = parts[i + 1], parts[i + 2]
        formulas.setdefault(formula, (version, []))[1].append(name)
    licences: dict[str, str] = {}
    brew = Path("/usr/local/bin/brew")
    if brew.exists():
        out = subprocess.run([str(brew), "info", "--json=v2", *sorted(formulas)], capture_output=True, text=True)
        if out.returncode == 0:
            for info in json.loads(out.stdout).get("formulae", []):
                licences[info["name"]] = info.get("license") or "see the formula"
    lines = ["# Libraries inside the engine", "",
             "Copied from x86_64 Homebrew by tools/bundle-libs.py. Sources: https://formulae.brew.sh and each project's site.", "",
             "| Formula | Version | Licence | Files |", "|---|---|---|---|"]
    for formula, (version, files) in sorted(formulas.items()):
        lines.append(f"| {formula} | {version} | {licences.get(formula, '?')} | {', '.join(sorted(files))} |")
    own = sorted(name for name, path in sources if str(path).startswith(str(MEDIA)))
    if own:
        lines += ["", "Built here by `scripts/build-engine.sh media`, LGPL-2.1-or-later: FFmpeg (decoders only, "
                  "no GPL parts) and GStreamer's gst-libav: " + ", ".join(own) + "."]
    (engine / "LICENSES.md").write_text("\n".join(lines) + "\n")
    print(f"wrote LICENSES.md ({len(formulas)} formulas)")


if __name__ == "__main__":
    main()
