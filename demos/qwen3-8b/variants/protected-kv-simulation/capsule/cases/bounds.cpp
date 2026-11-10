#include "Vqwen_kv_hbm_transport.h"
#include "verilated.h"
#include <array>
#include <type_traits>
#include <cstdint>
#include <deque>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>
#include <map>
static void require(bool ok,const std::string& why){if(!ok)throw std::runtime_error(why);}
struct Probe {
    Vqwen_kv_hbm_transport dut;
    uint64_t cycle=0;
    std::map<uint64_t,uint8_t> memory;
    bool request_taken=false,write_taken=false,done_taken=false,read_taken=false;
    std::array<uint32_t,64> data{};bool last=false;
    uint8_t byte(uint64_t a){require(a>=13697613312ULL&&a<13697613824ULL,"Boundary read escaped final digest");return memory.at(a);}
    void store_byte(uint64_t a,uint8_t v){require(a>=13697613312ULL&&a<13697613824ULL,"Boundary write escaped final digest");memory[a]=v;}
    #include "axi.inc.cpp"
    Probe(){
        dut.clk=0;dut.rst_n=0;dut.update_request_valid=0;dut.read_request_valid=0;
        dut.update_request_write=0;dut.update_address=0;dut.update_bytes=0;dut.read_address=0;dut.read_bytes=0;
        dut.update_read_ready=0;dut.update_write_valid=0;dut.update_write_last=0;dut.update_done_ready=0;
        dut.read_data_ready=0;dut.update_abort=0;dut.read_abort=0;
        for(unsigned i=0;i<64;i++)dut.update_write_data[i]=0;
        for(unsigned n=0;n<3;n++)tick();dut.rst_n=1;for(unsigned n=0;n<5;n++)tick();
    }
    void tick(){
        require(cycle<100000,"Finite transport-only bound");dut.clk=0;dut.eval();axi_drive();dut.eval();
        request_taken=(dut.update_request_valid&&dut.update_request_ready)||(dut.read_request_valid&&dut.read_request_ready);
        write_taken=dut.update_write_valid&&dut.update_write_ready;done_taken=dut.update_done_valid&&dut.update_done_ready;
        read_taken=dut.read_data_valid&&dut.read_data_ready;last=dut.read_last;
        if(read_taken)for(unsigned i=0;i<64;i++)data[i]=dut.read_data[i];
        axi_consume();dut.clk=1;dut.eval();cycle++;
    }
    void final_digest(){
        dut.update_request_write=1;dut.update_address=13697613312ULL;dut.update_bytes=512;dut.update_request_valid=1;
        do{tick();require(!dut.update_error,"Final digest header refused");}while(!request_taken);dut.update_request_valid=0;
        for(unsigned beat=0;beat<2;){
            dut.update_write_valid=1;dut.update_write_last=beat==1;
            for(unsigned w=0;w<64;w++){uint32_t v=0;
                for(unsigned b=0;b<4;b++)v|=uint32_t(uint8_t((beat*256+w*4+b)*29+17))<<(8*b);dut.update_write_data[w]=v;}
            tick();require(!dut.update_error,"Final digest write failed");if(write_taken)beat++;
        }
        dut.update_write_valid=0;dut.update_done_ready=1;do{tick();require(!dut.update_error,"Final digest completion failed");}while(!done_taken);
        dut.update_done_ready=0;while(!dut.read_quiescent)tick();
        dut.read_request_valid=1;dut.read_address=13697613312ULL;dut.read_bytes=512;
        do{tick();require(!dut.read_error,"Final digest read header refused");}while(!request_taken);dut.read_request_valid=0;dut.read_data_ready=1;
        for(unsigned beat=0;beat<2;){tick();require(!dut.read_error,"Final digest return failed");if(read_taken){
            require(last==(beat==1),"Final digest LAST");for(unsigned w=0;w<64;w++)for(unsigned b=0;b<4;b++)
                require(uint8_t(data[w]>>(8*b))==uint8_t((beat*256+w*4+b)*29+17),"Final digest data/striping mismatch");beat++;}}
        dut.read_data_ready=0;while(!dut.read_quiescent)tick();
        require(axi_write_words==16&&axi_read_words==16,"Final digest lane/beat coverage");
        std::cout<<"{\"event\":\"last_digest\",\"request\":13697613312,\"last_logical_beat\":13697613568,\"last_byte\":13697613823,\"axi_write_words\":"<<axi_write_words<<",\"axi_read_words\":"<<axi_read_words<<"}\n";
    }
    void reject(bool update,bool write,uint64_t address,unsigned bytes,const char* name){
        dut.update_request_valid=update;dut.read_request_valid=!update;dut.update_request_write=write;
        dut.update_address=address;dut.read_address=address;dut.update_bytes=bytes;dut.read_bytes=bytes;
        do{tick();}while(!request_taken);dut.update_request_valid=0;dut.read_request_valid=0;
        for(unsigned i=0;i<16;i++){tick();require(!dut.axi_arvalid&&!dut.axi_awvalid&&!dut.axi_wvalid,"Rejected descriptor reached AXI");}
        require(dut.read_error&&dut.update_error&&axi_reads==0&&axi_writes==0,"Malformed descriptor not refused");
        std::cout<<"{\"event\":\"typed_reject\",\"case\":\""<<name<<"\",\"address\":"<<address<<",\"bytes\":"<<bytes<<"}\n";
    }
};
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{
    Probe().final_digest();
    Probe().reject(false,false,13697613824ULL,512,"first_out_of_range");
    Probe().reject(false,false,13697613568ULL,512,"crosses_digest_end");
    Probe().reject(false,false,8828026880ULL-4096,4096,"model_read");
    Probe().reject(false,false,8828026880ULL,512,"payload_wrong_unit");
    Probe().reject(false,false,13659865088ULL,4096,"digest_wrong_unit");
    Probe().reject(true,true,8828026880ULL,256,"payload_short_update");
    Probe().reject(true,false,13659865088ULL,512,"update_digest_read");
    Probe().reject(true,true,13659865088ULL,65536,"layer36_payload_alias");
    Probe().reject(true,true,0,65536,"immutable_model_write");
    std::cout<<"PASS protected_transport_boundaries\n";return 0;
}catch(const std::exception& e){std::cerr<<"FAIL protected_transport_boundaries "<<e.what()<<'\n';return 1;}}
