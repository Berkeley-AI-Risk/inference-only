#include "Vswic_boot_admission.h"
#include "verilated.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
using Bytes=std::vector<unsigned char>;
static Bytes load(const char*name){std::ifstream f(name,std::ios::binary);if(!f)throw std::runtime_error("missing fixture");return Bytes(std::istreambuf_iterator<char>(f),{});}
static void wide(VlWide<8>&out,const unsigned char*p){for(unsigned i=0;i<8;i++)out[7-i]=(uint32_t(p[i*4])<<24)|(uint32_t(p[i*4+1])<<16)|(uint32_t(p[i*4+2])<<8)|uint32_t(p[i*4+3]);}
struct Campaign {
    Vswic_boot_admission d;Bytes prefix,grant,request;uint64_t cycles=0;unsigned leases=0;bool boot_verdict=false;
    void require(bool b,const char*s){if(!b)throw std::runtime_error(s);}
    void tick(){
        d.clk=0;d.eval();
        if(d.observe_lms_hash_selected)for(unsigned i=0;i<8;i++)d.proof_sha_digest[i]=d.observe_selected_key_root[i];
        else wide(d.proof_sha_digest,prefix.data()+72);
        d.eval();
        if(d.reset_n && d.observe_request_valid && d.proof_request_ready)request.push_back(d.observe_request_byte);
        if(d.reset_n && d.observe_home_grant)++leases;
        if(d.reset_n && !d.observe_lease_owner && d.observe_lms_valid)boot_verdict=true;
        d.clk=1;d.eval();d.clk=0;d.eval();++cycles;
        require(cycles<2000000,"handoff witness exceeded cycle bound");
    }
    void run(const char*model,const char*authorization){
        prefix=load(model);grant=load(authorization);require(prefix.size()==115396 && grant.size()==1420,"fixture lengths differ");
        for(unsigned i=0;i<32;i++)require(prefix[72+i]==grant[64+i],"fixture model root differs");
        d.reset_n=0;d.clk=0;d.boot_valid_i=0;d.boot_last_i=0;d.boot_byte_i=0;
        d.digest_read_i=0;d.digest_address_i=0;d.metadata_read_i=0;d.metadata_address_i=0;
        d.nonce_hash_start_i=0;d.nonce_hash_byte_valid_i=0;d.nonce_hash_byte_i=0;
        d.proof_sha_ready=1;d.proof_sha_busy=0;d.proof_sha_done=1;d.proof_sha_fault=0;d.proof_sha_offset=0;
        d.proof_memory_ready=0;d.proof_memory_fault=0;d.proof_nonce_valid=0;d.proof_nonce_fault=0;
        wide(d.proof_nonce,grant.data()+32);d.proof_request_ready=1;d.proof_grant_valid=0;d.proof_grant_last=0;d.proof_grant_byte=0;
        tick();tick();tick();d.reset_n=1;
        for(unsigned i=0;i<prefix.size();i++){
            require(d.boot_ready_o,"boot byte refused before frame end");
            d.boot_valid_i=1;d.boot_last_i=(i+1==prefix.size());d.boot_byte_i=prefix[i];tick();
        }
        d.boot_valid_i=0;d.boot_last_i=0;
        while(!d.sealed_o){require(!d.fail_closed_o,"model admission failed");tick();}
        require(boot_verdict,"did not reach an actual boot LMS verdict");
        require(!d.observe_lms_reset && !d.observe_lms_valid && !d.observe_lms_done && !d.observe_lease_epoch,"boot verdict survived lease ownership transfer");
        require(!d.observe_home_enabled && leases==0,"boot alone enabled inference");
        d.proof_memory_ready=1;d.proof_nonce_valid=1;tick();d.proof_nonce_valid=0;
        while(!d.observe_grant_ready){require(!d.observe_home_failed,"home gate failed before request");tick();}
        require(request.size()==128,"home request length differs");
        for(unsigned i=0;i<128;i++)require(request[i]==grant[i],"home request binding differs");
        for(unsigned i=0;i<grant.size();i++){d.proof_grant_valid=1;d.proof_grant_last=(i+1==grant.size());d.proof_grant_byte=grant[i];tick();}
        d.proof_grant_valid=0;d.proof_grant_last=0;
        while(!d.observe_home_enabled){require(!d.observe_home_failed,"home verification failed");tick();}
        require(leases==1 && d.observe_lease_epoch,"home grant lacks a lease verifier epoch");
        std::cout<<"WITNESS PASS cycles="<<cycles<<" real_boot_verdict_seen=1 boot_verdict_cleared=1 real_home_verifier_epoch=1 accepted_home_grants="<<leases<<" abstract_sha_results=1"<<std::endl;
    }
};
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{if(argc!=3)throw std::runtime_error("expected prefix/grant");Campaign c;c.run(argv[1],argv[2]);return 0;}catch(const std::exception&e){std::cerr<<"WITNESS FAIL "<<e.what()<<std::endl;return 1;}}
