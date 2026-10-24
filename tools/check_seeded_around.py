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
if __name__=='__main__' and _compat.dispatch_cli(_current_package,'around'):
    raise SystemExit(0)
_legacy_package=_compat.legacy_root(_current_package)
_legacy_source=_legacy_package/'tools/check_seeded_around.py'
__file__=str(_legacy_source)
EVIDENCE_CONTEXT='historical0e6'
exec(compile(_legacy_source.read_bytes(),str(_legacy_source),'exec'),globals())
if 'check'in globals():
    _original_check=check
    def check(package=_current_package):
        if _compat.is_current(package):
            return _compat.check_current(package,'around')
        return _original_check(package)
