import hashlib
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import home_auth as h
from home_server import make_server

A=hashlib.sha256(b'model A test commitment').digest()
B=hashlib.sha256(b'model B test commitment').digest()


class AuthorizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.authority=h.su.DemoAuthority(h.HOME_AUTHORITY)

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name)
        self.policy=self.path/'policy.json'
        self.write_policy([A,B])
        self.home=h.HomeBase(self.policy,self.path/'signer.json')
        self.now=0.
        self.device=h.BootDevice(self.home.public_key,timeout=10,lease=60,clock=lambda:self.now)

    def write_policy(self,roots):
        self.policy.write_text(json.dumps(h.policy_for(roots)))

    def approve(self,root=A):
        request=self.device.boot_verified_root(root)
        self.device.accept(self.home.authorize(request))
        return request

    def test_disabled_before_approval(self):
        self.device.boot_verified_root(A)
        with self.assertRaises(h.Reject): self.device.require_inference()

    def test_model_specific_approval(self):
        self.approve(A)
        self.assertEqual(self.device.require_inference(),A)

    def test_revoke_model_preserves_other_model(self):
        self.write_policy([B])
        with self.assertRaises(h.Reject): self.home.authorize(self.device.boot_verified_root(A))
        self.approve(B)
        self.assertEqual(self.device.require_inference(),B)

    def test_revoke_running_model_stops_at_lease_end(self):
        self.approve()
        self.write_policy([B])
        self.now=45
        with self.assertRaises(h.Reject): self.home.authorize(self.device.renew())
        self.assertEqual(self.device.require_inference(),A)
        self.now=60
        with self.assertRaises(h.Reject): self.device.require_inference()

    def test_successful_renewal_extends_without_reset(self):
        first=self.approve()
        self.now=45
        request=self.device.renew()
        self.assertNotEqual(first,request)
        self.assertEqual(self.device.require_inference(),A)
        self.device.accept(self.home.authorize(request))
        self.now=70
        self.assertEqual(self.device.require_inference(),A)
        self.now=105
        with self.assertRaises(h.Reject): self.device.require_inference()

    def test_delayed_delivery_does_not_extend_lease(self):
        request=self.device.boot_verified_root(A)
        grant=self.home.authorize(request)
        self.now=9
        self.device.accept(grant)
        self.now=60
        with self.assertRaises(h.Reject): self.device.require_inference()

    def test_late_reply_is_rejected(self):
        request=self.device.boot_verified_root(A)
        grant=self.home.authorize(request)
        self.now=10
        with self.assertRaises(h.Reject): self.device.accept(grant)

    def test_lease_lapse_requires_a_fresh_session(self):
        self.approve()
        self.now=59
        grant=self.home.authorize(self.device.renew())
        self.now=60
        with self.assertRaises(h.Reject):self.device.accept(grant)
        with self.assertRaises(h.Reject):self.device.require_inference()
        self.approve()
        self.assertEqual(self.device.require_inference(),A)

    def test_reset_clears_approval_and_old_grant_fails(self):
        request=self.approve()
        grant=self.home.authorize(request)
        fresh=self.device.boot_verified_root(A)
        self.assertNotEqual(request,fresh)
        with self.assertRaises(h.Reject): self.device.require_inference()
        with self.assertRaises(h.Reject): self.device.accept(grant)

    def test_wrong_model_grant(self):
        request=self.device.boot_verified_root(A)
        forged=h.request_bytes(h.DEVICE_ID,request[32:64],B)
        with self.assertRaises(h.Reject): self.device.accept(self.home.authorize(forged))

    def test_wrong_device_or_nonce(self):
        for at in [16,32]:
            request=self.device.boot_verified_root(A)
            fake=bytearray(request);fake[at]^=1
            grant=bytes(fake)+self.authority.sign_reserved_leaf(bytes(fake),0)
            with self.assertRaises(h.Reject): self.device.accept(grant)

    def test_wrong_key_and_corrupt_signature(self):
        request=self.device.boot_verified_root(A)
        wrong=h.su.DemoAuthority(18)
        with self.assertRaises(h.Reject):
            self.device.accept(request+wrong.sign_reserved_leaf(request,0))
        request=self.device.boot_verified_root(A)
        grant=bytearray(self.home.authorize(request));grant[-1]^=1
        with self.assertRaises(h.Reject): self.device.accept(bytes(grant))

    def test_frame_lengths_and_canonical_fields(self):
        request=self.device.boot_verified_root(A)
        for frame in [request[:-1],request+b'\0',bytes(128)]:
            with self.assertRaises(h.Reject): self.home.authorize(frame)
        grant=self.home.authorize(request)
        for frame in [grant[:-1],grant+b'\0']:
            self.device.boot_verified_root(A)
            with self.assertRaises(h.Reject): self.device.accept(frame)

    def test_policy_is_rechecked_for_cached_grant(self):
        request=self.device.boot_verified_root(A)
        first=self.home.authorize(request)
        self.assertEqual(first,self.home.authorize(request))
        self.assertEqual(json.loads(self.home.signer_state.read_text())['next_leaf'],1)
        self.write_policy([B])
        with self.assertRaises(h.Reject): self.home.authorize(request)

    def test_corrupt_policy_or_signer_fails_closed(self):
        request=self.device.boot_verified_root(A)
        self.policy.write_text('bad json')
        with self.assertRaises(h.Reject): self.home.authorize(request)
        self.write_policy([A])
        self.home.signer_state.write_text('{}')
        with self.assertRaises(h.Reject): self.home.authorize(request)

    def test_repeated_nonce_source_fails_closed(self):
        self.device.nonce_source=lambda n:b'x'*n
        self.approve()
        with self.assertRaises(h.Reject): self.device.renew()
        with self.assertRaises(h.Reject): self.device.require_inference()

    def test_entropy_failure_or_zero_nonce(self):
        self.device.nonce_source=lambda n:bytes(n)
        with self.assertRaises(h.Reject): self.device.boot_verified_root(A)
        with self.assertRaises(h.Reject): self.device.require_inference()

    def test_signer_capacity_fails_closed(self):
        self.home.signer_state.write_text(json.dumps({'schema':1,'PUBLIC_DEMO_ONLY':True,
            'key_sha256':hashlib.sha256(self.home.public_key).hexdigest(),'next_leaf':32}))
        with self.assertRaises(h.Reject): self.home.authorize(self.device.boot_verified_root(A))

    def test_http_allow_revoke_renew(self):
        server=make_server(self.policy,self.path/'http-signer.json')
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            url=f'http://127.0.0.1:{server.server_port}/authorize'
            def send(body):
                request=Request(url,data=body,headers={'Content-Type':'application/octet-stream'})
                with urlopen(request,timeout=5) as response:return response.read()
            request=self.device.boot_verified_root(A)
            self.device.accept(send(request))
            self.write_policy([B]);self.now=45
            with self.assertRaises(HTTPError) as caught:send(self.device.renew())
            self.assertEqual(caught.exception.code,403)
            self.now=60
            with self.assertRaises(h.Reject):self.device.require_inference()
        finally:
            server.shutdown();server.server_close();thread.join()

    def test_real_simplestories_package(self):
        demo=os.environ.get('S_AWIC_DEMO_ROOT')
        if not demo:self.skipTest('S_AWIC_DEMO_ROOT required for full package test')
        demo=Path(demo)
        image=(demo/'assets/board1-real-semantic-image2048.bin').read_bytes()
        metadata=bytes.fromhex(''.join((demo/'hardware/project/metadata192.memh').read_text().split()))
        authorities=[h.su.DemoAuthority(i) for i in range(3)]
        package=h.su.make_package(image,metadata,1,authorities[:2],[0,0])
        keys=[a.public_key for a in authorities]
        root=bytes.fromhex(h.su.verify_package(package,keys)['model_root'])
        self.write_policy([root])
        request=self.device.boot_package(package,keys)
        self.device.accept(self.home.authorize(request))
        self.assertEqual(self.device.require_inference(),root)
        # A modified physical image never reaches home-authorized operation.
        changed=bytearray(package);changed[-1]^=1
        with self.assertRaises(h.su.Reject):self.device.boot_package(bytes(changed),keys)
        with self.assertRaises(h.Reject):self.device.require_inference()


if __name__=='__main__': unittest.main(verbosity=2)
