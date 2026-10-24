"""Hash-verified distributed source packet for scoped seeded formal replay.

The native91 inventory is historical provenance. This replay verifies the87
distributed inputs and image bytes, never reads or elaborates the4 omitted
vendor files, and does not establish mapped or vendor-implementation behavior.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
PUBLIC = HERE.parents[1]
SOURCE = PUBLIC / 'variants/seeded-sampling/hardware'
IMAGE_PATH = PUBLIC / 'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'
IMAGE = '0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
IMAGE_BYTES = 41202015
ASSEMBLY_SHA = '0dd7a437353ddd8c77728b820f752764c924ca7768dca80939384e5614d82112'
INVENTORY_SHA = '26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831'
DISTRIBUTED_SHA = '2c34ed9ddc4e48a36f4a13911bcd410b71d37416a3614caccfe5447b31df6ebd'
SOURCE_RECEIPT_SHA = '5771efaa0c144e8989190a3a2d8cbe5cc0663cace3f689d5f62e21c693972d67'
PROOF_SUPPORT_SHA = '110befc80bc3d8b0f58e3c0c1f0bdb46e2180c95b5d9a29838193cc570528a41'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(row): return (json.dumps(row, sort_keys=True, separators=(',', ':')) + '\n').encode()


def load_packet():
    support_raw = (HERE / 'proof-support.json').read_bytes()
    if sha(support_raw) != PROOF_SUPPORT_SHA: raise ValueError('Proof support inventory changed')
    for name, digest in json.loads(support_raw).items():
        path = PUBLIC / name
        if path.is_symlink() or not path.is_file() or sha(path.read_bytes()) != digest:
            raise ValueError('Proof support changed: ' + name)
    raw = (PUBLIC / 'variants/seeded-sampling/SOURCE.json').read_bytes()
    if sha(raw) != SOURCE_RECEIPT_SHA: raise ValueError('Seeded source receipt changed')
    receipt = json.loads(raw)
    inventory = json.loads((PUBLIC / 'host-app/hardware-inputs-seeded-sampling.json').read_text())
    if len(inventory) != 91 or sha(canonical(inventory)) != INVENTORY_SHA:
        raise ValueError('Historical91-input inventory changed')
    omitted = receipt['omitted_vendor_inputs']
    if len(omitted) != 4 or any(not name.startswith('project/official/') for name in omitted):
        raise ValueError('Unexpected omitted vendor boundary')
    if any(inventory.get(name) != digest for name, digest in omitted.items()):
        raise ValueError('Vendor provenance disagrees with91-input inventory')
    distributed = {name: digest for name, digest in inventory.items() if name not in omitted}
    if len(distributed) != 87 or sha(canonical(distributed)) != DISTRIBUTED_SHA:
        raise ValueError('Distributed87-input inventory changed')
    for name, digest in distributed.items():
        parts = PurePosixPath(name).parts
        if not parts or parts[0] not in ('project', 'run.tcl') or '..' in parts or PurePosixPath(name).is_absolute():
            raise ValueError('Unsafe source path')
        path = SOURCE / name
        if path.is_symlink() or not path.is_file() or sha(path.read_bytes()) != digest:
            raise ValueError('Distributed source changed: ' + name)
    if (receipt['source_assembly_receipt_sha256'] != ASSEMBLY_SHA or
        receipt['hardware_inputs_sha256'] != INVENTORY_SHA or
        receipt['image_sha256'] != IMAGE or receipt['image_bytes'] != IMAGE_BYTES):
        raise ValueError('Source/image provenance changed')
    if IMAGE_PATH.is_symlink() or IMAGE_PATH.stat().st_size != IMAGE_BYTES or sha(IMAGE_PATH.read_bytes()) != IMAGE:
        raise ValueError('Seeded image changed')
    return distributed, inventory, omitted


def source_inputs():
    """Return only distributed, byte-verified inputs; vendor paths are absent."""
    return load_packet()[0]


def source_binding():
    distributed, inventory, omitted = load_packet()
    return dict(schema='seeded-public-formal-source-binding-v1',
        distributed_inputs_verified=len(distributed), distributed_inventory_sha256=DISTRIBUTED_SHA,
        historical_native_inputs=len(inventory), historical_native_inventory_sha256=INVENTORY_SHA,
        source_assembly_receipt_sha256=ASSEMBLY_SHA, source_receipt_sha256=SOURCE_RECEIPT_SHA,
        proof_support_inventory_sha256=PROOF_SUPPORT_SHA,
        image_sha256=IMAGE, image_bytes=IMAGE_BYTES, image_bytes_verified=True,
        omitted_vendor_inputs=omitted, omitted_vendor_bytes_verified=False,
        vendor_logic_elaborated=False, whole_native91_byte_audit=False,
        scope='Exactly 87 distributed input files and the packaged FS image bytes verified. The historical 91-input association and four omitted vendor digests are provenance only. These source/component proofs do not elaborate or prove vendor blocks or establish mapped-image correspondence.')
