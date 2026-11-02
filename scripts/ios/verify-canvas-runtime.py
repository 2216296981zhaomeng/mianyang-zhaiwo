#!/usr/bin/env python3
"""Reject an iOS IPA that lacks the Vapor canvas implementation or engine."""
import pathlib
import re
import sys
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        roots = [name[:-len('Info.plist')] for name in names
                 if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
        if len(roots) != 1:
            raise ValueError('Expected exactly one app in IPA')
        root = roots[0] + 'Frameworks/'
        plugin = root + 'unimoduleDcloudUniCanvasDom2.framework/unimoduleDcloudUniCanvasDom2'
        engine = root + 'DCloudUniCanvas.framework/DCloudUniCanvas'
        for name in (plugin, engine):
            if name not in names or archive.getinfo(name).file_size == 0:
                raise ValueError(f'Missing canvas framework: {name}')
        binary = archive.read(plugin)
        for marker in (b'UTSSDKModulesDCloudUniCanvasDom2UniNativeCanvasByJs',
                       b'UniCanvasElementRegister', b'ZWCanvasBootstrap',
                       b'@rpath/DCloudUniCanvas.framework/DCloudUniCanvas'):
            if marker not in binary:
                raise ValueError(f'Canvas implementation missing marker: {marker.decode()}')
        print(f'{path}: canvas framework, registration and engine verified')


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
