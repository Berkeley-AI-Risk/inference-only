"""Local contract controls with synthetic SDK files and a real stub process.

No Vivado, AWS, FPGA, synthesis or routing is exercised by these tests.
"""
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('qwen_build', HERE/'qwen_build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
SOURCE = Path(os.environ.get('QWEN_BUILD_TEST_SOURCE', HERE.parent))
HDK_REV = 'b603a81f65666e0cf7a67ee5cf18b148eb6b08c3'
IP_REV = '6d32be972e6da854e61a8d3d6ec0466ab491c1b3'

VIVADO = '''import json, os, pathlib, sys, time, zipfile
with open(os.environ['STUB_CALLS'], 'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
mode=os.environ.get('STUB_MODE','zip')
print('LOCAL UNIT STUB: NOT VIVADO OR AN FPGA BUILD')
if '-version' in sys.argv:
 if mode=='version19': sys.exit(19)
 print('Vivado v'+('2025.1' if mode=='wrong_version' else '2025.2')+' (64-bit)');sys.exit(0)
if mode.startswith('block_'):
 pathlib.Path(os.environ['STUB_READY']).write_text('inside batch stub after freshness')
 until=time.monotonic()+15
 while not pathlib.Path(os.environ['STUB_RELEASE']).exists():
  if time.monotonic()>until: sys.exit(97)
  time.sleep(.01)
 if mode=='block_missing': sys.exit(0)
if mode=='fail19': sys.exit(19)
if mode=='missing': sys.exit(0)
p=pathlib.Path(os.environ['CL_DIR'])/'build/checkpoints'/('cl_qwen.'+os.environ['BUILD_TAG']+'.post_synth.dcp')
p.parent.mkdir(parents=True,exist_ok=True)
if mode=='invalid': p.write_bytes(b'not a checkpoint');sys.exit(0)
with zipfile.ZipFile(p,'w') as z: z.writestr('STUB-NOT-A-DCP.txt','synthetic contract fixture')
if mode=='mutate':
 q=pathlib.Path(os.environ['CL_DIR'])/'build/scripts/build_all.tcl';q.write_text('changed by stub')
sys.exit(19 if mode=='fail19_with_zip' else 0)
'''
GIT = '''import os,pathlib,sys
args=sys.argv[1:];folder=pathlib.Path(args[1])
if os.environ.get('STUB_GIT_CALLS'):
 with open(os.environ['STUB_GIT_CALLS'],'a') as f: f.write(str(args)+'\\n')
if args[2:]==['rev-parse','HEAD']: print(os.environ['STUB_IP_REV'] if folder.name=='ip' else os.environ['STUB_HDK_REV'])
elif args[2:]==['rev-parse','--show-toplevel']: print(folder.resolve())
elif args[2:]==['diff','--quiet','HEAD','--']: pass
else: sys.exit(2)
'''


class Controls(unittest.TestCase):
    def tearDown(self):
        evidence = os.environ.get('QWEN_BUILD_TEST_EVIDENCE')
        if evidence:
            target = Path(evidence)/self._testMethodName
            target.mkdir(parents=True, exist_ok=False)
            members, links = {}, {}
            for source in sorted(self.root.rglob('*')):
                relative = source.relative_to(self.root)
                if source.is_symlink():
                    links[str(relative)] = os.readlink(source)
                elif source.is_file():
                    destination = target/relative
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, destination)
                    members[str(relative)] = build.identity(destination)
            (target/'TEST-EVIDENCE.json').write_text(json.dumps(dict(
                synthetic_SDK_git_and_shell=True, actual_Vivado_or_AWS=False,
                members=members, observed_symlinks_not_dereferenced=links), indent=2, sort_keys=True)+'\n')

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='qwen-build-contract-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root/'fixture-repository'
        self.hdk = self.root/'synthetic-sdk'
        self.bin = self.root/'bin'
        self.bin.mkdir()
        for name, content in (('vivado', VIVADO), ('git', GIT)):
            p = self.bin/name
            p.write_text('#!'+sys.executable+'\n'+content)
            p.chmod(0o755)
        (self.hdk/'hdk/common/ip').mkdir(parents=True)
        shell = self.hdk/'hdk/common/shell_stable'
        (shell/'build/checkpoints/from_aws').mkdir(parents=True)
        dcp = shell/'build/checkpoints/from_aws/cl_bb_routed.small_shell.dcp'
        dcp.write_bytes(b'SYNTHETIC SDK HASH FIXTURE, NOT A SHELL CHECKPOINT')
        (shell/'shell_version.txt').write_text('small_shell=0x10212415\n')
        (self.hdk/'release_version.txt').write_text('RELEASE_VERSION=STUB-UNIT-SDK\n')
        for profile in build.TAGS:
            base = self.repo/'demos'/profile
            (base/'tools').mkdir(parents=True)
            shutil.copyfile(SOURCE/'demos'/profile/'tools/prepare_hardware.py', base/'tools/prepare_hardware.py')
            files = {}
            for name, data in [('hardware/build/scripts/build_all.tcl', b'# unit stub only\n'),
                               ('hardware/design/cl_id_defines.vh', b"`define CL_SH_ID0 32'hf004_1d0f\n`define CL_SH_ID1 32'h1d51_fedc\n")]:
                p = base/name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(data)
                files[name] = build.identity(p)
            selected = dict(aws_hdk_revision=HDK_REV, aws_ip_revision=IP_REV, clock_recipes=build.CLOCKS,
                            shell_checkpoint_sha256=build.identity(dcp)['sha256'])
            if profile == 'qwen3-1.7b':
                selected.update(vivado_version='2025.2', source_bundle_manifest_sha256='0'*64, files={})
                (base/'hardware/IMPLEMENTATION-INPUTS.json').write_text(json.dumps(selected))
                record = dict(source_bundle_manifest_sha256='0'*64, source_files=files)
            else:
                record = dict(selected, tool_version='2025.2', frozen_hardware_inputs=files)
            (base/'SOURCE-INPUTS.json').write_text(json.dumps(record))
        self.calls = self.root/'stub-calls.jsonl'
        self.invocation_count = 0
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'], STUB_CALLS=str(self.calls),
                        STUB_HDK_REV=HDK_REV, STUB_IP_REV=IP_REV)

    def stage(self, profile):
        data = build.profile(self.repo, profile)
        output = self.root/('staged-'+profile)
        if profile == 'qwen3-1.7b':
            data['prepare'].prepare(output, data['root'])
        else:
            data['prepare'].stage(output, data['root'])
        return output

    def invoke(self, action='synth', profile='qwen3-1.7b', mode='zip', extra=(), staged=None):
        staged = staged or self.stage(profile)
        output = self.root/('result-'+profile+'-'+mode)
        argv = [action, '--profile', profile, '--build-dir', str(staged), '--hdk', str(self.hdk),
                '--output', str(output), *map(str, extra)]
        code = ('import importlib.util,pathlib,sys;'
                's=importlib.util.spec_from_file_location("tested_build",sys.argv[1]);'
                'm=importlib.util.module_from_spec(s);s.loader.exec_module(m);'
                'sys.exit(m.main(sys.argv[3:],repository=pathlib.Path(sys.argv[2])))')
        result = subprocess.run([sys.executable, '-I', '-S', '-B', '-c', code, str(HERE/'qwen_build.py'), str(self.repo), *argv],
                                env=dict(self.env, STUB_MODE=mode), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        self.invocation_count += 1
        (self.root/f'invocation-{self.invocation_count}.stdout.log').write_bytes(result.stdout)
        (self.root/f'invocation-{self.invocation_count}.stderr.log').write_bytes(result.stderr)
        (self.root/f'invocation-{self.invocation_count}.json').write_text(json.dumps(dict(argv=argv,actual_exit=result.returncode)))
        return result, output, staged

    def launch(self, staged, label, mode):
        output = self.root/('result-'+label)
        argv = ['synth','--profile','qwen3-1.7b','--build-dir',str(staged),'--hdk',str(self.hdk),'--output',str(output)]
        code = ('import importlib.util,pathlib,sys;'
                's=importlib.util.spec_from_file_location("tested_owner",sys.argv[1]);'
                'm=importlib.util.module_from_spec(s);s.loader.exec_module(m);'
                'sys.exit(m.main(sys.argv[3:],repository=pathlib.Path(sys.argv[2])))')
        client = os.environ.get('QWEN_BUILD_TEST_CLIENT', str(HERE/'qwen_build.py'))
        env = dict(self.env, STUB_MODE=mode, STUB_CALLS=str(self.root/(label+'-calls.jsonl')),
                   STUB_GIT_CALLS=str(self.root/(label+'-git.log')),
                   STUB_READY=str(self.root/(label+'-ready')),STUB_RELEASE=str(self.root/(label+'-release')))
        process = subprocess.Popen([sys.executable,'-I','-S','-B','-c',code,client,str(self.repo),*argv],
                                   env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        (self.root/(label+'-process.json')).write_text(json.dumps(dict(pid=process.pid,argv=argv,client=client)))
        return process, output

    def completed(self, process, label):
        stdout, stderr = process.communicate(timeout=20)
        (self.root/(label+'.stdout.log')).write_bytes(stdout)
        (self.root/(label+'.stderr.log')).write_bytes(stderr)
        (self.root/(label+'-exit.json')).write_text(json.dumps(dict(actual_exit=process.returncode)))
        return subprocess.CompletedProcess(process.args,process.returncode,stdout,stderr)

    def wait_inside_stub(self, process, label):
        deadline = time.monotonic()+10
        while not (self.root/(label+'-ready')).exists():
            self.assertIsNone(process.poll(), 'Controlled owner exited before its barrier')
            self.assertLess(time.monotonic(),deadline,'Controlled barrier was not reached')
            time.sleep(.01)

    def test_staged_owner_overlap_and_independent_stage(self):
        staged = self.stage('qwen3-1.7b')
        alias = self.root/'canonical-stage-alias'
        alias.symlink_to(staged,target_is_directory=True)
        owner, out_a = self.launch(staged,'owner-A','block_missing')
        try:
            self.wait_inside_stub(owner,'owner-A')
            lock_path = staged/'cl_qwen/.qwen-build.lock'
            inode = lock_path.stat().st_ino
            contender, out_b = self.launch(alias,'owner-B','zip')
            result_b = self.completed(contender,'owner-B')
            self.no_success(result_b,out_b)
            self.assertEqual(result_b.returncode,75)
            self.assertFalse((self.root/'owner-B-calls.jsonl').exists())
            self.assertFalse((self.root/'owner-B-git.log').exists())
            self.assertIsNone(owner.poll())
            other = self.root/'independent-stage'
            data = build.profile(self.repo,'qwen3-1.7b')
            data['prepare'].prepare(other,data['root'])
            independent, out_d = self.launch(other,'independent-D','zip')
            result_d = self.completed(independent,'independent-D')
            self.assertEqual(result_d.returncode,0,result_d.stderr)
            self.assertTrue((out_d/'FINISHED.json').exists())
            self.assertIsNone(owner.poll())
        finally:
            (self.root/'owner-A-release').touch()
            result_a = self.completed(owner,'owner-A')
        self.no_success(result_a,out_a)
        self.assertEqual(json.loads((out_a/'CHILD-EXIT.json').read_text())['actual_child_exit'],0)
        expected = staged/'cl_qwen/build/checkpoints/cl_qwen.private_supported_c2_100.post_synth.dcp'
        self.assertFalse(expected.exists())
        # The blocked owner wrote nothing and cannot collect the other stage's ZIP.
        after, out_c = self.launch(staged,'after-failure-C','zip')
        result_c = self.completed(after,'after-failure-C')
        self.assertEqual(result_c.returncode,0,result_c.stderr)
        self.assertTrue((out_c/'FINISHED.json').exists())
        self.assertEqual(lock_path.stat().st_ino,inode)
        (self.root/'RACE-VERIFIED.json').write_text(json.dumps(dict(
            forced_owner_inside_batch=True, contender_used_canonical_path_alias=True,
            contender_exit=result_b.returncode, contender_reached_SDK_or_Vivado=False,
            independent_stage_exit=result_d.returncode, independent_stage_completed_while_owner_blocked=True,
            owner_child_exit=0, owner_client_exit=result_a.returncode,
            zero_child_artifact_absent_before_next_owner=True, after_failure_owner_exit=result_c.returncode,
            persistent_lock_inode=inode, persistent_lock_not_unlinked=True,
            actual_vendor_or_AWS=False),indent=2)+'\n')

    def test_lock_released_after_nonzero_child(self):
        staged = self.stage('qwen3-1.7b')
        first,out,_ = self.invoke(mode='fail19',staged=staged)
        self.no_success(first,out)
        second,out,_ = self.invoke(mode='zip',staged=staged)
        self.assertEqual(second.returncode,0,second.stderr)
        self.assertTrue((out/'FINISHED.json').exists())

    def test_lock_released_after_preflight_failure(self):
        staged = self.stage('qwen3-1.7b')
        self.env['STUB_HDK_REV']='0'*40
        first,out,_ = self.invoke(staged=staged)
        self.no_success(first,out)
        self.env['STUB_HDK_REV']=HDK_REV
        second,out,_ = self.invoke(staged=staged)
        self.assertEqual(second.returncode,0,second.stderr)
        self.assertTrue((out/'FINISHED.json').exists())

    def test_lock_inode_persists_after_success(self):
        result,out,staged = self.invoke()
        self.assertEqual(result.returncode,0,result.stderr)
        record = json.loads((out/'WORKSPACE-LOCK.json').read_text())
        path = staged/'cl_qwen/.qwen-build.lock'
        self.assertTrue(path.is_file())
        with build.workspace_lock(staged.resolve()) as lease:
            self.assertEqual(lease['inode'],record['inode'])
            self.assertEqual(lease['canonical_stage'],str((staged/'cl_qwen').resolve()))
        self.assertTrue(path.exists())

    def test_symlink_workspace_lock_refused(self):
        staged = self.stage('qwen3-1.7b')
        sentinel = self.root/'preserve-lock-sentinel'
        sentinel.write_bytes(b'keep')
        (staged/'cl_qwen/.qwen-build.lock').symlink_to(sentinel)
        result,out,_ = self.invoke(staged=staged)
        self.no_success(result,out)
        self.assertFalse(self.calls.exists())
        self.assertEqual(sentinel.read_bytes(),b'keep')

    def no_success(self, result, output):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse((output/'FINISHED.json').exists())
        self.assertNotIn(b'"passed": true', result.stdout)
        if (output/'FAILED.json').exists():
            self.assertIs(json.loads((output/'FAILED.json').read_text())['passed'], False)

    def positive(self, profile):
        result, output, staged = self.invoke(profile=profile)
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads((output/'FINISHED.json').read_text())
        self.assertTrue(receipt['passed'])
        self.assertEqual(receipt['actual_child_exit'], 0)
        self.assertEqual(receipt['clock_recipes'], build.CLOCKS)
        self.assertEqual(receipt['aws_hdk_revision'], HDK_REV)
        self.assertEqual(receipt['aws_ip_revision'], IP_REV)
        self.assertEqual(receipt['tool']['version'], '2025.2')
        self.assertFalse(receipt['timing_or_hardware_qualified'])
        self.assertEqual(receipt['artifact_identity'], build.identity(Path(receipt['artifact'])))
        self.assertTrue(receipt['checkpoint_ZIP_CRC_checked'])
        calls = [json.loads(x) for x in self.calls.read_text().splitlines()]
        self.assertEqual(calls[0], ['-version'])
        self.assertEqual(calls[1][-4:], ['A0', 'B0', 'C2', 'H1'])
        environment = json.loads((output/'STARTED.json').read_text())['environment']
        self.assertEqual(environment['HDK_COMMON_DIR'], str((self.hdk/'hdk/common').resolve()))
        self.assertEqual(environment['HDK_IP_SRC_DIR'], str((self.hdk/'hdk/common/ip/cl_ip/cl_ip.srcs/sources_1/ip').resolve()))
        self.assertEqual(environment['VIVADO_TOOL_VERSION'], '2025.2')

    def test_q17_success_requires_fresh_checkpoint(self): self.positive('qwen3-1.7b')
    def test_q8_success_requires_fresh_checkpoint(self): self.positive('qwen3-8b')

    def test_q17_exit19_propagates(self):
        result, output, _ = self.invoke(mode='fail19')
        self.no_success(result, output)
        self.assertEqual(result.returncode, 19)
        self.assertEqual(json.loads((output/'CHILD-EXIT.json').read_text())['actual_child_exit'], 19)

    def test_q8_exit19_propagates(self):
        result, output, _ = self.invoke(profile='qwen3-8b', mode='fail19')
        self.no_success(result, output)
        self.assertEqual(result.returncode, 19)

    def test_nonzero_cannot_be_saved_by_an_artifact(self):
        result, output, _ = self.invoke(mode='fail19_with_zip')
        self.no_success(result, output)
        self.assertEqual(result.returncode, 19)

    def test_zero_without_artifact_fails(self):
        result, output, _ = self.invoke(mode='missing')
        self.no_success(result, output)

    def test_invalid_checkpoint_fails(self):
        result, output, _ = self.invoke(mode='invalid')
        self.no_success(result, output)

    def test_source_mutation_fails(self):
        result, output, _ = self.invoke(mode='mutate')
        self.no_success(result, output)

    def test_stale_artifact_does_not_launch_vivado(self):
        staged = self.stage('qwen3-1.7b')
        artifact = staged/'cl_qwen/build/checkpoints/cl_qwen.private_supported_c2_100.post_synth.dcp'
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b'old artifact')
        result, output, _ = self.invoke(staged=staged)
        self.no_success(result, output)
        self.assertFalse(self.calls.exists())
        self.assertEqual(artifact.read_bytes(), b'old artifact')

    def test_wrong_tool_version_fails(self):
        result, output, _ = self.invoke(mode='wrong_version')
        self.no_success(result, output)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_wrong_hdk_identity_refused_before_vivado(self):
        self.env['STUB_HDK_REV'] = '0'*40
        result, output, _ = self.invoke()
        self.no_success(result, output)
        self.assertFalse(self.calls.exists())

    def test_wrong_shell_hash_refused_before_vivado(self):
        (self.hdk/'hdk/common/shell_stable/build/checkpoints/from_aws/cl_bb_routed.small_shell.dcp').write_bytes(b'changed shell')
        result, output, _ = self.invoke()
        self.no_success(result, output)
        self.assertFalse(self.calls.exists())

    def test_failed_version_query_fails(self):
        result, output, _ = self.invoke(mode='version19')
        self.no_success(result, output)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def package_case(self, profile, suffix='route.dcp', digest=None, tag='2026_11_07-test'):
        checkpoint = self.root/suffix
        with zipfile.ZipFile(checkpoint, 'w') as stream:
            stream.writestr('STUB-NOT-A-DCP.txt', 'Synthetic package fixture')
        return self.invoke('package', profile, extra=['--checkpoint', checkpoint, '--checkpoint-sha256',
                            digest or build.identity(checkpoint)['sha256'], '--tag', tag])

    def package_positive(self, profile):
        result, output, _ = self.package_case(profile)
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads((output/'FINISHED.json').read_text())
        self.assertFalse(receipt['AFI_created'])
        manifest = receipt['manifest']
        self.assertEqual(manifest['manifest_format_version'], 2)
        self.assertEqual(manifest['tool_version'], 'v2025.2')
        self.assertEqual(manifest['shell_version'], '0x10212415')
        self.assertEqual(manifest['hdk_version'], 'STUB-UNIT-SDK')
        self.assertEqual([manifest['clock_recipe_'+key] for key in ('a','b','c','hbm')], ['A0','B0','C2','H1'])
        self.assertEqual(manifest['pci_device_id'], '0xf004')
        self.assertEqual(manifest['pci_subsystem_id'], '0x1d51')
        with tarfile.open(receipt['archive']) as stream:
            self.assertEqual(len(stream.getmembers()), 2)
            data = stream.extractfile('to_aws/'+manifest['dcp_file_name']).read()
            self.assertEqual(hashlib.sha256(data).hexdigest(), manifest['dcp_hash'])
        self.assertEqual([json.loads(x)for x in self.calls.read_text().splitlines()], [['-version']])

    def test_q17_package_contract(self): self.package_positive('qwen3-1.7b')
    def test_q8_package_contract(self): self.package_positive('qwen3-8b')

    def test_violated_checkpoint_refused(self):
        result, output, _ = self.package_case('qwen3-1.7b', suffix='route.VIOLATED.dcp')
        self.no_success(result, output)

    def test_wrong_checkpoint_hash_refused(self):
        result, output, _ = self.package_case('qwen3-1.7b', digest='0'*64)
        self.no_success(result, output)

    def test_unsafe_package_tag_refused(self):
        result, output, _ = self.package_case('qwen3-1.7b', tag='../escape')
        self.no_success(result, output)

    def test_empty_zip_checkpoint_refused(self):
        path = self.root/'empty.dcp'
        with zipfile.ZipFile(path, 'w'):
            pass
        with self.assertRaises(build.Failed):
            build.checkpoint(path)

    def test_bad_crc_checkpoint_refused(self):
        path = self.root/'crc.dcp'
        with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_STORED) as stream:
            stream.writestr('marker.txt', 'UNIQUE_CRC_PAYLOAD')
        raw = path.read_bytes()
        self.assertIn(b'UNIQUE_CRC_PAYLOAD', raw)
        path.write_bytes(raw.replace(b'UNIQUE_CRC_PAYLOAD', b'UNIQUE_CRC_PAYLOAE'))
        with self.assertRaises(build.Failed):
            build.checkpoint(path)

    def test_symlink_checkpoint_refused(self):
        real = self.root/'real.dcp'
        with zipfile.ZipFile(real, 'w') as stream:
            stream.writestr('stub.txt', 'fixture')
        path = self.root/'link.dcp'
        path.symlink_to(real)
        with self.assertRaises(build.Failed):
            build.checkpoint(path)

    def test_package_optional_probes(self):
        path = self.root/'route.dcp'
        with zipfile.ZipFile(path, 'w') as stream:
            stream.writestr('stub.txt', 'fixture')
        probes = self.root/'debug.ltx'
        probes.write_bytes(b'unit debug probe fixture')
        result, output, _ = self.invoke('package', extra=['--checkpoint', path, '--checkpoint-sha256',
            build.identity(path)['sha256'], '--tag', 'probe_test', '--probes', probes])
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads((output/'FINISHED.json').read_text())
        self.assertEqual(receipt['members']['probe_test.debug_probes.ltx'], build.identity(probes))

    def test_existing_output_preserved(self):
        self.stage('qwen3-1.7b')
        output = self.root/'result-qwen3-1.7b-zip'
        output.mkdir()
        (output/'sentinel').write_bytes(b'keep')
        result, _, _ = self.invoke(staged=self.root/'staged-qwen3-1.7b')
        self.no_success(result, output)
        self.assertEqual((output/'sentinel').read_bytes(), b'keep')

    def test_actual_released_profile_inventories_load(self):
        for name in build.TAGS:
            data = build.profile(SOURCE, name)
            self.assertEqual(data['selected']['aws_hdk_revision'], HDK_REV)
            self.assertEqual(data['selected']['aws_ip_revision'], IP_REV)
            self.assertEqual(data['version'], '2025.2')
            self.assertEqual(data['selected']['clock_recipes'], build.CLOCKS)

    def test_hardware_guide_commands_match_the_parser(self):
        for profile in build.TAGS:
            guide = (HERE.parent/'demos'/profile/'HARDWARE.md').read_text()
            self.assertNotIn('--package-only', guide)
            actions = []
            for block in re.findall(r'```sh\n(.*?)\n```', guide, re.DOTALL):
                syntax = subprocess.run(['/bin/bash', '-n'], input=block.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                for line in block.replace('\\\n', ' ').splitlines():
                    if line.strip().startswith('python3.12 ../../tools/qwen_build.py '):
                        args = build.argument_parser().parse_args(shlex.split(line)[2:])
                        self.assertEqual(args.profile, profile)
                        if args.action == 'package':
                            self.assertIsNotNone(args.checkpoint)
                            self.assertIsNotNone(args.checkpoint_sha256)
                            self.assertIsNotNone(args.tag)
                        actions.append(args.action)
            self.assertEqual(actions, ['synth', 'package'])


if __name__ == '__main__':
    unittest.main()
