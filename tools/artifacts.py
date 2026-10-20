#!/usr/bin/env python3
"""Owned developer scratch, bounded receipts, one rollback and one checked engine.
Never sweeps /tmp, /Applications, evidence roots or Windows environments by name.
"""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SOURCE_EXT = {'.c', '.h', '.cpp', '.swift', '.cs', '.py', '.sh', '.rs', '.js', '.ts',
              '.md', '.patch', '.diff', '.pdf', '.docx', '.wxs', '.csproj', '.wxi', '.s', '.m', '.mm',
              '.cc', '.cxx', '.hpp', '.hxx', '.idl', '.rc', '.in', '.go', '.java', '.kt', '.lua',
              '.rb', '.toml', '.yaml', '.yml', '.json', '.txt'}


def real_directory(path):
    path = Path(path).absolute()
    # Refuse symlink ancestors, including a replaced build/ or retained/ directory.
    for p in [path, *path.parents]:
        if p.is_symlink():
            raise RuntimeError('Symlink in managed path: ' + str(p))
    return path


def atomic_json(path, value):
    temp = path.with_name('.' + path.name + '.' + uuid.uuid4().hex)
    temp.write_text(json.dumps(value, indent=2) + '\n')
    os.replace(temp, path)


def digest(path):
    """Include every relative name, file byte and link target; never follow links."""
    h = hashlib.sha256()
    path = Path(path)
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as f:
            for block in iter(lambda: f.read(1024 * 1024), b''):
                h.update(block)
        return h.hexdigest()
    for base, dirs, files in os.walk(path, followlinks=False):
        for name in sorted(dirs + files):
            p = Path(base) / name
            h.update(os.fsencode(str(p.relative_to(path))) + b'\0')
            if p.is_symlink():
                h.update(b'L' + os.fsencode(os.readlink(p)))
            elif p.is_file():
                h.update(b'F' + bytes.fromhex(digest(p)))
            else:
                h.update(b'D')
        dirs.sort()
    return h.hexdigest()


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def busy(path):
    """Failure to inspect is a reason to retain data, never permission to remove."""
    p = subprocess.run(['/bin/ps', '-axo', 'pid=,command='], capture_output=True, text=True)
    if p.returncode:
        return True
    for line in p.stdout.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and int(fields[0]) != os.getpid() and str(path) in fields[1]:
            return True
    p = subprocess.run(['/usr/sbin/lsof', '-n', '-P', '-F', 'pn'], capture_output=True, text=True)
    if p.returncode:
        return True
    pid = None
    for line in p.stdout.splitlines():
        if line.startswith('p'):
            pid = int(line[1:])
        elif pid != os.getpid() and line.startswith('n'):
            if line[1:] == str(path) or line[1:].startswith(str(path) + '/'):
                return True
    return False


class Artifacts:
    def __init__(self, project=ROOT, in_use=busy, verify=None, installed=None):
        self.project = real_directory(project)
        self.installed = Path(installed) if installed else Path('/Applications/ExeRunner.app')
        self.root = real_directory(self.project / 'build/artifacts.noindex')
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        marker = real_directory(self.root / 'owner.json')
        owner = {'schema': 1, 'project': str(self.project), 'uid': os.getuid()}
        if marker.exists():
            if json.loads(marker.read_text()) != owner:
                raise RuntimeError('Artifact root belongs to another checkout')
        elif any(self.root.iterdir()):
            raise RuntimeError('Refusing to adopt an unknown nonempty directory')
        else:
            atomic_json(marker, owner)
        self.in_use = in_use
        self.verify = verify or self.verify_payload
        self.lockpath = real_directory(self.root / 'lock')
        for name in ['jobs', 'retained', 'reports', 'preserved']:
            real_directory(self.root / name).mkdir(exist_ok=True)
        self.statepath = real_directory(self.root / 'pins.json')

    @contextlib.contextmanager
    def lock(self):
        with self.lockpath.open('a') as fd:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield

    def state(self):
        return json.loads(self.statepath.read_text()) if self.statepath.exists() else {}

    def safe_pin(self, kind, path):
        path = real_directory(path)
        forbidden = [self.project / 'bottles', self.project / 'engine/src', self.project / 'app/Sources',
                     self.installed, Path('/Applications/ExeRunner.app'), Path.home() / 'Documents', Path.home() / 'Downloads']
        if any(path == p or path.is_relative_to(p) or p.is_relative_to(path) for p in forbidden):
            raise RuntimeError('Protected path cannot be a retention target: ' + str(path))
        if kind == 'backup':
            info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
            if info.get('CFBundleIdentifier') != 'local.exerunner.app':
                raise RuntimeError('Not an ExeRunner backup')
        elif kind == 'engine':
            if not (path / 'engine.json').is_file() or not (path / 'bin/wine').is_file():
                raise RuntimeError('Not a portable engine')
            if path in [self.project / 'engine/dist', self.project / 'engine/portable']:
                raise RuntimeError('Development runtime input is protected')
        elif kind == 'installer':
            if path.parent != self.project / 'build' or not re.fullmatch(r'ExeRunner-[0-9][0-9.]*\.dmg', path.name):
                raise RuntimeError('Not a project distribution image')
        else:
            raise RuntimeError('Unknown retained role')
        return path

    @staticmethod
    def verify_payload(kind, path):
        if kind == 'backup':
            info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
            if info.get('CFBundleIdentifier') != 'local.exerunner.app':
                raise RuntimeError('Not an ExeRunner app')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)
            subprocess.run([str(path / 'Contents/MacOS/ExeRunner'), '--self-test'], check=True, timeout=30)
        elif kind == 'engine':
            if not (path / 'engine.json').is_file() or not (path / 'bin/wineserver').is_file():
                raise RuntimeError('Incomplete portable engine')
            subprocess.run([str(path / 'bin/wine'), '--version'], check=True,
                           env={'HOME': str(Path.home()), 'PATH': '/usr/bin:/bin'}, timeout=20)
        elif kind == 'installer':
            with path.open('rb') as f:
                f.seek(-512, 2)
                if f.read(4) != b'koly':
                    raise RuntimeError('Invalid UDIF image')

    def engine_path(self):
        pin = self.state().get('engine')
        if not pin:
            return self.project / 'engine/portable'
        path = self.safe_pin('engine', pin['path'])
        if not path.exists() or digest(path) != pin['digest']:
            raise RuntimeError('Last checked engine is missing or changed; build refused')
        return path

    def referenced(self, path):
        support = Path.home() / 'Library/Application Support/ExeRunner'
        def contains(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key == 'enginePath' and isinstance(item, str):
                        selected = Path(item).expanduser().resolve()
                        if selected == path or selected.is_relative_to(path):
                            return True
                    if contains(item):
                        return True
            elif isinstance(value, list):
                return any(contains(item) for item in value)
            return False
        for name in ['settings.json', 'bottles.json']:
            p = support / name
            if p.exists():
                try:
                    if contains(json.loads(p.read_text())):
                        return True
                except (ValueError, OSError):
                    return True
        return False

    def check_retirement(self, kind, pin):
        p = self.safe_pin(kind, pin['path'])
        if not p.exists() or digest(p) != pin['digest'] or self.in_use(p) or self.referenced(p):
            raise RuntimeError('Retained artifact changed, is in use, or has an owner reference: ' + str(p))
        return p

    def retire(self, kind, pin):
        p = self.check_retirement(kind, pin)
        if pin.get('container'):
            container = real_directory(pin['container'])
            if container.parent != self.root / 'retained' or p.parent != container:
                raise RuntimeError('Invalid retained container')
            self.owned(container, 'retained')
            shutil.rmtree(container)
        elif p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink()

    def seed(self, values):
        # Register the already accepted retained copies without making more copies.
        with self.lock():
            state = self.state()
            for kind, value in values.items():
                if not value or kind in state:
                    continue
                p = self.safe_pin(kind, value)
                self.verify(kind, p)
                state[kind] = {'path': str(p), 'digest': digest(p), 'proof': 'existing accepted artifact'}
            atomic_json(self.statepath, state)

    def retain(self, kind, source, proof):
        source = real_directory(source)
        self.verify(kind, source)
        original = digest(source)
        with self.lock():
            state = self.state()
            old = state.get(kind)
            if old and old['path'] == str(source):
                if kind == 'installer':
                    self.safe_pin(kind, source)
                    state[kind] = {'path': str(source), 'digest': original, 'proof': proof}
                    atomic_json(self.statepath, state)
                    return
                if old['digest'] != original:
                    raise RuntimeError('Pinned artifact was modified in place')
                return
            if old:
                self.check_retirement(kind, old)
            if kind == 'installer':
                self.safe_pin(kind, source)
                new = {'path': str(source), 'digest': original, 'proof': proof}
            else:
                container = self.new_owned('retained', kind)
                payload = container / ('ExeRunner.app' if kind == 'backup' else 'engine')
                try:
                    subprocess.run(['/bin/cp', '-cR', '-P', str(source), str(payload)], check=True)
                    if digest(payload) != original:
                        raise RuntimeError('Retained copy verification failed')
                    self.verify(kind, payload)
                    lease = self.owned(container, 'retained')
                    lease.update(kind=kind, payload=str(payload), digest=original)
                    atomic_json(container / 'lease.json', lease)
                    new = {'path': str(payload), 'container': str(container), 'digest': original, 'proof': proof}
                except BaseException:
                    shutil.rmtree(container)
                    raise
            # If interrupted after publication, gc knows the old owned container is unpinned.
            state[kind] = new
            atomic_json(self.statepath, state)
            if old:
                self.retire(kind, old)

    def new_owned(self, area, label):
        parent = real_directory(self.root / area)
        p = parent / (label + '-' + uuid.uuid4().hex)
        p.mkdir(mode=0o700)
        atomic_json(p / 'lease.json', {'project': str(self.project), 'pid': os.getpid(),
                                      'area': area, 'created': time.time()})
        return p

    def owned(self, path, area):
        path = real_directory(path)
        if path.parent != self.root / area:
            raise RuntimeError('Outside managed area')
        lease = json.loads(real_directory(path / 'lease.json').read_text())
        if lease['project'] != str(self.project) or lease['area'] != area:
            raise RuntimeError('Foreign artifact')
        return lease

    def preserve_sources(self, path):
        for base, dirs, files in os.walk(path, followlinks=False):
            dirs[:] = [n for n in dirs if n not in ['cache', '.build', 'node_modules', 'windows', 'Program Files',
                       'Program Files (x86)', 'Contents', 'swiftpm', 'wine-build', 'wine-tools',
                       'device-build', 'dist-devices', 'candidate-engine'] and not (Path(base) / n).is_symlink()]
            for name in files:
                p = Path(base) / name
                if p.name in ['lease.json', 'result.json', 'results.json'] or p.is_symlink() or p.suffix.lower() not in SOURCE_EXT:
                    continue
                if p.stat().st_size > 8 * 1024 * 1024:
                    raise RuntimeError('Large source/document needs explicit preservation: ' + str(p))
                sha = digest(p)
                out = self.root / 'preserved' / (sha + p.suffix.lower())
                if not out.exists():
                    shutil.copy2(p, out)
                if digest(out) != sha:
                    raise RuntimeError('Source archive mismatch')

    def remove_job(self, path):
        self.owned(path, 'jobs')
        if self.in_use(path):
            return False
        self.preserve_sources(path)
        shutil.rmtree(path)
        return True

    def gc(self):
        with self.lock():
            for p in (self.root / 'jobs').iterdir():
                try:
                    lease = self.owned(p, 'jobs')
                except (OSError, ValueError, KeyError, RuntimeError):
                    continue  # Never guess ownership from a name.
                if not alive(lease['pid']):
                    self.remove_job(p)
            pins = self.state()
            keep = {x.get('container') for x in pins.values()}
            for p in (self.root / 'retained').iterdir():
                try:
                    lease = self.owned(p, 'retained')
                except (OSError, ValueError, KeyError, RuntimeError):
                    continue
                if str(p) not in keep and not alive(lease['pid']) and not self.in_use(p):
                    if lease.get('digest'):
                        try:
                            self.retire(lease['kind'], {'path': lease['payload'], 'container': str(p),
                                                       'digest': lease['digest']})
                        except RuntimeError:
                            continue
                    else:
                        # An interrupted copy was never published; preserve any test source first.
                        self.preserve_sources(p)
                        shutil.rmtree(p)
            reports = sorted((self.root / 'reports').glob('run-*.json'), key=lambda p: p.stat().st_mtime)
            for p in reports[:-20]:
                if not p.is_symlink():
                    p.unlink()

    @staticmethod
    def managed_workspace():
        import runpy
        return runpy.run_path(str(ROOT / 'tools/managed-context.py'))['workspace']()

    def run(self, label, command, exclusive=None):
        if not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', label):
            raise RuntimeError('Invalid job label')
        context = self.managed_workspace()
        if context is not None:
            # Reuse the already-admitted resource context. Never queue behind our own slot.
            env = dict(os.environ)
            with contextlib.ExitStack() as stack:
                if exclusive and exclusive not in env.get('EXERUNNER_HELD_LOCKS', '').split(','):
                    if exclusive not in ['build', 'engine']: raise RuntimeError('Invalid lock')
                    fd = stack.enter_context(real_directory(self.root / (exclusive + '.lock')).open('a'))
                    fcntl.flock(fd, fcntl.LOCK_EX)
                    env['EXERUNNER_HELD_LOCKS'] = ','.join(filter(None, [env.get('EXERUNNER_HELD_LOCKS'), exclusive]))
                interrupted = []
                def defer_signal(signum, frame): interrupted.append(signum)
                previous = {s: signal.signal(s, defer_signal) for s in [signal.SIGINT, signal.SIGTERM, signal.SIGHUP]}
                try:
                    child = subprocess.Popen(command, env=env)
                    status = child.wait()
                    if interrupted and status == 0: status = 128 + interrupted[0]
                finally:
                    for signum, handler in previous.items(): signal.signal(signum, handler)
                atomic_json(self.root / 'reports' / ('run-' + label + '.json'), {'status': status, 'scratch': str(context), 'cleanup': 'outer global managed job'})
                return status
        # Owner's cross-project runner supplies resource admission and disposable scratch.
        # Keep this project's retained app/engine/installer management separate; no nested
        # TMPDIR wrappers or heavy.sh calls. Other machines retain the reviewed local runner.
        runner = Path.home() / 'LifeOS/life/99_System/tools/dev-session/managed_job.py'
        python = Path.home() / 'lifeos-core/.venv/bin/python'
        if runner.is_file() and python.is_file():
            adapter = [str(python), str(runner), '--', str(python),
                       str(self.project / 'tools/managed-artifact-command.py')]
            if exclusive:
                adapter += ['--exclusive', exclusive]
            return subprocess.call(adapter + ['--'] + command)
        if not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', label):
            raise RuntimeError('Invalid job label')
        self.gc()
        with contextlib.ExitStack() as stack:
            if exclusive:
                if exclusive not in ['build', 'engine']:
                    raise RuntimeError('Invalid lock')
                fd = stack.enter_context(real_directory(self.root / (exclusive + '.lock')).open('a'))
                fcntl.flock(fd, fcntl.LOCK_EX)
            with self.lock():
                job = self.new_owned('jobs', label)
            for part in ['tmp', 'work', 'cache/clang', 'cache/swift', 'cache/ccache']:
                (job / part).mkdir(parents=True)
            env = dict(os.environ, EXERUNNER_ARTIFACT_SESSION=str(job), EXERUNNER_WORK_ROOT=str(job / 'work'),
                       TMPDIR=str(job / 'tmp') + '/', CLANG_MODULE_CACHE_PATH=str(job / 'cache/clang'),
                       SWIFT_MODULECACHE_PATH=str(job / 'cache/swift'), CCACHE_DIR=str(job / 'cache/ccache'),
                       PYTHONDONTWRITEBYTECODE='1')
            process = None
            tail = b''
            code = 1
            def stop(signum, frame):
                raise KeyboardInterrupt
            previous = {s: signal.signal(s, stop) for s in [signal.SIGINT, signal.SIGTERM]}
            try:
                process = subprocess.Popen(command, env=env, start_new_session=True, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT)
                while True:
                    chunk = process.stdout.read1(65536)
                    if not chunk:
                        break
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
                    tail = (tail + chunk)[-32768:]
                code = process.wait()
            except KeyboardInterrupt:
                if process and process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                code = 130
            finally:
                if process and process.stdout:
                    process.stdout.close()
                for s, handler in previous.items():
                    signal.signal(s, handler)
                # Test-owned Wine servers only; never use an owner's bottle or global wineserver -k.
                engine = Path('/Applications/ExeRunner.app/Contents/Resources/engine')
                if '--engine' in command:
                    engine = Path(command[command.index('--engine') + 1])
                if (engine / 'bin/wineserver').is_file():
                    for base, dirs, files in os.walk(job, followlinks=False):
                        dirs[:] = [d for d in dirs if not (Path(base) / d).is_symlink()]
                        if 'system.reg' in files:
                            prefix = Path(base)
                            e = {'HOME': str(Path.home()), 'PATH': '/usr/bin:/bin', 'WINEPREFIX': str(prefix)}
                            try:
                                subprocess.run([str(engine / 'bin/wineserver'), '-k'], env=e,
                                               capture_output=True, timeout=10)
                                subprocess.run([str(engine / 'bin/wineserver'), '-w'], env=e,
                                               capture_output=True, timeout=10)
                            except subprocess.TimeoutExpired:
                                pass
                report = self.root / 'reports' / ('run-' + label + '.json')
                atomic_json(report, {'label': label, 'status': code, 'time': time.time(),
                                     'output_tail': tail.decode('utf-8', 'replace')})
                lease = self.owned(job, 'jobs')
                lease['pid'] = 0
                atomic_json(job / 'lease.json', lease)
                with self.lock():
                    removed = self.remove_job(job)
                if not removed:
                    print('Cleanup deferred: workspace still in use: ' + str(job), file=sys.stderr)
                self.gc()
                log = real_directory(self.project / 'engine/build.log')
                if exclusive == 'engine' and log.is_file() and log.stat().st_size > 2 * 1024 * 1024:
                    with log.open('rb') as f:
                        f.seek(-2 * 1024 * 1024, 2)
                        tail_log = f.read()
                    log.write_bytes(tail_log)
            return code

    def install(self, candidate):
        """Idle-only deployment; only this explicit command changes the installed app."""
        destination = self.installed
        candidate = real_directory(candidate)
        self.verify('backup', candidate)
        if self.in_use(destination):
            raise RuntimeError('Installed app or one of its games is running; install refused')
        job = Path(os.environ['EXERUNNER_ARTIFACT_SESSION'])
        context = self.managed_workspace()
        if context is None or job.resolve() != context:
            self.owned(job, 'jobs')
        incoming, previous = job / 'incoming.app', job / 'previous.app'
        subprocess.run(['/bin/cp', '-cR', '-P', str(candidate), str(incoming)], check=True)
        self.verify('backup', incoming)
        existed = destination.exists()
        if existed:
            self.verify('backup', destination)
            # Commit the verified rollback before any installed bytes move.
            self.retain('backup', destination, 'verified installed app before replacement')
            os.rename(destination, previous)
        try:
            os.rename(incoming, destination)
            self.verify('backup', destination)
        except BaseException:
            if destination.exists():
                os.rename(destination, incoming)
            if existed:
                os.rename(previous, destination)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    run = sub.add_parser('run'); run.add_argument('--label', required=True); run.add_argument('--exclusive'); run.add_argument('command', nargs=argparse.REMAINDER)
    sub.add_parser('gc'); sub.add_parser('status'); sub.add_parser('idle-runtime')
    engine_query = sub.add_parser('engine'); engine_query.add_argument('--checked-only', action='store_true')
    seed = sub.add_parser('seed'); seed.add_argument('--backup'); seed.add_argument('--engine'); seed.add_argument('--installer')
    checked = sub.add_parser('check-engine'); checked.add_argument('source', type=Path); checked.add_argument('command', nargs=argparse.REMAINDER)
    image = sub.add_parser('record-installer'); image.add_argument('source', type=Path)
    install = sub.add_parser('install'); install.add_argument('source', type=Path)
    args = parser.parse_args(); store = Artifacts()
    if args.action == 'idle-runtime':
        if store.in_use(store.project / 'bottles') or store.in_use(store.installed / 'Contents/Resources/engine'):
            raise RuntimeError('A Windows session is running; refusing to quit it for a development relaunch')
        return 0
    if args.action == 'run':
        cmd = args.command[1:] if args.command[:1] == ['--'] else args.command
        if not cmd:
            parser.error('run requires a command')
        return store.run(args.label, cmd, args.exclusive)
    if args.action == 'gc':
        store.gc()
    elif args.action == 'status':
        print(json.dumps(store.state(), indent=2))
    elif args.action == 'seed':
        store.seed({k: getattr(args, k) for k in ['backup', 'engine', 'installer']})
    elif args.action == 'engine':
        pin = store.state().get('engine')
        if args.checked_only and not pin:
            return 1
        print(store.engine_path())
    elif args.action == 'check-engine':
        cmd = args.command[1:] if args.command[:1] == ['--'] else args.command
        if not cmd:
            parser.error('check-engine requires a successful verification command')
        source_hash = digest(args.source)
        status = store.run('engine-acceptance', cmd)
        if status:
            return status
        if digest(args.source) != source_hash:
            raise RuntimeError('Engine changed during acceptance')
        store.retain('engine', args.source, {'passed_command': cmd, 'time': time.time()})
    elif args.action == 'record-installer':
        store.retain('installer', args.source, 'successful distribution image creation')
    elif args.action == 'install':
        if not os.environ.get('EXERUNNER_ARTIFACT_SESSION'):
            return store.run('install', [sys.executable, __file__, 'install', str(args.source)], 'build')
        store.install(args.source)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError, ValueError) as error:
        print('Artifact policy: ' + str(error), file=sys.stderr)
        sys.exit(1)
