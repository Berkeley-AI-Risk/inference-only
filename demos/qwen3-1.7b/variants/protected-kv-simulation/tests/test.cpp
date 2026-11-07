#include "Voperand_test.h"
#include "verilated.h"
#include "sha256_reference.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>
#include "reference.hpp"

static constexpr bool protected_build=PROTECTED_BUILD;
static constexpr uint64_t PAYLOAD=1ULL<<32,DIGESTS=1ULL<<33;
static uint16_t source_word(unsigned role,unsigned head,unsigned coordinate,unsigned generation) {
    unsigned m=(head*53+coordinate*17+role*67+generation*29)&511;
    return (0x3e00+m)|(((head+coordinate+generation)%5==0)?0x8000:0);
}
template<class W>static uint16_t scalar(const W& w,unsigned i){return (w[i/2]>>(16*(i%2)))&65535;}
static Digest root(uint64_t epoch,const Bytes& digests) {
    Bytes message{0x21};auto tag=unhex("250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3");
    message.insert(message.end(),tag.begin(),tag.end());for(unsigned i=0;i<8;i++)message.push_back(epoch>>(8*i));
    for(unsigned v:{0u,0u,0u,16u,1u,0u,0u})message.push_back(v);
    message.insert(message.end(),digests.begin(),digests.end());return reference_sha256::hash(message);
}
struct Tx {bool write=false,cancelled=false;uint64_t address=0,due=0;unsigned bytes=0,beat=0;Bytes snapshot;};
struct Channel {std::optional<Tx> tx;bool offered=false;std::array<uint32_t,64> data{};bool last=false;};
struct Probe {
    Voperand_test dut;Channel update,read;
    Bytes payload=Bytes(65536,0),digests=Bytes(512,0),expected=Bytes(65536,0);
    unsigned scenario,generation=0;uint64_t cycle=0,epoch=0,writes=0,roots=0,read_headers=0,read_words=0;
    uint64_t key_edges=0,value_edges=0,key_wait=0,value_wait=0,fault_cycle=0;
    uint64_t clear_cycle=0,old_return_cycle=0,reopen_cycle=0,blocked_clear_checks=0;
    bool mutated=false,late_flip_pending=false,delay_next=false,fault_logged=false,published=false;
    bool key_changed=false,value_changed=false,pair_taken=false,last_write_start=false,last_write_word=false,last_write_done=false;
    bool target_blocked_on_fault=false;
    std::array<uint16_t,128> used_value{};
    explicit Probe(unsigned s):scenario(s) {
        dut.clk=0;dut.rst_n=0;dut.session_clear=0;dut.pair_clear=1;dut.pair_start=0;dut.pair_out_ready=0;
        dut.write_start_valid=0;dut.write_valid=0;dut.write_value=0;dut.write_index=0;dut.write_data=0;dut.write_done_ready=0;
        for(unsigned c=0;c<64;c++){dut.query0[c]=uint32_t(0x3d80+(2*c)%127)|(uint32_t(0x3d80+(2*c+1)%127)<<16);
            dut.query1[c]=uint32_t(0x3e00+(2*c)%127)|(uint32_t(0x3e00+(2*c+1)%127)<<16);}
        tick();tick();dut.rst_n=1;for(unsigned i=0;i<10;i++)tick();
    }
    void event(const std::string& name) {std::cout<<"{\"event\":\""<<name<<"\",\"scenario\":"<<scenario<<",\"cycle\":"<<cycle<<"}\n";}
    uint8_t byte(uint64_t address) {
        if(address>=PAYLOAD&&address<PAYLOAD+payload.size())return payload[address-PAYLOAD];
        if(address>=DIGESTS&&address<DIGESTS+digests.size())return digests[address-DIGESTS];
        throw std::runtime_error("Raw address escaped known stored page/digests");
    }
    void store_byte(uint64_t address,uint8_t value) {
        if(address>=PAYLOAD&&address<PAYLOAD+payload.size())payload[address-PAYLOAD]=value;
        else if(address>=DIGESTS&&address<DIGESTS+digests.size())digests[address-DIGESTS]=value;
        else throw std::runtime_error("Write escaped fixed memory");
    }
    void drive(Channel& ch,bool u) {
        bool abort=u?dut.update_abort:dut.read_abort;
        if(abort&&ch.tx&&!ch.tx->cancelled) {ch.tx->cancelled=true;ch.offered=false;event(u?"update_cancel_seen":"read_cancel_seen");}
        if(ch.tx&&ch.tx->cancelled&&cycle>=ch.tx->due) {
            if(!u){old_return_cycle=cycle;event("delayed_old_return_arrived_and_discarded");}
            ch.tx.reset();ch.offered=false;
        }
        if(ch.tx&&!ch.tx->write&&!ch.tx->cancelled&&!ch.offered&&cycle>=ch.tx->due) {
            for(unsigned i=0;i<64;i++){uint32_t v=0;for(unsigned j=0;j<4;j++)v|=uint32_t(ch.tx->snapshot[ch.tx->beat*256+i*4+j])<<(8*j);ch.data[i]=v;}
            ch.last=ch.tx->beat+1==ch.tx->bytes/256;ch.offered=true;
        }
        bool ready=!abort&&!ch.tx;
        bool read_valid=!abort&&ch.offered;
        bool ack=!abort&&ch.tx&&ch.tx->write&&!ch.tx->cancelled&&ch.tx->beat==ch.tx->bytes/256&&cycle>=ch.tx->due;
        if(u) {
            dut.update_request_ready=ready;dut.update_read_valid=read_valid;dut.update_read_last=ch.last;dut.update_read_error=0;
            for(unsigned i=0;i<64;i++)dut.update_read_data[i]=ch.data[i];
            dut.update_write_ready=!abort&&ch.tx&&ch.tx->write&&!ch.tx->cancelled&&ch.tx->beat<ch.tx->bytes/256;
            dut.update_done_valid=ack;dut.update_done_error=0;dut.update_error=0;dut.update_quiescent=!ch.tx;
        } else {
            dut.read_request_ready=ready;dut.read_data_valid=read_valid;dut.read_last=ch.last;dut.read_data_error=0;dut.read_error=0;
            for(unsigned i=0;i<64;i++)dut.read_data[i]=ch.data[i];dut.read_quiescent=!ch.tx;
        }
    }
    void consume(Channel& ch,bool u) {
        bool header=u?(dut.update_request_valid&&dut.update_request_ready):(dut.read_request_valid&&dut.read_request_ready);
        bool take=u?(dut.update_read_valid&&dut.update_read_ready):(dut.read_data_valid&&dut.read_data_ready);
        if(header) {
            require(!ch.tx,"Overlapping raw commands");Tx tx;tx.write=u&&dut.update_request_write;
            tx.address=u?dut.update_address:dut.read_address;tx.bytes=u?dut.update_bytes:dut.read_bytes;
            tx.due=cycle+((!u&&delay_next)?100:3);if(!u)delay_next=false;
            require(tx.bytes%256==0&&(tx.bytes==256||tx.bytes==512||tx.bytes==4096||tx.bytes==65536),"Raw length");
            if(!tx.write){tx.snapshot.resize(tx.bytes);for(unsigned i=0;i<tx.bytes;i++)tx.snapshot[i]=byte(tx.address+i);}
            ch.tx=tx;
            std::cout<<"{\"event\":\"raw_request\",\"scenario\":"<<scenario<<",\"cycle\":"<<cycle
              <<",\"update\":"<<(u?"true":"false")<<",\"write\":"<<(tx.write?"true":"false")
              <<",\"address\":"<<tx.address<<",\"bytes\":"<<tx.bytes<<",\"due\":"<<tx.due<<"}\n";
            if(!u)read_headers++;
        }
        if(take) {
            require(ch.tx&&!ch.tx->write&&!ch.tx->cancelled&&ch.offered,"Unexpected raw read acceptance");
            if(!u){read_words++;std::cout<<"{\"event\":\"raw_read\",\"scenario\":"<<scenario<<",\"cycle\":"<<cycle
                <<",\"address\":"<<ch.tx->address<<",\"beat\":"<<ch.tx->beat<<",\"last\":"<<(ch.last?"true":"false")<<"}\n";}
            ch.offered=false;
            if(++ch.tx->beat==ch.tx->bytes/256) {
                if(!u&&scenario==3&&ch.tx->address==PAYLOAD&&!mutated)late_flip_pending=true;
                ch.tx.reset();
            } else ch.tx->due=cycle+1;
        }
        if(u&&dut.update_write_valid&&dut.update_write_ready) {
            require(ch.tx&&ch.tx->write&&!ch.tx->cancelled,"Unowned raw write");
            require(bool(dut.update_write_last)==(ch.tx->beat+1==ch.tx->bytes/256),"Raw writer LAST");
            for(unsigned i=0;i<256;i++)store_byte(ch.tx->address+ch.tx->beat*256+i,uint8_t(dut.update_write_data[i/4]>>(8*(i%4))));
            if(++ch.tx->beat==ch.tx->bytes/256)ch.tx->due=cycle+3;
        }
        if(u&&dut.update_done_valid&&dut.update_done_ready){require(ch.tx&&ch.tx->write&&ch.tx->beat==ch.tx->bytes/256,"Completion before visible bytes");event("raw_write_completion");ch.tx.reset();}
    }
    void flip(unsigned role) {
        unsigned address=role*8*4096+14;uint16_t before=uint16_t(payload[address])|uint16_t(payload[address+1])<<8;
        payload[address]^=1;mutated=true;
        std::cout<<"{\"event\":\"stored_bit_changed\",\"scenario\":"<<scenario<<",\"cycle\":"<<cycle
          <<",\"address\":"<<PAYLOAD+address<<",\"bit\":0,\"role\":"<<role<<",\"coordinate\":7,\"before\":"<<before<<",\"after\":"<<(before^1)<<"}\n";
    }
    void operand(bool value) {
        bool changed=false;unsigned count=value?64:128,base=value?dut.value_group*64:0;
        require((value?dut.value_position:dut.key_position)==0,"Consumer position escaped written prefix");
        std::cout<<"{\"event\":\"operand_handshake\",\"scenario\":"<<scenario<<",\"cycle\":"<<cycle
          <<",\"generation\":"<<generation<<",\"role\":"<<(value?1:0)<<",\"group\":"<<(value?unsigned(dut.value_group):0)<<",\"valid\":true,\"ready\":true,\"BF16\":[";
        for(unsigned i=0;i<count;i++) {
            unsigned c=base+i;uint16_t actual=value?scalar(dut.values,i):scalar(dut.keys,i);
            uint16_t want=source_word(value?1:0,0,c,generation);
            require(actual==want || (c==7&&actual==(want^1)),"Consumer operand not original or selected one-bit variant");
            changed|=actual!=want;if(value)used_value[c]=actual;
            if(i)std::cout<<',';std::cout<<actual;
        }
        std::cout<<"],\"changed\":"<<(changed?"true":"false")<<"}\n";
        if(value){value_edges++;value_changed|=changed;}else{key_edges++;key_changed|=changed;}
    }
    void tick() {
        require(cycle<1000000,"Finite component observation bound");dut.clk=0;dut.eval();drive(update,true);drive(read,false);dut.eval();
        last_write_start=dut.write_start_valid&&dut.write_start_ready;last_write_word=dut.write_valid&&dut.write_ready;
        last_write_done=dut.write_done_valid&&dut.write_done_ready;
        if(dut.key_ready&&!dut.key_valid)key_wait++;if(dut.value_ready&&!dut.value_valid)value_wait++;
        if(dut.key_valid&&dut.key_ready)operand(false);if(dut.value_valid&&dut.value_ready)operand(true);
        if((dut.reader_fault_event||dut.authentication_error||dut.store_error)&&!fault_logged) {
            fault_logged=true;fault_cycle=cycle;
            target_blocked_on_fault = scenario==1
                ? (dut.authentication_error && dut.key_ready && !dut.key_valid)
                : scenario==2 ? (dut.authentication_error && dut.value_ready && !dut.value_valid) : false;
            std::cout<<"{\"event\":\"fault_edge\",\"scenario\":"<<scenario<<",\"cycle\":"<<cycle
              <<",\"reader_fault\":"<<(dut.reader_fault_event?"true":"false")<<",\"auth_error\":"<<(dut.authentication_error?"true":"false")
              <<",\"store_error\":"<<(dut.store_error?"true":"false")<<",\"key_valid\":"<<(dut.key_valid?"true":"false")
              <<",\"key_ready\":"<<(dut.key_ready?"true":"false")<<",\"value_valid\":"<<(dut.value_valid?"true":"false")
              <<",\"value_ready\":"<<(dut.value_ready?"true":"false")<<"}\n";
        }
        if(dut.root_publish) {
            auto manifests=manifest(epoch,0,0,1,expected);auto wanted=root(epoch,manifests);
            require(dut.published_epoch==epoch,"Published epoch");
            for(unsigned i=0;i<8;i++){uint32_t word=0;for(unsigned j=0;j<4;j++)word=(word<<8)|wanted[4*i+j];require(dut.published_root[7-i]==word,"Independent typed root");}
            roots++;event("independently_checked_root_commit");
        }
        if(last_write_start)event("write_start_accepted");
        if(last_write_done){require(!dut.store_error&&!dut.write_done_error&&!update.tx,"Writer publication before raw completion");writes++;published=true;event("writer_publication");}
        if(dut.session_clear&&read.tx) {
            require(!dut.store_quiescent&&!dut.write_start_ready&&!dut.key_valid&&!dut.value_valid,"CLEAR reopened/exposed operand before delayed old return drained");blocked_clear_checks++;
        }
        if(dut.pair_valid&&dut.pair_out_ready) {
            pair_taken=true;event(dut.pair_error?"attention_pair_error_result":"attention_pair_success_result");
            if(!dut.pair_error){require(key_edges>=1&&value_edges>=2,"Success without operands");for(unsigned c=0;c<128;c++)require(scalar(dut.result0,c)==used_value[c]&&scalar(dut.result1,c)==used_value[c],"Length-one AV result differs from actually consumed V");}
        }
        consume(update,true);consume(read,false);dut.clk=1;dut.eval();cycle++;
        if(late_flip_pending){late_flip_pending=false;flip(0);}
    }
    void write(unsigned gen) {
        generation=gen;expected.assign(65536,0);published=false;
        for(unsigned role=0;role<2;role++)for(unsigned head=0;head<8;head++)for(unsigned c=0;c<128;c++) {
            unsigned offset=(role*8+head)*4096+2*c;uint16_t v=source_word(role,head,c,generation);
            expected[offset]=v;expected[offset+1]=v>>8;
        }
        dut.write_start_valid=1;do{tick();require(!dut.store_error,"Known write start fault");}while(!last_write_start);dut.write_start_valid=0;
        for(unsigned i=0;i<2048;) {
            dut.write_valid=1;dut.write_value=i/1024;dut.write_index=i%1024;dut.write_data=source_word(i/1024,(i%1024)/128,i%128,generation);
            tick();require(!dut.store_error,"Known input/write fault");if(last_write_word)i++;
        }
        dut.write_valid=0;dut.write_done_ready=1;do{tick();require(!dut.store_error,"Known writer publication fault");}while(!last_write_done);dut.write_done_ready=0;
        require(published,"Missing actual writer publication");
        for(unsigned role=0;role<2;role++)for(unsigned head=0;head<8;head++)for(unsigned c=0;c<256;c++) {
            unsigned offset=(role*8+head)*4096+c;require(payload[offset]==expected[offset],"Actual external write differs from accepted known K/V");
        }
        if(protected_build)require(payload==expected&&digests==manifest(epoch,0,0,1,expected),"Actual page/digest differs from independent SHA fixture");
        event("known_external_write_checked");
    }
    void start_pair() {
        dut.pair_clear=0;while(!dut.pair_ready)tick();dut.pair_start=1;tick();dut.pair_start=0;event("actual_attention_started");
    }
    void finish_pair() {
        dut.pair_out_ready=1;while(!pair_taken)tick();dut.pair_out_ready=0;
        if(fault_logged)for(unsigned i=0;i<16;i++){tick();require(dut.store_error&&!dut.key_valid&&!dut.value_valid,"Fault session did not remain closed");}
    }
    void run() {
        write(0);
        if(scenario==1)flip(0);if(scenario==2)flip(1);
        delay_next=scenario==4;start_pair();
        if(scenario==4) {
            while(!read.tx)tick();require(read_headers>0&&key_wait>0&&key_edges==0&&value_edges==0,"CLEAR control never reached outstanding demand");
            clear_cycle=cycle;dut.session_clear=1;dut.pair_clear=1;event("session_clear_asserted_with_outstanding_read");
            do{tick();}while(read.tx||!dut.store_quiescent||!dut.attention_quiescent);
            require(old_return_cycle>clear_cycle&&blocked_clear_checks>0&&key_edges==0&&value_edges==0,"Delayed return/CLEAR evidence missing");
            reopen_cycle=cycle;event("actual_store_quiescent_after_old_return");epoch++;dut.session_clear=0;
            for(unsigned i=0;i<4;i++)tick();write(1);start_pair();
        }
        finish_pair();
        if(scenario==0||scenario==3||scenario==4)require(!fault_logged&&!key_changed&&!value_changed,"Honest/captured-copy/recovery control did not use original accepted source");
        if(scenario==3)require(mutated,"Captured-copy control never changed storage");
        unsigned target=scenario==2?1:0;
        bool target_changed=target?value_changed:key_changed;
        uint64_t target_edges=target?value_edges:key_edges;
        if(scenario==1 || scenario==2) {
            if(protected_build) {
                require(fault_logged && target_blocked_on_fault && !target_edges && !target_changed,
                    "Protected mutation was not rejected before the affected operand handshake");
                require(scenario==1 ? (key_edges==0 && value_edges==0) : (key_edges==1 && value_edges==0),
                    "Protected K/V fault control reached an unexpected consumer boundary");
            } else {
                require(!fault_logged && target_changed && key_edges==1 && value_edges==2,
                    "Plain control did not consume the independently selected mutated bytes");
            }
        }
        std::string outcome=target_changed?"changed_operand_used":target_edges?"original_operand_used":fault_logged?"fault_prevents_target_use":"no_target_use";
        std::cout<<"{\"event\":\"result\",\"scenario\":"<<scenario<<",\"protected_build\":"<<(protected_build?"true":"false")
          <<",\"outcome\":\""<<outcome<<"\",\"key_edges\":"<<key_edges<<",\"value_edges\":"<<value_edges
          <<",\"changed_key_used\":"<<(key_changed?"true":"false")<<",\"changed_value_used\":"<<(value_changed?"true":"false")
          <<",\"key_ready_waits\":"<<key_wait<<",\"value_ready_waits\":"<<value_wait<<",\"fault_cycle\":"<<fault_cycle
          <<",\"actual_writes\":"<<writes<<",\"independent_roots\":"<<roots<<",\"read_headers\":"<<read_headers
          <<",\"read_beats\":"<<read_words<<",\"clear_cycle\":"<<clear_cycle<<",\"old_return_cycle\":"<<old_return_cycle
          <<",\"reopen_cycle\":"<<reopen_cycle<<",\"blocked_clear_checks\":"<<blocked_clear_checks<<",\"cycles\":"<<cycle<<"}\n"<<std::flush;
    }
};
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    try{
        const std::array<std::pair<std::string,std::string>,2> vectors{{
            {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
            {"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}}};
        for(const auto& vector:vectors) {
            auto actual=reference_sha256::hash(Bytes(vector.first.begin(),vector.first.end()));
            auto expected=unhex(vector.second);
            require(std::equal(actual.begin(),actual.end(),expected.begin()), "Independent SHA known-answer control");
        }
        for(unsigned scenario=0;scenario<5;scenario++)Probe(scenario).run();
        std::cout<<"PASS operand_integrity_observation protected="<<(protected_build?1:0)<<"\n";return 0;
    }catch(const std::exception& error){std::cerr<<"FAIL operand_integrity_observation "<<error.what()<<'\n';return 1;}
}
