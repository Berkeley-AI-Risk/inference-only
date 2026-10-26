"""Exact original seeded host source context; never executes retained snapshots."""
import hashlib
import json
import stat
from pathlib import Path, PurePosixPath

CONTEXT_PATH='reference/seeded-sampling/recorded-host-context/SOURCE-CONTEXT.json'
CONTEXT_SHA='0ca65ba9e096de0c87b38b6ffbe24b095d5412e242e7e5164bddd3cc891fc3f4'
ORIGINAL_SOURCES={'host-app/fpga_backend.py': {'bytes': 21154, 'sha256': 'f0b8cf6a532d8c866658b8ad4c2442e4f76c8213fbe2a0a3256ff61981efc48f'}, 'host-app/runtime_profile.py': {'bytes': 10649, 'sha256': '0708f97a51863eed9f2a1140bfd578e3edc57736d3e3c839be83bec4e04c1fe0'}, 'host-app/streamlit_app.py': {'bytes': 11193, 'sha256': '0a5573305f470f36a10142bb4a123bbf358fbf59316c6ff6e7269ff621bd0a95'}}
TOKENIZER=('host-app/assets/tokenizer.json',dict(bytes=86463,sha256='01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51'))
PREFIX='reference/seeded-sampling/recorded-host-context/'

def need(ok,message):
    if not ok:raise ValueError(message)

def identity(path):
    need(path.is_file() and not path.is_symlink(),'Missing/linked recorded-host source')
    raw=path.read_bytes()
    return dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())

def regular(package,name):
    relative=PurePosixPath(name)
    need(type(name)is str and name and not relative.is_absolute() and '..'not in relative.parts
         and '\\'not in name and str(relative)==name,'Unsafe recorded-host source name')
    package=Path(package).resolve();path=package/name
    need(not any(p.is_symlink()for p in(path,*path.parents)if p.is_relative_to(package)),'Linked recorded-host source path')
    return path

def source_path(package,name):
    # Only these three literal paths route to snapshots. All other references,
    # UART sources, model assets and current production sources stay in package.
    return regular(package,PREFIX+name if name in ORIGINAL_SOURCES else name)

def check(package,candidate):
    package=Path(package).resolve();path=regular(package,CONTEXT_PATH)
    need(identity(path)['sha256']==CONTEXT_SHA,'Recorded-host context metadata changed')
    context=json.loads(path.read_bytes())
    need(context['original_source_names']==ORIGINAL_SOURCES,'Recorded-host source map changed')
    need(candidate['image_sha256']==context['image_sha256'],'Recorded-host context belongs to another seeded image')
    need(candidate['host_source_inputs']==dict(ORIGINAL_SOURCES,**{TOKENIZER[0]:TOKENIZER[1]}),
         'Seeded evidence host context changed')
    expected={PREFIX+name:row for name,row in ORIGINAL_SOURCES.items()}
    need(context['files']==expected,'Recorded-host context census changed')
    for name,row in expected.items():need(identity(regular(package,name))==row,'Recorded-host snapshot changed: '+name)
    found=set()
    for entry in path.parent.rglob('*'):
        mode=entry.lstat().st_mode
        need(not stat.S_ISLNK(mode),'Linked recorded-host context entry')
        need(stat.S_ISDIR(mode)or stat.S_ISREG(mode),'Special recorded-host context entry')
        if stat.S_ISREG(mode):found.add(entry.relative_to(package).as_posix())
    need(found==set(expected)|{CONTEXT_PATH},'Unlisted recorded-host context source')
    need(identity(regular(package,TOKENIZER[0]))==TOKENIZER[1],'Seeded tokenizer changed')
    need(context['current_shared_host_physical_qualification_inherited']is False
         and context['old_runnable_image_included']is False
         and context['full_historical_release_required']is False,'Recorded-host context scope changed')
    return dict(recorded_seeded_host_source_context_checked=True,
                current_shared_host_physical_qualification_inherited=False,
                recorded_host_sources=len(ORIGINAL_SOURCES),host_snapshots_executed=False)
