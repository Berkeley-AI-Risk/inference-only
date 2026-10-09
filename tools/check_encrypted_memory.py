#!/usr/bin/env python3
"""Offline source/image/cryptographic-format checks for encrypted-memory.

No synthesis, simulation, network, board access or physical-security claim.
Full release verification separately protects every shipped source byte.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
INPUTS_SHA = '840c12ce7d1a5886966aca73e7c44eb3e42b9ee07ab33adcb2de3d273125e262'
PLAIN_SHA = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
CIPHER_SHA = '88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb'


def load(name,path):
    spec = importlib.util.spec_from_file_location(name,path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
def sha(raw): return hashlib.sha256(raw).hexdigest()
def require(ok,message):
    if not ok: raise ValueError(message)


def check_initial_board(data):
    require(data['schema']=='encrypted-memory-initial-board-v1' and data['passed'] is True
        and data['original_receipt_sha256']=='91c562c72ded33b93f8f5e9a5867f49f1a259b91af49f94c2b1a431b0de85424'
        and data['encrypted_image_sha256']=='32970712a318f605d5822bb7ac2234f080df15341103e0a78bad8863b5c9361e'
        and data['restored_image_sha256']=='e22079c855cdf6cfb983c73850db15b1b5010f0511fa62f98f3d040ae0654ea2'
        and data['ciphertext_sha256']==CIPHER_SHA, 'Wrong initial board association')
    require(data['prompt_tokens']==[378] and data['generated_tokens']==[200,15,103,157,200,15]
        and data['clear_replay'] is True and data['complete_flash_readback_and_restoration'] is True,
        'Wrong initial known-answer/restoration scope')
    for key in ('physical_secrecy_qualified','timing_qualified','configuration_independently_attested',
                'full_context_board_test','new_catalog_or_browser_test'):
        require(data[key] is False, 'Unsupported physical qualification')
    require(data['public_test_keys_only'] is True, 'Keys are not secret')
    a,b=data['encrypted_step_seconds'],data['restored_step_seconds']
    require(len(a)==len(b)==6 and all(type(x) in (float,int) and math.isfinite(x) and x>0 for x in a+b),
        'Invalid observed elapsed time')
    groups={'all_six_short_kat_steps':list(range(6)),
        'first_step_after_append_including_prefill':[0,4], 'subsequent_short_context_steps':[1,2,3,5]}
    require(set(data['matched_timing'])==set(groups), 'Missing short-KAT timing group')
    for name,indices in groups.items():
        row=data['matched_timing'][name]; x=sum(a[i] for i in indices); y=sum(b[i] for i in indices)
        require(row['indices']==indices and row['count']==len(indices), 'Wrong measurement indices')
        expected=dict(encrypted_seconds=x,restored_seconds=y,encrypted_tokens_per_second=len(indices)/x,
            restored_tokens_per_second=len(indices)/y,latency_ratio=x/y,retained_throughput_fraction=y/x)
        require(all(math.isclose(row[k],v,rel_tol=1e-12,abs_tol=1e-12) for k,v in expected.items()),
            'Initial board timing arithmetic differs')
    return 6


def check(package):
    package = Path(package)
    checked = load('release_verify',package/'tools/verify_release.py').verify(package)
    history = load('encrypted_history',package/'tools/encrypted_memory_history.py')
    history.previous_bytes(package,history.SOURCE,(package/history.SOURCE).read_bytes())
    inventory = json.loads((package/history.INVENTORY).read_bytes())
    canonical = (json.dumps(inventory,sort_keys=True,separators=(',',':'))+'\n').encode()
    require(len(inventory) == 100 and sha(canonical) == INPUTS_SHA, 'Wrong physical source set')
    hardware = package/'variants/encrypted-memory/hardware'
    project = hardware/'project'
    enabled = [item.attrib['path'] for item in ET.parse(project/'product.gprj').findall('./FileList/File')
        if item.attrib['type'] == 'file.verilog' and item.attrib['enable'] == '1']
    require(len(enabled) == 88 and len(set(enabled)) == 88
        and (project/'production_sources.f').read_text().splitlines() == enabled, 'Changed actual physical compilation')
    require(all('project/'+name in inventory for name in enabled), 'Uninventoried RTL')
    plain = (package/'assets/board1-real-semantic-image2048.bin').read_bytes()
    cipher = (package/'assets/board1-encrypted-model2048.bin').read_bytes()
    require(len(plain) == len(cipher) == 7265984 and sha(plain) == PLAIN_SHA and sha(cipher) == CIPHER_SHA,
        'Changed fixed image')
    # Digests cover each 4096-byte plaintext page, including zero extension of
    # the final 3776-byte page. The full ciphertext boot digest is separate.
    digests = ''.join((project/'digests32.memh').read_text().split())
    computed = ''.join(sha(plain[start:start+4096].ljust(4096,b'\0')) for start in range(0,len(plain),4096))
    require(digests == computed and len(computed)//64 == 1774, 'Plaintext page digest ROM differs')
    auth = project/'fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv'
    require(auth.read_text().count("256'h"+CIPHER_SHA) == 2, 'Boot digest is not fixed ciphertext identity')
    keys = json.loads((package/'variants/encrypted-memory/PUBLIC-TEST-KEYS.json').read_bytes())
    values = {'weight_aes256_key_hex':bytes(range(32)).hex(), 'weight_ctr_nonce_hex':'112233445566778899aabbcc',
        'kv_siv_mac_key_hex':bytes(range(64,96)).hex(), 'kv_siv_ctr_key_hex':bytes(range(96,128)).hex()}
    require(keys['schema'] == 'tang-public-test-keys-v1' and keys['secret'] is False
        and keys['irreversible_provisioning_authorized'] is False
        and keys['otp_fuse_security_lock_programming'] is False
        and all(keys.get(k) == v for k,v in values.items()), 'Wrong public test keys')
    token = (project/'shared_token_probe.sv').read_text()
    require(all(token.count(v) == 1 for v in values.values()), 'RTL key/nonce constants differ')
    require("256'h"+PLAIN_SHA in (project/'tang_private_kv_siv_role.sv').read_text(), 'Wrong SIV model association')
    for name in ('tang_private_kv_siv_bridge.sv','tang_private_kv_siv_role.sv','tang_private_aes256_fixed2.sv'):
        require((project/name).read_bytes().startswith(b'`define SYNTHESIS 1\n'), 'Actual physical source prefix differs')
    build = json.loads((package/'prebuilt/encrypted-memory/BUILD.json').read_bytes())
    require(build['public_test_keys_only'] is True and build['physical_secrecy_qualified'] is False
        and build['timing_qualified'] is False, 'Unsupported qualification claim')
    board=json.loads((package/'evidence/encrypted-memory/initial-board.json').read_bytes())
    initial_outputs=check_initial_board(board)
    native=json.loads((package/'evidence/encrypted-memory/native.json').read_bytes())
    require(native['schema']=='encrypted-memory-native-summary-v1' and native['passed'] is True
        and native['image_sha256']=='32970712a318f605d5822bb7ac2234f080df15341103e0a78bad8863b5c9361e'
        and all(native[k] is False for k in ('timing_qualified','phy_reset_contract_qualified','physical_secrecy_qualified')),
        'Wrong historical native evidence scope')
    require(native['inference_setup']['slack_ns']==0.280 and native['inference_hold']['slack_ns']==0.186
        and native['reported_summary']==dict(setup_violated_endpoints=145,hold_violated_endpoints=2,inference_fmax_mhz=25.176),
        'Changed timing report summary')
    broad = load('encrypted_board_evidence',package/'tools/check_encrypted_board_evidence.py').validate(
        json.loads((package/'evidence/encrypted-memory/broad-board.json').read_bytes()),package)
    require(broad['passed'] is True,'Broader board summary failed')
    return dict(passed=True,hardware_inputs=100,redistributed_inputs=96,vendor_inputs=4,enabled_rtl=88,
        initial_board_outputs=initial_outputs,broader_board_tests_complete=broad['passed'],
        page_digests_checked=1774,final_plaintext_page_bytes=3776,final_zero_padding_bytes=320,
        manifest_sha256=checked['manifest_sha256'],hardware_access=False,network_access=False,
        physical_secrecy_qualified=False,timing_qualified=False,
        scope='Current source/build association and cryptographic format; original encrypted board/timing records checked as historical evidence. Current board tests: check_speed_release.py.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(parser.parse_args().package),indent=2))
