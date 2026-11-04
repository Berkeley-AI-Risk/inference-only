"""Bind immutable model-service metadata and expected page digests to I0.

This finite data check is not a theorem about returned runtime DDR values or
about the RTL SHA implementation. Those producer connections remain open.
"""
from pathlib import Path
import hashlib
import json

from check_model_rom import validate as norm_binding
from prepare import HERE, PROJECT, PUBLIC, BINDING, sha, write_json


def main():
    norm=norm_binding();image=Path(norm['model_image_path']).read_bytes()
    pins=json.loads(BINDING.read_text())['binding']['native_join']['distributed_inputs']
    data={}
    for name in ['metadata192.memh','digests32.memh']:
        raw=(PROJECT/name).read_bytes()
        if sha(raw)!=pins['project/'+name] or sha((PUBLIC/name).read_bytes())!=sha(raw):
            raise ValueError('Model-service table identity mismatch')
        data[name]=dict(sha256=sha(raw),words=[int(x,16) for x in raw.decode().split()])
    metadata=data['metadata192.memh']['words']
    if len(metadata)!=2328:raise ValueError('Metadata geometry changed')
    for index,packed in enumerate(metadata):
        expanded=sum(((packed>>(24*lane))&0xffffff)<<(32*lane) for lane in range(8))
        expected=int.from_bytes(image[6781440+index*32:6781440+(index+1)*32],'little')
        if packed>=1<<192 or expanded!=expected:raise ValueError('Wrong metadata at '+str(index))
    digests=data['digests32.memh']['words'];pages=(len(image)+4095)//4096
    if len(digests)!=pages*8 or any(x>=1<<32 for x in digests):raise ValueError('Digest geometry changed')
    for page in range(pages):
        payload=image[page*4096:(page+1)*4096].ljust(4096,b'\0')
        expected=int.from_bytes(hashlib.sha256(payload).digest(),'big')
        actual=sum(digests[page*8+i]<<(32*(7-i)) for i in range(8))
        if actual!=expected:raise ValueError('Wrong expected digest at page '+str(page))
    result=dict(schema='Fixed-model-service-table-binding-v1',passed=True,finite_artifact_check=True,
        model_image_sha256=norm['model_image_sha256'],metadata_words_compared=len(metadata),
        metadata_source_byte=6781440,metadata_reserved_bytes_reconstructed_zero=True,
        page_digests_compared=pages,page_bytes=4096,last_page_zero_tail=True,
        tables={k:{'sha256':v['sha256'],'words':len(v['words'])} for k,v in data.items()},
        runtime_operand_consumption_proved=False,RTL_SHA256_correspondence_proved=False)
    write_json(HERE/'MODEL-TABLE-BINDING.json',result)
    print('Bound',len(metadata),'expanded metadata words and',pages,'expected page digests to the fixed model image.')


if __name__=='__main__':main()
