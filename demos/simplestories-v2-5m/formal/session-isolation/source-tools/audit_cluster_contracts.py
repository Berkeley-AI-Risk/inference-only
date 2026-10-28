"""Join native cluster/tile permissions, read owners and primitive contracts.

This is a source/receipt audit. It records how the independently closed
contracts fit, without claiming a newly assembled subsystem solver theorem.
"""
import json
from pathlib import Path

from record_progress import audit, sha
from run_attention_ownership import HERE
from run_projection_relational import instance_con
from audit_semantic_permissions import dense
from audit_proof_instantiations import body
from audit_header_congruence import PURE


def stateless_native_function(variant, module, opaque):
    run={'baseline':'native-hierarchy-r1','seeded-sampling':'native-hierarchy-seeded-sampling-r1',
        'kv-protected':'native-hierarchy-kv-protected-r1','encrypted-memory':'native-hierarchy-encrypted-memory-r4'}[variant]
    root=HERE/'runs'/run;raw=(root/'hierarchy.json').read_bytes()
    if sha(raw)!=opaque['variants'][variant]['native_hierarchy_sha256']:raise ValueError('Native hierarchy changed')
    modules=json.loads(raw)['modules'];census=json.loads((root/'CENSUS.json').read_text())
    instances=[r for r in census['instances']if r['original_module']==module]
    if not instances:raise ValueError('Native stateless function is not instantiated')
    checked={};active=set()
    def check(name):
        if name in checked:return
        if name in active or name not in modules:raise ValueError('Recursive or opaque arithmetic function')
        active.add(name);g=modules[name];drivers={}
        inputs={b for p in g['ports'].values()if p['direction']=='input'for b in p['bits']if isinstance(b,int)}
        for cell_name,cell in g['cells'].items():
            if cell['type']not in PURE:check(cell['type'])
            for port,bits in cell['connections'].items():
                if cell['port_directions'][port]=='output':
                    for bit in bits:
                        if isinstance(bit,int):drivers.setdefault(bit,set()).add(cell_name)
        visited=set();busy=set()
        def bit_cone(bit):
            if isinstance(bit,str):
                if bit not in('0','1'):raise ValueError('Unknown stateless constant')
                return
            if bit in inputs or bit in visited:return
            if bit in busy or len(drivers.get(bit,set()))!=1:raise ValueError('Undriven or cyclic stateless function bit')
            busy.add(bit);cell=g['cells'][next(iter(drivers[bit]))]
            for port,bits in cell['connections'].items():
                if cell['port_directions'][port]=='input':
                    for value in bits:bit_cone(value)
            busy.remove(bit);visited.add(bit)
        for port in g['ports'].values():
            if port['direction']=='output':
                for bit in port['bits']:bit_cone(bit)
        active.remove(name);checked[name]=dict(cell_types=sorted({r['type']for r in g['cells'].values()}),
            graph_sha256=sha(json.dumps(g,sort_keys=True).encode()))
    for row in instances:check(row['module'])
    return dict(instances=len(instances),checked_module_graphs=checked,storage_or_opaque_cells=0,
        claim='Same-input congruence of the actual finite combinational RTL; no numerical-accuracy theorem is inferred')


def main():
    cases={
        'parallel':dict(parent='cluster-parent-parallel-r4',tile='tile-parent-parallel-r3',
            caller='cluster-reply-ownership-r2',variants={'baseline','seeded-sampling'}),
        'serial':dict(parent='cluster-parent-serial-r2',tile='tile-parent-serial-r2',
            caller='serial-cluster-reply-ownership-r1',variants={'kv-protected','encrypted-memory'}),
    }
    joins=json.loads((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_text())
    opaque=json.loads((HERE/'OPAQUE-STATE-AUDIT.json').read_text())
    if not joins['instantiation_audit_passed']or not opaque['configuration_audit_passed']:
        raise ValueError('Native instance/primitive configuration association incomplete')
    results={}
    for kind,case in cases.items():
        roots={k:HERE/'runs'/case[k]for k in('parent','tile','caller')}
        receipts={k:audit(case[k],'cluster contract prerequisite')for k in roots}
        if any(r['status']!='proved_component'for r in receipts.values()):raise ValueError('An input proof is incomplete')
        inputs={k:json.loads((root/'INPUTS.json').read_text())for k,root in roots.items()}
        parent,tile,caller=[roots[k]for k in('parent','tile','caller')]
        if(parent/'production-cluster.sv').read_bytes()!=(caller/'production-cluster.sv').read_bytes():
            raise ValueError('Actual cluster source differs')
        if(tile/'production-tile.sv').read_bytes()!=(caller/'production-tile.sv').read_bytes():
            raise ValueError('Actual tile source differs')
        if any(inputs[k]['binding']['initial_hard_reset']for k in roots):raise ValueError('A cluster prerequisite assumes hard reset')
        tb=inputs['tile']['binding'];pb=inputs['parent']['binding'];cb=inputs['caller']['binding']
        if not cb['selected_tile_registered_reply_ownership']:raise ValueError('Selected reply permission missing')
        if dense('wire f_rel_permission='+tb['caller_permissions']+';')not in dense((caller/'tile-monitor.inc.sv').read_text()):
            raise ValueError('Actual caller did not prove the exact tile protocol')
        cm=dense((caller/'tile-monitor.inc.sv').read_text())
        if 'always@*if(reset_n&&f_clear_seen_i)beginassert(f_rel_permission);'not in cm:
            raise ValueError('Caller permission is not an unconditional post-CLEAR assertion')
        # Prefix contains the exact cancel/first-product/accumulator and
        # registered metadata-history observer writers; only assertion guards
        # and additional nondriving taps differ later in the two proof scopes.
        def writer(root):return dense((root/'tile-monitor.inc.sv').read_text().split('    always @*if(',1)[0])
        if writer(tile)!=writer(caller):raise ValueError('Tile epoch/read-history observer writers differ')
        pm=dense((caller/'parent-monitor.inc.sv').read_text())
        required='if(scale_valid_q[0]&&state_q==EMIT&&row_pipe_q[0]==f_row)beginassert(selected_tile_q==f_row[5:4]);assert(f_tile_md_target[selected_tile_q]);assert(f_tile_dot_target[selected_tile_q]);end'
        if required not in pm:raise ValueError('Selected phase-0 metadata/dot reply ownership absent')
        if pb['selected_tile_data_reply_condition']!='live, EMIT, scale_valid[0], and selected tile index; other registered reply lanes independent':
            raise ValueError('Parent tile-reply coupling condition changed')
        raw=(parent/'production-cluster.sv').read_text()
        con=instance_con(raw,'board1_projection_tile16','u_tile')
        actual=pb['actual_tile_inputs']
        if set(actual)!=set(k for k in con if k not in('dot_o','multiplier_o','exponent_o','done_o','fault_o')):
            raise ValueError('Incomplete actual tile input inventory')
        for port,row in actual.items():
            if row['expression']!=con[port]:raise ValueError('Actual native tile connection differs')
        for port,guard in tb['operand_coupling_predicates'].items():
            if port=='f_mac_reply_i':continue
            expected=con[guard]if guard in con else guard
            if dense(actual[port]['guard'])!=dense(expected):raise ValueError('Parent does not meet tile input coupling: '+port)
        if actual['first_i']['guard']!='1'or 'first_i'in tb['operand_coupling_predicates']:
            raise ValueError('Native registered-MAC first control must agree even outside accumulation')
        if tb['per_field_relation']['op_first_q']!='1'or tb['per_field_relation']['product_first_q']!='1':
            raise ValueError('First pipeline tags are not compared unconditionally')
        for copy in('u_a','u_b'):
            graph=json.loads((tile/'elaborated.json').read_text())['modules']['tile_parent_relational']
            for memory,word_width in [('multiplier_q',16),('exponent_q',8)]+([('g_lane[0].accumulator_q',35)]if kind=='serial'else[]):
                cell=graph['cells'].get(copy+'.'+memory)
                if not cell or cell['type']!='$mem_v2':raise ValueError('Independent native tile memory missing')
                params=cell['parameters']
                if int(params['SIZE'],2)!=16 or int(params['WIDTH'],2)!=word_width or any(b in'01'for b in params['INIT']):
                    raise ValueError('Native memory resized or initialized in the tile proof')
        for instance,connections in pb['actual_postscale_inputs'].items():
            original=instance_con(raw,'board1_projection_postscale_mul',instance)
            if connections!=original:raise ValueError('Native postscale connection differs')
        if kind=='parallel':
            mac=HERE/'runs/projection-mac-r1';mr=audit(mac.name,'registered-MAC recurrence prerequisite')
            if mr['status']!='proved_component':raise ValueError('MAC recurrence lemma incomplete')
            if body((mac/'production-tile.sv').read_bytes(),'board1_projection_dsp_accumulator')!=body((tile/'production-tile.sv').read_bytes(),'board1_projection_dsp_accumulator'):
                raise ValueError('Native registered MAC implementation/configuration differs')
            native=body((tile/'production-tile.sv').read_bytes(),'board1_projection_tile16').decode()
            mc=instance_con(native,'board1_projection_dsp_accumulator','u_mac')
            expected=dict(clk='clk',multiply_i='op_valid_q',accumulate_i='product_valid_q',first_i='product_first_q',
                activation_i='activation_q',weight_i='weight_q[lane]',accumulator_o='accumulated')
            if mc!=expected:raise ValueError('MAC CE/first/operand connection changed')
            primitive=dict(kind='registered behavioral recurrence proved; vendor recurrence semantics assumed',proof_receipt=mr,
                matches_on='Current product ownership and first accumulation overwrite; exact native CE/ACCSEL/configuration checked')
        else:
            source=dense((tile/'wrapper.sv').read_text())
            if 'if(a_f_operands_owned_o)assert(a_f_tail_owned_o);'not in source or 'if(b_f_operands_owned_o)assert(b_f_tail_owned_o);'not in source:
                raise ValueError('Captured activation is not owned at stateless product congruence')
            native=body((tile/'production-tile.sv').read_bytes(),'board1_projection_tile16').decode()
            mc=instance_con(native,'board1_w10_a16_mul_exact','u_mul')
            if mc!=dict(activation_i='activation_q',weight_i='weight_q[lane]',product_o='product'):
                raise ValueError('Actual stateless multiplier inputs differ')
            primitive=dict(kind='stateless native RTL multiplier congruence',
                matches_on='Complete captured activation and weight agree under the exact operand-ownership predicate')
        variants=set(case['variants'])
        for name in(case['parent'],case['tile'],case['caller']):variants.intersection_update(joins['proof_module_joins'][name]['active_variant_source_joins'])
        if variants!=case['variants']:raise ValueError('Numerical source-class association incomplete')
        functions={}
        for variant in variants:
            needed={'board1_projection_postscale_mul'}|({'board1_w10_a16_mul_exact'}if kind=='serial'else set())
            functions[variant]={owner:stateless_native_function(variant,owner,opaque)for owner in needed}
        results[kind]=dict(variants=sorted(variants),proof_receipts=receipts,primitive_contract=primitive,
            stateless_native_functions=functions,
            caller_permissions_joined=True,selected_registered_tile_reply_permissions_joined=True,
            complete_native_geometry_preserved=True,primitive_vendor_semantics_proved=False)
    result=dict(cluster_source_and_permission_join_passed=True,classes=results,
        assembled_subsystem_solver_proof=False,session_milestone_complete=False,
        scope='Source/receipt join of exact native caller permissions, tile relations, selected registered-read owners, parent pipelines and stated primitive contracts for both current architectures. A new assembled temporal subsystem theorem and whole-device token publication remain separate.',
        instantiation_binding_sha256=sha((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()),
        opaque_configuration_audit_sha256=sha((HERE/'OPAQUE-STATE-AUDIT.json').read_bytes()),
        checker_sha256=sha(Path(__file__).read_bytes()))
    (HERE/'CLUSTER-CONTRACT-JOIN.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(cluster_source_and_permission_join_passed=True,source_classes=2,session_milestone_complete=False)))


if __name__=='__main__':main()
