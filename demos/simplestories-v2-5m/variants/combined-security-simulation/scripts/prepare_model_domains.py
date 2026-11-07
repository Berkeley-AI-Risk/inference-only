"""Extend the inherited fixed-model SIV domain to the two bound test models.

Real AES/SIV logic stays unchanged. Parameterize its existing MODEL_ID constant
and select the checked full-image SHA with each private test-vault key tuple.
"""
from pathlib import Path
import hashlib,json,shutil,sys
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from prepare import replace,slot_wrapper,KEYS
from pin_sources import sha

def main():
    source=HERE/'prepared-v1/source';out=HERE/'prepared-model-domains-v2';out.mkdir(exist_ok=False)
    target=out/'source';shutil.copytree(source,target)
    fixtures=json.loads((HERE/'fixtures-v1/FIXTURES.json').read_text())
    default="256'hcad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0"
    role=target/'tang_private_kv_siv_role.sv';before_role=role.read_text()
    role_param='    parameter [255:0] MAC_KEY=256\'d0,\n    parameter [255:0] CTR_KEY=256\'d0'
    # Both public revisions of this header are recognized explicitly.
    if role_param not in before_role:raise ValueError('Unexpected SIV role parameter header')
    new_param=role_param+',\n    parameter [255:0] MODEL_ID='+default
    constant='    localparam [255:0] MODEL_ID='+default+';\n'
    after_role=replace(replace(before_role,role_param,new_param),constant,'')
    if replace(replace(after_role,new_param,role_param),'    localparam [4:0] PRE_L=',constant+'    localparam [4:0] PRE_L=')!=before_role:raise ValueError('Role declaration inverse differs')
    role.write_text(after_role)
    bridge=target/'tang_private_kv_siv_bridge.sv';before_bridge=bridge.read_text()
    seam='    parameter integer DDR_TIMEOUT_CYCLES=50000000'
    new_seam='    parameter [255:0] MODEL_ID='+default+',\n'+seam
    call='.MAC_KEY(MAC_KEY),.CTR_KEY(CTR_KEY)) u_codec ('
    new_call='.MAC_KEY(MAC_KEY),.CTR_KEY(CTR_KEY),.MODEL_ID(MODEL_ID)) u_codec ('
    after_bridge=replace(replace(before_bridge,seam,new_seam),call,new_call)
    if replace(replace(after_bridge,new_seam,seam),new_call,call)!=before_bridge:raise ValueError('Bridge declaration inverse differs')
    bridge.write_text(after_bridge)
    slots=[{'KEY_IS_PROVISIONED':"1'b1",'MAC_KEY':"256'h"+KEYS['mac'+m],'CTR_KEY':"256'h"+KEYS['ctr'+m],
            'MODEL_ID':"256'h"+fixtures['models'][m]['image_sha256']} for m in 'AB']
    wrapper=target/'combined_kv_cipher.sv'
    wrapper.write_text(slot_wrapper(after_bridge,'combined_kv_cipher','',slots))
    result={'prepared_only':True,'A_checkpoint_preserved':True,'native_case_started':False,'same_full_AES_SIV_algorithm':True,'declaration_and_plumbing_inverse_byte_exact':True,
        'model_domains':{m:{'admitted_root':fixtures['models'][m]['model_commitment'],'SIV_MODEL_ID':fixtures['models'][m]['image_sha256'],'key_domain':i+1,'public_demo_keys':True} for i,m in enumerate('AB')},
        'changed_files':{n:{'before_sha256':sha(source/n),'after_sha256':sha(target/n)} for n in ('tang_private_kv_siv_role.sv','tang_private_kv_siv_bridge.sv','combined_kv_cipher.sv')},
        'scope':'Existing MODEL_ID constant becomes a parameter. A retains its original full-image identity; B gets its own checked image identity and distinct key tuple. No host-selected ID/key.'}
    (out/'MODEL-DOMAIN-BINDINGS.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('PREPARED_MODEL_DOMAINS; no native job')
if __name__=='__main__':main()
