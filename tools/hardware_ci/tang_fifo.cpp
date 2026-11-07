// The selected QSPI/auth-loader FIFO, with protocol-observing digital clocks.
// Reset both endpoints together; do not infer arbitrary independent-reset safety.
#include "Vboard1_qspi_async_word_fifo4.h"
#include "verilated.h"
#include "clock.h"
#include <array>
#include <deque>
#include <iostream>
#include <optional>
#include <random>
using Word=std::array<uint32_t,8>;
struct Bench {
    Vboard1_qspi_async_word_fifo4 d;
    ClockPlan clocks;
    std::mt19937 random{230719};
    std::deque<Word> expected;
    std::optional<Word> offer,held;
    bool produce=false,consume=true;
    uint64_t time=0,sent=0,received=0,discarded=0,resets=0,held_checks=0,full_checks=0,maximum=0;
    explicit Bench(ClockPlan p):clocks(p) {
        d.write_clk_i=d.read_clk_i=0; d.write_valid_i=d.read_ready_i=0;
        d.write_reset_n_i=d.read_reset_n_i=1; d.eval(); reset();
    }
    Word next_word() { Word w{};for(auto& x:w)x=random();return w; }
    Word data() const { Word w{};for(unsigned i=0;i<8;++i)w[i]=d.read_data_o[i];return w; }
    void tick() {
        bool running=d.write_reset_n_i&&d.read_reset_n_i;
        if(running&&produce&&!offer&&random()%4)offer=next_word();
        d.write_valid_i=running&&offer.has_value();
        for(unsigned i=0;i<8;++i)d.write_data_i[i]=offer?(*offer)[i]:0;
        d.read_ready_i=running&&consume&&random()%4;
        d.eval();
        bool we=clocks.source_edge(time),re=clocks.destination_edge(time);
        bool wr=we&&!d.write_clk_i,rr=re&&!d.read_clk_i;
        if(running&&rr) {
            if(held) {require(d.read_valid_o&&data()==*held,"tang_fifo held_data");++held_checks;}
            if(d.read_valid_o&&!d.read_ready_i)held=data();else held.reset();
            if(d.read_valid_o&&d.read_ready_i) {
                require(!expected.empty(),"tang_fifo invented_word");
                require(data()==expected.front(),"tang_fifo data_order");
                expected.pop_front();++received;
            }
        }
        if(running&&wr) {
            if(d.write_valid_i&&!d.write_ready_o)++full_checks;
            if(d.write_valid_i&&d.write_ready_o) {expected.push_back(*offer);offer.reset();++sent;}
        }
        if(expected.size()>maximum)maximum=expected.size();
        require(expected.size()<=4,"tang_fifo capacity");
        if(we)d.write_clk_i=!d.write_clk_i;
        if(re)d.read_clk_i=!d.read_clk_i;
        d.eval();++time;
    }
    void advance(unsigned n) {while(n--)tick();}
    void reset() {
        produce=false;offer.reset();held.reset();discarded+=expected.size();expected.clear();
        d.write_reset_n_i=d.read_reset_n_i=0;d.write_valid_i=0;d.read_ready_i=0;d.eval();
        advance(30*(clocks.source_half+clocks.destination_half));
        require(!d.read_valid_o,"tang_fifo reset_visible");
        d.write_reset_n_i=d.read_reset_n_i=1;
        advance(30*(clocks.source_half+clocks.destination_half));
        require(!d.read_valid_o,"tang_fifo stale_after_reset");++resets;
    }
    void drain() {
        produce=false;consume=true;uint64_t deadline=time+30000;
        do {tick();require(time<deadline,"tang_fifo drain_progress");}
        while(!expected.empty()||offer||d.read_valid_o);
        advance(30*(clocks.source_half+clocks.destination_half));
        require(!d.read_valid_o,"tang_fifo duplicate_word");
    }
    void traffic(unsigned words) {
        produce=consume=true;uint64_t target=sent+words,deadline=time+500000;
        while(sent<target) {tick();require(time<deadline,"tang_fifo traffic_progress");}
        drain();
    }
    void fill() {
        produce=true;consume=false;
        advance(200*(clocks.source_half+clocks.destination_half));
        require(expected.size()==4&&!d.write_ready_o&&d.read_valid_o,"tang_fifo full_backpressure");
        advance(100*(clocks.source_half+clocks.destination_half));
    }
};
int main(int argc,char** argv) {
    try {
        Verilated::commandArgs(argc,argv);
        // Two finite schedules use write:read ratio1:2; the third stresses
        // unequal edge placement. None qualifies a production clock recipe.
        const std::array<ClockPlan,3> plans{{{4,2,0},{4,2,1},{5,3,2}}};
        uint64_t sent=0,received=0,discarded=0,resets=0,held=0,full=0;
        for(auto plan:plans) {
            Bench b(plan);b.traffic(800);
            for(unsigned i=0;i<4;++i){b.fill();b.drain();}
            for(unsigned i=0;i<3;++i){b.fill();b.reset();b.traffic(100);}
            require(b.sent==b.received+b.discarded&&b.maximum==4&&b.held_checks>100&&b.full_checks>100,
                    "tang_fifo coverage");
            sent+=b.sent;received+=b.received;discarded+=b.discarded;resets+=b.resets;
            held+=b.held_checks;full+=b.full_checks;
        }
        std::cout<<"{\"passed\":true,\"schedules\":3,\"words_sent\":"<<sent
          <<",\"words_checked\":"<<received<<",\"reset_discarded_words\":"<<discarded
          <<",\"coordinated_resets\":"<<resets<<",\"held_checks\":"<<held
          <<",\"full_checks\":"<<full<<",\"capacity_words\":4}\n";
    }catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}
}
