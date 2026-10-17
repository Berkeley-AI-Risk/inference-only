"""Streamlit offline presentation tests; no FPGA/network access."""
from pathlib import Path
import unittest
from unittest.mock import patch

import streamlit as st
from streamlit.testing.v1 import AppTest
from qwen_backend import Result


class FakeController:
    needs_check = False
    def __init__(self): self.result = Result(); self.calls=[]
    def busy(self): return False
    def snapshot(self, owner): return self.result
    def start(self, owner, prompt, count, raw):
        self.calls.append((prompt, count, raw))
        self.result = Result(owner=owner, job_id='12345678', state='complete',
            prompt=prompt, prompt_tokens=[9707], requested=count,
            steps=[dict(index=0, token=25, step_ns=1000, generation_elapsed_ns=1000,
                        prompt_elapsed_ns=2000, text=': fixture', end_marker=False)], text=': fixture')


class Tests(unittest.TestCase):
    def tearDown(self): st.cache_resource.clear()

    def test_form_and_generation(self):
        controller=FakeController()
        with patch('qwen_backend.Controller', return_value=controller):
            app=AppTest.from_file(str(Path(__file__).with_name('streamlit_app.py'))).run(timeout=10)
            self.assertFalse(app.exception)
            self.assertEqual(app.title[0].value, 'FPGA Qwen lab')
            self.assertEqual(len(app.metric), 3)
            self.assertEqual(app.number_input[0].label, 'Max new tokens')
            self.assertEqual(controller.calls, [])
            app.text_area[0].set_value('Hello')
            app.number_input[0].set_value(3)
            app.button[0].click().run(timeout=10)
            self.assertFalse(app.exception)
            self.assertEqual(controller.calls, [('Hello',3,False)])
            self.assertIn(': fixture', [x.value for x in app.text])

    def test_unconfigured(self):
        with patch('qwen_backend.Controller', side_effect=RuntimeError('Configure connection')):
            app=AppTest.from_file(str(Path(__file__).with_name('streamlit_app.py'))).run(timeout=10)
            self.assertFalse(app.exception)
            self.assertIn('Configure connection', app.error[0].value)


if __name__ == '__main__': unittest.main()
