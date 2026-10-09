"""Offline Streamlit UI rendering plus clearly synthetic worker fixtures."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from streamlit.testing.v1 import AppTest
import fpga_backend
from test_fpga_backend import FakeLink


# Allow cold imports/rendering in the offline UI fixture. This is not
# a hardware-performance bound or a relaxation of reply assertions.
class AppTests(unittest.TestCase):
    def test_default_page_without_hardware(self):
        app = AppTest.from_file(str(Path(__file__).with_name('streamlit_app.py')), default_timeout=30).run()
        self.assertFalse(app.exception)
        self.assertEqual(app.title[0].value, 'FPGA story lab')
        self.assertEqual(app.text_area[0].value, 'once')
        self.assertEqual(app.number_input[0].value, 32)
        self.assertEqual(len(app.metric), 3)
        self.assertEqual(app.metric[0].value, '—')
        captions = '\n'.join(item.value for item in app.caption)
        explanation = '\n'.join(item.value for item in app.markdown)
        self.assertIn('All three hardware variants', captions)
        for phrase in ('Three builds are available', 'K/V-protected', 'encrypted-memory',
                       'public demonstration keys', 'matching encrypted flash image'):
            self.assertIn(phrase, explanation)
        self.assertNotIn('Both hardware variants', captions)
        self.assertNotIn('Two experimental builds', explanation)

    def test_synthetic_generation_render(self):
        with tempfile.TemporaryDirectory(prefix='fpga-ui-offline-') as directory:
            fake = FakeLink()
            controller = fpga_backend.Controller(link_factory=lambda observe: fake, logs=directory)
            with patch('fpga_backend.Controller', return_value=controller):
                # Clear any cached controller from the earlier no-hardware render.
                import streamlit as st
                st.cache_resource.clear()
                app = AppTest.from_file(str(Path(__file__).with_name('streamlit_app.py')), default_timeout=30).run()
                app.text_area[0].set_value('around')
                app.number_input[0].set_value(4)
                app.button[0].click().run()
                if controller.thread:
                    controller.thread.join(3)
                    self.assertFalse(controller.thread.is_alive(), "Synthetic worker did not finish")
                app.run()
                self.assertFalse(app.exception)
                self.assertTrue(any('around him. he felt' in item.value for item in app.text))
                self.assertEqual(app.metric[2].value, '4')
                self.assertEqual(app.text_area[0].value, 'around')
                self.assertEqual(app.number_input[0].value, 4)
                self.assertTrue(controller.result.clear_acknowledged)
                self.assertEqual(fake.calls[0], ('clear', 0))
                st.cache_resource.clear()


if __name__ == '__main__': unittest.main(verbosity=2)
