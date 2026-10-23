"""Streamlit sampling controls with a synthetic FPGA peer; no device access."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import streamlit as st
from streamlit.testing.v1 import AppTest
import fpga_backend

SEED = '0x99aabbccddeeff001122334455667788'


class SeededPeer:
    def __init__(self):
        self.calls = []
        self.code = '0'
        self.position = 0

    def __enter__(self): return self
    def __exit__(self, *args): pass

    def configure(self, temperature, seed):
        self.calls.append(('settings', temperature, seed))
        self.code = temperature
        self.position = 0

    def command(self, operation, operand=0):
        self.calls.append((operation, operand))
        if operation == 'clear':
            self.position = 0
        if operation == 'step':
            values = (357, 3898, 104) if self.code == '1' else (200, 15, 103)
            result = values[self.position]
            self.position += 1
            return result
        return None


class SeededUITests(unittest.TestCase):
    def setUp(self):
        st.cache_resource.clear()
        self.directory = tempfile.TemporaryDirectory(prefix='seeded-ui-offline-')
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(st.cache_resource.clear)
        self.peer = SeededPeer()
        self.controller = fpga_backend.Controller(link_factory=lambda observe: self.peer,
                                                  logs=self.directory.name)

    def render(self):
        return AppTest.from_file(str(Path(__file__).with_name('streamlit_app.py')),
                                 default_timeout=30).run()

    def test_sampling_controls_submit_and_display_the_actual_run_seed(self):
        with patch('fpga_backend.Controller', return_value=self.controller), \
             patch('runtime_profile.configured_variant_id', return_value='seeded-sampling'):
            app = self.render()
            self.assertFalse(app.exception)
            self.assertEqual(app.segmented_control[0].value, '0')
            self.assertEqual(app.text_input[0].value, '')
            app.text_area[0].set_value('around')
            app.number_input[0].set_value(3)
            app.segmented_control[0].set_value('1')
            app.text_input[0].set_value(SEED)
            app.button[0].click().run()
            if self.controller.thread:
                self.controller.thread.join(3)
            app.run()
            self.assertFalse(app.exception)
            self.assertEqual(self.controller.result.generated, [357, 3898, 104])
            self.assertEqual(self.peer.calls[:3], [('clear', 0),
                ('settings', '1', int(SEED, 0)), ('append', 378)])
            self.assertEqual(self.peer.calls[-1], ('clear', 0))
            self.assertIn(SEED, '\n'.join(item.value for item in app.caption))
            self.assertEqual(app.text_input[0].value, SEED)

    def test_bad_seed_is_reported_without_starting_a_worker(self):
        with patch('fpga_backend.Controller', return_value=self.controller), \
             patch('runtime_profile.configured_variant_id', return_value='seeded-sampling'):
            app = self.render()
            app.segmented_control[0].set_value('1')
            app.text_input[0].set_value('not-a-seed')
            app.button[0].click().run()
            self.assertFalse(app.exception)
            self.assertTrue(app.error)
            self.assertFalse(self.peer.calls)
            self.assertIsNone(self.controller.thread)

    def test_original_builds_have_no_sampling_controls(self):
        with patch('fpga_backend.Controller', return_value=self.controller), \
             patch('runtime_profile.configured_variant_id', return_value='baseline'):
            app = self.render()
            self.assertFalse(app.exception)
            self.assertFalse(app.segmented_control)
            self.assertFalse(app.text_input)


if __name__ == '__main__':
    unittest.main()
