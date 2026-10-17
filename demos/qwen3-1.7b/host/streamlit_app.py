"""Qwen FPGA lab: presentation matching the SimpleStories FPGA story lab."""
from dataclasses import asdict
import json
import uuid

import streamlit as st
from qwen_backend import ACTIVE, Controller, MAX_NEW, MAX_PROMPT

st.set_page_config(page_title='FPGA Qwen lab', page_icon=':material/memory:', layout='centered')
st.title('FPGA Qwen lab')
st.caption('Qwen3-1.7B · AWS F2 · Real generation on the FPGA')
st.write('Enter a prompt and watch the FPGA generate a response. This fixed numerical model uses deterministic greedy decoding.')
st.session_state.setdefault('owner', uuid.uuid4().hex)
st.session_state.setdefault('prompt', 'Explain what an FPGA is in two sentences.')
st.session_state.setdefault('new_tokens', 64)
st.session_state.setdefault('raw', False)
st.session_state.setdefault('input_error', '')


@st.cache_resource(max_entries=1, show_spinner=False)
def fpga_controller():
    # Cache only tokenizer and connection controller, never generated answers.
    return Controller()


try:
    fpga = fpga_controller()
except Exception as error:
    st.error('The local app is not ready: ' + str(error))
    st.stop()


@st.fragment(run_every=0.2)
def console():
    owner = st.session_state.owner
    result, busy = fpga.snapshot(owner), fpga.busy()
    with st.form('qwen_prompt', border=True):
        prompt = st.text_area('Prompt', key='prompt', height=100, max_chars=8000,
                              disabled=busy, persist_state='session')
        count = st.number_input('Max new tokens', min_value=1, max_value=MAX_NEW, step=1,
                                key='new_tokens', disabled=busy, persist_state='session')
        raw = st.checkbox('Raw text completion (no chat template)', key='raw', disabled=busy)
        submitted = st.form_submit_button('Generate on FPGA', icon=':material/play_arrow:',
                                          type='primary', disabled=busy or fpga.needs_check)
    if submitted:
        st.session_state.input_error = ''
        try:
            fpga.start(owner, prompt, count, raw)
            result, busy = fpga.snapshot(owner), fpga.busy()
        except (ValueError, RuntimeError) as error:
            st.session_state.input_error = str(error)
    if st.session_state.input_error:
        st.error(st.session_state.input_error)
    if result.state == 'idle':
        st.caption('Connection configured; FPGA readiness is checked when you generate.')
    elif result.state == 'busy in another tab':
        st.caption('The FPGA is in use by another browser tab.')
    elif result.state in ACTIVE:
        st.caption(result.state.capitalize() + '…')
    elif result.state == 'complete':
        st.caption('Complete · ' + (result.stop_reason.capitalize() or 'Finished') + ' · The next Generate starts with a fresh tape.')

    with st.container(horizontal=True):
        st.metric('Streaming tokens/s', f'{result.streaming_tps:.2f}' if result.streaming_tps is not None else '—', border=True,
                  help='F2 host reply-to-reply rate after the first token. Excludes prompt processing and browser/SSH delivery latency; needs at least two tokens.')
        st.metric('Time to first token', f'{result.first_token_seconds:.2f} s' if result.first_token_seconds is not None else '—', border=True,
                  help='F2 host time for prompt APPENDs plus first STEP. Excludes tokenization, connection/status checks, CLEAR, model upload and browser delivery.')
        st.metric('Tokens generated', len(result.steps), border=True,
                  help='Includes the end-of-response token when one is returned; that marker is not shown in the response text.')
    with st.container(border=True):
        st.subheader('Response')
        st.text(result.text if result.steps else 'Your response will appear here, token by token.', width='stretch')
    if result.error:
        st.error(result.error)
        st.caption('No software fallback, retry, reset or FPGA reconfiguration was used.')
    if result.job_id:
        st.caption(f'{len(result.prompt_tokens)} prompt tokens · {len(result.steps)} generated tokens · Run {result.job_id[:8]}')
        with st.expander('Timing details and test record'):
            st.caption('The first token includes prompt evaluation. Later STEPs reuse the private context cache. The displayed host timings exclude SSH/browser delivery; they are not arithmetic-cycle measurements.')
            if result.ui_first_token_seconds is not None:
                st.write(f'App elapsed time to receipt of first token: {result.ui_first_token_seconds:.2f} s (includes connection/status checks).')
            if result.steps:
                st.dataframe([{'Token': s['index']+1, 'Token ID': s['token'], 'STEP seconds': s['step_ns']/1e9}
                              for s in result.steps], hide_index=True)
            if result.state not in ACTIVE:
                record = asdict(result)
                record.pop('owner')
                record['streaming_tokens_per_second'] = result.streaming_tps
                st.download_button('Download run record', json.dumps(record, indent=2),
                                   file_name='qwen-fpga-run-'+result.job_id[:8]+'.json', mime='application/json')


console()
st.caption(f'Interactive limit: {MAX_PROMPT} prompt tokens (including chat formatting) and {MAX_NEW} new tokens. Full 32,768-token execution is not hardware-qualified.')
with st.expander('What this demo does—and does not do'):
    st.write('The computer converts text to tokens and displays replies. All model inference runs on the AWS FPGA; there is no CPU/GPU model or cached-answer fallback. Each Generate uses CLEAR, APPEND and STEP. The browser cannot upload weights, program the FPGA, select clocks or issue tensor operations.')
    st.write('Generation stops at the first end-of-response marker or Max new tokens, whichever comes first. Special formatting tokens are omitted from the response text, but the generated-token count and timings include the ending token. There is no mid-run Stop button; let the request finish before disconnecting or using another client. Each prompt is a separate request, not conversation history.')
    st.write('Weights are authenticated before use; K/V is not authenticated and weights are not encrypted. A configured connection and matching output are not independent attestation of the loaded circuit. Prompts are sent over your configured connection to your AWS host, not to an online model service. Downloaded run records contain your prompt and response.')
