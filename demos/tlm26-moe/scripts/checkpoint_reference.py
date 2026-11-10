"""Pin the weights-only checkpoint and evaluate two greedy CPU continuations."""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')
import hashlib
import json
import sys
from pathlib import Path

import sentencepiece
import torch

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / 'upstream'
sys.path.insert(0, str(UPSTREAM))
from model_moe import MoEModelArgs, MoETransformer

EXPECTED = 'c12f73ec224a8ee9de02ff81402eb5777c1658e7151ff31998cb0accc358e2a0'
PROMPTS = ['Once upon a time', 'The little cat']

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load():
    weights = UPSTREAM / 'model.pt'
    assert digest(weights) == EXPECTED
    record = torch.load(weights, map_location='cpu', weights_only=True)
    args = MoEModelArgs(**record['model_args'])
    net = MoETransformer(args).eval()
    net.load_state_dict(record['model'], strict=True)
    return net, record

@torch.inference_mode()
def main():
    torch.set_num_threads(1)
    tree = json.loads((ROOT / 'metadata/tree.json').read_bytes())
    blobs = {item['path'].split('/')[-1]:item['sha'] for item in tree['tree'] if item.get('type') == 'blob' and item['path'].startswith('tinylm/') and ('/' not in item['path'][7:] or item['path'].startswith(('tinylm/data/tok512.model','tinylm/esp32_wokwi/')))}
    pins = {}
    for path in sorted(UPSTREAM.iterdir()):
        if not path.is_file():
            continue
        data = path.read_bytes()
        if path.name != 'model.pt':
            assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\x00' + data).hexdigest() == blobs[path.name]
        pins[path.name] = digest(path)
    net, ck = load()
    sp = sentencepiece.SentencePieceProcessor(model_file=str(UPSTREAM / 'tok512.model'))
    assert sp.vocab_size() == net.params.vocab_size
    receipts = []
    for prompt in PROMPTS:
        ids = [sp.bos_id()] + sp.encode(prompt, out_type=int)
        seq = list(ids)
        traces = []
        for _ in range(12):
            top = []
            hooks = [layer.feed_forward.gate.register_forward_hook(lambda m, args, out: top.append(torch.topk(out[-1],2).indices.tolist())) for layer in net.layers]
            logits = net(torch.tensor([seq]))[0,-1]
            for hook in hooks:
                hook.remove()
            token = int(logits.argmax())
            traces.append({'accepted_id':seq[-1], 'routes':top,'next_id':token,'logit_margin':float(logits.topk(2).values.diff().neg()[0])})
            seq.append(token)
        receipts.append({'prompt':prompt,'prompt_ids':ids,'generated_ids':seq[len(ids):],'decoded':sp.decode(seq),'trace':traces})
    receipt = {'scope':'CPU FP32, author implementation, greedy, BOS once','checkpoint_revision': '804c2137003ede3820fc57608221deb620c2d6d7','source_revision':tree['sha'],'sha256':pins,'args':ck['model_args'],'parameters':sum(p.numel() for p in net.parameters()),'training_step':ck['iter_num'],'torch':torch.__version__,'sentencepiece':sentencepiece.__version__,'prompts':receipts}
    (ROOT/'receipts/checkpoint-cpu.json').write_text(json.dumps(receipt,indent=2)+'\n')
    for item in receipts:
        print(item['prompt_ids'],item['generated_ids'],item['decoded'])
if __name__=='__main__':
    main()
