// Matching complete numerical-core tests for two SEPARATE hardware builds.
// Both retain fixed authenticated weights and the same arithmetic/token core.
// QWEN_KV_PROTECTED selects only a simulator build/test expectation. There is
// no runtime protection-bypass command in either RTL design.
// External AXI memory is behavioral; tensor/K/V references only monitor results.
#include "Vqwen_kv_variant_core.h"
#include "Vqwen_kv_variant_core___024root.h"
#include "verilated.h"
#include "sha256_reference.h"
#include "kv_page_monitor.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <random>
#include <stdexcept>
#include <string>
#include <tuple>
#include <vector>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef QWEN_KV_PROTECTED
#error Select QWEN_KV_PROTECTED at build time
#endif
static_assert(QWEN_KV_PROTECTED==0||QWEN_KV_PROTECTED==1);
static constexpr bool kKvProtected=QWEN_KV_PROTECTED!=0;
using VariantDut=Vqwen_kv_variant_core;
#if QWEN_KV_PROTECTED
#define ENGINE(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__model_machine__DOT__machine__DOT__engine__DOT__##name
#define MACHINE(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__model_machine__DOT__machine__DOT__##name
#define WRAPPER(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__model_machine__DOT__##name
#define TOP(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__##name
#define BUS(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__##name
#else
#define ENGINE(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__model_machine__DOT__machine__DOT__engine__DOT__##name
#define MACHINE(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__model_machine__DOT__machine__DOT__##name
#define WRAPPER(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__model_machine__DOT__##name
#define TOP(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__verified__DOT__##name
#define BUS(name) d.rootp->qwen_hbm_cdc_verified_machine__DOT__##name
#endif
namespace fs=std::filesystem;
static void need(bool condition,const std::string& message) { if(!condition) throw std::runtime_error(message); }
#include "kv_variant_core_axi_fixture.h"
struct Event { unsigned bank;std::vector<uint16_t> values; };
using EventKey=std::tuple<unsigned,unsigned,unsigned>;
struct Step { unsigned input=0,next=0; };
struct Response { unsigned status,token; };

using Bytes=std::vector<uint8_t>;using Digest=std::array<uint8_t,32>;
static Bytes unhex(const std::string& s){Bytes b;for(size_t i=0;i<s.size();i+=2)b.push_back(uint8_t(std::stoul(s.substr(i,2),nullptr,16)));return b;}
static uint32_t le32(const uint8_t* p){return uint32_t(p[0])|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24;}
static Bytes manifest(uint64_t epoch,unsigned layer,unsigned group,unsigned count,const Bytes& page){
    Bytes result,tag=unhex("250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3");
    for(unsigned n=0;n<16;++n){Bytes msg{0x20};msg.insert(msg.end(),tag.begin(),tag.end());
        for(unsigned i=0;i<8;++i)msg.push_back(uint8_t(epoch>>(8*i)));
        for(unsigned v:{layer,group&255,group>>8,n,count,0u,0u})msg.push_back(uint8_t(v));
        msg.insert(msg.end(),page.begin()+n*4096,page.begin()+(n+1)*4096);auto h=reference_sha256::hash(msg);result.insert(result.end(),h.begin(),h.end());
    }return result;
}

class Bench {
public:
    VariantDut d;
    std::mt19937_64 model_rng{0x25759b},kv_rng{0x4b56abcd};
    bool random_transport=true;
    uint64_t cycles=0,operations=0,boundaries=0,values_checked=0,model_reads=0,model_payload_bytes=0;
    uint64_t raw_pages=0,raw_beats=0,raw_drain_checks=0,kv_writes=0,kv_key_reads=0,kv_value_beats=0;
    uint64_t kv_commits=0,kv_update_requests=0,kv_read_requests=0,kv_transport_beats=0,kv_drain_checks=0;
    std::array<uint64_t,24> operation_cycles{};
    std::map<EventKey,std::vector<Event>> events;
    std::array<Step,18> steps;
    std::array<std::vector<uint16_t>,10> shadow;
    // Reference monitors only: never drive an input to the numerical engine.
    std::array<std::array<std::array<uint16_t,2048>,18>,28> cache{};
    std::array<std::array<bool,18>,28> committed{};
    uint64_t boundary15_commits=0,boundary16_commits=0,boundary17_commits=0;
    // External memory contains ONLY bytes written by the actual RTL writer.
    // CLEAR/reset intentionally do not erase external memory.
    std::map<uint64_t,Bytes> memory;
    ModelBusView model_bus{d};
    ModelAxiFixture model_axi{model_bus,model_rng};
    KvBusView kv_bus{d};
    kv_axi::Fixture<KvBusView> kv_axi_memory{kv_bus,kv_rng,memory};
    Bytes before_update;
    unsigned issued_nodes=0;
    unsigned kv_hold_mode=0,kv_hold_remaining=0;
    bool kv_hold_started=false;
    uint64_t epoch=0;
    bool clear_seen=false;
    std::vector<Response> responses;
    const uint8_t* image=nullptr;
    size_t image_size=0;
    int image_fd=-1;
    bool w_active=false,accept_core_errors=false;
    unsigned w_layer=0,w_position=0,w_count=0;
    unsigned inject_mode=0,kv_inject_mode=0,injected_faults=0,core_errors=0,clears=0,midstep_clears=0,midstep_resets=0;
    std::optional<unsigned> held_header;
    uint64_t response_watchdog=250000000;
    uint64_t last_activity=0,last_activity_cycle=0;
    unsigned clock_variant=0,core_half=2,memory_half=3,phase=0,last_opcode=0;
    uint64_t simulation_time=0,next_core_edge=2,next_memory_edge=3,memory_cycles=0,clear_ack_checks=0;
    Bench(const fs::path& image_path,const fs::path& capture,const fs::path& jobs,unsigned variant,bool random):random_transport(random),clock_variant(variant) {
        model_axi.random_transport=random;kv_axi_memory.random_transport=random;
        // Variant 6 has the proposed 125 MHz core / 450 MHz memory ratio.
        // It establishes no physical frequency or timing result.
        const std::array<std::array<unsigned,3>,10> clocks{{{{2,3,0}},{{3,2,1}},{{5,7,2}},{{7,5,3}},{{5,4,0}},{{3,3,1}},{{18,5,0}},{{8,1,0}},{{5,4,1}},{{8,4,1}}}};
        need(variant<clocks.size(),"Unknown clock variant");core_half=clocks[variant][0];memory_half=clocks[variant][1];phase=clocks[variant][2];
        next_core_edge=core_half;next_memory_edge=memory_half-phase;
        image_fd=open(image_path.c_str(),O_RDONLY);need(image_fd>=0,"Cannot open fixed model image");
        struct stat st{};need(fstat(image_fd,&st)==0,"Cannot stat image");image_size=size_t(st.st_size);
        need(image_size==2354380800ULL,"Unexpected image size");
        void* p=mmap(nullptr,image_size,PROT_READ,MAP_PRIVATE,image_fd,0);
        need(p!=MAP_FAILED,"Cannot map image");image=static_cast<const uint8_t*>(p);
        model_axi.image=image;model_axi.size=image_size;
        for(unsigned bank=0;bank<10;++bank) shadow[bank].resize(bank==9?151936:bank>=7?6144:(bank==3||bank==4)?1024:2048);
        std::ifstream in(jobs);need(bool(in),"Cannot open core jobs");std::string kind;
        while(in>>kind) {
            if(kind=="STEP") {unsigned pos,input,next;in>>pos>>input>>next;need(pos<18,"Invalid step");steps[pos]={input,next};}
            else if(kind=="EVENT") {
                unsigned pos,code,layer,bank,count;std::string file;in>>pos>>code>>layer>>bank>>count>>file;
                need(bool(in)&&pos<18&&bank<10&&count==shadow[bank].size(),"Invalid tensor event geometry");
                Event e{bank,std::vector<uint16_t>(count)};
                std::ifstream data(capture/file,std::ios::binary);need(bool(data),"Missing tensor capture");
                data.read(reinterpret_cast<char*>(e.values.data()),count*2);need(bool(data),"Short tensor capture");
                events[{pos,code,layer}].push_back(std::move(e));
            } else throw std::runtime_error("Unknown job line");
        }
        need(events.size()==18*479,"Incomplete full-model oracle");
        d.core_clk=d.memory_clk=0;d.rst_n=0;d.model_ready=1;d.cmd_valid=0;d.cmd_opcode=0;d.cmd_token=0;d.response_ready=1;

    }
    ~Bench() {if(image)munmap(const_cast<uint8_t*>(image),image_size);if(image_fd>=0)close(image_fd);}
    unsigned code() const {return ENGINE(code);}
    unsigned layer() const {return ENGINE(layer);}
    unsigned position() const {return ENGINE(position);}

    void check_operation() {
        unsigned c=code(),l=layer(),pos=position();auto found=events.find({pos,c,l});
        if(found!=events.end()) for(const Event& e:found->second) {
            const auto& actual=shadow[e.bank];
            for(unsigned i=0;i<e.values.size();++i) if(actual[i]!=e.values[i]) {
                std::cerr<<"Mismatch position="<<pos<<" layer="<<l<<" operation="<<c<<" bank="<<e.bank
                         <<" index="<<i<<" actual=0x"<<std::hex<<actual[i]<<" expected=0x"<<e.values[i]<<std::dec<<'\n';
                throw std::runtime_error("Verified-model core tensor mismatch");
            }
            ++boundaries;values_checked+=e.values.size();
        } else need(c==8||c==10||c==11||c==23,"No oracle for completed operation");
        ++operations;
        if(c==20)std::cout<<"PASS layer position="<<pos<<" layer="<<l<<" cycles="<<cycles<<std::endl;
    }


    static uint64_t page_address(unsigned l,unsigned p){return (1ULL<<32)+(uint64_t(l)*2048+p/16)*65536;}
    static uint64_t manifest_address(unsigned l,unsigned p){return (1ULL<<33)+(uint64_t(l)*2048+p/16)*512;}
    const uint8_t* memory_range(uint64_t address,unsigned count) {
        auto it=memory.upper_bound(address);need(it!=memory.begin(),"Read of unwritten private memory");--it;
        need(address-it->first+count<=it->second.size(),"Private read crosses unwritten memory");
        return it->second.data()+size_t(address-it->first);
    }
    void check_committed_page() {
        need(w_active&&w_count==2048&&!kv_axi_memory.pending(),"Premature K/V completion");
        unsigned first=kKvProtected?w_position/16*16:w_position;
        for(unsigned p=first;p<w_position;++p)need(committed[w_layer][p],"Updated page lacks committed prefix");
        Bytes expected=expected_kv_page(w_position,kKvProtected,before_update,
            [&](unsigned p,unsigned i){return cache[w_layer][p][i];});
        need(memory.at(page_address(w_layer,w_position))==expected,"Writer altered K/V or untouched slots");
        if constexpr(kKvProtected) {
            need(memory.at(manifest_address(w_layer,w_position))==manifest(epoch,w_layer,w_position/16,w_position%16+1,expected),
                "Protected writer manifest differs from independent SHA/epoch");
        } else {
            need(issued_nodes==0xffff,"Baseline did not write exactly sixteen head vectors");
            need(memory.count(manifest_address(w_layer,w_position))==0,"Baseline wrote a digest list");
        }
        committed[w_layer][w_position]=true;w_active=false;++kv_commits;
        boundary15_commits+=w_position==15;boundary16_commits+=w_position==16;boundary17_commits+=w_position==17;
    }
    bool tick() {
        // Event-driven clock scheduling: evaluate real rising/falling edges,
        // not every unit of otherwise idle simulation time. Signals are driven
        // and scored only in their owning domain. Coincident edges sample the
        // same pre-edge state.
        for(;;){
            d.cmd_clear_valid=d.cmd_valid && d.cmd_opcode==3; d.eval();
            uint64_t when=std::min(next_core_edge,next_memory_edge);
            bool core_edge=when==next_core_edge,memory_edge=when==next_memory_edge;
            bool core_rise=core_edge&&!d.core_clk,memory_rise=memory_edge&&!d.memory_clk;
            const bool raw_abort=BUS(raw_model_abort),kv_abort=TOP(kv_abort);
            if(!d.rst_n){
                for(auto& l:model_axi.lanes)l=ModelAxiFixture::Lane{};
                for(auto& l:kv_axi_memory.lanes)l=kv_axi::Lane{};
            }
            if(core_rise){
                if(!BUS(core_reset_n)){epoch=0;clear_seen=false;kv_hold_mode=kv_hold_remaining=0;kv_hold_started=false;}
                else if(kv_abort){if(!clear_seen)++epoch;clear_seen=true;}
                else clear_seen=false;
                if(kv_abort||!BUS(core_reset_n)){w_active=false;for(auto& valid:committed)valid.fill(false);}
                if(kv_hold_mode&&kv_abort&&!kv_hold_started){kv_hold_started=true;kv_hold_remaining=37;}
            }
            bool hold=kv_hold_mode&&(!kv_hold_started||kv_hold_remaining);
            kv_axi_memory.hold_b=hold&&kv_hold_mode==1;
            kv_axi_memory.hold_read_data=hold&&kv_hold_mode==2;
            if(memory_rise){
                if(inject_mode){model_axi.inject=inject_mode;inject_mode=0;}
                if(kv_inject_mode==1){kv_axi_memory.read_fault_region=1;kv_inject_mode=0;}
                if(kv_inject_mode==2){kv_axi_memory.write_fault_region=1;kv_inject_mode=0;}
                model_axi.drive();kv_axi_memory.drive();
                injected_faults=unsigned(model_axi.faults+kv_axi_memory.bus_faults);
                if constexpr(!kKvProtected)
                    need(((d.kv_axi_arvalid|d.kv_axi_awvalid|d.kv_axi_wvalid)&0xff00)==0,
                         "Baseline accessed manifest channels");
                d.cmd_clear_valid=d.cmd_valid && d.cmd_opcode==3; d.eval();

            }
            d.cmd_clear_valid=d.cmd_valid && d.cmd_opcode==3; d.eval();
            bool command_taken=false;
            if(core_rise){
                command_taken=d.cmd_valid&&d.cmd_ready;
                if(command_taken)last_opcode=d.cmd_opcode;
                if(d.response_valid&&d.response_ready){
                    if(last_opcode==3&&d.response_status==0){
                        need(!model_axi.pending()&&!kv_axi_memory.pending(),"Public CLEAR acknowledged before actual AXI drainage");
                        ++clear_ack_checks;
                    }
                    responses.push_back({d.response_status,d.response_token});
                }
                if(held_header&&!raw_abort)need(BUS(raw_model_request_valid)&&BUS(raw_model_page)==*held_header,"Raw model header changed under backpressure");
                held_header=BUS(raw_model_request_valid)&&!BUS(raw_model_request_ready)?std::optional<unsigned>(BUS(raw_model_page)):std::nullopt;
                if(raw_abort&&model_axi.pending()){need(!BUS(raw_model_quiescent),"Premature model AXI drain acknowledgement");++raw_drain_checks;}
                if(BUS(raw_model_request_valid)&&BUS(raw_model_request_ready)){need(BUS(raw_model_page)<35925,"Model page outside fixed image");++raw_pages;}
                if(BUS(raw_model_data_valid)&&BUS(raw_model_data_ready))++raw_beats;
                if(BUS(kv_update_request_valid)&&BUS(kv_update_request_ready)){
                    auto address=BUS(kv_update_address);auto n=BUS(kv_update_bytes);bool write=BUS(kv_update_request_write);
                    need(w_active,"K/V transaction outside active numerical update");
                    if constexpr(kKvProtected) {
                        need((n==65536&&address==page_address(w_layer,w_position))
                            ||(write&&n==512&&address==manifest_address(w_layer,w_position)),
                            "Protected writer escaped fixed numerical K/V address");
                    } else {
                        uint64_t base=page_address(w_layer,w_position),offset=address-base;
                        unsigned node=unsigned(offset/4096);
                        need(write&&n==256&&address>=base&&node<16
                            &&offset%4096==(w_position%16)*256,"Baseline writer escaped fixed head-vector slot");
                        need(!(issued_nodes&(1u<<node)),"Duplicate baseline vector write");
                        issued_nodes|=1u<<node;
                    }
                    ++kv_update_requests;
                }
                if(BUS(kv_read_request_valid)&&BUS(kv_read_request_ready))++kv_read_requests;
                if(BUS(kv_update_read_valid)&&BUS(kv_update_read_ready))++kv_transport_beats;
                if(BUS(kv_update_write_valid)&&BUS(kv_update_write_ready))++kv_transport_beats;
                if(BUS(kv_read_data_valid)&&BUS(kv_read_data_ready))++kv_transport_beats;
                if(kv_abort&&kv_hold_remaining&&kv_axi_memory.pending()){
                    // Each crossing owns its own fence. The unrelated idle owner can
                    // be quiescent; the cancelled active owner and session cannot reopen.
                    need(!TOP(kv_write_start_ready)&&(kv_hold_mode==1 ? !BUS(kv_update_quiescent) : !BUS(kv_read_quiescent)),
                        "K/V active owner reopened before held AXI traffic drained");
                    ++kv_drain_checks;
                }
                if(WRAPPER(model_request_valid)&&WRAPPER(model_request_ready)) {
                    need(WRAPPER(model_bytes)>0&&uint64_t(WRAPPER(model_address))+WRAPPER(model_bytes)<=image_size,"Private model request outside image");
                    ++model_reads;model_payload_bytes+=WRAPPER(model_bytes);
                }
                if(TOP(kv_write_start_valid)&&TOP(kv_write_start_ready)) {
                    need(!w_active&&!kv_abort&&!kv_axi_memory.pending(),"K/V writer accepted before reader drain");
                    w_layer=TOP(kv_write_layer);w_position=TOP(kv_write_position);w_count=0;w_active=true;issued_nodes=0;
                    auto previous=memory.find(page_address(w_layer,w_position));
                    before_update=previous==memory.end()?Bytes(65536,0xcd):previous->second;
                    need(w_layer<28&&w_position<18&&!committed[w_layer][w_position],"Invalid K/V destination");
                    kv_axi_memory.payload_address=page_address(w_layer,w_position);kv_axi_memory.manifest_address=manifest_address(w_layer,w_position);
                }
                if(TOP(kv_write_valid)&&TOP(kv_write_ready)) {
                    need(w_active&&TOP(kv_write_value)==w_count/1024&&TOP(kv_write_index)==w_count%1024,"K/V write order changed");
                    cache[w_layer][w_position][w_count++]=TOP(kv_write_data);++kv_writes;
                }
                if(TOP(kv_write_done_valid)&&TOP(kv_write_done_ready))check_committed_page();
                if(TOP(key_valid)&&TOP(key_ready)) {
                    unsigned l=TOP(attention_memory_layer),h=TOP(attention_memory_head),p=TOP(key_position);
                    need(l<28&&h<8&&p<18&&committed[l][p],"Private reader exposed uncommitted K");
                    for(unsigned i=0;i<128;++i)need(uint16_t(TOP(keys)[i/2]>>(16*(i%2)))==cache[l][p][h*128+i],"Private reader altered K");
                    ++kv_key_reads;
                }
                if(TOP(value_valid)&&TOP(value_ready)) {
                    unsigned l=TOP(attention_memory_layer),h=TOP(attention_memory_head),p=TOP(value_position),g=TOP(value_group);
                    need(l<28&&h<8&&p<18&&g<2&&committed[l][p],"Private reader exposed uncommitted V");
                    for(unsigned i=0;i<64;++i)need(uint16_t(TOP(values)[i/2]>>(16*(i%2)))==cache[l][p][1024+h*128+g*64+i],"Private reader altered V");
                    ++kv_value_beats;
                }

                if(ENGINE(tensor_write)) {
                    unsigned bank=ENGINE(tensor_write_bank),index=ENGINE(tensor_write_index);
                    need(bank<9&&index<shadow[bank].size(),"Private tensor write outside fixed bank");
                    shadow[bank][index]=ENGINE(tensor_write_data);
                }
                if(code()==22&&ENGINE(p_result_valid)&&!kv_abort) {
                    unsigned index=ENGINE(p_result_index);need(index<151936,"Head row outside vocabulary");shadow[9][index]=ENGINE(p_result);
                }
                if(ENGINE(state)>=2&&code()<24)++operation_cycles[code()];
                if(MACHINE(core_done)) {
                    if(MACHINE(core_error)){need(accept_core_errors,"Numerical core reported an error");++core_errors;}
                    else check_operation();
                }

            }
            if(memory_rise){model_axi.consume();kv_axi_memory.consume();++memory_cycles;}
            if(core_edge){d.core_clk=!d.core_clk;next_core_edge+=core_half;}
            if(memory_edge){d.memory_clk=!d.memory_clk;next_memory_edge+=memory_half;}
            d.cmd_clear_valid=d.cmd_valid && d.cmd_opcode==3; d.eval();simulation_time=when;
            if(core_rise){
                ++cycles;
                if(kv_hold_started&&kv_hold_remaining)--kv_hold_remaining;
                uint64_t activity=operations+model_reads+raw_beats+kv_writes+kv_key_reads+kv_value_beats+kv_transport_beats;
                if(activity!=last_activity||!d.busy){last_activity=activity;last_activity_cycle=cycles;}
                need(cycles-last_activity_cycle<1000000,"No integration activity for one million clocks at state "+std::to_string(ENGINE(state))+" op "+std::to_string(code()));
                if(cycles%1000000==0)std::cout<<"PROGRESS cycles="<<cycles<<" state="<<unsigned(ENGINE(state))
                    <<" op="<<code()<<" layer="<<layer()<<" raw_pages="<<raw_pages<<" kv_commits="<<kv_commits
                    <<" operations="<<operations<<std::endl;

                return command_taken;
            }
        }
    }
    void initialize() {
        for(unsigned i=0;i<4;++i)tick();d.rst_n=1;
        for(unsigned i=0;i<1000&&!d.cmd_ready;++i)tick();need(d.cmd_ready,"Reset did not drain");
    }
    void command(unsigned opcode,unsigned token=0) {
        d.cmd_opcode=opcode;d.cmd_token=token;d.cmd_valid=1;bool accepted=false;
        for(unsigned i=0;i<10000;++i)if(tick()){accepted=true;break;}
        d.cmd_valid=0;need(accepted,"Command was not accepted");if(opcode==3)++clears;
        std::cout<<"COMMAND accepted opcode="<<opcode<<" token="<<token<<std::endl;
    }
    Response response() {
        const uint64_t deadline=cycles+response_watchdog;
        while(responses.empty()) {
            need(cycles<deadline,"Token watchdog at state "+std::to_string(ENGINE(state))+" op "+std::to_string(code())+" layer "+std::to_string(layer()));tick();
        }
        Response r=responses.front();responses.erase(responses.begin());return r;
    }
    void expect_response(unsigned status,unsigned token=0) {
        auto r=response();need(r.status==status&&r.token==token,"Public token/status differs: "+std::to_string(r.status)+"/"+std::to_string(r.token));
    }
};


int main(int argc,char** argv) {
    try {
        Verilated::commandArgs(argc,argv);
        need(argc==4,"Usage: long18-test MODEL_IMAGE ORACLE_DIR JOBS");
        auto abc=reference_sha256::hash(Bytes{'a','b','c'});
        need(Bytes(abc.begin(),abc.end())==unhex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),"Scalar SHA self-test failed");
        // Fixed production 100:125 core/memory ratio; not physical timing proof.
        Bench b(argv[1],argv[2],argv[3],4,false);
        b.initialize(); b.command(3); b.expect_response(0);
        b.command(1,b.steps[0].input); b.expect_response(0);
        const uint64_t begin=b.cycles;
        for(unsigned p=0;p<18;++p) {
            const uint64_t start=b.cycles;
            b.command(2); b.expect_response(0,b.steps[p].next);
            std::cout<<"PASS token position="<<p<<" token="<<b.steps[p].next
                     <<" step_cycles="<<b.cycles-start<<std::endl;
        }
        need(b.operations==10152 && b.responses.empty(),"Wrong complete-token stopping boundary");
        need(b.boundaries==9126 && b.values_checked==27581184 && b.kv_commits==504,"Incomplete numerical coverage");
        need(b.boundary15_commits==28 && b.boundary16_commits==28 && b.boundary17_commits==28,"Missing page-boundary publications");
        const uint64_t elapsed=b.cycles-begin;
        b.command(3); b.expect_response(0);
        need(b.clear_ack_checks==2 && b.clears==2,"Application CLEAR did not drain actual AXI traffic");
        std::cout<<"PASS working_qwen_profile layers=28 core_half="<<b.core_half
                 <<" memory_half="<<b.memory_half<<" phase="<<b.phase<<" cycles="<<elapsed
                 <<" operations="<<b.operations<<" tensor_boundaries="<<b.boundaries
                 <<" bf16_values="<<b.values_checked<<" raw_pages="<<b.raw_pages
                 <<" raw_beats="<<b.raw_beats<<" kv_commits="<<b.kv_commits
                 <<" clear_ack_checks="<<b.clear_ack_checks
                 <<" boundary15_commits="<<b.boundary15_commits
                 <<" boundary16_commits="<<b.boundary16_commits
                 <<" boundary17_commits="<<b.boundary17_commits
                 <<" tokens_generated=18 random_transport=0"<<std::endl;
        return 0;
    } catch(const std::exception& e) {
        std::cerr<<"FAIL portable_qwen_long18: "<<e.what()<<std::endl; return 1;
    }
}
