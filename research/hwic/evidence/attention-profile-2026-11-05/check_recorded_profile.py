"""Check recorded attention/geometry arithmetic; no source, model or hardware run."""
import json
from pathlib import Path


def main():
    data = json.loads(Path(__file__).with_name("results.json").read_text())
    normal = data["normal_cases"]
    alternate = data["latency_sensitivity_cases"]
    assert len(normal) == data["distinct_tensor_workloads"] == 30
    assert len(normal)+len(alternate) == data["positive_runs"] == 42
    assert data["checked_scalar_outputs"] == 42*256
    assert data["negative_control"]["detected"] is True
    assert data["negative_control"]["native_exit"] != 0
    assert data["baseline_RTL_modified"] is False
    families = data["state_families_disjoint"]
    flat = [i for group in families.values() for i in group]
    assert len(flat) == len(set(flat))
    for case in normal+alternate:
        assert case["native_exit"] == 0
        count = case["counts"]
        states = {int(k):v for k,v in case["states"].items()}
        assert sum(states.values()) == count["cycles"]
        assert sum(case["shift_clients"].values()) == count["shift_wait"] == states[28]
        assert states[27] == states[31] == 0
        context = case["context"]
        assert count["divider_busy"] == 46*(4*context+256)
        assert count["requests"] == 10*context
        assert count["key"] == count["value"] == 4*context
        assert count["scan"] == 2*context
        assert states[33] == states[24] == 256*context
        recomputed = {name:sum(states[i] for i in ids) for name,ids in families.items()}
        assert recomputed == case["family_clocks"]
        assert sum(recomputed.values()) == count["cycles"]
    for row in data["budgets"]:
        context = row["context"]
        selected = [x for x in normal if x["context"] == context]
        assert len(selected) == 6
        total = sum(x["counts"]["cycles"] for x in selected)
        assert row["attention_all_six_layers_cycles"] == total
        for family in families:
            cycles = sum(x["family_clocks"][family] for x in selected)
            assert row["family_clocks"][family] == cycles
            assert row["family_percent"][family] == 100*cycles/total
        if context <= 16:
            assert row["accepted_full_model_attention_cycles"] == total and row["cycle_join_gap"] == 0
        else:
            second = sum(x["counts"]["cycles"] for x in alternate if x["context"] == context)
            assert row["service_sensitivity_history14_cycles"] == second
            assert total-second == 60*(context-1)*(59-14)
            assert row["service_sensitivity_speedup"] == total/second
    memory = data["memory_process"]
    macro = memory["public_research_reference"]
    assert macro["KV_width_tiles"] == (256+macro["width"]-1)//macro["width"] == 6
    assert macro["KV_depth_banks"] == (221184+macro["depth"]-1)//macro["depth"] == 216
    assert macro["KV_instances"] == 6*216 == 1296
    assert abs(macro["KV_macro_rectangles_mm2"] - 1296*95.3*297.1/1e6) < 1e-10
    capacity = memory["alternative_candidate"]["capacity_only_lower_macro_counts_assuming_k_equals1024"]
    assert capacity["ROM"] == (57962496+1152*1024-1)//(1152*1024)
    assert capacity["KV"] == (56623104+288*1024-1)//(288*1024)
    rom = memory["ordinary_ROM_public_reference"]
    assert rom["weight_width_slices"] == (640+63)//64 == 10
    assert rom["weight_depth_banks"] == (84720+2047)//2048 == 42
    assert rom["misc_width_slices"] == (256+63)//64 == 4
    assert rom["misc_depth_banks"] == (14616+2047)//2048 == 8
    assert rom["total_banks"] == 10*42+4*8 == 452
    assert rom["allocated_bytes"] == 452*2048*64//8 == 7405568
    assert rom["padding_bytes"] == rom["allocated_bytes"]-7245312 == 160256
    assert rom["area_mm2_decimal_MB"] == 7405568/1e6/1.308
    assert rom["area_mm2_binary_MB"] == 7405568/(1024*1024)/1.308
    dolphin = memory["additional_same_process_candidate"]
    proposal = dolphin["KV_proposed_organization"]
    maxima = dolphin["single_port_SRAM_advertised_maxima"]
    assert proposal["banks"]*proposal["depth"]*proposal["width"] == 56623104
    assert proposal["capacity_bits"] == 56623104
    assert proposal["depth"] <= maxima["depth_words"]
    assert proposal["width"] <= maxima["width_bits"]
    assert proposal["depth"]*proposal["width"] <= maxima["capacity_bits"]
    print("PASS: 42 recorded kernel runs, 10,752 outputs, three full-model cycle joins, negative-control summary, state/traffic/geometry arithmetic")
    print("Scope: recorded arithmetic only; no private fixture replay, physical memory qualification or ASIC/GPU performance claim")


if __name__ == "__main__": main()
