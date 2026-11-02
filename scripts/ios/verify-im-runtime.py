#!/usr/bin/env python3
"""Reject an IPA whose Tencent IM plugin references a missing runtime."""
import pathlib
import sys
import zipfile

REFERENCE = b'@rpath/ImSDK_Plus.framework/ImSDK_Plus'


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        plugins = [name for name in names if name.endswith('/Frameworks/unimoduleZwTencentIm.framework/unimoduleZwTencentIm')]
        for plugin in plugins:
            if REFERENCE not in archive.read(plugin):
                continue
            app_root = plugin.split('/Frameworks/', 1)[0]
            runtime = app_root + '/Frameworks/ImSDK_Plus.framework/ImSDK_Plus'
            if runtime not in names or archive.getinfo(runtime).file_size == 0:
                raise ValueError(f'{path}: {plugin} references missing {runtime}')
        print(f'{path}: Tencent IM runtime dependency check passed')


if __name__ == '__main__':
    source = pathlib.Path(sys.argv[1])
    files = sorted(source.glob('*.ipa')) if source.is_dir() else [source]
    if not files:
        sys.exit(f'No IPA found in {source}')
    try:
        for ipa in files:
            verify(ipa)
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
