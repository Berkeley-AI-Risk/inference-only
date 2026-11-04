"""Independently decode every fixed norm ROM word from the named model image.

Finite artifact equality, separate from the unbounded RTL proof. No image
builder or numerical oracle is imported. Offsets/packing follow MODEL-IMAGE.md.
"""
from pathlib import Path
import re

from prepare import HERE, CAMPAIGN, PUBLIC, ROM, sha, verify_inventory, write_json

IMAGE_SHA='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
IMAGE_NAME='board1-real-semantic-image2048.bin'


def validate():
    verify_inventory()
    candidates=[PUBLIC.parent.parent/'assets'/IMAGE_NAME]
    image_path=next(path for path in candidates if path.is_file())
    image=image_path.read_bytes()
    if len(image)!=7265984 or sha(image)!=IMAGE_SHA:raise ValueError('Wrong fixed model image')
    text=(HERE/'project'/ROM).read_text()
    text=re.sub(r'/\*[\s\S]*?\*/|//[^\n]*','',text)
    words=[int(word,16) for word in text.split()]
    if len(words)!=13*256 or any(word>=1<<34 for word in words):raise ValueError('ROM geometry changed')
    banks=[]
    for role in range(13):
        coefficient_base=6777600+role*320 if role<12 else 6856000
        metadata_base=6855936+role*4 if role<12 else 6856320
        exponent=image[metadata_base]
        multiplier=int.from_bytes(image[metadata_base+1:metadata_base+3],'little')
        for row in range(256):
            bit=row*10;offset=coefficient_base+bit//8
            coefficient=(int.from_bytes(image[offset:offset+2],'little')>>(bit%8))&1023
            expected=coefficient|(multiplier<<10)|(exponent<<26)
            if words[role*256+row]!=expected:
                raise ValueError('Model/ROM mismatch at role '+str(role)+' row '+str(row))
        banks.append(dict(role=role,coefficient_byte=coefficient_base,metadata_byte=metadata_base,rows=256))
    return dict(schema='RMSNorm-model-ROM-binding-v1',passed=True,finite_artifact_check=True,
        model_image_sha256=IMAGE_SHA,model_image_bytes=len(image),model_image_path=str(image_path),
        norm_rom_sha256=sha((HERE/'project'/ROM).read_bytes()),words_compared=len(words),banks=banks,
        packing='Four little-endian signed int10 coefficients per five bytes; ROM coefficient[9:0], multiplier[25:10], exponent[33:26].',
        runtime_DDR_model_consumption_proved=False,independent_numerical_oracle_theorem=False)


if __name__=='__main__':
    result=validate();write_json(HERE/'MODEL-ROM-BINDING.json',result)
    print('Fixed model image agrees with all',result['words_compared'],'norm ROM words in all 13 role banks.')
