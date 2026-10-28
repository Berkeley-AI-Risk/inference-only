"""Audit selected raw proof records without promoting component results.

Each run keeps its frozen producer, exact inputs, solver queries/replies and
incomplete secondary lanes. A complete lane requires base, induction and all
requested covers from the same backend. Mutants require real BMC counterexamples
under their recorded entry policy. This ledger does not discharge composition obligations.
"""
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
RAMS=['query-clear-r1','accumulator-clear-r1']+['native-leaf-clear-r1-'+k for k in
    ('workspace','output','vector256','vector128','scratch','rope')]
CASES={
    **{n:'native RAM history and conditional two-copy ownership'for n in RAMS},
    'attention-ownership-clear-baseline-r1':'attention parent ownership after CLEAR, baseline/seeded source class',
    'attention-ownership-clear-kv-protected-r1':'attention parent ownership after CLEAR, protected/encrypted source class',
    'semantic-ingress-r5':'joined sequence/datapath hidden ingress ownership',
    'semantic-scratch-clear-r1':'semantic scratch, resetless query/RoPE staging and retained metadata ownership after CLEAR',
    'semantic-clear-normal-r2':'actual semantic parent normal form after CLEAR with previously accepted DDR work allowed; canonical control retained until new upper operation, pending and drained covers',
    'model-transport-drain-client-r1':'actual four core model FIFOs and native 16-owner arbiter; exact accepted word/role histories, total and per-client conservation across busy CLEAR, no hard reset',
    'semantic-drain-r1':'actual semantic DDR owner/count and response routing; accepted-request conservation across busy CLEAR and healthy busy-low implies zero owed responses, no hard reset',
    'group-drain-r6':'full native group reader and all reachable children; accepted request accounting, metadata pending, busy-CLEAR drain and quiet control normal form, no hard reset',
    'embedding-drain-r1':'connected native embedding and full group reader; exact pending count and healthy embedding busy/quiet-CLEAR barrier with numerical normalizer free, no hard reset',
    'projection-drain-r2':'connected native projection job and full group reader; exact pending count and healthy job busy/quiet-CLEAR barrier with numerical engine free, no hard reset',
    'lookup-drain-r1':'full native semantic lookup accepted-read ledger and quiet-CLEAR barrier; requests imply busy, busy-low implies no owed response, no hard reset',
    'shell-drain-r3':'connected actual greedy token shell, embedding and complete model-read hierarchy; command-ready/busy/quiet-CLEAR barrier with native RAMs retained, no hard reset',
    'seeded-shell-drain-r1':'connected actual seeded token shell, embedding and complete model-read hierarchy; command-ready/busy/quiet-CLEAR barrier with native RAMs retained, no hard reset',
    'connected-semantic-drain-r1':'actual semantic model-read mux connected to native projection/group and lookup hierarchies; exact common-epoch pending sum and request/busy barrier, no hard reset',
    'core-model-drain-r4':'actual connected greedy core model-read barrier: healthy active busy-low implies no owed/presented model read; native control/queues with data-only RAM/numerical seams, no hard reset',
    'core-model-drain-seeded-r1':'actual connected seeded core model-read barrier: healthy active busy-low implies no owed/presented model read; native control/queues with data-only RAM/numerical seams, no hard reset',
    'kv-session-drain-baseline-r2':'full native baseline/seeded typed K/V cache and mapper: accepted read/write conservation through CLEAR, healthy busy-low barrier, prefix/pending/cache revocation and fault-only cancelled replies, no hard reset',
    'kv-session-drain-protected-r1':'full native protected/encrypted typed K/V cache and mapper: accepted read/write conservation through CLEAR, healthy busy-low barrier, prefix/pending revocation and fault-only cancelled replies, no hard reset',
    'kv-staging-owner-baseline-r4':'full native baseline/seeded K/V staging RAM initialization and actual symbolic coordinate history after logical CLEAR, current descriptor exponents and permitted staging-read ownership, no hard reset',
    'kv-staging-owner-protected-r1':'full native protected/encrypted K/V staging RAM initialization and actual symbolic coordinate history after logical CLEAR, current descriptor exponents and permitted staging-read ownership, no hard reset',
    'kv-cached-row-owner-r1':'full native baseline/seeded K/V staging and committed-kind cache; all nine current reply chunks before cache validity and exact symbolic cache RAM/metadata history after logical CLEAR, no hard reset',
    'kv-typed-write-history-r2':'full native baseline/seeded K/V staging/prefetch/pack through actual typed write data; every current coordinate/exponent equals its legal writer after logical CLEAR, committed cache history retained, no hard reset',
    'connected-kv-drain-baseline-r2':'actual baseline/seeded semantic model-reader and full native K/V hierarchy, all thirty K/V child outputs restored; common accepted-work tracking and healthy idle barrier for model and typed work, no hard reset',
    'connected-kv-drain-protected-r1':'actual protected/encrypted semantic model-reader and full native K/V hierarchy, all thirty K/V child outputs restored; common accepted-work tracking and healthy idle barrier for model and typed work, no hard reset',
    'service-rms-clear-r1':'RMS vector RAM ownership, registered history and fresh ROM-read tags after CLEAR',
    'rms-rom-r1':'complete immutable RMS ROM and resetless registered output isolation',
    'service-projection-clear-r1':'projection activation RAM ownership and registered read history after CLEAR without hard reset',
    'service-normalizer-clear-r1':'normalizer record RAM ownership and registered read history after CLEAR',
    'rms-parent-ready-clear-r2':'conditional RMS parent correspondence; all scalar state, child admissions and independent unused delivery readiness',
    'normalizer-parent-ready-clear-r1':'conditional normalizer parent correspondence; all scalar state, child admissions and independent unused delivery readiness',
    'stateless-rms-modes-r1':'native RMS DSP mode input relevance with actual behavioral multiplication',
    'stateless-unified-modes-r1':'native unified DSP mode input relevance with actual behavioral multiplication',
    'shell-memory-clear-r1':'greedy token shell tape/vector RAM ownership and history',
    'shell-memory-seeded-clear-r1':'seeded token shell tape/vector RAM ownership and history',
    'shell-parent-clear-r4':'conditional native greedy token-shell correspondence after healthy drained CLEAR; all scalar fields, actual child admissions, tape/vector writes and guarded token publication',
    'shell-parent-seeded-clear-r1':'conditional native seeded token-shell correspondence after healthy drained CLEAR; includes actual bounded-settings admission and guarded token publication',
    'sampler-clear-ownership-r5':'full native seeded sampler and greedy/comparator children after CLEAR without hard reset; all logit/mass rows and registered-read ownership, immutable ROM retained',
    'sampler-parent-clear-r3':'native seeded sampler and concrete greedy hierarchy correspondence after healthy CLEAR with common authorized configuration; actual PRNG/arithmetic, scalar state and logical memory/ROM ports compared',
    'embedding-parent-clear-r1':'actual tied-embedding controller and normalizer/group-reader input correspondence; 91 closed inductive conclusions plus one source-bound multiplication-congruence corollary',
    'embedding-clear-normal-r1':'actual embedding parent control and token/header-authority revocation after CLEAR with busy children allowed, through IDLE/drain until new accepted work',
    'shell-clear-normal-r1':'actual greedy token shell control/tape counters and metadata authority after CLEAR with busy children allowed, through IDLE/drain until new accepted work',
    'seeded-shell-clear-normal-r1':'actual seeded token shell control/tape counters and metadata authority after CLEAR with busy children allowed, through IDLE/drain until new accepted work',
    **{'scalar-'+k+'-valid-r1':'concrete arithmetic healthy session relation with independent invalid operands'
       for k in ('attention-shift','attention-divider','rms-bounded-divider','isqrt')},
    'scalar-normalizer-valid-r1':'concrete resetless normalizer pipeline CLEAR relation',
    'concrete-align8-clear-r1':'concrete resetless align8 CLEAR relation',
    'concrete-norm-candidate-clear-r3':'concrete fresh norm-candidate capture relation; logical cancellation can discard unmatched captures',
    'prefix-session-valid-r1':'concrete prefix-summary healthy CLEAR relation',
    'exp-session-valid-r1':'concrete full native exponential ROM/pipeline CLEAR relation',
    'cluster-reply-ownership-r2':'active parallel cluster after CLEAR; all four actual tile caller permissions and selected registered metadata/dot reply ownership, stalled pipeline',
    'serial-cluster-reply-ownership-r1':'active protected/encrypted serial cluster after CLEAR; all sixteen contexts per tile, actual caller permissions and selected registered reply ownership',
    'projection-mac-r1':'behavioral MAC recurrence isolation; checked native configuration, vendor recurrence premise',
    'elementwise-relevant-ready-r2':'active elementwise CLEAR relation, operation-relevant coefficients/LUT data, independent unused readiness and stateless product congruence',
    'greedy-head-clear-r1':'concrete greedy selector healthy CLEAR relation including resetless pending row',
    'group-stream-ownership-clear-r1':'native metadata word and complete group header ownership/history after CLEAR without hard reset, with all reachable children retained',
    'lookup-history-clear-r1':'native semantic lookup request ownership, response history and CLEAR-drain isolation',
    'weight-beat-register-r1':'native resetless beat payload isolation after production local cancellation',
    'weight-width-adapter-r1':'native full width-adapter state isolation after production local cancellation',
    'lut-protocol-join-r10':'actual semantic/elementwise/normalizer controller join; SiLU cache consumption permission, fresh gate read and job/capture sequencing',
    'semantic-parent-clear-r15':'conditional native semantic correspondence; all scalar state, 64 query lanes, actual child inputs and guarded outputs except final hidden-vector reads',
    'semantic-result-clear-r8':'actual sequence/datapath/layer join after healthy drained CLEAR; complete hidden ingress, final read tags and matching parent ownership permissions',
    'sequence-parent-clear-r2':'conditional actual sequence correspondence after healthy CLEAR; every native register and guarded output, independent hidden replies outside consuming phases',
    'projection-stream-join-r6':'actual projection job and DDR-stream controller join; full activation RAM, current-job ownership and exact weight-column read alignment after healthy drained CLEAR',
    'projection-parent-clear-r9':'conditional actual projection job and DDR-stream correspondence; 207 native scalar bits, 16-bit registered activation seam, complete fresh header seam, matched native memory write/read ports and every child input including local cancellation reset',
    'metadata-reader-clear-r1':'concrete full projection metadata reader correspondence after healthy drained CLEAR, all native registers and irrelevant operand/readiness independence',
    'projection-adapter-clear-r2':'native packed-header adapter correspondence after CLEAR; all 38 register bits and every cluster input, with source-audited stateless header-congruence contract',
    'tile-parent-parallel-r3':'conditional native parallel projection tile relation; all 249 scalar/register bits and sixteen metadata rows, always-matched first tags, current-MAC recurrence and caller permissions explicit',
    'tile-parent-serial-r2':'conditional native serial projection tile relation; all 289 scalar/register bits, sixteen metadata/accumulator contexts, always-matched first tags, captured multiplier operands and caller permissions explicit',
    'cluster-parent-parallel-r4':'conditional actual parallel cluster controller and full stalled postscale pipeline relation after CLEAR; all 331 native register bits and child input admissions including always-matched first_i',
    'cluster-parent-serial-r2':'conditional actual serial cluster controller and full stalled postscale pipeline relation after CLEAR; all 335 native register bits and child input admissions including always-matched first_i',
    'assembled-cluster-parallel-r2':'connected parallel cluster and all four full native tiles after CLEAR; concrete registered replies and metadata arrays, registered-MAC and stateless postscale contracts explicit',
    'assembled-cluster-serial-r3':'connected serialized cluster and all four full native tiles after CLEAR; concrete registered replies, all metadata and accumulator contexts, stateless products explicit',
}
PARTITIONS={'exp-session-valid-r1':'exp-session-valid-r1-z3',
    'kv-session-drain-baseline-r2':'kv-session-drain-baseline-r2-steps',
    'elementwise-relevant-ready-r2':'elementwise-relevant-ready-r2-z3',
    'assembled-cluster-parallel-r2':'assembled-cluster-parallel-r2-joint-one',
    'assembled-cluster-serial-r3':'assembled-cluster-serial-r3-groups'}
CERTIFICATES={'semantic-parent-clear-r15':'runs/semantic-strengthening-r2/CERTIFICATE.json',
    'embedding-parent-clear-r1':'runs/embedding-congruence-r2/CERTIFICATE.json',
    'model-transport-drain-client-r1':'runs/transport-wordwise-r1/CERTIFICATE.json',
    'core-model-drain-r4':'runs/core-wordwise-r1/CERTIFICATE.json',
    'core-model-drain-seeded-r1':'runs/core-wordwise-seeded-r1/CERTIFICATE.json'}
MUTANTS=['workspace-mutant-r1','query-mutant-r1','query-parent-mutant-r1']+[
    'service-'+k+'-dropword-r1'for k in ('rms','projection','normalizer')]+[
    'group-stream-metadata-mutant-r1','lut-protocol-idle-mutant-r1','semantic-result-premature-mutant-r1',
    'model-transport-drain-mutant-r1','core-premature-clear-mutant-r1','kv-session-drop-write-mutant-r1',
    'kv-staging-drop-lane-mutant-r1']


def sha(raw):return hashlib.sha256(raw).hexdigest()


def check_hash(path,expected):
    actual=sha(path.read_bytes())
    if actual!=expected:raise ValueError('Recorded artifact changed: '+str(path))


def audit(name,kind):
    run=HERE/'runs'/name
    if not(run/'FINISHED.json').is_file():return dict(scope=kind,status='running_or_absent')
    d=json.loads((run/'FINISHED.json').read_text())
    inputs=json.loads((run/'INPUTS.json').read_text())
    check_hash(run/'INPUTS.json',d['inputs_sha256'])
    for n,row in inputs['files'].items():
        if (run/n).stat().st_size!=row['bytes']:raise ValueError('Input length changed: '+n)
        check_hash(run/n,row['sha256'])
    check_hash(run/'yosys.log',d['yosys_log_sha256'])
    if d['assertion_cells']!=inputs['assertion_cells']:raise ValueError('Assertion census mismatch')
    for label,row in d['results'].items():
        for suffix,key in [('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')]:
            if row.get(key):check_hash(run/(label+suffix),row[key])
        for n,digest in row['traces'].items():check_hash(run/n,digest)
    mutant=bool(d['mutant'])
    phases=('bmc',)if mutant else('bmc','induction','cover')
    lanes={s:all(d['results'].get(s+'-'+p,{}).get('passed',False)for p in phases)
           for s in ('z3','cvc5')}
    partition_record=None
    if name in PARTITIONS:
        out=HERE/'runs'/PARTITIONS[name];part=json.loads((out/'FINISHED.json').read_text())
        check_hash(run/'INPUTS.json',part['source_inputs_sha256'])
        check_hash(run/'elaborated.il',part['rtlil_sha256'])
        model_path=run/'design.smt2'if part.get('state_encoding')=='native'else out/'model.smt2'
        check_hash(model_path,part['model_sha256'])
        if part['assertion_count']!=d['assertion_cells']or not part['complete_conclusion_inventory']:
            raise ValueError('Incomplete partition property inventory')
        if not part['prior_state_joint_invariants_only']:
            raise ValueError('Unexpected partition premise policy')
        corollaries=part.get('corollary_conclusions',[])
        if part['current_state_extra_assumptions']and not(corollaries and
            part.get('all_current_state_premises_independently_proved')and
            part.get('current_state_premises_for_corollaries')==part.get('inductive_conclusions')):
            raise ValueError('Current-state corollary premises are not independently closed')
        if part['base_constraint_text']!=(run/'reset.smtc').read_text():
            raise ValueError('Partition base constraints differ')
        expected=({'base','joint-induction'}if part.get('joint_complete_invariant_step')else
            {'base'}|{'induction-'+str(i).zfill(3)for i in range(d['assertion_cells'])if i not in corollaries}|
            {'corollary-'+str(i).zfill(3)for i in corollaries})
        if part.get('conclusion_groups'):expected={'base'}|set(part['conclusion_groups'])
        if set(part['results'])!=expected:raise ValueError('Missing partition conclusion')
        from join_parent_conclusions import query_templates, template_text
        normalized=dict(part)
        if 'inductive_conclusions'not in normalized:
            normalized.update(inductive_conclusions=list(range(d['assertion_cells'])),
                corollary_conclusions=[],current_state_premises_for_corollaries=[])
        templates=query_templates(model_path.read_text(),normalized,inputs['top'],d['assertion_cells'],compact=True)
        for n,row in part['results'].items():
            from join_parent_conclusions import checked_query
            if checked_query(out/(n+'.smt2'),row)!=template_text(templates[n]).encode():
                raise ValueError('Partition query or prior-state premises changed')
            check_hash(out/(n+'.log'),row['reply_sha256'])
            if row['passed']and(row['answers']!=['sat','unsat']or row['exit']!=0):raise ValueError('Invalid partition success')
        partition_passed=part['passed']and all(r['passed']for r in part['results'].values())
        solver=part['solver']
        if partition_passed and d['results'].get(solver+'-cover',{}).get('passed',False):lanes[solver]=True
        partition_record=dict(run=PARTITIONS[name],passed=partition_passed,solver=solver,
            result_sha256=sha((out/'FINISHED.json').read_bytes()),complete_conclusions=d['assertion_cells'])
    certificate_record=None
    if name in CERTIFICATES:
        path=HERE/CERTIFICATES[name];cert=json.loads(path.read_text())
        if (not cert['conditional_parent_proof_passed']or cert['missing']or cert['assertions']!=d['assertion_cells']or
            cert['source_input_sha256']!=sha((run/'INPUTS.json').read_bytes())or
            cert['source_result_sha256']!=sha((run/'FINISHED.json').read_bytes())or
            not cert['no_current_state_corollary_is_an_induction_premise']or
            cert['closed_inductive_conclusions']+cert['current_state_corollaries']!=d['assertion_cells']):
            raise ValueError('Incomplete or mismatched conditional certificate')
        for p,h in cert['artifact_manifest'].items():
            target=Path(p).resolve()
            if HERE.resolve()not in target.parents:raise ValueError('Certificate artifact outside campaign')
            check_hash(target,h)
        check_hash(path.parent/'checker.py',cert['checker_sha256'])
        external_cover_record=None
        for solver,passed in cert['complete_backend_lanes'].items():
            covered=d['results'].get(solver+'-cover',{}).get('passed',False)
            if passed and not covered and solver=='z3'and cert.get('external_cover_receipt'):
                cp=Path(cert['external_cover_receipt']).resolve()
                if HERE.resolve()not in cp.parents or str(cp)not in cert['artifact_manifest']:
                    raise ValueError('External cover is outside the pinned certificate')
                check_hash(cp,cert['artifact_manifest'][str(cp)])
                cover=json.loads(cp.read_text())
                if (not cover['passed']or cover['status']!=['PASSED']or cover['exit']!=0 or
                    cover['source_inputs_sha256']!=sha((run/'INPUTS.json').read_bytes())or
                    cover['source_model_sha256']!=sha((run/'design.smt2').read_bytes())or
                    cover['cover_count']!=d['cover_cells']or not cert.get('complete_source_model_cover_passed')):
                    raise ValueError('External cover source/model/target qualification differs')
                for filename,digest in cover['artifact_manifest'].items():
                    if filename not in cert['artifact_manifest']or digest!=cert['artifact_manifest'][filename]:
                        raise ValueError('External raw cover artifact is not pinned by the certificate')
                    check_hash(Path(filename),digest)
                covered=True;external_cover_record=dict(path=str(cp),cover_count=cover['cover_count'],
                    source_model_sha256=cover['source_model_sha256'],inputs_fixed_only_for_reachability=True)
            if passed and covered:lanes[solver]=True
        certificate_record=dict(path=CERTIFICATES[name],sha256=sha(path.read_bytes()),
            assertions=cert['assertions'],complete_backend_lanes=cert['complete_backend_lanes'],
            child_contracts_composed=False,whole_device_token_output_theorem=False,external_cover_record=external_cover_record)
    return dict(scope=kind,status='proved_component'if any(lanes.values())else'incomplete',
        complete_backend_lanes=lanes,assertions=d['assertion_cells'],covers=d['cover_cells'],
        corruption_sensitivity_case=mutant,scope_statement=d['scope'],
        phases={n:dict(passed=v['passed'],status=v['status'],timed_out=v['timed_out'])
                for n,v in d['results'].items()},
        partition_record=partition_record,
        certificate_record=certificate_record,
        input_sha256=sha((run/'INPUTS.json').read_bytes()),
        result_sha256=sha((run/'FINISHED.json').read_bytes()))


def main():
    cases={n:audit(n,k)for n,k in CASES.items()}
    mutants={n:audit(n,'BMC corruption counterexample under its recorded entry policy')for n in MUTANTS}
    progress=dict(status='in_progress',milestone_complete=False,
        selected_component_records=cases,selected_sensitivity_records=mutants,
        source_binding_audit='MEMORY-BINDINGS.json; source/image associations retained in each INPUTS.json',
        remaining=[
            'Compose the checked attention parent/interface correspondence with its numerical and RAM reply contracts.',
            'Join semantic/service/shell storage ownership with numerical-child state and operand correspondence.',
            'Close the common core/client CLEAR/drain barrier, typed K/V/outer transport and healthy current-session correspondence through token publication.',
            'Complete mutable-state census and source projection/composition audit before release claims.'
        ],hardware_changed=False,hardware_access=False,public_repository_updated=False)
    (HERE/'PROGRESS.json').write_text(json.dumps(progress,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(components=len(cases),complete_components=sum(v['status']=='proved_component'for v in cases.values()),
        sensitivity_cases=len(mutants),complete_sensitivity_cases=sum(v['status']=='proved_component'for v in mutants.values()),
        milestone_complete=False)))


if __name__=='__main__':main()
