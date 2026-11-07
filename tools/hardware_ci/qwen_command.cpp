// Fresh production command-CLEAR/FIFO simulation. The core is a protocol
// stimulus, not a numerical model. Follow the one-command/one-CLEAR contract.
#include "Vqwen_token_command_cdc.h"
#include "verilated.h"
#include "clock.h"
#include <array>
#include <deque>
#include <iostream>
#include <tuple>
#include <vector>

using Frame=std::tuple<uint32_t,uint32_t,uint32_t>;
struct Bench {
    Vqwen_token_command_cdc d;
    ClockPlan clocks;
    uint64_t time=0, sent=0, core_commands=0, responses=0, received=0;
    uint64_t held_checks=0, resets=0, cancellations=0, pending_replacements=0;
    std::deque<Frame> expected;
    std::vector<std::pair<uint32_t,uint32_t>> accepted_core;
    bool held=false;
    Frame held_frame{};
    explicit Bench(ClockPlan plan):clocks(plan) {
        d.rst_n=1; d.shell_clk=d.core_clk=0;
        d.command_valid=0; d.command_id=0; d.command_opcode=0; d.command_token=0;
        d.result_ready=1; d.core_cmd_ready=1; d.core_response_valid=0;
        d.core_response_status=0; d.core_response_token=0; d.eval();
        reset();
    }
    Frame frame() const { return {d.result_id,d.result_status,d.result_token}; }
    void tick() {
        d.eval();
        bool se=clocks.source_edge(time), ce=clocks.destination_edge(time);
        bool sr=se&&!d.shell_clk, cr=ce&&!d.core_clk;
        if (d.rst_n && sr) {
            if (d.command_valid&&d.command_ready) ++sent;
            if (held) {
                require(d.result_valid && frame()==held_frame,"qwen_command_cdc held_result");
                ++held_checks;
            }
            held=d.result_valid&&!d.result_ready;
            if (held) held_frame=frame();
            if (d.result_valid&&d.result_ready) {
                require(!expected.empty(),"qwen_command_cdc cancelled_response");
                require(frame()==expected.front(),"qwen_command_cdc result_ownership");
                expected.pop_front(); ++received;
            }
        }
        if (d.rst_n && cr) {
            if (d.core_cmd_valid&&d.core_cmd_ready) {
                accepted_core.emplace_back(d.core_cmd_opcode,d.core_cmd_token);
                ++core_commands;
            }
            if (d.core_response_valid&&d.core_response_ready) ++responses;
        }
        if (se) d.shell_clk=!d.shell_clk;
        if (ce) d.core_clk=!d.core_clk;
        d.eval(); ++time;
    }
    void advance(unsigned count) { while(count--) tick(); }
    template<class Predicate> void until(Predicate done,const char* label) {
        uint64_t limit=time+20000;
        while(!done()) { require(time<limit,label); tick(); }
    }
    void reset() {
        d.command_valid=0; d.core_response_valid=0; expected.clear(); held=false;
        d.rst_n=0; d.eval(); advance(40*(clocks.source_half+clocks.destination_half));
        require(!d.result_valid&&!d.core_cmd_valid,"qwen_command_cdc reset_closed");
        d.rst_n=1; d.result_ready=1; d.core_cmd_ready=1;
        advance(40*(clocks.source_half+clocks.destination_half));
        require(!d.result_valid&&!d.core_cmd_valid,"qwen_command_cdc stale_after_reset");
        ++resets;
    }
    void command(uint32_t id,uint32_t opcode,uint32_t token) {
        uint64_t before=sent;
        d.command_id=id; d.command_opcode=opcode; d.command_token=token; d.command_valid=1;
        until([&]{return sent!=before;},"qwen_command_cdc source_progress");
        d.command_valid=0; d.eval();
    }
    void response(uint32_t status,uint32_t token) {
        uint64_t before=responses;
        d.core_response_status=status; d.core_response_token=token; d.core_response_valid=1;
        until([&]{return responses!=before;},"qwen_command_cdc response_progress");
        d.core_response_valid=0; d.eval();
    }
    void drain() {
        d.result_ready=1;
        until([&]{return expected.empty();},"qwen_command_cdc result_progress");
        advance(40*(clocks.source_half+clocks.destination_half));
        require(!d.result_valid,"qwen_command_cdc duplicate_result");
    }
    void ordinary(uint32_t id) {
        uint64_t before=core_commands;
        uint32_t input=id*17+5, output=id*101+3;
        command(id,1,input);
        until([&]{return core_commands!=before;},"qwen_command_cdc command_progress");
        require(accepted_core.back()==std::make_pair(1u,input),"qwen_command_cdc command_data");
        expected.emplace_back(id,2,output);
        d.result_ready=0; response(2,output);
        until([&]{return bool(d.result_valid);},"qwen_command_cdc result_visible");
        advance(30*(clocks.source_half+clocks.destination_half));
        drain();
    }
    void clear_active(uint32_t id) {
        uint64_t before=core_commands;
        command(id,2,0);
        until([&]{return core_commands!=before;},"qwen_command_cdc active_progress");
        d.core_cmd_ready=0;
        command(id+1,3,0);
        until([&]{return bool(d.core_cmd_clear_valid);},"qwen_command_cdc clear_visible");
        require(d.core_cmd_valid&&d.core_cmd_opcode==3&&d.core_cmd_token==0,
                "qwen_command_cdc clear_qualification");
        // The old STEP response and CLEAR acceptance occur on the same core edge.
        // The documented pending-CLEAR/clear_take rule must discard that response.
        before=core_commands; d.core_cmd_ready=1; response(2,0xdeadbeefu);
        require(core_commands==before+1&&accepted_core.back()==std::make_pair(3u,0u),
                "qwen_command_cdc clear_acceptance");
        advance(50*(clocks.source_half+clocks.destination_half));
        require(!d.result_valid,"qwen_command_cdc cancelled_response");
        expected.emplace_back(id+1,0,0); response(0,0); drain(); ++cancellations;
    }
    void replace_pending(uint32_t id) {
        uint64_t before=core_commands; d.core_cmd_ready=0;
        command(id,1,0x12345678u);
        until([&]{return bool(d.core_cmd_valid);},"qwen_command_cdc pending_visible");
        command(id+1,3,0);
        until([&]{return bool(d.core_cmd_clear_valid);},"qwen_command_cdc replacement_visible");
        require(core_commands==before,"qwen_command_cdc unaccepted_not_owned");
        d.core_cmd_ready=1;
        until([&]{return core_commands!=before;},"qwen_command_cdc replacement_progress");
        require(accepted_core.back()==std::make_pair(3u,0u),"qwen_command_cdc pending_replaced");
        expected.emplace_back(id+1,0,0); response(0,0); drain(); ++pending_replacements;
    }
    void reset_with_queued_result(uint32_t id) {
        uint64_t before=core_commands; command(id,1,9);
        until([&]{return core_commands!=before;},"qwen_command_cdc reset_command");
        d.result_ready=0; response(2,0xaabbccddu);
        until([&]{return bool(d.result_valid);},"qwen_command_cdc reset_queued");
        // This is coordinated FABRIC reset, never an APPEND/STEP/CLEAR substitute.
        reset(); ordinary(id+1);
    }
};
int main(int argc,char** argv) {
    try {
        Verilated::commandArgs(argc,argv);
        const std::array<ClockPlan,3> plans{{{2,3,0},{3,2,1},{3,5,2}}};
        uint64_t sent=0,received=0,held=0,resets=0,cancelled=0,replaced=0,commands=0;
        for (auto plan:plans) {
            Bench b(plan);
            for(unsigned i=0;i<40;++i) b.ordinary(100+i);
            b.clear_active(1000); b.replace_pending(2000); b.reset_with_queued_result(3000);
            require(b.sent>=46&&b.received==43&&b.held_checks>100&&b.resets==2,
                    "qwen_command_cdc coverage");
            sent+=b.sent;received+=b.received;held+=b.held_checks;resets+=b.resets;
            cancelled+=b.cancellations;replaced+=b.pending_replacements;commands+=b.core_commands;
        }
        std::cout<<"{\"passed\":true,\"schedules\":3,\"commands_sent\":"<<sent
          <<",\"core_accepts\":"<<commands<<",\"results_checked\":"<<received
          <<",\"held_checks\":"<<held<<",\"fabric_resets\":"<<resets
          <<",\"active_clear_cancellations\":"<<cancelled<<",\"pending_clear_replacements\":"<<replaced<<"}\n";
    } catch(const std::exception& e) { std::cerr<<"FAIL "<<e.what()<<'\n'; return 1; }
}
