// Behavioral AXI3 memory fixture, not vendor HBM IP. Stored bytes come only
// from real RTL AW/W transactions; tests may separately corrupt those bytes.
#pragma once
#include <array>
#include <deque>
#include <map>
#include <optional>
#include <random>
#include <stdexcept>
#include <type_traits>
#include <vector>
namespace kv_axi {
inline void check(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
template<class A> uint64_t bits(const A& a,unsigned offset,unsigned width){
    uint64_t v=0;for(unsigned i=0;i<width;++i){
        if constexpr(std::is_integral_v<A>)v|=uint64_t((a>>(offset+i))&1)<<i;
        else v|=uint64_t((a[(offset+i)/32]>>((offset+i)%32))&1)<<i;
    }return v;
}
template<class A> void set(A& a,unsigned offset,unsigned width,uint64_t value){
    for(unsigned i=0;i<width;++i){
        if constexpr(std::is_integral_v<A>){uint64_t m=1ULL<<(offset+i);a=(a&~m)|(((value>>i)&1)?m:0);}
        else {uint32_t m=1u<<((offset+i)%32);auto& w=a[(offset+i)/32];w=(w&~m)|(((value>>i)&1)?m:0);}
    }
}
using Word=std::array<uint32_t,8>;
struct Address {uint64_t value;unsigned words;};
struct Burst {Address address;unsigned beat=0,delay=0;};
struct Lane {
    std::deque<Burst> reads;
    bool rvalid=false,rlast=false;unsigned rresp=0;Word rdata{};
    std::optional<Address> write,held_ar,held_aw;
    std::vector<Word> words;std::vector<bool> lasts;
    std::optional<Word> held_w;bool held_wlast=false;
    bool visible=false,bvalid=false;unsigned delay=0,bresp=0;
};
template<class DUT> struct Fixture {
    DUT& d;std::mt19937_64& rng;std::map<uint64_t,std::vector<uint8_t>>& memory;
    std::array<Lane,16> lanes;
    bool random_transport=true,hold_read_data=false,hold_b=false;
    unsigned preemption_hold=0,write_fault_region=0,read_fault_region=0;
    uint64_t payload_address=0,manifest_address=0;
    uint64_t read_requests=0,write_requests=0,rbeats=0,wbeats=0,bresponses=0,stored_bytes=0;
    uint64_t drain_checks=0,held_address_checks=0,held_data_checks=0,bus_faults=0;
    Fixture(DUT& dut,std::mt19937_64& random,std::map<uint64_t,std::vector<uint8_t>>& mem):d(dut),rng(random),memory(mem){}
    bool pending() const {
        for(const auto& l:lanes)if(!l.reads.empty()||l.rvalid||l.write||!l.words.empty()||l.bvalid||l.held_ar||l.held_aw||l.held_w)return true;
        return false;
    }
    uint64_t logical(uint64_t physical,unsigned lane)const {
        check(physical>>29==lane+8,"AXI request selected wrong HBM pseudochannel");
        return (uint64_t(lane/8+1)<<32)+((physical&((1ULL<<29)-1))/32)*256+(lane%8)*32;
    }
    uint8_t byte(uint64_t address)const {
        auto it=memory.upper_bound(address);check(it!=memory.begin(),"Read before any private memory write");--it;
        check(address-it->first<it->second.size(),"Read crosses unwritten K/V memory");return it->second[size_t(address-it->first)];
    }
    void drive(){
        if(!d.rst_n){for(auto& l:lanes)l=Lane{};preemption_hold=0;}
        if(!hold_read_data)preemption_hold=0;
        if(hold_read_data&&d.write_start_valid&&pending()){
            if(preemption_hold<37){++preemption_hold;++drain_checks;check(!d.write_start_ready,"Writer opened before held AXI reads drained");}
        }
        bool release_read=!hold_read_data||(d.write_start_valid&&preemption_hold>=37);
        d.axi_arready=d.axi_awready=d.axi_wready=d.axi_rvalid=d.axi_rlast=d.axi_rresp=d.axi_bvalid=d.axi_bresp=0;
        for(unsigned i=0;i<3;++i){d.axi_rid[i]=0;d.axi_bid[i]=0;}
        for(unsigned lane=0;lane<16;++lane){
            auto& l=lanes[lane];
            if(!random_transport||rng()%4)d.axi_arready|=1u<<lane;
            if(!random_transport||rng()%4)d.axi_awready|=1u<<lane;
            if(!random_transport||rng()%4)d.axi_wready|=1u<<lane;
            if(!l.rvalid&&!l.reads.empty()&&release_read){
                auto& b=l.reads.front();if(b.delay)--b.delay;
                else if(!random_transport||rng()%3){
                    uint64_t a=logical(b.address.value+b.beat*32,lane);
                    for(unsigned i=0;i<8;++i){l.rdata[i]=0;for(unsigned j=0;j<4;++j)l.rdata[i]|=uint32_t(byte(a+i*4+j))<<(8*j);}
                    l.rvalid=true;l.rlast=b.beat+1==b.address.words;l.rresp=0;
                    if(read_fault_region==lane/8+1){l.rresp=2;read_fault_region=0;++bus_faults;}
                }
            }
            if(l.visible&&!l.bvalid){
                if(l.delay)--l.delay;
                else if(!hold_b){l.bvalid=true;l.bresp=0;
                    if(write_fault_region==lane/8+1){l.bresp=2;write_fault_region=0;++bus_faults;}
                }
            }
            if(l.rvalid){d.axi_rvalid|=1u<<lane;if(l.rlast)d.axi_rlast|=1u<<lane;d.axi_rresp|=l.rresp<<(lane*2);}
            for(unsigned i=0;i<8;++i)d.axi_rdata[lane*8+i]=l.rdata[i];
            if(l.bvalid){d.axi_bvalid|=1u<<lane;d.axi_bresp|=l.bresp<<(lane*2);}
        }
    }
    void consume(){
        for(unsigned lane=0;lane<16;++lane){
            auto& l=lanes[lane];
            bool arvalid=(d.axi_arvalid>>lane)&1,awvalid=(d.axi_awvalid>>lane)&1,wvalid=(d.axi_wvalid>>lane)&1;
            bool arready=(d.axi_arready>>lane)&1,awready=(d.axi_awready>>lane)&1,wready=(d.axi_wready>>lane)&1;
            Address ar{bits(d.axi_araddr,lane*34,34),unsigned(bits(d.axi_arlen,lane*4,4)+1)};
            Address aw{bits(d.axi_awaddr,lane*34,34),unsigned(bits(d.axi_awlen,lane*4,4)+1)};
            if(l.held_ar){check(arvalid&&ar.value==l.held_ar->value&&ar.words==l.held_ar->words,"AR changed before acceptance");++held_address_checks;}
            if(l.held_aw){check(awvalid&&aw.value==l.held_aw->value&&aw.words==l.held_aw->words,"AW changed before acceptance");++held_address_checks;}
            l.held_ar=arvalid&&!arready?std::optional<Address>(ar):std::nullopt;
            l.held_aw=awvalid&&!awready?std::optional<Address>(aw):std::nullopt;
            if(arvalid&&arready){
                check((ar.value&31)==0&&(ar.value&4095)+ar.words*32<=4096,"AR burst crossed alignment/boundary");logical(ar.value,lane);
                check(bits(d.axi_arid,lane*6,6)==0&&bits(d.axi_arsize,lane*3,3)==5&&bits(d.axi_arburst,lane*2,2)==1,"Bad AR attributes");
                l.reads.push_back({ar,0,random_transport?unsigned(rng()%23):0});++read_requests;
            }
            if(l.rvalid&&((d.axi_rready>>lane)&1)){
                check(!l.reads.empty(),"Read response has no request");l.rvalid=false;++rbeats;
                if(++l.reads.front().beat==l.reads.front().address.words)l.reads.pop_front();
            }
            if(awvalid&&awready){
                check(!l.write&&!l.bvalid,"Overlapping write bursts");
                check((aw.value&31)==0&&(aw.value&4095)+aw.words*32<=4096,"AW burst crossed alignment/boundary");
                check(bits(d.axi_awid,lane*6,6)==0&&bits(d.axi_awsize,lane*3,3)==5&&bits(d.axi_awburst,lane*2,2)==1,"Bad AW attributes");
                logical(aw.value,lane);l.write=aw;++write_requests;
            }
            Word word{};for(unsigned i=0;i<8;++i)word[i]=d.axi_wdata[lane*8+i];bool last=(d.axi_wlast>>lane)&1;
            if(l.held_w){check(wvalid&&word==*l.held_w&&last==l.held_wlast,"W changed before acceptance");++held_data_checks;}
            if(wvalid&&!wready){l.held_w=word;l.held_wlast=last;}else l.held_w.reset();
            if(wvalid&&wready){
                check(!l.bvalid&&l.words.size()<16&&d.axi_wstrb[lane]==0xffffffffu,"Unexpected/partial AXI write");
                l.words.push_back(word);l.lasts.push_back(last);++wbeats;
            }
            if(l.write&&!l.visible&&l.words.size()==l.write->words){
                uint64_t expected=lane<8?payload_address:manifest_address;unsigned size=lane<8?65536:512;
                auto& mem=memory[expected];if(mem.empty())mem.assign(size,0xcd);check(mem.size()==size,"Invalid memory allocation");
                for(unsigned b=0;b<l.words.size();++b){
                    check(l.lasts[b]==(b+1==l.write->words),"AXI WLAST differs");uint64_t a=logical(l.write->value+b*32,lane);
                    check(a>=expected&&a+32<=expected+size,"Writer escaped fixed current K/V page/manifest");
                    for(unsigned i=0;i<32;++i)mem[size_t(a-expected)+i]=uint8_t(l.words[b][i/4]>>(8*(i%4)));stored_bytes+=32;
                }
                l.visible=true;l.delay=random_transport?unsigned(rng()%41)+1:1;
            }
            if(l.bvalid&&((d.axi_bready>>lane)&1)){
                check(l.visible&&l.write&&l.words.size()==l.write->words,"B retired before all writes visible");
                ++bresponses;l.write.reset();l.words.clear();l.lasts.clear();l.visible=l.bvalid=false;
            }
        }
    }
};
}
