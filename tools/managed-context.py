"""Validate the owner's global scratch provenance without pretending it is a legacy lease."""
import os,stat
from pathlib import Path

def workspace():
    if os.environ.get('EXERUNNER_GLOBAL_MANAGED_ROOT') is None:return None
    root=Path(os.environ['EXERUNNER_GLOBAL_MANAGED_ROOT'])
    work=Path(os.environ['EXERUNNER_WORK_ROOT'])
    temp=Path(os.environ['TMPDIR'])
    if root.parent!=Path('/private/tmp') or not root.name.startswith('lifeos-job-'):
        raise RuntimeError('Invalid global managed root')
    for directory in [root,temp,work]:
        s=directory.lstat()
        if directory.resolve()!=directory or not stat.S_ISDIR(s.st_mode) or s.st_uid!=os.getuid() or (directory==root and s.st_mode&0o077):
            raise RuntimeError('Unsafe global managed workspace')
    if temp!=root/'tmp' or work!=temp/'exerunner-work':raise RuntimeError('Managed scratch mismatch')
    return work
