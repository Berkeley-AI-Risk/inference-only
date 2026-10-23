"""Synthetic seed-domain archive validation tests; never physical evidence."""
import copy
import importlib.util
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('seed_domain_check',HERE/'check_seeded_domain.py')
check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)
PACKAGE=HERE.parent

def synthetic_wire(plan):
    rows=[];ns=0
    for operation,tx,kind,operand in plan:
        rows.append(dict(event='tx',operation=operation,frame_hex=tx,sequence=len(rows)+1,elapsed_ns=ns))
        rows.append(dict(event='rx',operation=operation,frame_hex=check.reply(kind,operand),sequence=len(rows)+1,elapsed_ns=ns+9_000_000))
        rows.append(dict(event='operation',operation=operation,response_kind=kind,operand=operand,
            seconds=.01,sequence=len(rows)+1,elapsed_ns=ns+10_000_000));ns+=11_000_000
    rows.append(dict(event='wire_quiet',operation='final-clear-drain',requested_seconds=.1,
        buffered_hex='',sequence=len(rows)+1,elapsed_ns=ns+100_000_000))
    return rows

def fixture():
    cases=[]
    for path,reference,digest in check.read_references(PACKAGE):
        plan=check.commands(reference)
        cases.append(dict(label=Path(path).stem,temperature=reference['temperature'],seed=reference['seed'],
            prompt_tokens=reference['prompt_tokens'],generated_tokens=reference['generated_tokens'],
            replayed_tokens=reference['generated_tokens'][:8],step_seconds=[.01]*len(reference['generated_tokens']),
            reference_path=path,reference_sha256=digest,source_reference_receipt_sha256=reference['source_reference_receipt_sha256'],
            all_tokens_match_independent_reference=True,replay_without_settings=True,
            final_clear_acknowledged=True,image_sha256=check.IMAGE_SHA,passed=True,
            source_uart_sha256='1'*64,wire=synthetic_wire(plan)))
    return dict(schema='seeded-seed-domain-public-v1',passed=True,image_sha256=check.IMAGE_SHA,
        model_image_sha256=check.MODEL_SHA,source_inventory_sha256=check.SOURCE_SHA,
        source_plan_sha256=check.SOURCE_PLAN_SHA or'2'*64,source_finished_sha256=check.SOURCE_FINISHED_SHA or'3'*64,
        source_runner_sha256=check.SOURCE_RUNNER_SHA,runtime_pinned_files=19,
        runtime_pin_scope='19 runner, transport and numerical-reference files; not all 91 native inputs.',
        cases=cases,full_reference_outputs=960,clear_replay_outputs=96,final_greedy_reference_outputs=3,total_reference_outputs=1059,
        final_greedy_wire=synthetic_wire(check.final_commands()),final_greedy_source_uart_sha256='4'*64,
        per_command_deadline_seconds=120,claims=dict(physical_fpga=True,final_empty_greedy=True,usb_released=True,
            flash_modified=False,automatic_retries=False,configuration_independently_attested=False,
            timing_qualified=False,security_certified=False,full_context_qualified_by_this_campaign=False,
            zero_seed_remap_checked_by_transcript=True,internal_prng_state_observed=False,oracle_replayed_by_archive_checker=False))

class SyntheticSeedDomainTests(unittest.TestCase):
    def test_synthetic_plan_census(self):
        result=check.validate(fixture(),PACKAGE);self.assertEqual(result['total_reference_outputs'],1059)
        self.assertEqual(result['commands'],1897)
    def test_no_completed_physical_campaign_claim_before_pinning(self):
        if check.ARCHIVE_SHA is None:
            with self.assertRaisesRegex(ValueError,'No completed physical'):check.check(PACKAGE)
    def test_reject_wrong_seed_long_tail_replay_crc_and_order(self):
        for mutation in('seed','tail','replay','crc','order','count','reference','final-token','final-clear'):
            with self.subTest(mutation=mutation):
                data=fixture()
                if mutation=='seed':data['cases'][3]['seed']='0x'+'1'*32
                elif mutation=='tail':data['cases'][3]['generated_tokens']=list(data['cases'][3]['generated_tokens']);data['cases'][3]['generated_tokens'][20]+=1
                elif mutation=='replay':data['cases'][0]['replayed_tokens']=[]
                elif mutation=='crc':data['cases'][0]['wire'][7]['frame_hex']='5a80000000'
                elif mutation=='order':data['cases'].reverse()
                elif mutation=='count':data['total_reference_outputs']=960
                elif mutation=='reference':data['cases'][0]['reference_sha256']='0'*64
                elif mutation=='final-token':data['final_greedy_wire'][10]['frame_hex']=check.reply(0x81,357)
                else:data['final_greedy_wire']=data['final_greedy_wire'][:-4]
                with self.assertRaises(ValueError):check.validate(data,PACKAGE)
    def test_reject_timing_and_scope_mutations(self):
        for mutation in('nan','timeline','deadline','pins','inflight','proof','retry'):
            with self.subTest(mutation=mutation):
                data=fixture()
                if mutation=='nan':data['cases'][0]['wire'][2]['seconds']=float('nan')
                elif mutation=='timeline':data['cases'][0]['wire'][2]['elapsed_ns']=0
                elif mutation=='deadline':data['per_command_deadline_seconds']=3600
                elif mutation=='pins':data['runtime_pinned_files']=91
                elif mutation=='inflight':data['claims']['internal_prng_state_observed']=True
                elif mutation=='proof':data['claims']['security_certified']=True
                else:data['claims']['automatic_retries']=True
                with self.assertRaises(ValueError):check.validate(data,PACKAGE)

if __name__=='__main__':unittest.main()
