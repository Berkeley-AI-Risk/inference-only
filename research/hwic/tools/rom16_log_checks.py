"""Original finite ROM16 log checks; parsing a recording does not run hardware."""
import re

def positive_log(text):
    summaries=re.findall(r'^PASS ROM16_MAPPED_PUBLIC rows=(\d+) dots=(\d+) tiles=(\d+) held=(\d+) clear=(\d+) fault=(\d+) replays=(\d+) cycles=(\d+)$',text,re.M)
    assert len(summaries)==1;rows,dots,tiles,held,clear,fault,replays,cycles=map(int,summaries[0])
    assert (rows,dots,tiles,clear,fault,replays)==(17136,0,0,7,21,66) and held>0 and cycles>0
    vectors=re.findall(r'^VECTOR mode=(\S+) case=(\d+) first=(\d+) last=(\d+)$',text,re.M)
    expected=[('clean',i) for i in range(29)]+[('stalls_and_bubbles',i) for i in range(29)]+[
        ('after_partial_load_clear',24),('after_compute_clear',23),('after_group_boundary_clear',12),
        ('after_flush_clear',11),('after_postscale_clear',10),('after_held_packet_clear',9),
        ('after_partial_final_packet_clear',8),('after_terminal_fault_resets',24)]
    assert len(vectors)==66 and [(mode,int(case)) for mode,case,first,last in vectors]==expected
    assert all((int(first),int(last))==(91,106) for mode,case,first,last in vectors if mode in ['clean','after_terminal_fault_resets'])
    assert all(int(first)>0 and int(last)>=int(first) for mode,case,first,last in vectors)
    assert not re.search(r'^%Error|^%Fatal|^FATAL:|Assertion failed|ROM16_RESULT_MISMATCH|ROM16_INVALID_PAYLOAD_NOT_ZERO',text,re.M)
    return dict(rows=rows,dots=dots,tiles=tiles,held=held,clear=clear,fault=fault,replays=replays,cycles=cycles,
        actual_vectors=[dict(mode=m,case=int(i),first=int(f),last=int(l)) for m,i,f,l in vectors],
        private_dot_tile_state_observations=0,clean_first=91,clean_last=106)

def wrong_log(text):
    pattern=r'^\s*(?:\[[^\]\r\n]+\]\s+)?%(?:Fatal|Error)(?:-[A-Z0-9_]+)?:'
    diagnostics=[line for line in text.splitlines()if re.match(pattern,line)]
    assert diagnostics,'No supported genuine assertion diagnostic'
    first=diagnostics[0]
    assert re.search(r'\bROM16_RESULT_MISMATCH case=0 row=0\b',first),'First error is not intended first public arithmetic row'
    assert re.search(r'(?:^|[/\s])tb_rom16_mapped_public\.sv:\d+:',first),'First error is not from original pinned public bench'
    assert 'PASS ROM16_MAPPED_PUBLIC'not in text and 'ROM16_INVALID_PAYLOAD_NOT_ZERO'not in text
    return dict(actual_first_assertion=first,actual_supported_diagnostics=diagnostics,first_case=0,first_row=0,private_DOT_or_tile_observations=0,original_public_arithmetic_assertion_only=True)
