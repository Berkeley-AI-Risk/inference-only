"""Reviewed current/historical dispatch; original APIs retain archived source context."""
from pathlib import Path as _Path
import importlib.util as _importlib
import sys as _sys
import hashlib as _hashlib
_current_package=_Path(__file__).resolve().parents[1]
_compat_name='_current_release_compat_'+_hashlib.sha256(str(_current_package).encode()).hexdigest()[:16]
if _compat_name not in _sys.modules:
    _spec=_importlib.spec_from_file_location(_compat_name,_current_package/'tools/seeded_release_compat.py')
    _value=_importlib.module_from_spec(_spec);_sys.modules[_compat_name]=_value;_spec.loader.exec_module(_value)
_compat=_sys.modules[_compat_name]
_legacy_package=_compat.legacy_root(_current_package)
_legacy_source=_legacy_package/'tools/test_encrypted_board_evidence.py'
EVIDENCE_CONTEXT='historical0e6'
if __name__=='__main__':
    __file__=str(_legacy_source)
    exec(compile(_legacy_source.read_bytes(),str(_legacy_source),'exec'),globals())
else:
    # Keep wrapper metadata discoverable and all original test globals historical.
    _legacy_name=_compat_name+'_'+__name__
    _legacy_spec=_importlib.spec_from_file_location(_legacy_name,_legacy_source)
    _legacy_tests=_importlib.module_from_spec(_legacy_spec)
    _sys.modules[_legacy_name]=_legacy_tests
    _legacy_spec.loader.exec_module(_legacy_tests)
    globals().update({name:value for name,value in vars(_legacy_tests).items() if not name.startswith('__')})
