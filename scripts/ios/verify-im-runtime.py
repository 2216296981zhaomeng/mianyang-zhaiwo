#!/usr/bin/env python3
"""Check embedded iOS Mach-O binaries and the Tencent IM runtime in an IPA."""
import pathlib
import struct
import sys
import zipfile

REFERENCE = b'@rpath/ImSDK_Plus.framework/ImSDK_Plus'
ARM64 = 0x0100000C
MAGICS = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce',
          b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'}


def check_macho(data, name):
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'):
        endian = '>' if magic[:1] == b'\xca' else '<'
        wide = magic in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
        count = struct.unpack_from(endian + 'I', data, 4)[0]
        if count != 1:
            raise ValueError(f'{name}: expected only arm64; fat binary has {count} slices')
        cpu = struct.unpack_from(endian + 'I', data, 8)[0]
        offset, size = struct.unpack_from(endian + ('QQ' if wide else 'II'), data, 16)
        if cpu != ARM64 or size == 0 or offset + size > len(data):
            raise ValueError(f'{name}: invalid or unsupported fat architecture 0x{cpu:x}')
        data = data[offset:offset + size]
    if len(data) < 32 or data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError(f'{name}: expected 64-bit little-endian iOS Mach-O')
    cpu = struct.unpack_from('<I', data, 4)[0]
    if cpu != ARM64:
        raise ValueError(f'{name}: unsupported architecture 0x{cpu:x}')
    ncmds, sizeofcmds = struct.unpack_from('<II', data, 16)
    end = 32 + sizeofcmds
    if end > len(data):
        raise ValueError(f'{name}: invalid Mach-O load commands')
    pos = 32
    encryption = []
    for _ in range(ncmds):
        if pos + 8 > end:
            raise ValueError(f'{name}: truncated Mach-O load command')
        cmd, length = struct.unpack_from('<II', data, pos)
        if length < 8 or pos + length > end:
            raise ValueError(f'{name}: malformed Mach-O load command')
        if cmd == 0x2c:
            if length < 24:
                raise ValueError(f'{name}: malformed encryption information')
            encryption.append(struct.unpack_from('<III', data, pos + 8))
        if cmd == 0x32 and (length < 24 or struct.unpack_from('<I', data, pos + 8)[0] != 2):
            raise ValueError(f'{name}: binary is not built for the iOS device platform')
        pos += length
    if len(encryption) != 1:
        raise ValueError(f'{name}: missing or duplicate LC_ENCRYPTION_INFO_64')
    offset, size, cryptid = encryption[0]
    if not size or not offset or offset + size > len(data) or cryptid != 0:
        raise ValueError(f'{name}: invalid or already-encrypted Mach-O information')


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        plugins = [n for n in names if n.endswith('/Frameworks/unimoduleZwTencentIm.framework/unimoduleZwTencentIm')]
        if len(plugins) != 1 or REFERENCE not in archive.read(plugins[0]):
            raise ValueError(f'{path}: Tencent IM plugin or runtime reference missing')
        runtime = plugins[0].split('/Frameworks/', 1)[0] + '/Frameworks/ImSDK_Plus.framework/ImSDK_Plus'
        if runtime not in names or archive.getinfo(runtime).file_size == 0:
            raise ValueError(f'{path}: missing {runtime}')
        count = 0
        for entry in archive.infolist():
            if entry.is_dir() or not entry.filename.startswith('Payload/'):
                continue
            with archive.open(entry) as stream:
                magic = stream.read(4)
            if magic in MAGICS:
                check_macho(archive.read(entry), entry.filename)
                count += 1
        if not count:
            raise ValueError(f'{path}: no Mach-O binaries found')
        print(f'{path}: Tencent IM runtime and {count} arm64 iOS Mach-O binaries verified')


if __name__ == '__main__':
    source = pathlib.Path(sys.argv[1])
    files = sorted(source.glob('*.ipa')) if source.is_dir() else [source]
    if not files:
        sys.exit(f'No IPA found in {source}')
    try:
        for ipa in files:
            verify(ipa)
    except (ValueError, OSError, struct.error, zipfile.BadZipFile) as error:
        sys.exit(str(error))
