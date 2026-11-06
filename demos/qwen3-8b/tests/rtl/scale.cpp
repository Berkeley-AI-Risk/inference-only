// Independent native IEEE-FP32 RNE oracle; not a hardware/security proof.
#include "Vqwen_projection_scale.h"
#include "verilated.h"
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <iostream>
#include <limits>
#include <stdexcept>

static void need(bool okay, const char* message) { if (!okay) throw std::runtime_error(message); }
static uint32_t random_state = 0x514e3806u;
static uint32_t random32() {
    random_state ^= random_state << 13; random_state ^= random_state >> 17;
    random_state ^= random_state << 5; return random_state;
}
static float as_float(uint32_t bits) { float value; std::memcpy(&value, &bits, 4); return value; }
static uint32_t as_bits(float value) { uint32_t bits; std::memcpy(&bits, &value, 4); return bits; }
struct Input { int64_t sum; uint32_t row, vector; };
struct Expected { uint16_t bits; bool error; };
static Expected reference(Input input) {
    volatile float converted = static_cast<float>(input.sum);
    volatile float first = converted*as_float(input.row);
    volatile float second = first*as_float(input.vector);
    uint32_t bits = as_bits(second);
    uint16_t bf16 = uint16_t((bits+0x7fffu+((bits>>16)&1u))>>16);
    auto invalid_scale = [](uint32_t value) {
        return (value>>31) || !(value&0x7fffffffu) || (value&0x7f800000u)==0x7f800000u;
    };
    bool error = invalid_scale(input.row) || invalid_scale(input.vector)
        || !std::isfinite(first) || !std::isfinite(second) || (bf16&0x7f80u)==0x7f80u;
    return {bf16, error};
}
int main(int argc, char** argv) { try {
    Verilated::commandArgs(argc, argv);
    need(sizeof(float)==4 && std::numeric_limits<float>::is_iec559
         && std::fesetround(FE_TONEAREST)==0 && as_float(1)>0,
         "IEEE FP32 RNE with subnormals is required");
    Vqwen_projection_scale d;
    d.clk = 0; d.rst_n = 0; d.clear = 0; d.in_valid = 0; d.out_ready = 0;
    auto edge = [&]() { d.clk = 1; d.eval(); d.clk = 0; d.eval(); };
    for (unsigned n = 0; n < 4; ++n) edge();
    d.rst_n = 1;
    const uint64_t mask40 = (uint64_t(1)<<40)-1;
    const int64_t sums[] = {0,1,-1,(int64_t(1)<<39)-1,-(int64_t(1)<<39),
        (int64_t(1)<<24)+1,(int64_t(1)<<24)+3,-((int64_t(1)<<24)+1),255,-255};
    const uint32_t scales[] = {0x3f800000,0x3f000000,0x3f808000,0x3fffffff,
        0x00800000,0x00000001,0x7f7fffff,0,0x80000000,0xbf800000,0x7f800000,0x7fc00000};
    constexpr unsigned limit = 12000;
    unsigned sent=0, checked=0, cancelled=0, cycles=0, clears=0, resets=0, held_checks=0, errors=0;
    bool offered=false, held=false;
    uint16_t held_bits=0; bool held_error=false;
    Input input{};
    std::deque<Expected> pending;
    while (sent<limit || offered || !pending.empty()) {
        need(++cycles<limit*8, "scaling pipeline watchdog");
        if (!offered && sent<limit && random32()%5) {
            if (sent<1200) input={sums[sent%10], scales[(sent/10)%12], scales[(sent/120)%10]};
            else {
                uint64_t raw = (uint64_t(random32())<<32 | random32())&mask40;
                int64_t value = raw&(uint64_t(1)<<39) ? int64_t(raw)-int64_t(uint64_t(1)<<40) : int64_t(raw);
                input={value, uint32_t(((100+random32()%40)<<23)|(random32()&0x7fffff)),
                              uint32_t(((100+random32()%40)<<23)|(random32()&0x7fffff))};
            }
            offered=true;
        }
        d.clear=cycles%997==0 && sent<limit;
        d.rst_n=!(cycles%1237==0 && sent<limit && !d.clear);
        d.in_valid=offered; d.integer_sum=uint64_t(input.sum)&mask40;
        d.row_scale=input.row; d.vector_scale=input.vector; d.out_ready=random32()%4 != 0;
        d.eval();
        if (d.clear || !d.rst_n) {
            need(!d.in_ready && !d.out_valid, "reset/CLEAR did not mask transfers");
            cancelled+=pending.size(); pending.clear(); held=false;
            if (d.clear) ++clears; else ++resets;
        } else {
            if (held) {
                need(d.out_valid && d.result==held_bits && bool(d.out_error)==held_error,
                     "stalled scaling result changed");
                ++held_checks;
            }
            held=d.out_valid && !d.out_ready; held_bits=d.result; held_error=d.out_error;
            if (d.out_valid && d.out_ready) {
                need(!pending.empty(), "unexpected scaling output");
                auto expected=pending.front(); pending.pop_front();
                need(bool(d.out_error)==expected.error && (expected.error || d.result==expected.bits),
                     "FP32/BF16 scaling mismatch");
                ++checked; if (expected.error) ++errors;
            }
            if (d.in_valid && d.in_ready) { pending.push_back(reference(input)); offered=false; ++sent; }
        }
        edge();
    }
    need(checked+cancelled==limit && clears && resets && held_checks && errors,
         "incomplete scaling/protocol workload");
    std::cout << "{\"passed\":true,\"inputs\":" << sent << ",\"checked\":" << checked
              << ",\"cancelled\":" << cancelled << ",\"clears\":" << clears
              << ",\"resets\":" << resets << ",\"held_checks\":" << held_checks
              << ",\"error_results\":" << errors << ",\"cycles\":" << cycles << "}\n";
    d.final(); return 0;
} catch (const std::exception& error) { std::cerr << error.what() << "\n"; return 1; } }
