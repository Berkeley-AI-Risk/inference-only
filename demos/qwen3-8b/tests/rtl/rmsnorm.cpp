// Finite native IEEE-FP32/BF16 oracle and synchronous RMSNorm protocol checks.
#include "Vqwen_rms_norm.h"
#include "verilated.h"
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

static void need(bool okay, const char* message) { if (!okay) throw std::runtime_error(message); }
static float as_float(uint32_t bits) { float v; std::memcpy(&v, &bits, 4); return v; }
static uint32_t as_bits(float v) { uint32_t bits; std::memcpy(&bits, &v, 4); return bits; }
static float decode(uint16_t v) { return as_float(uint32_t(v)<<16); }
static uint16_t narrow(float v) {
    uint32_t bits = as_bits(v);
    return uint16_t((bits+0x7fffu+((bits>>16)&1u))>>16);
}
static uint32_t random_state=0x514e3807u;
static uint32_t random32() {
    random_state^=random_state<<13; random_state^=random_state>>17;
    random_state^=random_state<<5; return random_state;
}
struct Input { std::vector<uint16_t> x, w; };
struct Expected { std::vector<uint16_t> bits; bool error=false; };
static Expected reference(const Input& in) {
    // Separate rounded FP32 operations, ordered left-to-right accumulation,
    // epsilon from exact bits, sqrt then reciprocal, and TWO BF16 boundaries.
    Expected out;
    volatile float sum=0;
    for (unsigned i=0; i<in.x.size(); ++i) {
        if (!std::isfinite(decode(in.x[i])) || !std::isfinite(decode(in.w[i]))) return {{},true};
        volatile float square=decode(in.x[i])*decode(in.x[i]);
        sum=sum+square;
        if (!std::isfinite(square) || !std::isfinite(sum)) return {{},true};
    }
    volatile float mean=sum*(1.0f/float(in.x.size()));
    volatile float variance=mean+as_float(0x358637bdu);
    volatile float root=std::sqrt(float(variance));
    volatile float inverse=1.0f/root;
    if (!std::isfinite(mean) || !std::isfinite(variance) || !std::isfinite(root)
        || !std::isfinite(inverse)) return {{},true};
    for (unsigned i=0; i<in.x.size(); ++i) {
        volatile float normalized=decode(in.x[i])*inverse;
        uint16_t rounded=narrow(normalized);
        volatile float product=decode(rounded)*decode(in.w[i]);
        uint16_t result=narrow(product);
        if (!std::isfinite(normalized) || !std::isfinite(decode(rounded))
            || !std::isfinite(product) || !std::isfinite(decode(result))) return {{},true};
        out.bits.push_back(result);
    }
    return out;
}
static Input pattern(unsigned width, unsigned kind) {
    Input in{std::vector<uint16_t>(width),std::vector<uint16_t>(width,0x3f80)};
    for (unsigned i=0; i<width; ++i) {
        switch (kind) {
        case 0: in.x[i]=i%2 ? 0x8000 : 0; break;
        case 1: in.x[i]=0x3f80; break;
        case 2: in.x[i]=i%2 ? 0xbf80 : 0x3f80; in.w[i]=0x3f00; break;
        case 3: in.x[i]=i==width-1 ? 0x4000 : 0; break;
        case 4: in.x[i]=uint16_t(((118+i%14)<<7)|(i%128)); break;
        case 5: in.x[i]=uint16_t(1+i%127); break;
        case 6: in.x[i]=uint16_t(0x3e80+i%128); in.w[i]=i%2 ? 0xbf80 : 0x3f80; break;
        default:
            in.x[i]=uint16_t((random32()&0x807fu)|((119+random32()%12)<<7));
            in.w[i]=uint16_t((random32()&0x807fu)|((124+random32()%5)<<7));
        }
    }
    return in;
}
struct Counts {
    unsigned normal_frames=0, head_frames=0, full_frames=0, error_frames=0;
    unsigned cancelled_frames=0, checked_values=0, clears=0, resets=0;
    unsigned held_checks=0, input_bubbles=0, accepted_inputs=0, cycles=0;
};
int main(int argc, char** argv) { try {
    Verilated::commandArgs(argc,argv);
    need(sizeof(float)==4 && std::numeric_limits<float>::is_iec559
         && std::fesetround(FE_TONEAREST)==0 && as_float(1)>0,
         "IEEE FP32 RNE with subnormals is required");
    Vqwen_rms_norm d;
    Counts c;
    d.clk=0; d.rst_n=0; d.clear=0; d.start=0; d.in_valid=0; d.out_ready=0;
    auto edge=[&]() { d.clk=1; d.eval(); d.clk=0; d.eval(); ++c.cycles; };
    for (unsigned i=0;i<4;++i) edge();
    d.rst_n=1;
    auto execute=[&](const Input& in,unsigned cancel) {
        Expected expected=reference(in);
        unsigned width=in.x.size(), sent=0, got=0, cycles=0;
        bool offered=false, held=false;
        uint16_t held_bits=0, held_index=0; bool held_error=false;
        d.eval(); need(!d.busy && !d.out_valid,"old RMS frame survived completion/cancel");
        d.head_mode=width==128; d.start=1; d.in_valid=0; d.out_ready=0; edge(); d.start=0;
        while (true) {
            need(++cycles<width*25+10000,"RMSNorm finite watchdog");
            if (!offered && sent<width && random32()%4) offered=true;
            d.in_valid=offered;
            if (sent<width) { d.activation=in.x[sent]; d.norm_weight=in.w[sent]; }
            d.out_ready=random32()%4!=0 && cycles%97>6;
            if (cancel==2) d.out_ready=0;
            d.eval();
            bool stop=(cancel==1 && sent>=17) || (cancel==2 && d.out_valid) || (cancel==3 && got>=11);
            if (stop) {
                d.in_valid=0; d.clear=cancel!=3; d.rst_n=cancel!=3; d.eval();
                need(!d.in_ready && !d.out_valid,"CLEAR/reset did not mask RMS transfers");
                edge(); edge(); d.clear=0; d.rst_n=1; edge();
                need(!d.busy && !d.out_valid,"cancelled RMS frame not retired");
                ++c.cancelled_frames;
                if (cancel==3) ++c.resets; else ++c.clears;
                return;
            }
            if (held) {
                need(d.out_valid && d.result==held_bits && d.out_index==held_index
                     && bool(d.out_error)==held_error,"held RMS result/tag/error changed");
                ++c.held_checks;
            }
            held=d.out_valid && !d.out_ready;
            held_bits=d.result; held_index=d.out_index; held_error=d.out_error;
            bool done=false;
            if (d.out_valid && d.out_ready) {
                if (expected.error) {
                    need(d.out_error,"nonfinite RMS frame was not rejected");
                    ++c.error_frames; done=true;
                } else {
                    if (d.out_error || d.out_index!=got || d.result!=expected.bits[got]) {
                        std::cerr << "width=" << width << " index=" << got << " actual=" << d.result
                                  << " expected=" << expected.bits[got] << " error=" << unsigned(d.out_error) << "\n";
                        throw std::runtime_error("ordered FP32/BF16 RMSNorm mismatch");
                    }
                    ++got; ++c.checked_values;
                    if (got==width) {
                        need(sent==width,"output completed before all RMS inputs");
                        ++c.normal_frames; if (width==128) ++c.head_frames; else ++c.full_frames;
                        done=true;
                    }
                }
            }
            if (d.in_valid && d.in_ready) { ++sent; ++c.accepted_inputs; offered=false; }
            else if (!d.in_valid && d.in_ready) ++c.input_bubbles;
            edge();
            if (done) { d.in_valid=0; d.out_ready=0; d.eval(); return; }
        }
    };
    for (unsigned width : {128u,4096u}) {
        for (unsigned kind=0;kind<10;++kind) execute(pattern(width,kind),0);
        for (unsigned cancel=1;cancel<=3;++cancel) {
            execute(pattern(width,7),cancel);
            // A complete freshly filled frame after every cancellation checks reuse.
            execute(pattern(width,8),0);
        }
        for (unsigned kind=0;kind<4;++kind) {
            auto in=pattern(width,1);
            if (kind==0) in.x[0]=0x7fc0;
            if (kind==1) in.w[3]=0x7f80;
            if (kind==2) for (auto& x:in.x) x=0x7f7f;
            if (kind==3) {
                for (auto& x:in.x) x=0;
                in.x[0]=0x3f80; in.w[0]=0x7f7f;
            }
            need(reference(in).error,"error vector did not exercise a nonfinite boundary");
            execute(in,0);
        }
    }
    need(c.normal_frames==26 && c.head_frames==13 && c.full_frames==13 && c.error_frames==8
         && c.cancelled_frames==6 && c.checked_values==54934 && c.clears==4 && c.resets==2
         && c.held_checks>0 && c.input_bubbles>0,"incomplete RMSNorm/protocol workload");
    std::cout << "{\"passed\":true,\"normal_frames\":" << c.normal_frames
              << ",\"head_frames\":" << c.head_frames << ",\"full_frames\":" << c.full_frames
              << ",\"error_frames\":" << c.error_frames << ",\"cancelled_frames\":" << c.cancelled_frames
              << ",\"checked_values\":" << c.checked_values << ",\"clears\":" << c.clears
              << ",\"resets\":" << c.resets << ",\"held_checks\":" << c.held_checks
              << ",\"input_bubbles\":" << c.input_bubbles << ",\"accepted_inputs\":" << c.accepted_inputs
              << ",\"cycles\":" << c.cycles << "}\n";
    d.final(); return 0;
} catch (const std::exception& error) { std::cerr << error.what() << "\n"; return 1; } }
