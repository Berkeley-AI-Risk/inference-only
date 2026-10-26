"""Local interactive frontend for the actual fixed-model FPGA."""
from dataclasses import asdict
import json
from pathlib import Path
import uuid

import streamlit as st

from fpga_backend import ACTIVE, Controller, limits_for_variant
from runtime_profile import configured_port, configured_variant, configured_variant_id

st.set_page_config(page_title='FPGA story lab', page_icon=':material/memory:', layout='centered')
st.title('FPGA story lab')
st.caption('SimpleStories 5M · Tang Mega 138K · Real generation over USB')
variant_label = configured_variant()
variant_id = configured_variant_id()
sampling_enabled = variant_id == 'seeded-sampling'
limits = limits_for_variant(variant_id)
st.caption('Locally selected build: ' + (variant_label or 'not yet checked')
           + '. Selection is not independent attestation of the loaded FPGA.')
st.write('Start a story and watch the FPGA continue it. This tiny model completes stories; it is not a general chat assistant.')
st.session_state.setdefault('owner', uuid.uuid4().hex)
st.session_state.setdefault('prompt', 'once')
st.session_state.setdefault('new_tokens', 32)
st.session_state.setdefault('input_error', '')
st.session_state.setdefault('temperature', '0')
st.session_state.setdefault('seed_input', '')


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
        prompt = st.text_area('Story beginning', key='prompt', height=100, max_chars=limits.max_chars,
            placeholder='once upon a time, a little fox', disabled=busy, persist_state='session')
        count = st.number_input('Maximum new tokens', min_value=1, max_value=limits.max_new,
            step=1, key='new_tokens', disabled=busy, persist_state='session',
            help='Prompt and new tokens together must fit the context window. Longer prompts leave fewer output slots.')
        temperature, seed_input = '0', ''
        if sampling_enabled:
            temperature = st.segmented_control('Temperature', ('0', '0.5', '1', '2'),
                required=True, key='temperature', disabled=busy, persist_state='session',
                help='0 chooses the highest-scoring token. Higher temperatures allow more varied continuations.')
            seed_input = st.text_input('Seed (optional)', key='seed_input', max_chars=40,
                placeholder='Leave blank for a fresh seed', disabled=busy, persist_state='session',
                help='Use a decimal number or 0x-prefixed hexadecimal number, up to 128 bits. '
                     'The same prompt, temperature and seed repeat a story. Greedy generation ignores the seed.')
        submitted = st.form_submit_button('Generate on FPGA', icon=':material/play_arrow:',
            type='primary', disabled=busy or board.needs_board_check)
    if submitted:
        st.session_state.input_error = ''
        try:
            if sampling_enabled:
                board.start(owner, prompt, count, temperature=temperature, seed=seed_input)
            else:
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
        if result.seed_used:
            st.caption(f'Run settings: temperature {result.temperature} · Seed {result.seed}')
        elif sampling_enabled:
            st.caption('Run settings: temperature 0 (greedy) · Seed unused')
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
if sampling_enabled:
    st.caption(f'Up to {limits.max_prompt:,} prompt tokens and {limits.max_new} new tokens; '
               f'{limits.total:,} tokens combined. Longer prompts leave fewer output slots. '
               'The first token can take several minutes for a long prompt.')
else:
    st.caption(f'Initial interactive-demo limit: {limits.max_prompt} prompt tokens, {limits.max_new} new tokens, '
               f'{limits.total} total. Separate board campaigns exercise longer contexts; '
               'see the repository validation report for each build.')
with st.expander('What this demo does—and does not do'):
    st.write('This computer only converts between text and token IDs, sends APPEND / STEP / CLEAR, and measures the replies. All inference runs on the FPGA. Each Generate starts with CLEAR; successful completion or Stop clears the tape again. A successful run retains the exclusive USB connection for the next run. Stop or Disconnect USB releases it. No weights, tensors or arithmetic commands are sent.')
    st.write('Four SimpleStories images are supported: the greedy baseline without K/V integrity checks; the greedy K/V-protected image, which checks cached attention data before use; the greedy encrypted-memory image, which retains K/V integrity and replay protection and adds encryption for external weights and K/V; and the seeded image, which adds temperature sampling with a public seed and has no K/V integrity or encryption. All four authenticate model weights. Encryption uses public demonstration keys and requires its matching encrypted flash image. Published board results apply to the exact image tested. K/V corruption and replay rejection were tested in simulation, not by physically altering DDR. Vendor-DDR timing remains unresolved. The short local check does not reproduce the larger campaigns or attest the loaded circuit. The app stops on errors and cannot reset, reflash or reconfigure the board.')
    st.write('An optional seeded-sampling build adds the temperature and seed controls above. '
             'It uses the same SimpleStories model and plaintext flash as the baseline. '
             'Each Generate starts a new story, and a blank seed chooses and displays a fresh seed for that run. '
             'A chosen seed lets you replay the same prompt and temperature. '
             'This build has its own source-bound board tests and qualification evidence. It has no K/V integrity protection or memory encryption.')
    st.write('Keep the board powered: its tested configuration is in SRAM. The app cannot restore it after a power cycle. Local raw logs include your prompt; nothing is published or sent to an online model.')
