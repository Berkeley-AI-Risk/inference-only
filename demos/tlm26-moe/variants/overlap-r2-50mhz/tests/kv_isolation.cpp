// Full unchanged product at UART pins, with an explicitly modeled DDR port.
// Observation only: counters never drive the DUT or supply predicted tokens.
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
#include "Vtlm_product.h"
#include "Vtlm_product___024root.h"
#include "verilated.h"
static Vtlm_product d;
#define R(name) (d.rootp->tlm_product__DOT__##name)
#define DEC(name) R(decoder__DOT__##name)
#define C(name) R(cache__DOT__##name)
static std::vector<uint8_t> image, rx;
static uint64_t ticks=0, reads=0;
static bool owe=false, active=false;
static uint32_t address=0;
static int lag=0, txphase=-1, txbit=0, txbyte=0;
constexpr int baud=109;
constexpr unsigned KV_CACHE_2=16;
constexpr unsigned KV_CACHE_END=20;
constexpr unsigned KV_SCORE_DOT_1_GOT=29;
constexpr unsigned KV_HEAD_VALUE_1_GOT=48;
struct Stats {
    std::array<uint64_t,229> state{}, mat_call{};
    std::array<uint64_t,9> cache{};
    uint64_t began=0, ended=0, hold=0, sha_busy=0, hits=0, misses=0;
    uint64_t words=0, macs=0, rows=0, ddr_wait=0, ddr_backpressure=0;
    uint64_t wh=14695981039346656037ull, mh=14695981039346656037ull;
    uint64_t rh=14695981039346656037ull, dh=14695981039346656037ull;
} s;
static void hash64(uint64_t &h, uint64_t v) {
    for(int i=0;i<8;i++){h^=uint8_t(v);h*=1099511628211ull;v>>=8;}
}

// Observation-only epoch scoreboard. No production state or response is driven here.
static std::array<bool,81920> epoch_written{};
static uint64_t kv_writes=0,kv_reads=0,kv_read_hash=14695981039346656037ull;
static uint64_t epoch_number=0,clears_with_old_cache=0;
static unsigned last_read_address=0;
static bool last_read_known=false;
static void kv_before_edge() {
    unsigned st=DEC(state),addr=DEC(sadr);
    if(!d.rst_n || R(clr)) {
        if(R(clr)) {epoch_number++;if(kv_writes)clears_with_old_cache++;}
        epoch_written.fill(false);last_read_known=false;
        return;
    }
    if(DEC(swe) && addr>=2048) {
        if(addr>=83968 || (st!=KV_CACHE_2 && st!=KV_CACHE_END))
            throw std::runtime_error("unaccounted KV writer/address");
        unsigned relative=addr-2048;
        if((relative>>14)!=DEC(layer) || ((relative>>6)&255)!=DEC(pos)
          || (relative&63)!=DEC(i)+(st==KV_CACHE_END?32:0))
            throw std::runtime_error("KV writer aliases another row/layer");
        epoch_written[relative]=true;kv_writes++;
    }
    if(st==KV_SCORE_DOT_1_GOT || st==KV_HEAD_VALUE_1_GOT) {
        unsigned lane=((DEC(head)>>1)<<3)+DEC(j)+(st==KV_HEAD_VALUE_1_GOT?32:0);
        unsigned expected=2048+(DEC(layer)<<14)+(DEC(t)<<6)+lane;
        if(!last_read_known || last_read_address!=expected || expected>=83968
          || DEC(layer)>=5 || DEC(pos)>=256 || DEC(t)>DEC(pos) || lane>=64)
            throw std::runtime_error("KV reader exceeds live history");
        if(!epoch_written[expected-2048])
            throw std::runtime_error("prior-history/unwritten KV consumed after CLEAR");
        hash64(kv_read_hash,expected);hash64(kv_read_hash,uint32_t(DEC(srdata)));kv_reads++;
    }
    if(!DEC(swe)) {last_read_address=addr;last_read_known=true;}
}
static uint64_t cache_hash(bool live_only) {
    uint64_t h=14695981039346656037ull;
    for(unsigned l=0;l<5;l++)for(unsigned p=0;p<(live_only?unsigned(DEC(pos)):256u);p++)
      for(unsigned n=0;n<64;n++)hash64(h,DEC(scratch)[2048+l*16384+p*64+n]);
    return h;
}

void tick() {
    d.clk=0; d.rd_ready=(ticks%7)!=0; d.rd_valid=owe && lag==0;
    if(d.rd_valid) {
        if(address+32>image.size()) throw std::runtime_error("DDR address out of range");
        std::memcpy(d.rd_data.data(),image.data()+address,32);
    }
    d.eval();
    if(R(cv) && R(cr)) {
        if(active) throw std::runtime_error("overlapping decoder jobs");
        active=true; s.began=ticks;
    }
    if(R(clr)) active=false;
    if(active) {
        unsigned st=DEC(state), cs=C(state);
        if(st>=s.state.size() || cs>=s.cache.size()) throw std::runtime_error("state range");
        s.state[st]++; s.cache[cs]++;
        if(st>=131 && st<=145) s.mat_call.at(DEC(back_MAT))++;
        s.hold+=R(hold_first__DOT__held) && R(hold_first__DOT__delay_count)>0;
        s.sha_busy+=C(sha__DOT__busy);
        s.ddr_wait+=cs==2 && !R(delayed_valid) && !R(hold_first__DOT__held);
        s.ddr_backpressure+=d.rd_req && !d.rd_ready;
        if(cs==0 && R(wreq)) {
            bool hit=C(good) && C(page)==(R(wa)>>11);
            s.hits+=hit; s.misses+=!hit;
        }
        if(R(wvalid) && R(wreq)) {
            if(!C(good) || C(page)!=(R(wa)>>11)) throw std::runtime_error("unverified weight consumed");
            hash64(s.wh,R(wa));hash64(s.wh,R(wd));s.words++;
        }
        if(st==139) { // MAT_MAC_2_M: actual multiplier operands, in arithmetic order.
            hash64(s.mh,DEC(wi));hash64(s.mh,DEC(ma));hash64(s.mh,DEC(mb));
            hash64(s.mh,DEC(accum));s.macs++;
        }
        if(st==143) { // MAT_WRITE: complete unrounded row sum and target.
            hash64(s.rh,DEC(dst)+DEC(r));hash64(s.rh,DEC(accum));s.rows++;
        }
    }
    bool take=d.rd_req && d.rd_ready;
    if(d.rd_valid) owe=false;
    if(take) {
        if(owe) throw std::runtime_error("more than one accepted DDR read");
        address=d.rd_byte_addr;
        if(active) hash64(s.dh,address);
        reads++;lag=2+reads%6;owe=true;
    } else if(owe && lag>0) lag--;
    if(txphase==-1) {
        if(d.uart_tx==0){txphase=0;txbit=0;txbyte=0;}
    } else {
        txphase++;
        if(txphase==baud+baud/2+txbit*baud && txbit<8){txbyte|=d.uart_tx<<txbit;txbit++;}
        if(txphase==9*baud+baud/2) {
            if(!d.uart_tx) throw std::runtime_error("UART stop bit");
            rx.push_back(txbyte);txphase=-1;
        }
    }
    bool was_clear=R(clr); kv_before_edge();
    d.clk=1;d.eval();ticks++;
    if(was_clear && (DEC(pos)!=0 || DEC(next_token)!=0 || DEC(state)!=0)) throw std::runtime_error("CLEAR failed to invalidate history");
    if(active && R(rv)){s.ended=ticks;active=false;}
}
void clocks(unsigned n){while(n--)tick();}
uint8_t crc(std::array<uint8_t,5> f) {
    int x=0;for(int i=0;i<4;i++){x^=f[i];for(int b=0;b<8;b++)x=((x<<1)^((x&128)?7:0))&255;}return x;
}
void send_byte(uint8_t b) {
    d.uart_rx=0;clocks(baud);
    for(unsigned i=0;i<8;i++){d.uart_rx=(b>>i)&1;clocks(baud);}
    d.uart_rx=1;clocks(baud);
}
void send(int op,int tok) {
    std::array<uint8_t,5> f={0xa5,(uint8_t)op,(uint8_t)tok,(uint8_t)(tok>>8),0};f[4]=crc(f);
    for(auto b:f)send_byte(b);
}
void receive(int kind,int token) {
    auto start=ticks;
    while(rx.size()<5 && ticks-start<30000000)tick();
    if(rx.size()!=5)throw std::runtime_error("timeout or stale UART bytes");
    std::array<uint8_t,5> f={0x5a,(uint8_t)kind,(uint8_t)token,(uint8_t)(token>>8),0};f[4]=crc(f);
    if(!std::equal(f.begin(),f.end(),rx.begin())){
        std::cerr<<"expected "<<kind<<":"<<token<<" got ";for(auto b:rx)std::cerr<<(int)b<<" ";
        throw std::runtime_error("wrong dependent token/opcode/CRC");
    }
    rx.clear();clocks(baud);
}

struct Snapshot {
 uint64_t live,kh,wh,mh,rh,reads,writes; unsigned next,pos;
 std::vector<uint32_t> live_words;
 bool operator==(const Snapshot&) const = default;
};
static Snapshot command(int op,int token,int kind,int wanted) {
 s=Stats{};kv_read_hash=14695981039346656037ull;
 auto rb=kv_reads,wb=kv_writes;
 send(op,token);receive(kind,wanted);
 Snapshot v{cache_hash(true),kv_read_hash,s.wh,s.mh,s.rh,kv_reads-rb,kv_writes-wb,unsigned(DEC(next_token)),unsigned(DEC(pos))};
 for(unsigned l=0;l<5;l++)for(unsigned p=0;p<v.pos;p++)for(unsigned n=0;n<64;n++)
  v.live_words.push_back(DEC(scratch)[2048+l*16384+p*64+n]);
 if(op!=2 && (v.writes!=320 || v.reads!=640*v.pos)) throw std::runtime_error("incomplete layer/row KV coverage");
 return v;
}
static void report_snapshot(const char* name,const Snapshot& step) {
 std::cout<<"{\"case\":\""<<name<<"\",\"accepted\":true,\"next_token\":"<<step.next
  <<",\"position\":"<<step.pos<<",\"live_KV_fnv64\":\""<<step.live<<"\",\"KV_read_fnv64\":\""<<step.kh
  <<"\",\"weight_word_fnv64\":\""<<step.wh<<"\",\"matrix_term_fnv64\":\""<<step.mh
  <<"\",\"matrix_row_fnv64\":\""<<step.rh<<"\",\"step_KV_reads\":"<<step.reads
  <<",\"step_KV_writes\":"<<step.writes<<",\"all_KV_fnv64\":\""<<cache_hash(false)<<"\"}\n"<<std::flush;
}
static Snapshot target(const char* name) {
 command(2,0,130,0);auto append=command(0,1,128,0);auto step=command(1,0,129,403);
 if(append.pos!=1 || step.pos!=2 || step.next!=407) throw std::runtime_error("new-history reference mismatch");
 report_snapshot(name,step);
 return step;
}
static Snapshot empty_target(const char* name) {
 command(2,0,130,0);auto step=command(1,0,129,0);
 if(step.pos!=1)throw std::runtime_error("direct STEP after CLEAR position mismatch");
 report_snapshot(name,step);return step;
}
int main(int argc,char**argv) {
 Verilated::commandArgs(argc,argv);
 std::ifstream raw("model.bin",std::ios::binary|std::ios::ate);
 if(!raw)throw std::runtime_error("missing model");
 auto size=raw.tellg();raw.seekg(0);image.resize(size);raw.read((char*)image.data(),size);
 d.rst_n=0;d.uart_rx=1;clocks(10);d.rst_n=1;clocks(20);
 auto clean=target("clean");auto initial_all=cache_hash(false);
 command(2,0,130,0);
 for(auto token:std::array<int,4>{1,403,407,261}) command(0,token,128,0);
 auto a=target("reused_history_A");
 if(!(a==clean) || cache_hash(false)==initial_all)throw std::runtime_error("history A isolation failed or no stale tail exercised");
 command(2,0,130,0);
 for(auto token:std::array<int,5>{1,291,376,280,294})command(0,token,128,0);
 auto b=target("reused_history_B");
 if(!(b==clean) || cache_hash(false)==initial_all)throw std::runtime_error("history B isolation failed or no stale tail exercised");
 command(2,0,130,0);command(0,1,128,0);
 auto before=kv_writes;send(1,0);auto begin=ticks;
 while(kv_writes==before && ticks-begin<30000000)tick();
 if(kv_writes==before)throw std::runtime_error("partial-history cancellation did not reach KV writer");
 send(2,0);receive(130,0);clocks(2000);
 if(!rx.empty())throw std::runtime_error("stale token after cancelled history");
 auto c=target("cancelled_partial_history");if(!(c==clean))throw std::runtime_error("cancelled history isolation failed");
 auto empty_clean=empty_target("clean_no_append");
 command(2,0,130,0);
 for(auto token:std::array<int,4>{1,403,407,261})command(0,token,128,0);
 auto ea=empty_target("reused_A_no_append");if(!(ea==empty_clean))throw std::runtime_error("direct STEP history A isolation failed");
 command(2,0,130,0);
 for(auto token:std::array<int,5>{1,291,376,280,294})command(0,token,128,0);
 auto eb=empty_target("reused_B_no_append");if(!(eb==empty_clean))throw std::runtime_error("direct STEP history B isolation failed");
 command(2,0,130,0);command(0,1,128,0);
 before=kv_writes;send(1,0);begin=ticks;
 while(kv_writes==before && ticks-begin<30000000)tick();
 if(kv_writes==before)throw std::runtime_error("direct STEP cancellation precondition");
 send(2,0);receive(130,0);clocks(2000);
 if(!rx.empty())throw std::runtime_error("stale token after second cancelled history");
 auto ec=empty_target("cancelled_no_append");if(!(ec==empty_clean))throw std::runtime_error("direct STEP cancelled history isolation failed");
 command(2,0,130,0);
 if(active || owe)throw std::runtime_error("pending transaction at end");
 std::cout<<"{\"summary\":true,\"accepted\":true,\"epochs\":"<<epoch_number<<",\"KV_reads_checked\":"<<kv_reads
  <<",\"KV_writes_checked\":"<<kv_writes<<",\"clears_with_existing_cache\":"<<clears_with_old_cache
  <<",\"production_state_assignments\":false,\"physical_device_access\":false}\n";
}
