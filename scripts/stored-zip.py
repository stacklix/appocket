"""Deterministic, regular-file-only ZIP_STORED packages understood by the host."""
from pathlib import Path
import sys
import zipfile
source, target = map(Path, sys.argv[1:])
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_STORED) as archive:
    for file in sorted(source.rglob('*')):
        if file.is_symlink():
            raise ValueError('Symlinks are not allowed')
        if not file.is_file():
            continue
        info = zipfile.ZipInfo(file.relative_to(source).as_posix(), date_time=(2020,1,1,0,0,0))
        info.external_attr = 0o100644 << 16
        archive.writestr(info, file.read_bytes())
