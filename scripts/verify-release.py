"""Validate the exact catalog, ZIP packages and browser files before publishing."""
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlparse
import zipfile

root = Path(__file__).resolve().parent.parent
output = root / 'dist'
expected = json.loads((root / 'modules.json').read_text())
catalog = json.loads((output / 'catalog.json').read_text())
assert set(catalog) == {'modules'}, 'Catalog must be plain JSON with modules'
assert [module['id'] for module in catalog['modules']] == expected, 'Catalog does not match modules.json'
assert (output / 'index.html').is_file() and (output / '.nojekyll').is_file()
for module in catalog['modules']:
    name = module['id']
    directory = output / name
    manifest = json.loads((directory / 'manifest.json').read_text())
    assert all(module[key] == value for key, value in manifest.items()), f'{name}: manifest mismatch'
    web_url, zip_url = urlparse(module['webUrl']), urlparse(module['downloadUrl'])
    assert web_url.scheme == zip_url.scheme == 'https'
    assert web_url.netloc == zip_url.netloc
    assert web_url.path.endswith(f'/{name}/')
    assert zip_url.path.endswith(f'/packages/{name}-{module["version"]}.zip')
    package = output / 'packages' / f'{name}-{module["version"]}.zip'
    data = package.read_bytes()
    assert len(data) == module['size'], f'{name}: size mismatch'
    assert hashlib.sha256(data).hexdigest() == module['sha256'], f'{name}: hash mismatch'
    files = {file.relative_to(directory).as_posix(): file.read_bytes() for file in directory.rglob('*') if file.is_file()}
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None, f'{name}: corrupt ZIP'
        assert len(archive.namelist()) == len(set(archive.namelist()))
        assert set(archive.namelist()) == set(files), f'{name}: ZIP and browser files differ'
        for entry in archive.infolist():
            assert entry.compress_type == zipfile.ZIP_STORED
            assert archive.read(entry.filename) == files[entry.filename]
    html = (directory / module['entry']).read_text()
    for asset in re.findall(r'(?:src|href)="([^"#]+)"', html):
        assert not asset.startswith(('http:', 'https:', '/')), f'{name}: entry asset must be relative: {asset}'
        assert (directory / asset).is_file(), f'{name}: missing entry asset: {asset}'
    print(f'PASS {name}: catalog, ZIP integrity, identical browser files and entry assets')
print('Release artifacts verified')
