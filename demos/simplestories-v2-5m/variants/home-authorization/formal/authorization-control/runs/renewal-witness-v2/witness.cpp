#include "Vhome_boot_gate.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>

struct Campaign {
    Vhome_boot_gate d;
    uint64_t cycles=0;
    unsigned grants=0;
    std::vector<unsigned> request;
    void require(bool p,const char* message) { if(!p) throw std::runtime_error(message); }
    void tick() {
        d.clk=0;d.eval();
        if(d.reset_n && d.request_valid_o && d.request_ready_i) request.push_back(d.request_byte_o);
        if(d.new_lease_o) ++grants;
        d.clk=1;d.eval();d.clk=0;d.eval();++cycles;
        if(cycles%25000000==0) std::cout<<"progress cycles="<<cycles<<" grants="<<grants<<std::endl;
        require(cycles<500000000,"production-timer witness exceeded its expected cycle bound");
    }
    void start() {
        d.reset_n=0;d.clk=0;d.nonce_valid_i=0;d.nonce_fault_i=0;d.model_fault_i=0;
        d.admitted_root_valid_i=1;d.request_ready_i=1;d.grant_valid_i=0;d.grant_last_i=0;
        d.grant_byte_i=0;d.shared_busy_i=0;d.shared_done_i=0;d.shared_valid_i=0;d.shared_fault_i=0;
        d.shared_signature_address_i=0;d.shared_message_address_i=0;
        for(unsigned i=0;i<8;++i) {d.nonce_i[i]=0;d.admitted_root_i[i]=0;}
        d.nonce_i[0]=0xfeedbeef;d.admitted_root_i[0]=0x12345678;
        tick();tick();tick();d.reset_n=1;
    }
    void challenge(uint32_t value) {
        request.clear();d.nonce_i[0]=value;d.nonce_valid_i=1;tick();d.nonce_valid_i=0;
        while(!d.grant_ready_o) {require(!d.failed_o,"challenge failed before receive");tick();}
        require(request.size()==128,"canonical request length differs");
        require(request[0]==0x53 && request[1]==0x41,"request domain differs");
        for(unsigned i=0;i<4;++i)
            require(request[60+i]==((value>>(24-8*i))&255),"request nonce differs");
    }
    void authorize() {
        const unsigned before=grants;
        for(unsigned i=0;i<1420;++i) {
            d.grant_valid_i=1;d.grant_last_i=(i==1419);
            d.grant_byte_i=i<128?request[i]:0x5c;tick();
        }
        d.grant_valid_i=0;d.grant_last_i=0;
        while(!d.shared_start_o) {require(!d.failed_o,"grant failed before start");tick();}
        tick();d.shared_done_i=1;d.shared_valid_i=1;tick();
        require(grants==before+1 && d.inference_enabled_o,"complete grant did not activate permission");
        // Keep the old verdict high deliberately. Without another complete
        // challenge/frame/start it must never create a new controller grant.
    }
    void run() {
        start();challenge(0xfeedbeef);authorize();
        while(!d.nonce_request_o) {require(d.inference_enabled_o,"initial lease failed before renewal");tick();}
        const uint64_t before=d.lease_cycles_remaining_o;
        require(before>100000000 && before<150000000,"renewal did not begin at the production threshold");
        for(unsigned i=0;i<101;++i) tick();
        require(d.lease_cycles_remaining_o+101==before,"waiting for a nonce refreshed the old lease");
        challenge(0xfeedbef0);authorize();
        require(d.lease_cycles_remaining_o>before,"successful renewal did not extend permission");
        require(grants==2,"challenge created more than one grant");
        while(!d.nonce_request_o) {require(d.inference_enabled_o,"renewed lease failed before next request");tick();}
        // Home base withholds the next nonce/grant. The old successful verdict
        // remains present at the abstract private seam throughout the stall.
        bool guard_seen=false;
        while(d.inference_enabled_o) {
            if(d.lease_cycles_remaining_o<=20000) {guard_seen=true;require(!d.publication_allowed_o,"publication runway guard late");}
            require(grants==2,"stale verdict reauthorized stalled renewal");tick();
        }
        require(d.failed_o && guard_seen,"withheld renewal did not expire closed");
        d.grant_valid_i=1;d.grant_last_i=1;d.grant_byte_i=0;
        for(unsigned i=0;i<32;++i) {tick();require(d.failed_o && !d.inference_enabled_o && !d.new_lease_o,"late grant revived expired permission");}
        std::cout<<"WITNESS PASS cycles="<<cycles<<" grants="<<grants
                 <<" actual_timer_values=1 successful_renewal=1 stalled_nonce_consumes_old_budget=1 stale_verdict_does_not_renew=1 expiry_sticky=1 abstract_crypto=1"<<std::endl;
    }
};
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    try {Campaign c;c.run();return 0;}
    catch(const std::exception&e) {std::cerr<<"WITNESS FAIL "<<e.what()<<std::endl;return 1;}
}
