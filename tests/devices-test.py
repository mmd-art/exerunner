#!/usr/bin/env python3
"""Native Windows print-to-file, COM pseudo-terminal, CoreMIDI and device API controls.
Uses only a fresh test prefix and virtual endpoints. No paper job or physical-device write.
"""
import argparse, json, os, pathlib, pty, select, subprocess, tempfile, termios, threading, tty
parser=argparse.ArgumentParser();parser.add_argument('--engine',type=pathlib.Path,required=True);args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];engine=args.engine.resolve()
work=pathlib.Path(tempfile.mkdtemp(prefix='exerunner-device-check-',dir='/private/tmp'));prefix=work/'prefix'
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','TMPDIR','LANG','TERM','PATH'} or k.startswith('LC_')}
env.update(WINEPREFIX=str(prefix),WINEDEBUG='-all',WINEMSYNC='1',DYLD_FALLBACK_LIBRARY_PATH=str(engine/'lib')+':/usr/lib')
def wine(params,timeout=45):
    r=subprocess.run([str(engine/'bin/wine'),*[str(x) for x in params]],env=env,cwd=work,capture_output=True,text=True,timeout=timeout)
    (work/'wine.log').open('a').write(r.stdout+r.stderr)
    if r.returncode:raise RuntimeError(f'Wine {params}: {r.returncode}\n{r.stdout}\n{r.stderr}')
    return r.stdout
winpath=lambda p:'Z:\\'+str(p).lstrip('/').replace('/','\\')
passed=[];midi=None;fds=[];details={}
try:
    wine(['wineboot','--init'],timeout=90)
    subprocess.run([str(engine/'bin/wineserver'),'-w'],env=env,check=True,timeout=30)
    exe=work/'probe.exe'
    subprocess.run(['x86_64-w64-mingw32-gcc','-O2','-static','-municode',str(root/'tests/devices-probe.c'),'-lwinspool','-lgdi32','-luser32','-ladvapi32','-lwinmm','-lsetupapi','-o',str(exe)],check=True)
    details['inventory']=wine([exe,'inventory']);passed.append('Windows WinUSB/HID/OpenCL API inventory')
    jobs_before=subprocess.check_output(['lpstat','-W','not-completed','-o'],text=True)
    output=work/'output.ps';details['printing']=wine([exe,'printing',winpath(output)])
    subprocess.run([str(engine/'bin/wineserver'),'-w'],env=env,check=True,timeout=30)
    assert output.is_file() and output.read_bytes().startswith(b'%!PS'), 'PostScript output missing'
    assert subprocess.check_output(['lpstat','-W','not-completed','-o'],text=True)==jobs_before,'Physical print queue changed'
    passed.append('CUPS printer discovery and GDI print-to-file, no physical queue change')
    master,slave=pty.openpty();fds=[master,slave];tty.setraw(slave);node=os.ttyname(slave)
    # Preserve a registry-only mapping made outside ExeRunner, then configure through AppState.
    reg=work/'manual.reg'
    text='Windows Registry Editor Version 5.00\n\n[HKEY_LOCAL_MACHINE\\Software\\Wine\\Ports]\n"COM23"="/dev/cu.exerunner-manual-canary"\n'
    reg.write_bytes(b'\xff\xfe'+text.encode('utf-16le'));wine(['regedit','/S',winpath(reg)])
    subprocess.run([str(engine/'bin/wineserver'),'-w'],env=env,check=True,timeout=30)
    mapper=work/'mapper-helper'
    subprocess.run(['bash',str(root/'tests/environment-native-helper.sh'),str(mapper)],check=True)
    subprocess.run([str(mapper),str(engine),str(prefix),node],env=env,check=True,timeout=45)
    def respond():
        if select.select([master],[],[],10)[0]:
            value=os.read(master,64)
            if value==b'EXERUNNER-PING':os.write(master,b'EXERUNNER-PONG')
    thread=threading.Thread(target=respond);thread.start();details['serial']=wine([exe,'serial','COM22']);thread.join(timeout=1)
    subprocess.run([str(mapper),str(engine),str(prefix),''],env=env,check=True,timeout=45)
    assert not (prefix/'dosdevices/com22').exists(), 'Managed COM link was not removed'
    passed.append('AppState COM22 setup/removal, Unicode registry, manual mapping preserved, bidirectional PTY transport')
    collector=work/'midi-helper'
    subprocess.run(['swiftc',str(root/'tests/midi-loopback.swift'),'-o',str(collector)],check=True)
    midi=subprocess.Popen([str(collector)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    assert midi.stdout.readline().strip()=='READY'
    details['midi']=wine([exe,'midi','ExeRunner Probe'])
    assert midi.stdout.readline().strip()=='RECEIVED 90 40 64','Native CoreMIDI did not receive note'
    midi.wait(timeout=5);passed.append('Windows WinMM MIDI output to a native virtual CoreMIDI endpoint')
    result={'passed':passed,'details':details,'work':str(work),'physical_USB_transfer':'not tested: no WinUSB test device','physical_print_job':'not sent'}
    (work/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
finally:
    if midi and midi.poll() is None:midi.terminate();midi.wait(timeout=5)
    for fd in fds:os.close(fd)
    subprocess.run([str(engine/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15)
    print('Evidence retained:',work)
