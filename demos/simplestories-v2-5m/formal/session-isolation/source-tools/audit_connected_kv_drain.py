"""Join connected semantic/model/KV drain proofs to actual image hierarchies."""
import argparse
import json
from pathlib import Path
import re

from record_progress import audit, sha
from run_attention_ownership import HERE
from run_projection_relational import instance_con
from audit_core_model_drain import instance_parameters
from audit_connected_drain import GROUP, PROJECTION
from audit_model_drain import observer_only
from run_kv_session_drain import TOP


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--runs',nargs='+',required=True)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);manifest={};results={}
    def pin(path,digest=None):
        raw=path.read_bytes();h=sha(raw)
        if digest is not None and h!=digest:raise ValueError('Source artifact changed')
        manifest[str(path.resolve())]=h;return raw
    joins_raw=(HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes();joins=json.loads(joins_raw)
    (out/'instantiation-bindings.json').write_bytes(joins_raw);pin(out/'instantiation-bindings.json')
    dp='board1_context2048_semantic_datapath';mapper='board1_context2048_typed_address_mapper'
    edges=[(dp,TOP,'u_kv_cache'),(TOP,mapper,'u_write_shadow_mapper'),(TOP,mapper,'u_read_shadow_mapper'),
        (dp,'board1_fixed_group_projection_scale_job','u_projection'),
        (dp,'board1_context2048_semantic_lookup','u_lookup'),PROJECTION]+GROUP
    for name in args.runs:
        run=HERE/'runs'/name;receipt=audit(name,'Connected native semantic/model/KV drain')
        if receipt['status']!='proved_component':raise ValueError('Connected proof is incomplete')
        inp=json.loads(pin(run/'INPUTS.json'));pin(run/'FINISHED.json');b=inp['binding']
        if inp['assumption_cells']or b['initial_hard_reset']or b['native_KV_child_outputs_restored']!=30:
            raise ValueError('Unexpected reset, assumptions or native output count')
        if any(r.get('instance')in ('u_kv_cache','u_projection','u_lookup')for r in inp['internal_cuts']):
            raise ValueError('A whole connected child reply remains free')
        originals={};compiled={}
        for filename,row in inp['files'].items():
            raw=pin(run/filename,row['sha256'])
            if not filename.endswith('.sv')or filename.endswith('.inc.sv'):continue
            target=originals if filename.startswith('production')else compiled if filename in inp['compile_sources']else None
            if target is None:continue
            for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',raw.decode(),re.M):
                if m[1]in target and target[m[1]]!=m[0]:raise ValueError('Conflicting active native definitions')
                target[m[1]]=m[0]
        connected=[]
        for parent,child,instance in edges:
            original=instance_con(originals[parent],child,instance)
            actual=instance_con(compiled[parent],child,instance)
            if {n:v for n,v in actual.items()if not n.startswith('f_')}!=original:
                raise ValueError('Native functional port connection changed')
            if instance_parameters(originals[parent],child,instance)!=instance_parameters(compiled[parent],child,instance):
                raise ValueError('Native parameter expression changed')
            connected.append(dict(parent=parent,child=child,instance=instance,ports=original))
        cm=(run/'session-drain-monitor.inc.sv').read_text();observer_only(cm)
        # The only additional native-cache instrumentation is these exact,
        # nondriving output taps and the cancellation monitor. Cover calls were
        # replaced by empty statements when selecting parent-only covers.
        cache_expected=originals[TOP]
        cache_actual=compiled[TOP]
        for port,shape,value in [('f_dp_scope_o','','f_scope'),
            ('f_dp_write_pending_o','[1:0] ','f_write_pending'),('f_dp_read_pending_o','[4:0] ','f_read_pending')]:
            declaration=',\n    output wire '+shape+port
            assignment='    assign '+port+'='+value+';'
            if cache_actual.count(declaration)!=1 or cache_actual.count(assignment)!=1:
                raise ValueError('Native pending observer tap differs')
            cache_actual=cache_actual.replace(declaration,'',1).replace(assignment,'',1)
        # Remove just original covers, preserving the assertion statements.
        coverless=cm
        while 'cover('in coverless:
            at=coverless.index('cover(');end=at+6;level=1
            while level:level+=(coverless[end]=='(')-(coverless[end]==')');end+=1
            coverless=coverless[:at]+' begin end '+coverless[end+1:]
        if cache_actual.count(coverless)!=1:raise ValueError('Native cache observer not uniquely removable')
        cache_actual=cache_actual.replace(coverless,'',1)
        dense=lambda s:re.sub(r'\s+','',s)
        if dense(cache_actual)!=dense(cache_expected):raise ValueError('Native cache functional body changed')
        observer_only((run/'connected-kv-monitor.inc.sv').read_text())
        for module in b['concrete_hierarchy_modules']:
            expected=joins['proof_module_joins'][name]['modules'][module]['original_module_sha256']
            if sha(originals[module].encode())!=expected:raise ValueError('Concrete source does not match native images')
        variants=joins['proof_module_joins'][name]['active_variant_source_joins']
        if variants!=(['baseline','seeded-sampling']if b['variant']=='baseline'else['encrypted-memory','kv-protected']):
            raise ValueError('Native variant source class differs')
        results[name]=dict(receipt=receipt,active_variants=variants,native_edges=connected,
            all_thirty_native_KV_child_outputs_connected=True,remaining_seams=inp['internal_cuts'])
    checker=out/'checker.py';checker.write_bytes(Path(__file__).read_bytes());pin(checker)
    result=dict(connected_semantic_KV_source_join_passed=True,cases=results,artifact_manifest=manifest,
        whole_device_session_theorem=False,core_shell_and_outer_transport_composed=False,
        scope='Actual semantic/model-reader/native-KV hierarchy with exact functional edges and unchanged cache controller/RAM. Common accepted-work tracking, healthy idle barrier for model and typed K/V work, no hard reset. Numerical/attention seams, full payload/public token composition and core/outer drain entry remain separate.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(connected_semantic_KV_source_join_passed=True,source_classes=len(results),whole_device_session_theorem=False)))


if __name__=='__main__':raise SystemExit(main())
