// Finite arithmetic/protocol regression, not a host interface or security proof.
#include "Vprivate_dot8_accumulator.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <stdexcept>

#ifndef TEST_GROUPS
#error TEST_GROUPS must match the Verilator GROUPS parameter
#endif
using Dut = Vprivate_dot8_accumulator;
static constexpr unsigned groups = TEST_GROUPS;
static uint32_t random_state = 0x514e3805u;
static uint64_t cycles = 0, beats = 0, frames = 0, bubbles = 0, held_checks = 0;
static uint32_t random32() {
    random_state ^= random_state << 13;
    random_state ^= random_state >> 17;
    random_state ^= random_state << 5;
    return random_state;
}
static void need(bool okay, const char* message) {
    if (!okay) throw std::runtime_error(message);
}
static void edge(Dut& d) {
    d.clk = 1; d.eval(); ++cycles; d.clk = 0; d.eval();
}
static int64_t signed_result(const Dut& d) {
    uint64_t value = d.result & ((uint64_t(1) << 40)-1);
    return value & (uint64_t(1) << 39) ? int64_t(value)-int64_t(uint64_t(1) << 40) : int64_t(value);
}
static void inputs(Dut& d, unsigned lane, int a, int w, bool random_data) {
    d.weights = 0;
    for (unsigned n = 0; n < 4; ++n) d.activations[n] = 0;
    for (unsigned n = 0; n < 8; ++n) {
        uint16_t av = random_data ? uint16_t(random32()) : uint16_t(n == lane ? a : 0);
        uint8_t wv = random_data ? uint8_t(random32()) : uint8_t(n == lane ? w : 0);
        d.activations[n/2] |= uint32_t(av) << ((n%2)*16);
        d.weights |= uint64_t(wv) << (n*8);
    }
}
static int64_t input_sum(const Dut& d) {
    int64_t sum = 0;
    for (unsigned n = 0; n < 8; ++n) {
        uint16_t av = uint16_t(d.activations[n/2] >> ((n%2)*16));
        uint8_t wv = uint8_t(d.weights >> (n*8));
        // Explicit signed decoding avoids implementation-defined narrowing.
        int a = av >= 32768 ? int(av)-65536 : int(av);
        int w = wv >= 128 ? int(wv)-256 : int(wv);
        sum += int64_t(a)*w;
    }
    return sum;
}
static void launch(Dut& d) {
    need(!d.busy && !d.out_valid, "not idle before start");
    d.start = 1; d.in_valid = 0; d.out_ready = 0; d.eval(); edge(d);
    d.start = 0; d.eval();
}
static void frame(Dut& d, unsigned lane, int a, int w, bool random_data, bool stalled) {
    launch(d);
    unsigned fed = 0, elapsed = 0;
    int64_t expected = 0;
    while (fed < groups) {
        need(++elapsed < groups*4+100, "input watchdog");
        inputs(d, lane, a, w, random_data);
        d.in_valid = !stalled || random32()%4 != 0;
        d.start = elapsed == 2;  // A busy start pulse must not restart the frame.
        d.eval();
        if (d.in_valid && d.in_ready) { expected += input_sum(d); ++fed; ++beats; }
        else if (!d.in_valid) ++bubbles;
        need(!d.out_valid, "result before the fixed number of accepted beats");
        edge(d);
    }
    d.start = 0; d.in_valid = 0;
    for (unsigned n = 0; !d.out_valid; ++n) {
        need(n < 16, "result watchdog");
        inputs(d, 0, 0, 0, true);  // Invalid-cycle payload is not an accepted beat.
        edge(d);
    }
    need(signed_result(d) == expected, "signed dot product mismatch");
    for (unsigned n = 0; n < 13; ++n) {
        need(d.out_valid && d.busy && !d.in_ready && signed_result(d) == expected,
             "held result changed under backpressure");
        ++held_checks; inputs(d, 0, 0, 0, true); edge(d);
    }
    d.out_ready = 1; d.eval(); edge(d); d.out_ready = 0;
    need(!d.busy && !d.out_valid, "result did not retire once");
    for (unsigned n = 0; n < 5; ++n) { edge(d); need(!d.out_valid, "duplicate/stale result"); }
    ++frames;
}
static void cancel(Dut& d, unsigned phase, bool reset) {
    launch(d);
    unsigned fed = 0;
    const unsigned target = phase == 0 ? 1 : groups;
    while (fed < target) {
        inputs(d, 0, 32767, 127, true); d.in_valid = 1; d.eval();
        if (d.in_ready) ++fed;
        edge(d);
    }
    d.in_valid = 0;
    if (phase == 2) {
        for (unsigned n = 0; !d.out_valid; ++n) { need(n < 16, "cancel hold watchdog"); edge(d); }
    }
    if (reset) d.rst_n = 0; else d.clear = 1;
    d.eval(); need(!d.in_ready, "input accepted during reset/CLEAR"); edge(d);
    // This leaf's out_valid is synchronously revoked, not an asynchronous gate.
    need(!d.busy && !d.out_valid, "reset/CLEAR did not revoke frame at the clock edge");
    d.rst_n = 1; d.clear = 0; d.in_valid = 0;
    for (unsigned n = 0; n < 16; ++n) { edge(d); need(!d.busy && !d.out_valid, "stale result after cancellation"); }
}
int main(int argc, char** argv) { try {
    Verilated::commandArgs(argc, argv);
    Dut d;
    d.clk = 0; d.rst_n = 0; d.clear = 0; d.start = 0; d.in_valid = 0; d.out_ready = 0;
    for (unsigned n = 0; n < 4; ++n) edge(d);
    d.rst_n = 1; d.eval();
    const int activations[] = {-32768, -32767, -1, 0, 1, 32767};
    const int weights[] = {-128, -127, -1, 0, 1, 127};
    for (unsigned lane = 0; lane < 8; ++lane)
        for (int a : activations) for (int w : weights) frame(d, lane, a, w, false, true);
    for (unsigned n = 0; n < 32; ++n) frame(d, 0, 0, 0, true, n%2);
    for (bool reset : {false, true}) for (unsigned phase = 0; phase < 3; ++phase) {
        cancel(d, phase, reset);
        frame(d, phase, -32768, -128, false, true);
    }
    need(frames == 326 && held_checks && bubbles, "incomplete arithmetic/protocol workload");
    std::cout << "{\"passed\":true,\"groups\":" << groups << ",\"frames\":" << frames
              << ",\"accepted_beats\":" << beats << ",\"checked_products\":" << beats*8
              << ",\"input_bubbles\":" << bubbles << ",\"held_checks\":" << held_checks
              << ",\"cancellations\":6,\"cycles\":" << cycles << "}\n";
    d.final(); return 0;
} catch (const std::exception& error) { std::cerr << error.what() << "\n"; return 1; } }
