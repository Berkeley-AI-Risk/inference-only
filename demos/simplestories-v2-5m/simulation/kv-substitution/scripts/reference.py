if not __debug__:
    raise SystemExit("Optimized Python is unsupported; run without -O or -OO")
"""Numerical comparison independent of the production RTL and DDR testbench."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout",type=Path)
    package=parser.parse_args().checkout.resolve()/"demos/simplestories-v2-5m"
    spec=importlib.util.spec_from_file_location("invert",package/"reference/seeded-sampling/reconstruct_rom.py")
    invert=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(invert)
    with tempfile.TemporaryDirectory() as folder:
        root=Path(folder)
        for name,content in invert.reconstruct().items():
            (root/name).write_bytes(content)
        from quantization import oracle
        model=oracle.QuantizedModel.load(root)
        import numpy as np
        def frame(f):
            data=f.value.astype("<i2").tobytes()
            return dict(sha256=hashlib.sha256(data).hexdigest(),exponent=int(f.exponent),
                        first8=[int(x) for x in f.value[:8]])
        class Observed(oracle.IntegerLlama):
            def _attention(self,q,layer):
                result=super()._attention(q,layer)
                if layer in (0,4) and self.position==1:
                    # Native head 0 consumes key/value head 0. Reconstruct its
                    # actual two quantized probabilities and aligned V inputs.
                    keys,values=self.keys[layer],self.values[layer]
                    scores=oracle._normalize_mixed(
                        np.array([int(q.value[:64].astype(np.int64) @ k.value[:64].astype(np.int64)) for k in keys]),
                        np.array([k.exponent+q.exponent-3 for k in keys]),self.stats)
                    differences=scores.value.astype(np.int64)-int(max(scores.value))
                    q8=oracle._round_shift_even(differences,-(scores.exponent+oracle.SOFTMAX_FRACTION))
                    exp=self.model.exp_neg[-np.clip(q8,-4096,0)].astype(np.int64)
                    weights=[oracle._round_div_even_scalar(int(e)*oracle.Q_PROBABILITY,int(sum(exp))) for e in exp]
                    aligned=oracle._normalize_mixed(np.stack([v.value[:64] for v in values]).astype(np.int64),
                        np.array([v.exponent for v in values])[:,None],self.stats)
                    self.trace[f"layer{layer}"]=dict(query=frame(q),attention=frame(result),
                        probabilities=weights,aligned_v0=[int(x) for x in aligned.value[:,0]],
                        aligned_exponent=int(aligned.exponent))
                return result
        outputs={}
        for name,layer in [("honest",0),("negated",0),("layer4",4)]:
            m=Observed(model)
            m.trace={}
            first,_=m.forward_token(378)
            assert first==200
            recorded=m.values[layer][0]
            assert np.all(recorded.value!=-32768)
            offered=oracle.BFP(-recorded.value,recorded.exponent) if name!="honest" else recorded
            m.values[layer][0]=offered
            second,_=m.forward_token(first)
            outputs[name]=dict(first_token=first,second_token=second,
                original_v=frame(recorded),returned_v=frame(offered),
                layer1_k=frame(m.keys[1][1]), layer1_v=frame(m.values[1][1]),
                layer5_k=frame(m.keys[5][1]), layer5_v=frame(m.values[5][1]),**m.trace)
        for name, layer in [("negated",0),("layer4",4)]:
            assert outputs["honest"][f"layer{layer}"]["query"]==outputs[name][f"layer{layer}"]["query"]
        print(json.dumps(outputs,indent=2))


if __name__=="__main__":
    main()
