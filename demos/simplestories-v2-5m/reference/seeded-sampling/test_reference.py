#!/usr/bin/env python3
"""Exact numeric and synthetic framing tests; no physical measurements or UART."""
import argparse
from dataclasses import asdict
import importlib.util
import json
from pathlib import Path
import random
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec)
    sys.modules[name]=m;spec.loader.exec_module(m);return m
model=module('_reference_test_model',HERE/'model.py')
reconstruct=module('_reference_test_reconstruct',HERE/'reconstruct_rom.py')
board=module('_reference_test_board',HERE/'compare_board.py')
ENGINE='scalar'

class ReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch=tempfile.TemporaryDirectory(prefix='seeded-reference-tests-');cls.root=Path(cls.scratch.name)
        rom=cls.root/'rom';rom.mkdir();cls.payloads=reconstruct.reconstruct()
        for name,raw in cls.payloads.items():(rom/name).write_bytes(raw)
        cls.loaded=model.load(rom,engine=ENGINE,build_dir=cls.root/'native')
        cls.np=cls.loaded['np'];cls.base=cls.loaded['baseline'];cls.fast=cls.loaded['oracle']
    @classmethod
    def tearDownClass(cls):cls.scratch.cleanup()

    def test_canonical_reconstruction_and_corruption_rejection(self):
        self.assertEqual(len(self.payloads),8)
        image=model.PACKAGE/'assets/board1-real-semantic-image2048.bin';raw=bytearray(image.read_bytes())
        raw[len(raw)//2]^=1;mutant=self.root/'wrong-image.bin';mutant.write_bytes(raw)
        with self.assertRaises(ValueError):reconstruct.reconstruct(mutant)

    def test_exact_normalization_and_rne_boundaries(self):
        rng=random.Random(9814761);np=self.np
        for _ in range(250):
            n=rng.randint(1,256);e=np.array([rng.randint(-28,-5)for _ in range(n)],dtype=np.int16)
            v=np.array([rng.randint(-(1<<rng.randint(0,35)),(1<<rng.randint(0,35))-1)for _ in range(n)],dtype=np.int64)
            a,b=self.base.OracleStats(),self.fast.OracleStats()
            x=self.base._normalize_mixed(v,e,a);y=self.fast._normalize_mixed(v,e,b)
            self.assertEqual(x.exponent,y.exponent);self.assertTrue(np.array_equal(x.value,y.value));self.assertEqual(asdict(a),asdict(b))
        values=np.array([0,1,-1,32767,-32767,32768,-32768,(1<<49)-1,-((1<<49)-1)],dtype=np.int64)
        for shift in range(-12,70):self.assertTrue(np.array_equal(self.base._round_shift_even(values,shift),self.fast._round_shift_even(values,shift)))

    def test_normalization_power_boundaries_and_even_odd_rne_ties(self):
        np=self.np
        for exponent in(-80,-64,-40,-33,-32,-20,-1,0,30,31,32,50,80):
            for bit in range(51):
                for sign in(-1,1):
                    values=np.array([sign*((1<<bit)-1),sign*(1<<bit),sign*((1<<bit)+1),0],dtype=np.int64)
                    before=after=None;old_error=new_error=False;a,b=self.base.OracleStats(),self.fast.OracleStats()
                    try:before=self.base._normalize_mixed(values,np.full(4,exponent,dtype=np.int16),a)
                    except(self.base.QuantizationError,OverflowError):old_error=True
                    try:after=self.fast._normalize_mixed(values,np.full(4,exponent,dtype=np.int16),b)
                    except(self.fast.QuantizationError,OverflowError):new_error=True
                    self.assertEqual(old_error,new_error)
                    if not old_error:
                        self.assertEqual(before.exponent,after.exponent)
                        self.assertTrue(np.array_equal(before.value,after.value));self.assertEqual(asdict(a),asdict(b))
        for shift in range(63):
            midpoint=1<<(shift-1)if shift else 0;values=[]
            for quotient in(0,1,2,3,32766,32767):
                for delta in(-1,0,1):
                    value=(quotient<<shift)+midpoint+delta
                    if 0<=value<1<<63:values.extend((value,-value))
            values=np.array(values,dtype=np.int64)
            self.assertTrue(np.array_equal(self.base._round_shift_even(values,shift),self.fast._round_shift_even(values,shift)))

    def test_whole_model_greedy_kv_and_range_stats_lockstep(self):
        old=self.base.IntegerLlama(self.loaded['canonical_model']);new=self.loaded['Model'](self.loaded['data'])
        cases=json.loads((model.PACKAGE/'tests/reference-cases.json').read_bytes())['around128']
        for i,token in enumerate([378]+cases['generated_tokens'][:7]):
            expected=old.forward_token(token);head=new.consume(token)
            actual,_=self.loaded['sampler'].sample(head,0,(1,0))
            self.assertEqual(actual,expected[0]);self.assertEqual(actual,cases['generated_tokens'][i])
            self.assertEqual(model.state_digest(old),model.state_digest(new));self.assertEqual(asdict(old.stats),asdict(new.stats))

    def test_all_temperatures_seeded_kats_and_zero_mapping(self):
        sampler=self.loaded['sampler'];Model=self.loaded['Model']
        for code,tokens in enumerate(([200,15,103],[247,130,32],[357,3898,104],[3436,4007,141])):
            engine=Model(self.loaded['data']);head=engine.consume(378)
            self.assertEqual(model.generate(engine,head,sampler,code,model.SEED_A,3)['generated_tokens'],tokens)
        self.assertEqual(sampler.initial_state(0),sampler.initial_state(1))
        self.assertEqual(sampler.initial_state(0),(1,0))

    def test_reference_fault_latches_before_position_commit_and_clear_recovers(self):
        engine=self.loaded['Model'](self.loaded['data']);original=engine.raw_head
        def rejected(_):raise self.fast.QuantizationError('synthetic head range fault')
        engine.raw_head=rejected
        with self.assertRaises(self.fast.QuantizationError):engine.consume(378)
        self.assertTrue(engine.faulted);self.assertEqual(engine.position,0)
        with self.assertRaises(ValueError):engine.consume(378)
        engine.clear();engine.raw_head=original
        self.assertFalse(engine.faulted);self.assertEqual(engine.position,0)
        self.assertEqual(self.loaded['sampler'].sample(engine.consume(378),0,(1,0))[0],200)

    def test_native_build_cannot_write_inside_public_package(self):
        with self.assertRaises(ValueError):
            model.native_functions(self.fast,self.np,model.PACKAGE/'unwanted-native-build')

    def test_synthetic_board_mutations(self):
        import copy
        golden=json.loads((HERE/'goldens/around128-t2-seed-a.json').read_bytes());code=2;seed=int(golden['seed'],16)
        pairs=[(board.legacy(2),board.response(0x82)),
            (board.frame(bytes([0xa5,3,code])+seed.to_bytes(16,'little')),board.response(0x83,code)),
            (board.legacy(0,378),board.response(0x80))]
        pairs.extend((board.legacy(1),board.response(0x81,t))for t in golden['generated_tokens'])
        pairs.append((board.legacy(2),board.response(0x82)))
        data={k:golden[k]for k in('case','temperature','seed','prompt_tokens','generated_tokens')}
        data.update(image_sha256=board.FPGA_SHA,wire=[dict(direction=d,frame_hex=raw)for pair in pairs for d,raw in zip(('tx','rx'),pair)])
        self.assertEqual(board.compare(data,golden)['outputs_compared'],128)
        for mutation in('token','wire','seed','missing'):
            changed=copy.deepcopy(data)
            if mutation=='token':changed['generated_tokens'][40]+=1
            elif mutation=='wire':changed['wire'][7]['frame_hex']=board.response(0x81,13)
            elif mutation=='seed':changed['seed']='0x'+'0'*32
            else:changed['wire'].pop()
            with self.assertRaises(ValueError):board.compare(changed,golden)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--engine',choices=('scalar','native'),default='scalar')
    args,rest=parser.parse_known_args();ENGINE=args.engine;unittest.main(argv=[sys.argv[0],*rest])
