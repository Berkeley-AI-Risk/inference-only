"""Check that the README JPEG has no embedded personal metadata or trailer.

Only a minimal JFIF format header (no thumbnail) is allowed among application
and comment segments. EXIF/GPS, XMP, ICC, IPTC, maker notes and trailing bytes
are rejected. This checks JPEG structure, not steganography or visible content.
"""
import argparse
import hashlib
import json
from pathlib import Path


def check(path):
    data = path.read_bytes()
    if data[:2] != b'\xff\xd8':
        raise ValueError('Not a JPEG')
    offset, scans, ended = 2, 0, False
    headers = []
    dimensions = None
    while offset < len(data):
        if data[offset] != 255:
            raise ValueError('Invalid JPEG marker boundary')
        while offset < len(data) and data[offset] == 255:
            offset += 1
        if offset >= len(data):
            raise ValueError('Truncated JPEG marker')
        marker = data[offset]
        offset += 1
        if marker == 0xd9:
            if offset != len(data):
                raise ValueError('Trailing data after JPEG end')
            ended = True
            break
        if marker == 0x01 or 0xd0 <= marker <= 0xd7:
            continue
        if offset + 2 > len(data):
            raise ValueError('Truncated JPEG segment')
        size = int.from_bytes(data[offset:offset+2], 'big')
        if size < 2 or offset + size > len(data):
            raise ValueError('Invalid JPEG segment size')
        payload = data[offset+2:offset+size]
        offset += size
        if 0xe0 <= marker <= 0xef or marker == 0xfe:
            if not (marker == 0xe0 and payload[:5] == b'JFIF\0' and
                    len(payload) == 14 and payload[-2:] == b'\0\0'):
                raise ValueError(f'Embedded metadata/comment segment FF{marker:02X}')
            headers.append('minimal JFIF format header; no thumbnail')
        if marker in (0xc0, 0xc1, 0xc2):
            if len(payload) < 6:
                raise ValueError('Invalid image frame')
            dimensions = [int.from_bytes(payload[3:5], 'big'),
                          int.from_bytes(payload[1:3], 'big')]
        if marker == 0xda:
            scans += 1
            while True:
                boundary = data.find(b'\xff', offset)
                if boundary < 0:
                    raise ValueError('Unterminated image scan')
                end = boundary + 1
                while end < len(data) and data[end] == 255:
                    end += 1
                if end >= len(data):
                    raise ValueError('Truncated image scan')
                if data[end] == 0 or 0xd0 <= data[end] <= 0xd7:
                    offset = end + 1
                    continue
                offset = boundary
                break
    if not ended or scans == 0 or dimensions is None:
        raise ValueError('Incomplete JPEG')
    return {'passed': True, 'sha256': hashlib.sha256(data).hexdigest(),
            'bytes': len(data), 'dimensions': dimensions, 'scans': scans,
            'retained_format_headers': headers,
            'exif_gps_xmp_iptc_icc_comments': 'absent', 'trailing_data': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('photo', nargs='?', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'fpga.jpeg')
    print(json.dumps(check(parser.parse_args().photo), indent=2))
