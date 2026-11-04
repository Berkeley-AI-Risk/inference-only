"""Replay declarative native SMT induction rules with bounded engine resources.

This is shared orchestration for source-bound setup checks. Its return value
reports the selected rules, not completion of a whole inference-only theorem.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import time

from checkpoint import atomic_bytes, atomic_json, snapshot
from prepare import sha


def conjunction(items):
    return '(and '+' '.join(items)+')' if items else 'true'


def validate(project, plan_name='PLAN.json', ancestors=None):
    ancestors = set() if ancestors is None else set(ancestors)
    path = (project/plan_name).resolve()
    if path in ancestors: raise ValueError('Circular external proof dependency')
    ancestors.add(path)
    plan = json.loads((project/plan_name).read_text())
    for name, expected in plan['inputs'].items():
        if sha((project/name).read_bytes()) != expected:
            raise ValueError('Input identity changed: '+name)
    source = json.loads((project/plan.get('source_manifest','SOURCES.json')).read_text())
    from prepare import MODEL
    for row in source['sources'].values():
        if sha((MODEL/row['model_source']).read_bytes()) != row['sha256']:
            raise ValueError('Source identity changed: '+row['model_source'])
    external = {}
    for alias, descriptor in plan.get('external_facts', {}).items():
        prior = validate(project, descriptor['plan'], ancestors)
        if (not set(prior['bodies']) <= set(plan['bodies']) or
                not set(prior['declarations']) <= set(plan['declarations'])):
            raise ValueError('External fact has a different source/formula context')
        checks = json.loads((project/prior.get('checks_file','CHECKS.json')).read_text())
        if checks['plan_sha256'] != sha((project/descriptor['plan']).read_bytes()):
            raise ValueError('External verification is stale')
        name = descriptor['rule'];rule = prior['rules'][name];result = checks['rules'][name]
        if rule.get('expected','unsat') != 'unsat' or not result['passed']:
            raise ValueError('External fact is not a proved implication')
        body = '\n'.join((project/filename).read_text() for filename in prior['bodies'])
        exact = query(prior,name,body).encode()
        query_path = (project/result['command'][-1]).resolve()
        if not query_path.is_relative_to((project/'queries').resolve()):
            raise ValueError('External engine query outside this project')
        raw = (query_path.parent/'z3.log').read_bytes()
        if (query_path.read_bytes() != exact or sha(exact) != result['query_sha256'] or
                sha(raw) != result['log_sha256'] or raw.strip() != b'unsat'):
            raise ValueError('External engine evidence differs from its exact rule')
        external[alias] = rule
    plan['_external_rules'] = external
    seen = set(external)
    for name in plan['order']:
        rule = plan['rules'][name]
        if not set(rule.get('dependencies', [])) <= seen:
            raise ValueError('Forward/circular proof dependency')
        seen.add(name)
    if seen != set(plan['rules']) | set(external):
        raise ValueError('Proof order omits rules')
    return plan


def query(plan, rule_name, body):
    rule = plan['rules'][rule_name]
    facts = list(rule['assumptions'])
    for name in rule.get('dependencies', []):
        prior = plan['rules'].get(name,plan.get('_external_rules',{}).get(name))
        if prior.get('expected', 'unsat') != 'unsat':
            raise ValueError('A satisfiable example is not a theorem import')
        facts.append('(=> '+conjunction(prior['assumptions'])+' '+prior['conclusion']+')')
    return ('(set-option :produce-models true)\n'+body+'\n'+
            '\n'.join(plan['declarations'])+'\n'+
            '\n'.join('(assert '+fact+')' for fact in facts)+'\n'+
            '(assert (not '+rule['conclusion']+'))\n(check-sat)\n')

