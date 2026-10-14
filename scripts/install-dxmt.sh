#!/bin/bash
# Installs only the optional backend. Never replace Wine's default renderer DLLs.
set -euo pipefail
exec python3 -I - "$1" <<'PY'
import hashlib, io, json, os, pathlib, sys, tarfile, tempfile, urllib.request
engine = pathlib.Path(sys.argv[1])
version = "v0.80"
digest = "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
url = "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
required = [arch + "/" + name for arch in ["x86_64-windows", "i386-windows"]
            for name in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]]
required += ["x86_64-unix/winemetal.so"]
def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "ExeRunner-DXMT-installer"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(64 * 1024 * 1024 + 1)
    if len(data) > 64 * 1024 * 1024: raise RuntimeError("Unexpectedly large DXMT download")
    return data
cached = os.environ.get("EXERUNNER_DXMT_ARCHIVE")
blob = pathlib.Path(cached).read_bytes() if cached else fetch(url)
if hashlib.sha256(blob).hexdigest() != digest: raise RuntimeError("DXMT SHA-256 mismatch")
files = {}
with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as archive:
    for name in required:
        member = archive.getmember(version + "/" + name)
        if not member.isfile() or member.size > 128 * 1024 * 1024: raise RuntimeError("Invalid DXMT member: " + name)
        files[name] = archive.extractfile(member).read()
license_text = fetch("https://raw.githubusercontent.com/3Shain/dxmt/v0.80/LICENSE")
if b"MIT License" not in license_text or b"Feifan He" not in license_text:
    raise RuntimeError("Missing DXMT licence")
files["LICENSE"] = license_text
files["SOURCE_URL"] = b"https://github.com/3Shain/dxmt/tree/v0.80\n"
files["manifest.json"] = json.dumps({"version":version,"url":url,"sha256":digest,
    "files":{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}},indent=2).encode()
files["DXMT_VERSION"] = b"0.80\n"
target = engine / "lib/dxmt"
for name, data in files.items():
    out = target / name
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists() and out.read_bytes() == data: continue
    with tempfile.NamedTemporaryFile(dir=out.parent, prefix=".dxmt-", delete=False) as f:
        f.write(data); temp = pathlib.Path(f.name)
    try:
        temp.chmod(0o644)
        os.replace(temp, out)
    finally:
        temp.unlink(missing_ok=True)
print("DXMT 0.80 installed at", target, "(official SHA-256 verified)")
PY
