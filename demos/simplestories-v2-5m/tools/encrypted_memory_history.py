"""Exact inverse of the additive catalog edit, for historical evidence only.

Old receipts still check their original host bytes. This does not relabel an
old board/app test as a test of the new encrypted-memory profile.
"""
import hashlib
import importlib.util
import json
from pathlib import Path

SOURCE = 'host-app/runtime_profile.py'
BEFORE = '8deb6ba53fbdbee046fe98c0572e5fc261366457bf89f24d903f6174c41a3fc4'
INVENTORY = 'host-app/hardware-inputs-encrypted-memory.json'
INPUTS_SHA = 'd2f75e9b1425bc82b712569b7ea754c3fdc9116fa2460ebffac6d6dc1ad26ba6'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def require(ok, message):
    if not ok: raise ValueError(message)


def previous_bytes(package, name, raw):
    """First undo the speed revision, then the additive encrypted catalog."""
    path = Path(package)/'tools/speed_release_history.py'
    spec = importlib.util.spec_from_file_location('speed_history',path)
    speed = importlib.util.module_from_spec(spec); spec.loader.exec_module(speed)
    raw = speed.previous_bytes(package,name,raw)
    if name != SOURCE: return raw
    package = Path(package)
    record = json.loads((package/'evidence/encrypted-memory/catalog-revision.json').read_bytes())
    require(record['schema'] == 'encrypted-memory-catalog-revision-v1'
        and record['source'] == SOURCE and record['before_sha256'] == BEFORE
        and record['added_host_inventory'] == INVENTORY
        and record['new_physical_app_test'] is False, 'Wrong catalog history')
    inventory_raw = speed.previous_bytes(package,INVENTORY,(package/INVENTORY).read_bytes())
    inventory = json.loads(inventory_raw)
    canonical = (json.dumps(inventory,sort_keys=True,separators=(',',':'))+'\n').encode()
    require(len(inventory) == 98 and sha(canonical) == INPUTS_SHA
        and sha(inventory_raw) == record['inventory_sha256'], 'Changed added inventory')
    expected = ("    'encrypted-memory': {\n        'label': 'Encrypted external memory (public test keys)',\n"
        "        'inventory': 'hardware-inputs-encrypted-memory.json',\n        'hardware_root': 'variants/encrypted-memory/hardware',\n"
        f"        'inputs_sha256': '{INPUTS_SHA}', 'input_files': 98,\n    }},\n")
    old_error = 'choose baseline or kv-protected.'
    new_error = 'choose baseline, kv-protected or encrypted-memory.'
    require(record['insertion'] == expected and record['old_error'] == old_error
        and record['new_error'] == new_error and sha(raw) == record['after_sha256'],
        'Changed catalog revision')
    text = raw.decode()
    require(text.count('VARIANTS = {\n'+expected) == 1 and text.count(new_error) == 1,
        'Ambiguous catalog inverse')
    result = text.replace('VARIANTS = {\n'+expected,'VARIANTS = {\n',1).replace(new_error,old_error,1).encode()
    require(sha(result) == BEFORE, 'Catalog inverse did not recover original host source')
    return result
