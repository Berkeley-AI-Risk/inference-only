"""Print a bounded set of signals from a local projection proof witness."""
import sys
from pathlib import Path
path=Path(sys.argv[1]);scope=[];names={};states=[];state={}
for line in path.read_text().splitlines():
    if line.startswith('$scope'):scope.append(line.split()[2])
    elif line.startswith('$upscope'):scope.pop()
    elif line.startswith('$var'):
        parts=line.split();names[parts[3]]='.'.join(scope+[parts[4]])
    elif line.startswith('#'):
        if state:states.append(state);state={}
    elif line.startswith('b'):
        value,key=line.split();state[names.get(key,key)]=value[1:]
if state:states.append(state)
keys=['state_q','columns_q','column_q','group_q','groups_q','activation_count_q','f_completed_clear','f_job_owned','f_read_live','f_read_tag','activation_store_read','activation_store_read_address','weight_transfer','weight_protocol_error','integrated_fail','stream_done_seen_q','engine_done_seen_q','group_retiring','stream_done_transfer','engine_done_transfer','stream_weight_valid','stream_start_transfer','f_stream_state_o','f_stream_columns_o','f_stream_accepted_o']
for index,state in enumerate(states):
    if index%2:continue
    print(index//2,{name.split('.')[-1]:int(value,2)if set(value)<=set('01')else value
        for name,value in state.items()if name.startswith('native_projection_stream_join.u_native.')
        and len(name.split('.'))==3 and name.split('.')[-1]in keys})
