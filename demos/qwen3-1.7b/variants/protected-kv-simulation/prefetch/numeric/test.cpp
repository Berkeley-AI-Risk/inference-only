#include "Voperand_test.h"
#include "verilated.h"
#include "sha256_reference.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>
#include "reference.hpp"
#include "numeric_fixture.hpp"

static constexpr uint64_t PAYLOAD=1ULL<<32,DIGEST=1ULL<<33;
static unsigned profile=0,workload=0;
static uint16_t input_word(unsigned mode,unsigned p,unsigned role,unsigned head,unsigned c){return fixture_input[((((mode*33+p)*2+role)*8+head)*128+c)];}
static uint16_t query_word(unsigned head,unsigned q,unsigned c){return fixture_query[(head*2+q)*128+c];}
static uint16_t output_word(unsigned mode,unsigned n,unsigned head,unsigned q,unsigned c){unsigned ci=n==2?0:n==16?1:n==17?2:3;return fixture_expected[((((mode*4+ci)*2+head)*2+q)*128+c)];}
template<class W>static uint16_t scalar(const W& w,unsigned i){return (w[i/2]>>(16*(i%2)))&65535;}
static uint64_t page_address(unsigned layer,unsigned group){return PAYLOAD+(uint64_t(layer)*2048+group)*65536;}
static uint64_t manifest_address(unsigned layer,unsigned group){return DIGEST+(uint64_t(layer)*2048+group)*512;}
static Digest root_hash(uint64_t epoch,unsigned layer,unsigned group,unsigned count,const Bytes& m){
    Bytes msg{0x21};auto tag=unhex("250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3");msg.insert(msg.end(),tag.begin(),tag.end());
    for(unsigned i=0;i<8;i++)msg.push_back(epoch>>(8*i));
    for(unsigned x:{layer,group&255,group>>8,16u,count,0u,0u})msg.push_back(x);
    msg.insert(msg.end(),m.begin(),m.end());return reference_sha256::hash(msg);
}
struct Tx{bool write=false,cancelled=false;uint64_t address=0,due=0;unsigned bytes=0,beat=0,node=0,group=0;Bytes snapshot;};
struct Channel{std::optional<Tx> tx;bool offered=false,last=false;std::array<uint32_t,64> data{};};
struct Stats{uint64_t read_requests=0,read_bytes=0,write_requests=0,write_bytes=0;};
struct Bench{
    Voperand_test dut;Channel update,read;std::map<uint64_t,Bytes> memory;
    uint64_t epoch=0,cycle=0,publications=0,verification_events=0,allocations=0,evictions=0;
    unsigned mode=workload==1,phase=0,head_index=0,current_head=0,current_context=0;
    bool expected_fault=false,fault_seen=false,target_leaf_rejected=false,delay_used=false,clearing=false;
    unsigned clear_stage=0;uint64_t fault_cycle=0,old_return=0,clear_cycle=0,blocked_clear_checks=0,target_uses=0;
    Stats stats;bool writing=false,last_write_start=false,last_word=false,last_write_done=false,last_start=false,last_result=false,in_sequence=false;
    uint64_t pair_start=0,pair_result=0,k_ready=0,v_ready=0,k_first=0,v_first=0,k_group1=0,v_group1=0,k_wait=0,v_wait=0;
    uint64_t sequence_start=0;std::map<unsigned,unsigned> certificates;
    Bench(){
        dut.clk=0;dut.rst_n=0;dut.session_clear=0;dut.pair_clear=1;dut.pair_start=0;dut.pair_out_ready=0;
        dut.write_start_valid=0;dut.write_valid=0;dut.write_done_ready=0;dut.fixture_write_layer=0;dut.fixture_write_position=0;dut.fixture_head=0;dut.fixture_context=2;
        tick();tick();dut.rst_n=1;for(unsigned i=0;i<10;i++)tick();
    }
    void prefix(const char* event){std::cout<<"{\"event\":\""<<event<<"\",\"cycle\":"<<cycle<<",\"profile\":"<<profile<<",\"workload\":"<<workload<<",\"phase\":"<<phase<<",\"head_index\":"<<head_index;}
    unsigned gap(uint64_t address,unsigned beat){return profile?1+unsigned(((address>>8)+beat*5)%5):1;}
    Bytes range(uint64_t address,unsigned n){auto it=memory.upper_bound(address);require(it!=memory.begin(),"Read before any written memory");--it;require(address>=it->first&&address-it->first+n<=it->second.size(),"Read outside written private range");return Bytes(it->second.begin()+size_t(address-it->first),it->second.begin()+size_t(address-it->first+n));}
    void drive(Channel& ch,bool u){
        bool abort=u?dut.update_abort:dut.read_abort;
        if(abort&&ch.tx&&!ch.tx->cancelled){ch.tx->cancelled=true;ch.offered=false;}
        if(ch.tx&&ch.tx->cancelled&&cycle>=ch.tx->due){
            if(!u){old_return=cycle;prefix("old_return_discarded");std::cout<<",\"epoch\":"<<epoch<<"}\n";}
            ch.tx.reset();ch.offered=false;}
        if(ch.tx&&!ch.tx->write&&!ch.tx->cancelled&&!ch.offered&&cycle>=ch.tx->due){
            for(unsigned i=0;i<64;i++){uint32_t v=0;for(unsigned j=0;j<4;j++)v|=uint32_t(ch.tx->snapshot[ch.tx->beat*256+i*4+j])<<(8*j);ch.data[i]=v;}
            ch.last=ch.tx->beat+1==ch.tx->bytes/256;ch.offered=true;
        }
        bool ready=!abort&&!ch.tx,valid=!abort&&ch.offered;
        bool ack=!abort&&ch.tx&&ch.tx->write&&!ch.tx->cancelled&&ch.tx->beat==ch.tx->bytes/256&&cycle>=ch.tx->due;
        if(u){dut.update_request_ready=ready;dut.update_read_valid=valid;dut.update_read_last=ch.last;dut.update_read_error=0;
            for(unsigned i=0;i<64;i++)dut.update_read_data[i]=ch.data[i];
            dut.update_write_ready=!abort&&ch.tx&&ch.tx->write&&!ch.tx->cancelled&&ch.tx->beat<ch.tx->bytes/256&&cycle>=ch.tx->due;
            dut.update_done_valid=ack;dut.update_done_error=0;dut.update_error=0;dut.update_quiescent=!ch.tx;
        }else{dut.read_request_ready=ready;dut.read_data_valid=valid;dut.read_last=ch.last;dut.read_data_error=0;dut.read_error=0;
            for(unsigned i=0;i<64;i++)dut.read_data[i]=ch.data[i];dut.read_quiescent=!ch.tx;}
    }
    void consume(Channel& ch,bool u){
        bool header=u?(dut.update_request_valid&&dut.update_request_ready):(dut.read_request_valid&&dut.read_request_ready);
        bool take=u?(dut.update_read_valid&&dut.update_read_ready):(dut.read_data_valid&&dut.read_data_ready);
        if(header){
            require(!ch.tx,"Overlapping private transactions");Tx t;t.write=u&&dut.update_request_write;t.address=u?dut.update_address:dut.read_address;t.bytes=u?dut.update_bytes:dut.read_bytes;
            require(t.bytes%256==0,"Raw beat granularity");
            if(u){require(writing,"Update outside writer operation");unsigned g=dut.fixture_write_position/16;
                require((t.bytes==65536&&t.address==page_address(dut.fixture_write_layer,g))||(t.write&&t.bytes==512&&t.address==manifest_address(dut.fixture_write_layer,g)),"Writer descriptor escaped fixed layout");}
            else{t.node=dut.observed_read_node;t.group=dut.observed_read_group;
                require(t.group*16<current_context&&t.node<16,"Read escaped committed attention prefix");
                require((t.bytes==4096&&t.address==page_address(0,t.group)+t.node*4096)||(t.bytes==512&&t.address==manifest_address(0,t.group)),"Attention descriptor/address mismatch");}
            unsigned initial=3+(profile?unsigned(((t.address>>8)+t.bytes/256)%7):0);
            if(workload==3&&!u&&!delay_used&&t.bytes==4096&&t.group==1&&t.node==(clear_stage==0?0:8)){initial=100;delay_used=true;}
            t.due=cycle+initial;
            if(t.write){auto [it,fresh]=memory.try_emplace(t.address,Bytes(t.bytes,0));require(it->second.size()==t.bytes,"Write range changed size");stats.write_requests++;stats.write_bytes+=t.bytes;}
            else{t.snapshot=range(t.address,t.bytes);stats.read_requests++;stats.read_bytes+=t.bytes;}
            prefix("request");std::cout<<",\"update\":"<<(u?"true":"false")<<",\"write\":"<<(t.write?"true":"false")<<",\"address\":"<<t.address<<",\"bytes\":"<<t.bytes<<",\"node\":"<<t.node<<",\"group\":"<<t.group<<",\"initial_delay\":"<<initial<<"}\n";
            ch.tx=std::move(t);
        }
        if(take){require(ch.tx&&!ch.tx->write&&!ch.tx->cancelled&&ch.offered,"Unowned accepted read");
            if(!u){prefix("read_beat");std::cout<<",\"address\":"<<ch.tx->address<<",\"node\":"<<ch.tx->node<<",\"group\":"<<ch.tx->group<<",\"beat\":"<<ch.tx->beat<<"}\n";}
            ch.offered=false;if(++ch.tx->beat==ch.tx->bytes/256)ch.tx.reset();else ch.tx->due=cycle+gap(ch.tx->address,ch.tx->beat);
        }
        if(u&&dut.update_write_valid&&dut.update_write_ready){require(ch.tx&&ch.tx->write,"Unowned write beat");
            auto& dst=memory.at(ch.tx->address);require(bool(dut.update_write_last)==(ch.tx->beat+1==ch.tx->bytes/256),"Writer LAST mismatch");
            for(unsigned i=0;i<256;i++)dst[ch.tx->beat*256+i]=uint8_t(dut.update_write_data[i/4]>>(8*(i%4)));
            if(++ch.tx->beat==ch.tx->bytes/256)ch.tx->due=cycle+3;else ch.tx->due=cycle+gap(ch.tx->address,ch.tx->beat);
        }
        if(u&&dut.update_done_valid&&dut.update_done_ready){require(ch.tx&&ch.tx->write&&ch.tx->beat==ch.tx->bytes/256,"Write completed before all bytes");ch.tx.reset();}
    }
    unsigned cert_key(unsigned node,unsigned group,unsigned count){return node|(group<<4)|(count<<15);}
    void operand(bool value){
        unsigned pos=value?dut.value_position:dut.key_position,half=value?dut.value_group:0;
        unsigned node=(value?8:0)+current_head,g=pos/16,count=std::min(16u,current_context-g*16);
        if(pos==16&&((workload==4&&!value)||(workload==5&&value)))target_uses++;
        require(pos<current_context&&certificates[cert_key(node,g,count)]==3,"Operand lacks its own current root/leaf passes");
        if(value){if(!v_first)v_first=cycle;if(pos==16&&!v_group1)v_group1=cycle;}else{if(!k_first)k_first=cycle;if(pos==16&&!k_group1)k_group1=cycle;}
        prefix("operand");std::cout<<",\"KV_head\":"<<current_head<<",\"context\":"<<current_context<<",\"role\":"<<(value?1:0)<<",\"position\":"<<pos<<",\"half\":"<<half<<",\"bits\":[";
        unsigned begin=value?half*64:0,n=value?64:128;
        for(unsigned c=0;c<n;c++){uint16_t actual=value?scalar(dut.values,c):scalar(dut.keys,c);require(actual==input_word(mode,pos,value,current_head,begin+c),"Consumed operand differs from independent fixture input");if(c)std::cout<<',';std::cout<<actual;}
        std::cout<<"]}\n";
    }
    void check_publication(){
        unsigned layer=dut.published_layer,pos=dut.published_position,g=pos/16,count=pos%16+1;
        require(writing&&layer==dut.fixture_write_layer&&pos==dut.fixture_write_position&&dut.published_epoch==epoch,"Publication descriptor mismatch");
        Bytes wanted(65536,0);
        for(unsigned p=g*16;p<=pos;p++)for(unsigned node=0;node<16;node++)for(unsigned c=0;c<128;c++){uint16_t x=input_word(mode,p,node/8,node%8,c);unsigned off=node*4096+(p%16)*256+2*c;wanted[off]=x;wanted[off+1]=x>>8;}
        require(memory.at(page_address(layer,g))==wanted,"Actual published page differs from accepted inputs");
        auto m=manifest(epoch,layer,g,count,wanted);require(memory.at(manifest_address(layer,g))==m,"Actual manifest differs from independent SHA");
        auto r=root_hash(epoch,layer,g,count,m);for(unsigned i=0;i<8;i++){uint32_t x=0;for(unsigned j=0;j<4;j++)x=x<<8|r[4*i+j];require(dut.published_root[7-i]==x,"Actual trusted root differs from independent typed root");}
        publications++;prefix("publication");std::cout<<",\"layer\":"<<layer<<",\"position\":"<<pos<<"}\n";
    }
    void tick(){
        require(cycle<30000000,"Finite component sequence bound");dut.clk=0;dut.eval();drive(update,true);drive(read,false);dut.eval();
        if(dut.store_error||dut.authentication_error||dut.reader_fault_event){
            require(expected_fault,"Unexpected actual fault");
            if(!fault_seen){fault_seen=true;fault_cycle=cycle;prefix("fault");std::cout<<",\"target_uses\":"<<target_uses<<",\"leaf_rejected\":"<<(target_leaf_rejected?"true":"false")<<"}\n";}
        }
        if(clearing){
            require(!dut.key_valid&&!dut.value_valid,"Operand exposed during CLEAR");
            if(read.tx){require(!dut.attention_quiescent&&!dut.store_quiescent&&!dut.write_start_ready,"CLEAR reopened before old transport drained");blocked_clear_checks++;}
            require(!dut.follow_pending,"Queued follow-up survived CLEAR");
        }
        last_write_start=dut.write_start_valid&&dut.write_start_ready;last_word=dut.write_valid&&dut.write_ready;last_write_done=dut.write_done_valid&&dut.write_done_ready;
        last_start=dut.pair_start&&dut.pair_ready;last_result=dut.pair_valid&&dut.pair_out_ready;
        if(in_sequence)require(!dut.read_abort,"Reader aborted between numerical heads");
        if(dut.root_publish)check_publication();
        if(dut.verification_event){require(dut.verification_epoch==epoch&&dut.verification_layer==0,"Verification descriptor/failure in honest sequence");
            unsigned key=cert_key(dut.verification_node,dut.verification_group,dut.verification_count);
            if(dut.verification_ok){if(dut.verification_root)certificates[key]|=1;else{require(certificates[key]&1,"Leaf pass before own root");certificates[key]|=2;}}
            else{require(expected_fault,"Unexpected failed comparison");if(dut.verification_group==1&&dut.verification_node==(workload==4?0:8)&&!dut.verification_root)target_leaf_rejected=true;}
            verification_events++;prefix("verification");std::cout<<",\"node\":"<<unsigned(dut.verification_node)<<",\"group\":"<<dut.verification_group<<",\"count\":"<<unsigned(dut.verification_count)<<",\"root\":"<<(dut.verification_root?"true":"false")<<",\"ok\":"<<(dut.verification_ok?"true":"false")<<",\"epoch\":"<<epoch<<"}\n";
        }
        if(dut.fill_event){require(certificates[cert_key(dut.fill_node,dut.fill_group,dut.fill_count)]==3,"Cache publication lacks verification");}
        if(dut.allocation_event){allocations++;if(dut.allocation_old_valid&&dut.allocation_old_tag!=dut.allocation_new_tag)evictions++;
            prefix("allocation");std::cout<<",\"slot\":"<<unsigned(dut.allocation_slot)<<",\"old_valid\":"<<(dut.allocation_old_valid?"true":"false")<<",\"old_tag\":"<<dut.allocation_old_tag<<",\"new_tag\":"<<dut.allocation_new_tag<<"}\n";
        }
        if(dut.follow_pending){prefix("follow_pending");std::cout<<",\"layer\":"<<unsigned(dut.follow_layer)<<",\"head\":"<<unsigned(dut.follow_head)<<",\"group\":"<<dut.follow_group<<"}\n";}
        if(last_start){pair_start=cycle;if(!sequence_start)sequence_start=cycle;}
        if(dut.key_ready){if(!k_ready)k_ready=cycle;if(!dut.key_valid)k_wait++;}
        if(dut.value_ready){if(!v_ready)v_ready=cycle;if(!dut.value_valid)v_wait++;}
        if(dut.key_valid&&dut.key_ready)operand(false);if(dut.value_valid&&dut.value_ready)operand(true);
        if(last_result&&dut.pair_error){require(expected_fault&&fault_seen,"Unexpected error result");prefix("error_result");std::cout<<"}\n";}
        if(last_result&&!dut.pair_error){
            pair_result=cycle;prefix("numerical_result");std::cout<<",\"KV_head\":"<<current_head<<",\"context\":"<<current_context<<",\"outputs\":[";
            for(unsigned q=0;q<2;q++){if(q)std::cout<<',';std::cout<<'[';for(unsigned c=0;c<128;c++){uint16_t actual=q?scalar(dut.result1,c):scalar(dut.result0,c);require(actual==output_word(mode,current_context,current_head,q,c),"Numerical output differs from independent tree/softmax/AV reference");if(c)std::cout<<',';std::cout<<actual;}std::cout<<']';}std::cout<<"]}\n";
        }
        consume(update,true);consume(read,false);dut.clk=1;dut.eval();cycle++;
    }
    void write(unsigned position,unsigned layer){
        writing=true;dut.fixture_write_layer=layer;dut.fixture_write_position=position;dut.write_start_valid=1;
        do{tick();}while(!last_write_start);dut.write_start_valid=0;
        for(unsigned i=0;i<2048;){dut.write_valid=1;dut.write_value=i/1024;dut.write_index=i%1024;dut.write_data=input_word(mode,position,i/1024,(i%1024)/128,i%128);tick();if(last_word)i++;}
        dut.write_valid=0;dut.write_done_ready=1;do{tick();}while(!last_write_done);dut.write_done_ready=0;writing=false;
    }
    void populate(unsigned first,unsigned end){
        dut.pair_clear=1;certificates.clear();for(unsigned pos=first;pos<end;pos++)for(unsigned layer=0;layer<28;layer++)write(pos,layer);
        prefix("population_complete");std::cout<<",\"first_position\":"<<first<<",\"end_position\":"<<end<<",\"publications\":"<<publications<<"}\n";
    }
    void sequence(unsigned context,unsigned sequence_phase){
        phase=sequence_phase;current_context=context;dut.fixture_context=context;dut.pair_clear=0;sequence_start=0;in_sequence=false;
        uint64_t first=0,last=0,evict_begin=evictions,read_begin=stats.read_bytes,request_begin=stats.read_requests;
        const unsigned heads[]={0,1,0};
        for(head_index=0;head_index<3;head_index++){
            current_head=heads[head_index];dut.fixture_head=current_head;
            for(unsigned i=0;i<64;i++){dut.query0[i]=query_word(current_head,0,2*i)|(uint32_t(query_word(current_head,0,2*i+1))<<16);dut.query1[i]=query_word(current_head,1,2*i)|(uint32_t(query_word(current_head,1,2*i+1))<<16);}
            k_ready=v_ready=k_first=v_first=k_group1=v_group1=k_wait=v_wait=0;
            while(!dut.pair_ready||!dut.attention_quiescent)tick();
            dut.pair_start=1;do{tick();}while(!last_start);dut.pair_start=0;in_sequence=true;if(!first)first=pair_start;
            uint64_t reads=stats.read_bytes,requests=stats.read_requests;dut.pair_out_ready=1;do{tick();}while(!last_result);dut.pair_out_ready=0;last=pair_result;
            prefix("pair_done");std::cout<<",\"KV_head\":"<<current_head<<",\"context\":"<<context<<",\"start\":"<<pair_start<<",\"result\":"<<pair_result<<",\"pair_cycles\":"<<pair_result-pair_start<<",\"first_K_ready\":"<<k_ready<<",\"first_K_use\":"<<k_first<<",\"first_V_ready\":"<<v_ready<<",\"first_V_use\":"<<v_first<<",\"K_waits\":"<<k_wait<<",\"V_waits\":"<<v_wait<<",\"first_K_group1\":"<<k_group1<<",\"first_V_group1\":"<<v_group1<<",\"read_bytes\":"<<stats.read_bytes-reads<<",\"read_requests\":"<<stats.read_requests-requests<<"}\n";
        }
        while(!dut.attention_quiescent||read.tx)tick();
        prefix("sequence_done");std::cout<<",\"context\":"<<context<<",\"first_start\":"<<first<<",\"last_result\":"<<last<<",\"through_last_result\":"<<last-first<<",\"through_quiescence\":"<<cycle-first<<",\"tail_drain\":"<<cycle-last<<",\"evictions\":"<<evictions-evict_begin<<",\"read_bytes\":"<<stats.read_bytes-read_begin<<",\"read_requests\":"<<stats.read_requests-request_begin<<"}\n";in_sequence=false;
    }
    void start_control(){
        current_context=17;current_head=0;head_index=0;dut.fixture_head=0;dut.fixture_context=17;dut.pair_clear=0;
        k_ready=v_ready=k_first=v_first=0;
        for(unsigned i=0;i<64;i++){dut.query0[i]=query_word(0,0,2*i)|(uint32_t(query_word(0,0,2*i+1))<<16);dut.query1[i]=query_word(0,1,2*i)|(uint32_t(query_word(0,1,2*i+1))<<16);}
        while(!dut.pair_ready||!dut.attention_quiescent)tick();dut.pair_start=1;do{tick();}while(!last_start);dut.pair_start=0;dut.pair_out_ready=1;
    }
    void clear_controls(){
        start_control();
        while(!read.tx||read.tx->node!=0||read.tx->group!=1||read.tx->bytes!=4096)tick();
        require(dut.follow_pending&&delay_used,"No actual queued V1 with outstanding K1");
        clear_cycle=cycle;dut.pair_clear=1;prefix("attention_clear_with_queued_V1");std::cout<<"}\n";
        tick();clearing=true;certificates.clear();do{tick();}while(read.tx||!dut.attention_quiescent);
        require(old_return>clear_cycle&&blocked_clear_checks>0,"No actual queued-CLEAR drain evidence");
        clearing=false;prefix("attention_clear_drained");std::cout<<",\"old_return\":"<<old_return<<",\"blocked_checks\":"<<blocked_clear_checks<<"}\n";
        clear_stage=1;delay_used=false;blocked_clear_checks=0;old_return=0;start_control();
        while(!read.tx||read.tx->node!=8||read.tx->group!=1||read.tx->bytes!=4096)tick();
        require(delay_used,"No actual outstanding V1 fetch");clear_cycle=cycle;dut.session_clear=1;dut.pair_clear=1;
        prefix("session_clear_with_outstanding_V1");std::cout<<"}\n";tick();clearing=true;certificates.clear();
        do{tick();}while(read.tx||!dut.attention_quiescent||!dut.store_quiescent);
        require(old_return>clear_cycle&&blocked_clear_checks>0,"No actual session-CLEAR drain evidence");
        prefix("session_clear_drained");std::cout<<",\"old_return\":"<<old_return<<",\"blocked_checks\":"<<blocked_clear_checks<<"}\n";
        clearing=false;dut.session_clear=0;epoch++;mode=1;phase=3;for(unsigned i=0;i<4;i++)tick();populate(0,2);sequence(2,3);
        prefix("clear_recovery_passed");std::cout<<",\"epoch\":"<<epoch<<"}\n";
    }
    void mutation_control(){
        auto address=page_address(0,1);unsigned node=workload==4?0:8;memory.at(address)[node*4096]^=1;expected_fault=true;
        prefix("stored_K_or_V1_changed");std::cout<<",\"node\":"<<node<<",\"group\":1,\"address\":"<<address+node*4096<<"}\n";
        start_control();do{tick();}while(!last_result);
        require(dut.pair_error&&fault_seen&&target_leaf_rejected&&target_uses==0,"Mutation not rejected before affected group-one operand");
        for(unsigned i=0;i<32;i++){tick();require(dut.store_error&&!dut.key_valid&&!dut.value_valid,"Fault did not remain closed");}
        prefix("mutation_rejected");std::cout<<",\"node\":"<<node<<",\"fault_cycle\":"<<fault_cycle<<",\"target_uses\":"<<target_uses<<"}\n";
    }
    void run(){
        if(workload<2){populate(0,2);sequence(2,0);}
        else if(workload==2){populate(0,16);sequence(16,0);populate(16,17);sequence(17,1);populate(17,33);sequence(33,2);}
        else if(workload==3){populate(0,17);clear_controls();}
        else{populate(0,17);mutation_control();}
        require(publications==(workload<2?56:workload==2?924:workload==3?532:476),"Wrong actual ordered publication count");
        prefix("case_done");std::cout<<",\"cycles_through_last_result_and_quiescence\":"<<cycle<<",\"publications\":"<<publications<<",\"verifications\":"<<verification_events<<",\"evictions\":"<<evictions<<",\"all_read_bytes\":"<<stats.read_bytes<<",\"all_write_bytes\":"<<stats.write_bytes<<"}\n";
    }
};
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    try{
        for(int i=1;i<argc;i++){std::string a=argv[i];if(a.rfind("+STALLS=",0)==0)profile=std::stoul(a.substr(8));if(a.rfind("+WORKLOAD=",0)==0)workload=std::stoul(a.substr(10));}
        require(profile<=1&&workload<=5,"Unknown finite profile/workload");Bench b;b.run();std::cout<<"PASS paired_multi_position profile="<<profile<<" workload="<<workload<<"\n";return 0;
    }catch(const std::exception& e){std::cerr<<"FAIL paired_multi_position "<<e.what()<<'\n';return 1;}
}
