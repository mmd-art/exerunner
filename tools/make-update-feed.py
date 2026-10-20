#!/usr/bin/env python3
"""Sign one already-verified release. Never exports the publisher's Keychain key."""
import argparse,plistlib,re,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--app',type=Path,required=True);p.add_argument('--dmg',type=Path,required=True);p.add_argument('--tag',required=True);p.add_argument('--sign-tool',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('updates/appcast.xml'));a=p.parse_args()
info=plistlib.loads((a.app/'Contents/Info.plist').read_bytes())
version=info['CFBundleShortVersionString']; build=info['CFBundleVersion']
if a.tag!=f'v{version}-alpha.1':raise SystemExit('Tag/version mismatch; review release channel before changing tag format')
if not re.fullmatch(r'[0-9.]+',build):raise SystemExit('Invalid build')
if info.get('SURequireSignedFeed') is not True or info.get('SUVerifyUpdateBeforeExtraction') is not True:raise SystemExit('Release must enforce signed feed/payload')
if info.get('SUPublicEDKey')!='H/EVor0z1CA9i7efFoYIWA+3XBz0AqtjQ3sEqOHwOIw=':raise SystemExit('Unexpected production public key')
cmd=[str(a.sign_tool),'--account','local.exerunner.app']
signature=subprocess.check_output(cmd+['-p',str(a.dmg)],text=True).strip()
namespace='http://www.andymatuschak.org/xml-namespaces/sparkle';ET.register_namespace('sparkle',namespace)
rss=ET.Element('rss',{'version':'2.0'});channel=ET.SubElement(rss,'channel');ET.SubElement(channel,'title').text='ExeRunner updates'
item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text='ExeRunner '+version+' alpha'
ET.SubElement(item,'link').text='https://github.com/mmd-art/exerunner/releases/tag/'+a.tag
for k,v in [('version',build),('shortVersionString',version),('minimumSystemVersion',info['LSMinimumSystemVersion'])]:ET.SubElement(item,'{'+namespace+'}'+k).text=v
ET.SubElement(item,'enclosure',{'url':f'https://github.com/mmd-art/exerunner/releases/download/{a.tag}/{a.dmg.name}','length':str(a.dmg.stat().st_size),'type':'application/octet-stream','{'+namespace+'}edSignature':signature})
a.output.parent.mkdir(parents=True,exist_ok=True);ET.indent(rss);ET.ElementTree(rss).write(a.output,encoding='utf-8',xml_declaration=True)
subprocess.run(cmd+[str(a.output)],check=True)
subprocess.run(cmd+['--verify',str(a.dmg),signature],check=True)
subprocess.run(cmd+['--verify',str(a.output)],check=True)
print('Verified signed feed:',a.output,'build:',build)
