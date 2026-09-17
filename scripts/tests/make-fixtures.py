from pathlib import Path
import json,sys,zipfile
root=Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
base=json.loads(Path('sentra/manifest.json').read_text())
for name,version in [('valid','1.1.0'),('newer','1.2.0')]:
    with zipfile.ZipFile(root/f'{name}.zip','w',compression=zipfile.ZIP_STORED) as archive:
        archive.writestr('manifest.json',json.dumps({**base,'version':version}))
        archive.writestr('index.html','<!doctype html><html><head></head><body>test</body></html>')
for name,entry,compression in [('traversal','../escape',zipfile.ZIP_STORED),('absolute','/escape',zipfile.ZIP_STORED),('compressed','index.html',zipfile.ZIP_DEFLATED)]:
    with zipfile.ZipFile(root/f'{name}.zip','w',compression=compression) as archive:archive.writestr(entry,'bad')
with zipfile.ZipFile(root/'symlink.zip','w') as archive:
    info=zipfile.ZipInfo('link');info.external_attr=0o120777 << 16;archive.writestr(info,'/tmp/escape')
(root/'truncated.zip').write_bytes((root/'valid.zip').read_bytes()[:45])
builtin=root/'builtin'/'sentra';builtin.mkdir(parents=True,exist_ok=True)
(builtin/'manifest.json').write_text(json.dumps(base));(builtin/'index.html').write_text('builtin')
