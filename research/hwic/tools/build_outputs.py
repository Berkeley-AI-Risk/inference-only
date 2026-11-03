"""File-only arm64 Mach-O metadata and BSD archive checks. No native execution."""
from pathlib import Path
import hashlib,struct

def pin(path):
    path=Path(path).resolve(strict=True);h=hashlib.sha256()
    with path.open('rb') as f:
        while b:=f.read(4<<20):h.update(b)
    return dict(path=str(path),bytes=path.stat().st_size,sha256=h.hexdigest())

def macho(path):
    with Path(path).open('rb') as f:
        head=f.read(32);magic,cpu,subtype,kind,ncmds,size,flags,reserved=struct.unpack('<8I',head)
        assert magic==0xfeedfacf and cpu==16777228 and kind==2 and size<16<<20
        commands=f.read(size);assert len(commands)==size
    libraries=[];versions=[];at=0
    for _ in range(ncmds):
        command,length=struct.unpack_from('<2I',commands,at);assert length>=8 and at+length<=len(commands)
        if command in [0xc,0x80000018,0x8000001f,0x80000023]:
            off=struct.unpack_from('<I',commands,at+8)[0];assert 8<=off<length
            libraries.append(commands[at+off:at+length].split(b'\0',1)[0].decode())
        elif command==0x32:
            platform,minimum,sdk,tools=struct.unpack_from('<4I',commands,at+8)
            def version(v):return '.'.join(str(x) for x in [v>>16,(v>>8)&255,v&255])
            versions.append(dict(platform=platform,minimum=version(minimum),SDK=version(sdk),tools=tools))
        at+=length
    assert at==len(commands)
    return dict(CPU_type=cpu,libraries=libraries,build_versions=versions)

def verify_archive(path,expected):
    members=[];objects={};pending={Path(x['path']).name:x for x in expected}
    assert len(pending)==len(expected),'DUPLICATE_EXPECTED_OBJECT_BASENAME'
    with Path(path).open('rb') as f:
        assert f.read(8)==b'!<arch>\n'
        while head:=f.read(60):
            assert len(head)==60 and head[58:]==b'`\n'
            name=head[:16].decode().strip();length=int(head[48:58]);remaining=length
            if name.startswith('#1/'):
                n=int(name[3:]);assert n<=remaining
                name=f.read(n).rstrip(b'\0').decode();remaining-=n
            else:name=name.rstrip('/')
            h=hashlib.sha256();payload=remaining
            while remaining:
                b=f.read(min(4<<20,remaining));assert b;h.update(b);remaining-=len(b)
            if length&1:assert f.read(1)==b'\n'
            row=dict(name=name,payload_bytes=payload,sha256=h.hexdigest());members.append(row)
            if name.endswith('.o'):
                assert name in pending and name not in objects
                assert payload==pending[name]['bytes'] and row['sha256']==pending[name]['sha256']
                objects[name]=row
            else:assert name in ['__.SYMDEF','__.SYMDEF SORTED','/','/SYM64/']
    assert set(objects)==set(pending)
    return dict(actual_members=members,actual_design_object_count=len(objects),all_actual_design_object_bytes_match=True)


def verify_design_archive(object_directory, object_stems, archive_name):
    obj=Path(object_directory)
    expected=[pin(obj/(name+'.o')) for name in object_stems]
    return verify_archive(obj/archive_name,expected)
