#!/usr/bin/env python3
"""Real generic Wine/WoW64/MSI/Mono controls in a new prefix; no third-party apps.
Requires macOS, Rosetta, MinGW-w64 and the built portable engine. No account/login.
"""
from pathlib import Path
import argparse, json, os, shutil, subprocess, tempfile

# Direct invocation also gets an owned workspace and automatic cleanup.
import os as _artifact_os, sys as _artifact_sys
from pathlib import Path as _ArtifactPath
if not _artifact_os.environ.get('EXERUNNER_ARTIFACT_SESSION'):
    _artifact_os.execv(_artifact_sys.executable, [_artifact_sys.executable, '-I',
        str(_ArtifactPath(__file__).resolve().parents[1] / 'tools/artifacts.py'),
        'run', '--label', 'test-general-runtime-test', '--', _artifact_sys.executable, __file__, *_artifact_sys.argv[1:]])

parser = argparse.ArgumentParser()
parser.add_argument("--engine", type=Path, default=Path("/Applications/ExeRunner.app/Contents/Resources/engine"))
parser.add_argument("--keep", action="store_true")
args = parser.parse_args()
source = Path(__file__).resolve().parent
work = Path(tempfile.mkdtemp(prefix="exerunner-general-check-", dir=os.environ.get("TMPDIR", "/private/tmp")))
prefix = work / "programs"
engine = args.engine.resolve()
env = {k: v for k, v in os.environ.items() if k in {"HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "TERM", "PATH"} or k.startswith("LC_")}
env.update(WINEPREFIX=str(prefix), WINEDEBUG="-all", WINEMSYNC="1", ROSETTA_ADVERTISE_AVX="1",
           DYLD_FALLBACK_LIBRARY_PATH=str(engine / "lib") + ":/usr/lib",
           GST_PLUGIN_SYSTEM_PATH_1_0=str(engine / "lib/gstreamer-1.0"),
           GST_PLUGIN_SCANNER_1_0=str(engine / "libexec/gstreamer-1.0/gst-plugin-scanner"),
           GST_REGISTRY_1_0=str(work / "gstreamer-registry.bin"))
results = []

def command(argv, *, cwd=None, expected=0, timeout=60):
    result = subprocess.run([str(x) for x in argv], env=env, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != expected:
        raise RuntimeError(f"{Path(str(argv[0])).name}: status {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result.stdout

def wine(argv, **kw):
    return command([engine / "bin/wine", *argv], **kw)

def windows(path):
    return "Z:\\" + str(path).lstrip("/").replace("/", "\\")

try:
    wine(["wineboot", "--init"], timeout=90)
    command([engine / "bin/wineserver", "-w"], timeout=30)
    if not (prefix / "system.reg").is_file(): raise RuntimeError("prefix was not initialized")
    results.append("fresh ordinary prefix")
    for bits, compiler in [(64, "x86_64-w64-mingw32-gcc"), (32, "i686-w64-mingw32-gcc")]:
        exe = work / f"probe-{bits}.exe"
        command([compiler, "-O2", "-static", "-municode", source / "general-runtime-probe.c", "-lgdi32", "-luser32", "-ladvapi32", "-o", exe])
        output = wine([exe])
        if "RESULT PASS" not in output or f"ARCH {bits}" not in output: raise RuntimeError(output)
        results.append(f"Win{bits}: Unicode files/registry, DLLs, GDI fonts")
    wine([work / "probe-64.exe", "--reboot-code"], expected=3010 & 255)
    results.append("MSI reboot exit-code transport")
    installer = prefix / "drive_c/installer"
    installer.mkdir()
    shutil.copyfile(work / "probe-32.exe", installer / "probe.exe")
    generator = work / "make-msi.exe"
    command(["x86_64-w64-mingw32-gcc", "-O2", "-static", source / "general-msi-fixture.c", "-lmsi", "-lole32", "-o", generator])
    wine([generator], cwd=installer)
    wine(["msiexec", "/i", installer / "probe.msi", "/qn", "/l*v", work / "msi.log"], cwd=installer)
    installed = list((prefix / "drive_c").glob("Program Files*/ExeRunnerProbe/probe.exe"))
    if not installed or "RESULT PASS" not in wine([installed[0]]): raise RuntimeError("MSI payload not installed/runnable")
    results.append("MSI with adjacent payload files: install and launch")
    compilers = list((prefix / "drive_c/windows/mono").rglob("mcs.exe"))
    if not compilers: raise RuntimeError("bundled Wine Mono did not install its compiler")
    for arch, bits in [("x86", 32), ("x64", 64)]:
        exe = work / f"winforms-{arch}.exe"
        wine([compilers[0], "-r:System.Windows.Forms", "-r:System.Drawing", "-platform:" + arch,
              "-out:" + windows(exe), windows(source / "general-winforms-probe.cs")])
        output = wine([exe])
        if "RESULT PASS" not in output or f"ARCH {bits}" not in output: raise RuntimeError(output)
        results.append(f"WinForms Mono {arch}: window, drawing, Unicode")
    print(json.dumps({"passed": results, "work": str(work) if args.keep else "removed after test"}, indent=2))
finally:
    subprocess.run([str(engine / "bin/wineserver"), "-k"], env=env, capture_output=True, timeout=15)
    if not args.keep: shutil.rmtree(work)
