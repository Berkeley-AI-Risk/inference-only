"""Physical fanout hints for the existing permission register; no logic change."""
from pathlib import Path

OLD='logic token_reset_asserted /* synthesis syn_preserve = 1 */;'

def transform(name,text,fanout):
    if name!='top.sv':return text
    assert 16<=fanout<=512 and text.count(OLD)==1
    return text.replace(OLD,f'logic token_reset_asserted /* synthesis syn_preserve = 1 syn_maxfan = {fanout} */;')

def apply(project,fanout):
    path=Path(project)/'top.sv';path.write_text(transform('top.sv',path.read_text(),fanout))
