"""Finite trace-review controls, not RTL or numerical execution."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('short_trace_review', HERE/'run.py')
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)


def fixture(protected):
    events = []
    for scenario in range(5):
        mutation = scenario in (1, 2)
        if mutation:
            if protected:
                events.append(dict(event='fault_edge', scenario=scenario, auth_error=True,
                                   key_valid=False, value_valid=False, key_ready=False, value_ready=False))
            else:
                events.append(dict(event='operand_handshake', scenario=scenario,
                                   role=scenario-1, changed=True))
        writes = 2 if scenario == 4 else 1
        outcome = ('fault_prevents_target_use' if protected else 'changed_operand_used') if mutation else 'original_operand_used'
        events.append(dict(event='result', scenario=scenario, protected_build=protected,
                           actual_writes=writes, independent_roots=writes if protected else 0,
                           outcome=outcome, target_valid_seen=mutation and not protected,
                           fault_cycle=1 if mutation and protected else 0,
                           changed_key_used=mutation and not protected and scenario == 1,
                           changed_value_used=mutation and not protected and scenario == 2,
                           clear_cycle=1 if scenario == 4 else 0,
                           old_return_cycle=2 if scenario == 4 else 0,
                           reopen_cycle=3 if scenario == 4 else 0,
                           blocked_clear_checks=1 if scenario == 4 else 0))
    return events


class TraceControls(unittest.TestCase):
    def review(self, plain=None, protected=None):
        with tempfile.TemporaryDirectory() as d:
            paths = []
            for selected, events in [(False, fixture(False) if plain is None else plain),
                                     (True, fixture(True) if protected is None else protected)]:
                path = Path(d)/('protected.log' if selected else 'plain.log')
                path.write_text(''.join(json.dumps(x)+'\n' for x in events)
                                +'PASS operand_integrity_observation protected='+str(int(selected))+'\n')
                paths.append(path)
            return r.review_logs(*paths)

    def test_prefetch_fault_with_consumer_not_ready_is_accepted(self):
        self.assertTrue(self.review()['passed'])

    def test_any_affected_valid_exposure_is_rejected(self):
        events = fixture(True)
        next(x for x in events if x['event'] == 'result' and x['scenario'] == 2)['target_valid_seen'] = True
        with self.assertRaisesRegex(RuntimeError, 'asserted valid'):
            self.review(protected=events)

    def test_affected_handshake_is_rejected_even_for_unchanged_bytes(self):
        events = fixture(True)
        events.insert(0, dict(event='operand_handshake', scenario=2, role=1, changed=False))
        with self.assertRaisesRegex(RuntimeError, 'was consumed'):
            self.review(protected=events)

    def test_authentication_fault_and_invalid_target_are_required(self):
        for field, value in [('auth_error', False), ('value_valid', True)]:
            events = fixture(True)
            next(x for x in events if x['event'] == 'fault_edge' and x['scenario'] == 2)[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, 'Authentication fault'):
                self.review(protected=events)

    def test_plain_control_requires_real_target_exposure_and_changed_use(self):
        for field, value in [('target_valid_seen', False), ('remove_handshake', True)]:
            events = copy.deepcopy(fixture(False))
            if field == 'remove_handshake':
                events = [x for x in events if not (x['event'] == 'operand_handshake' and x['scenario'] == 2)]
            else:
                next(x for x in events if x['event'] == 'result' and x['scenario'] == 2)[field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                self.review(plain=events)


if __name__ == '__main__':
    unittest.main()
