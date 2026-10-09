"""Local interactive frontend for the actual fixed-model FPGA."""
from dataclasses import asdict
import json
from pathlib import Path
import uuid

import streamlit as st

from fpga_backend import ACTIVE, Controller, DEMO_CAP, MAX_NEW, MAX_PROMPT
from runtime_profile import configured_port, configured_variant

st.set_page_config(page_title='FPGA story lab', page_icon=':material/memory:', layout='centered')
st.title('FPGA story lab')
st.caption('SimpleStories 5M · Tang Mega 138K · Real generation over USB')
variant_label = configured_variant()
st.caption('Locally selected build: ' + (variant_label or 'not yet checked')
           + '. Selection is not independent attestation of the loaded FPGA.')
st.write('Start a story and watch the FPGA continue it. This tiny model completes stories; it is not a general chat assistant.')
st.session_state.setdefault('owner', uuid.uuid4().hex)
st.session_state.setdefault('prompt', 'once')
st.session_state.setdefault('new_tokens', 32)
st.session_state.setdefault('input_error', '')


@st.cache_resource(max_entries=1, show_spinner=False)
def board_controller():
    # Only the tokenizer and the one physical-board controller are cached.
    # Generated answers are never supplied from a cache or a software LLM.
    return Controller()


try:
    board = board_controller()
except Exception as error:
    st.error('The local app is not ready: ' + str(error))
    st.stop()


@st.fragment(run_every=0.2)
def console():
    owner = st.session_state.owner
    result = board.snapshot(owner)
    busy = board.busy()
    with st.form('story_prompt', border=True):
        prompt = st.text_area('Story beginning', key='prompt', height=100, max_chars=4000,
            placeholder='once upon a time, a little fox', disabled=busy, persist_state='session')
        count = st.number_input('Maximum new tokens', min_value=1, max_value=MAX_NEW,
            step=1, key='new_tokens', disabled=busy, persist_state='session')
        submitted = st.form_submit_button('Generate on FPGA', icon=':material/play_arrow:',
            type='primary', disabled=busy or board.needs_board_check)
    if submitted:
        st.session_state.input_error = ''
        try:
            board.start(owner, prompt, count)
            # Finish this render: aborting it with a full rerun discarded the
            # just-submitted widget values. The timed fragment updates controls.
            result = board.snapshot(owner)
            busy = board.busy()
        except (ValueError, RuntimeError) as error:
            st.session_state.input_error = str(error)
    if st.session_state.input_error:
        st.error(st.session_state.input_error)
    with st.container(horizontal=True):
        if st.button('Stop', icon=':material/stop:', disabled=not (busy and result.owner == owner),
                     help='Finish the in-flight command, then clear the tape and release the board.'):
            board.stop(owner)
        if st.button('Disconnect USB', icon=':material/usb_off:',
                     disabled=busy or not board.connection_retained(),
                     help='Release the idle connection before another program uses or programs the board.'):
            try:
                board.disconnect()
            except RuntimeError as error:
                st.session_state.input_error = str(error)
        if result.state in ACTIVE:
            label = f'Uploading prompt: {result.uploaded}/{len(result.prompt_tokens)} tokens' if result.state == 'loading prompt' else result.state.capitalize()
            st.caption(label + (' · Stop requested; finishing the current command' if board.stop_event.is_set() else ''))
        elif result.state == 'busy in another tab':
            st.caption('The FPGA is in use by another browser tab.')
        elif result.state == 'idle':
            port = configured_port()
            if port is None:
                st.caption('Local board setup is incomplete. Follow README.md before generating.')
            else:
                st.caption('Configured USB device present; readiness checked when you generate.' if Path(port).exists()
                           else 'Configured FPGA USB device not found. Stop the app and check the board connection.')
        elif result.state != 'error':
            suffix = (' · Tape cleared; USB connection retained' if board.connection_retained()
                      else ' · Tape cleared; board released') if result.clear_acknowledged else ''
            st.caption(result.stop_reason + suffix)

    rate = result.streaming_tps
    with st.container(horizontal=True):
        st.metric('Streaming tokens/s', f'{rate:.2f}' if rate is not None else '—', border=True,
            help='Measured receive-to-receive rate after the first token. Includes USB/host overhead; excludes prompt processing. Needs at least two tokens.')
        st.metric('Time to first token', f'{result.first_token_seconds:.2f} s' if result.first_token_seconds is not None else '—', border=True,
            help='From starting this run, including connection checks, prompt upload and first inference. A newly opened connection has a one-second startup check; a healthy retained connection does not repeat it.')
        st.metric('Tokens generated', len(result.generated), border=True)

    with st.container(border=True):
        st.subheader('Story')
        st.text(result.text if result.job_id else 'Your story will appear here, token by token.', width='stretch')
    if result.error:
        st.error(result.error)
        st.caption('No software-model fallback, automatic retry, reset or flash programming was used.')
    if 0 in result.prompt_tokens:
        st.warning('Some prompt text is outside this small vocabulary and became [UNK]. Try simpler words.')
    if result.job_id:
        st.caption(f'{len(result.prompt_tokens)} prompt tokens · {len(result.generated)} generated tokens · '
                   f'Run {result.job_id[:8]}. Output uses the model’s lowercase tokenizer.')
        with st.expander('Timing details and test record'):
            st.caption('Token 1 includes evaluation of the previously unevaluated prompt. Later STEP commands reuse the private context cache. These are measured command latencies, not pure arithmetic-cycle timing.')
            if result.step_seconds:
                st.dataframe([{'Token':i+1, 'Token ID':token, 'STEP seconds':seconds}
                    for i, (token, seconds) in enumerate(zip(result.generated, result.step_seconds))], hide_index=True)
            if result.state not in ACTIVE:
                record = asdict(result)
                record['streaming_tokens_per_second'] = rate
                st.download_button('Download run record', json.dumps(record, indent=2),
                    file_name='fpga-run-' + result.job_id[:8] + '.json', mime='application/json')
            if result.log_path:
                st.caption('Raw serial evidence stays on this computer: ' + result.log_path)


console()
st.caption(f'Initial interactive-demo limit: {MAX_PROMPT} prompt tokens, {MAX_NEW} new tokens, '
           f'{DEMO_CAP} total. All three hardware variants have passed separate tests at the 2,048-input limit.')
with st.expander('What this demo does—and does not do'):
    st.write('This computer only converts between text and token IDs, sends APPEND / STEP / CLEAR, and measures the replies. All inference runs on the FPGA. Each Generate starts with CLEAR; successful completion or Stop clears the tape again. A successful run retains the exclusive USB connection for the next run. Stop or Disconnect USB releases it. No weights, tensors or arithmetic commands are sent.')
    st.write('Three builds are available: the faster baseline without K/V integrity checks; the K/V-protected build that checks cached attention data before use; and the experimental encrypted-memory build, which also encrypts external weights and K/V. Encryption uses public demonstration keys, not secret deployment keys, and requires its matching encrypted flash image. All three authenticate model weights and have passed normal-inference board tests through the full context window. K/V corruption/replay rejection was tested in simulation, not by physically altering DDR. Vendor-DDR timing remains unresolved for all three. The local four-token check does not reproduce the larger campaigns or attest the loaded circuit. The app stops on errors and cannot reset, reflash or reconfigure the board.')
    st.write('Keep the board powered: its tested configuration is in SRAM. The app cannot restore it after a power cycle. Local raw logs include your prompt; nothing is published or sent to an online model.')
