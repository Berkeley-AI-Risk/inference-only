import hashlib,json,os,pty,select,sys,tempfile,threading,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'reference'))
import home_auth as h
from home_server import make_server
from serial_client import AuthorizedSerial,BackgroundAuthorization,crc8

class SerialRelayTest(unittest.TestCase):
    def test_real_grant_and_token_frames_on_pseudoterminal(self):
        self.exercise(False)
    def test_background_relay_responds_while_controller_is_busy(self):
        self.exercise(True)
    def test_paced_grant_preserves_exact_signature_and_token_frames(self):
        self.exercise(True,1,.0001)
    def exercise(self,background,grant_chunk_bytes=0,grant_chunk_pause=0):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);root=hashlib.sha256(b'pty root').digest()
            (p/'policy.json').write_text(json.dumps(h.policy_for([root])))
            server=make_server(p/'policy.json',p/'state.json')
            serving=threading.Thread(target=server.serve_forever,daemon=True);serving.start()
            master,slave=pty.openpty();port=os.ttyname(slave)
            client=AuthorizedSerial(port,f'http://127.0.0.1:{server.server_port}/authorize',root.hex(),
                                    grant_chunk_bytes=grant_chunk_bytes,grant_chunk_pause=grant_chunk_pause)
            relay=BackgroundAuthorization(client) if background else None
            granted=threading.Event()
            errors=[]
            request=h.request_bytes(h.DEVICE_ID,bytes(range(1,33)),root)
            def read(n):
                data=b''
                while len(data)<n:
                    if not select.select([master],[],[],5)[0]:raise TimeoutError('peer timeout')
                    data+=os.read(master,n-len(data))
                return data
            def peer():
                try:
                    os.write(master,b'\xa6'+request)
                    grant=read(h.GRANT_BYTES)
                    self.assertEqual(grant[:128],request)
                    self.assertTrue(h.su.lms_verify(server.home.public_key,request,grant[128:]))
                    granted.set()
                    command=read(5)
                    self.assertEqual(command,bytes([0xa5,2,0,0,crc8(bytes([0xa5,2,0,0]))]))
                    reply=bytes([0x5a,0x82,0,0]);os.write(master,reply+bytes([crc8(reply)]))
                    # De-whitelisting must cause no grant bytes to be sent.
                    (p/'policy.json').write_text(json.dumps(h.policy_for([])))
                    os.write(master,b'\xa6'+h.request_bytes(h.DEVICE_ID,bytes(range(2,34)),root))
                    self.assertFalse(select.select([master],[],[],.3)[0])
                except BaseException as exc:errors.append(exc)
            thread=threading.Thread(target=peer,daemon=True);thread.start()
            try:
                if background:
                    # No main-thread serial read: represents a blocking FPGA load.
                    self.assertTrue(granted.wait(5),'Grant must be served before controller resumes')
                receive=relay.next_home if relay else client.next
                command=relay.command if relay else client.command
                self.assertEqual(receive()['decision'],'approved')
                self.assertEqual(command(2)['status'],0x82)
                self.assertEqual(receive()['decision'],'denied')
                if relay:relay.expect_quiet(.1)
                thread.join(6);self.assertFalse(thread.is_alive())
                if errors:raise errors[0]
                if relay:
                    unexpected=bytes([0x5a,0x82,0,0]);os.write(master,unexpected+bytes([crc8(unexpected)]))
                    with self.assertRaisesRegex(RuntimeError,'Unexpected serial output'):relay.expect_quiet(1)
            finally:
                if relay:relay.close()
                else:client.close()
                os.close(master);os.close(slave)
                server.shutdown();server.server_close();serving.join()

if __name__=='__main__':unittest.main(verbosity=2)
