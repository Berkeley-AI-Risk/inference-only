// Shared behavioral AXI model for both compile-time K/V variants. The optional
// no-stall mode is a deterministic comparison fixture, NOT a physical HBM model.
// Bus-only simulation fixtures for the complete AXI-backed token machine.
// The reference values are monitors. They never replace the numerical core,
// K/V writer, verification engines, caches, or actual AXI adapters.
#pragma once
#include "kv_hbm_axi_fixture.h"
struct ModelBusView {
    VariantDut& d;
    decltype(d.rst_n)& rst_n=d.rst_n;
    decltype(d.model_axi_araddr)& axi_araddr=d.model_axi_araddr;
    decltype(d.model_axi_arid)& axi_arid=d.model_axi_arid;
    decltype(d.model_axi_arlen)& axi_arlen=d.model_axi_arlen;
    decltype(d.model_axi_arsize)& axi_arsize=d.model_axi_arsize;
    decltype(d.model_axi_arburst)& axi_arburst=d.model_axi_arburst;
    decltype(d.model_axi_arvalid)& axi_arvalid=d.model_axi_arvalid;
    decltype(d.model_axi_arready)& axi_arready=d.model_axi_arready;
    decltype(d.model_axi_rdata)& axi_rdata=d.model_axi_rdata;
    decltype(d.model_axi_rid)& axi_rid=d.model_axi_rid;
    decltype(d.model_axi_rresp)& axi_rresp=d.model_axi_rresp;
    decltype(d.model_axi_rlast)& axi_rlast=d.model_axi_rlast;
    decltype(d.model_axi_rvalid)& axi_rvalid=d.model_axi_rvalid;
    decltype(d.model_axi_rready)& axi_rready=d.model_axi_rready;
};
struct KvBusView {
    VariantDut& d;
    decltype(d.rst_n)& rst_n=d.rst_n;
    decltype(TOP(kv_write_start_valid))& write_start_valid=TOP(kv_write_start_valid);
    decltype(TOP(kv_write_start_ready))& write_start_ready=TOP(kv_write_start_ready);
    decltype(d.kv_axi_araddr)& axi_araddr=d.kv_axi_araddr;
    decltype(d.kv_axi_arid)& axi_arid=d.kv_axi_arid;
    decltype(d.kv_axi_arlen)& axi_arlen=d.kv_axi_arlen;
    decltype(d.kv_axi_arsize)& axi_arsize=d.kv_axi_arsize;
    decltype(d.kv_axi_arburst)& axi_arburst=d.kv_axi_arburst;
    decltype(d.kv_axi_arvalid)& axi_arvalid=d.kv_axi_arvalid;
    decltype(d.kv_axi_arready)& axi_arready=d.kv_axi_arready;
    decltype(d.kv_axi_rdata)& axi_rdata=d.kv_axi_rdata;
    decltype(d.kv_axi_rid)& axi_rid=d.kv_axi_rid;
    decltype(d.kv_axi_rresp)& axi_rresp=d.kv_axi_rresp;
    decltype(d.kv_axi_rlast)& axi_rlast=d.kv_axi_rlast;
    decltype(d.kv_axi_rvalid)& axi_rvalid=d.kv_axi_rvalid;
    decltype(d.kv_axi_rready)& axi_rready=d.kv_axi_rready;
    decltype(d.kv_axi_awaddr)& axi_awaddr=d.kv_axi_awaddr;
    decltype(d.kv_axi_awid)& axi_awid=d.kv_axi_awid;
    decltype(d.kv_axi_awlen)& axi_awlen=d.kv_axi_awlen;
    decltype(d.kv_axi_awsize)& axi_awsize=d.kv_axi_awsize;
    decltype(d.kv_axi_awburst)& axi_awburst=d.kv_axi_awburst;
    decltype(d.kv_axi_awvalid)& axi_awvalid=d.kv_axi_awvalid;
    decltype(d.kv_axi_awready)& axi_awready=d.kv_axi_awready;
    decltype(d.kv_axi_wdata)& axi_wdata=d.kv_axi_wdata;
    decltype(d.kv_axi_wstrb)& axi_wstrb=d.kv_axi_wstrb;
    decltype(d.kv_axi_wlast)& axi_wlast=d.kv_axi_wlast;
    decltype(d.kv_axi_wvalid)& axi_wvalid=d.kv_axi_wvalid;
    decltype(d.kv_axi_wready)& axi_wready=d.kv_axi_wready;
    decltype(d.kv_axi_bid)& axi_bid=d.kv_axi_bid;
    decltype(d.kv_axi_bresp)& axi_bresp=d.kv_axi_bresp;
    decltype(d.kv_axi_bvalid)& axi_bvalid=d.kv_axi_bvalid;
    decltype(d.kv_axi_bready)& axi_bready=d.kv_axi_bready;
};
struct ModelAxiFixture {
    struct Burst {uint64_t address;unsigned beat=0,delay=0;};
    struct Lane {
        std::deque<Burst> queue;bool offer=false,last=false;unsigned response=0;
        std::array<uint32_t,8> data{};std::optional<uint64_t> held_address;
    };
    ModelBusView& d;std::mt19937_64& rng;std::array<Lane,8> lanes;
    const uint8_t* image=nullptr;size_t size=0;
    bool random_transport=true,hold_responses=false;unsigned inject=0;
    uint64_t requests=0,beats=0,faults=0,held_address_checks=0;
    ModelAxiFixture(ModelBusView& bus,std::mt19937_64& random):d(bus),rng(random){}
    bool pending()const{for(const auto& l:lanes)if(l.offer||!l.queue.empty()||l.held_address)return true;return false;}
    void drive(){
        if(!d.rst_n)for(auto& l:lanes)l=Lane{};
        d.axi_arready=d.axi_rvalid=d.axi_rlast=d.axi_rresp=0;d.axi_rid=0;
        for(unsigned lane=0;lane<8;++lane){
            auto& l=lanes[lane];if(!random_transport||rng()%4)d.axi_arready|=1u<<lane;
            if(!l.offer&&!l.queue.empty()&&!hold_responses){
                auto& b=l.queue.front();if(b.delay)--b.delay;
                else if(!random_transport||rng()%3){
                    uint64_t local=(b.address&((1ULL<<29)-1))+b.beat*32,logical=(local/32)*256+lane*32;
                    need(logical+32<=size,"Model AXI read outside selected image");
                    std::memcpy(l.data.data(),image+logical,32);l.last=b.beat==15;l.response=0;l.offer=true;
                    if(inject){if(inject==1)l.response=2;else if(inject==2)l.data[3]^=0x100;
                        else throw std::runtime_error("Unknown model AXI fault");inject=0;++faults;}
                }
            }
            if(l.offer){d.axi_rvalid|=1u<<lane;if(l.last)d.axi_rlast|=1u<<lane;d.axi_rresp|=l.response<<(lane*2);}
            for(unsigned i=0;i<8;++i)d.axi_rdata[lane*8+i]=l.data[i];
        }
    }
    void consume(){
        for(unsigned lane=0;lane<8;++lane){
            auto& l=lanes[lane];bool av=(d.axi_arvalid>>lane)&1,ready=(d.axi_arready>>lane)&1;
            uint64_t address=kv_axi::bits(d.axi_araddr,lane*34,34);
            if(l.held_address){need(av&&address==*l.held_address,"Model AR changed or withdrawn before acceptance");++held_address_checks;}
            l.held_address=av&&!ready?std::optional<uint64_t>(address):std::nullopt;
            if(av&&ready){
                need(address>>29==lane&&(address&511)==0,"Invalid model AXI channel/alignment");
                need(kv_axi::bits(d.axi_arid,lane*6,6)==0&&kv_axi::bits(d.axi_arlen,lane*4,4)==15
                    &&kv_axi::bits(d.axi_arsize,lane*3,3)==5&&kv_axi::bits(d.axi_arburst,lane*2,2)==1,"Invalid model AXI attributes");
                uint64_t end=(((address&((1ULL<<29)-1))/32)+16)*256;
                need(end<=size,"Model AXI burst outside selected image");
                l.queue.push_back({address,0,random_transport?unsigned(rng()%23):0});++requests;
            }
            if(l.offer&&((d.axi_rready>>lane)&1)){
                need(!l.queue.empty(),"Model R without request");l.offer=false;++beats;
                if(++l.queue.front().beat==16)l.queue.pop_front();
            }
        }
    }
};
