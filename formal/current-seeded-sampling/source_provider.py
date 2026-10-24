"""Current87/image provenance for the original limited formal replay scope.

No omitted vendor file, changed numerical backend or production SHA is proved.
All constants remain unset until a chosen passed image has been reviewed.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
PUBLIC = HERE.parents[1]
SOURCE = PUBLIC / 'variants/seeded-sampling/hardware'
IMAGE_PATH = PUBLIC / 'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'
BINDING_SHA = 'c17060016035e92ec7c37382a5eb8b164fe7620601005749ba399087494f48f7'
IMAGE = 'd271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725'
IMAGE_BYTES = 42070540
ASSEMBLY_SHA = '0a3c8fa5498641374b1205f325f2bbedecd820bbeb8cc74d1d796292f61d4376'
INVENTORY_SHA = 'bd6979971359e5a18e0736ef5771ae9074ef9719d32e75970577eba9bb9d8c30'
DISTRIBUTED_SHA = '2aed505f6fd3428492b3addae554517c2c3b7e7f4852f23a9570432f0a53ca7b'
SOURCE_RECEIPT_SHA = 'b3e46bb79fe8d91cbc5bf0afe8a54eb13da477a38168d11f156bb1de8b2c190d'
PROOF_SUPPORT_SHA = '43d40dc466e5dff046a6df64bdd886582759ed5cf21eb06a7ddb421b6a6bcf51'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(row): return (json.dumps(row, sort_keys=True, separators=(',', ':')) + '\n').encode()


def safe(root, name):
    relative = PurePosixPath(name)
    if not relative.parts or relative.is_absolute() or '..' in relative.parts or '\\' in name:
        raise ValueError('Unsafe package path')
    path = root
    for part in relative.parts:
        path = path / part
        if path.is_symlink(): raise ValueError('Package symlink: ' + name)
    if not path.is_file(): raise ValueError('Missing package input: ' + name)
    return path


def pinned(name, row):
    raw = safe(PUBLIC, name).read_bytes()
    if type(row.get('bytes')) is not int or len(raw) != row['bytes'] or sha(raw) != row['sha256']:
        raise ValueError('Current input changed: ' + name)
    return raw


def load_packet():
    if any(value is None for value in (BINDING_SHA, IMAGE, IMAGE_BYTES, ASSEMBLY_SHA,
            INVENTORY_SHA, DISTRIBUTED_SHA, SOURCE_RECEIPT_SHA, PROOF_SUPPORT_SHA)):
        raise ValueError('Current chosen-image formal authority is pending')
    raw = safe(HERE, 'CURRENT-BINDING.json').read_bytes()
    if sha(raw) != BINDING_SHA: raise ValueError('Current formal binding changed')
    current = json.loads(raw)
    if current['schema'] != 'current-seeded-formal-capsule-binding-v1': raise ValueError('Binding schema changed')
    for name, row in current['package_inputs'].items(): pinned(name, row)
    support_raw = safe(HERE, 'proof-support.json').read_bytes()
    if sha(support_raw) != PROOF_SUPPORT_SHA: raise ValueError('Proof support inventory changed')
    for name, digest in json.loads(support_raw).items():
        if sha(safe(PUBLIC, name).read_bytes()) != digest: raise ValueError('Proof support changed: ' + name)
    receipt_raw = safe(PUBLIC, 'variants/seeded-sampling/SOURCE.json').read_bytes()
    if sha(receipt_raw) != SOURCE_RECEIPT_SHA: raise ValueError('Current source receipt changed')
    receipt = json.loads(receipt_raw)
    inventory = json.loads(safe(PUBLIC, 'host-app/hardware-inputs-seeded-sampling.json').read_bytes())
    if len(inventory) != 91 or sha(canonical(inventory)) != INVENTORY_SHA: raise ValueError('Current native91 inventory changed')
    omitted = receipt['omitted_vendor_inputs']
    if len(omitted) != 4 or any(not name.startswith('project/official/') for name in omitted):
        raise ValueError('Unexpected omitted vendor boundary')
    if any(inventory.get(name) != digest for name, digest in omitted.items()): raise ValueError('Omitted vendor provenance changed')
    distributed = {name: digest for name, digest in inventory.items() if name not in omitted}
    if len(distributed) != 87 or sha(canonical(distributed)) != DISTRIBUTED_SHA:
        raise ValueError('Current distributed87 inventory changed')
    for name, digest in distributed.items():
        if PurePosixPath(name).parts[0] not in ('project', 'run.tcl'): raise ValueError('Unsafe native input')
        if sha(safe(SOURCE, name).read_bytes()) != digest: raise ValueError('Distributed source changed: ' + name)
    if (receipt['hardware_inputs_sha256'] != INVENTORY_SHA or receipt['image_sha256'] != IMAGE or
        receipt['image_bytes'] != IMAGE_BYTES or receipt['model_assembly_receipt_sha256'] != ASSEMBLY_SHA):
        raise ValueError('Current source/image/model provenance changed')
    image = safe(PUBLIC, str(IMAGE_PATH.relative_to(PUBLIC))).read_bytes()
    if len(image) != IMAGE_BYTES or sha(image) != IMAGE: raise ValueError('Current selected image changed')
    if current['image_sha256'] != IMAGE or current['native_inventory_sha256'] != INVENTORY_SHA:
        raise ValueError('Current chosen-image binding mismatch')
    if current['current_solver_replay_passed'] is not False or current['qualification_inherited'] is not False:
        raise ValueError('Construction binding cannot grant replay or qualification')
    return distributed, inventory, omitted


def source_inputs(): return load_packet()[0]


def source_binding():
    distributed, inventory, omitted = load_packet()
    current = json.loads(safe(HERE, 'CURRENT-BINDING.json').read_bytes())
    return dict(schema='current-seeded-public-formal-source-binding-v1',
        distributed_inputs_verified=len(distributed), distributed_inventory_sha256=DISTRIBUTED_SHA,
        current_native_inputs=len(inventory), current_native_inventory_sha256=INVENTORY_SHA,
        source_assembly_receipt_sha256=ASSEMBLY_SHA, source_receipt_sha256=SOURCE_RECEIPT_SHA,
        proof_support_inventory_sha256=PROOF_SUPPORT_SHA, current_binding_sha256=BINDING_SHA,
        retained_scope_association=current['retained_scope_association'], source_delta_disclosure=current['source_delta_disclosure'],
        image_sha256=IMAGE, image_bytes=IMAGE_BYTES, image_bytes_verified=True,
        omitted_vendor_inputs=omitted, omitted_vendor_bytes_verified=False,
        vendor_logic_elaborated=False, whole_native91_byte_audit=False,
        sha_compression_arithmetic_proved=False, whole_machine_refinement=False,
        scope='Current87 distributed files and selected FS bytes verified as provenance. The original scoped selector/control proofs retain their cuts and limits. Changed private numerical logic and production SHA are not proved; native91 includes four omitted vendor digests only.')
