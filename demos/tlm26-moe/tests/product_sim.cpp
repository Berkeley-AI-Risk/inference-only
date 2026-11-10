#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <vector>
#include <stdexcept>
#include <cstring>
#ifdef BOOT_TEST
#include "Vboot_product.h"
#else
#include "Vtlm_product.h"
#endif

#include "verilated.h"

#ifdef BOOT_TEST
static Vboot_product d;
#define rd_ready ready
#define rd_req cmd
#define rd_valid read_valid
#define rd_data read_data
#else
static Vtlm_product d;
#endif
static std::vector<uint8_t> image,source;
static uint32_t writes=0;
static bool owe=false, hold=false;
static int bad_page=-1,lag=0;
static uint32_t address=0;
static uint64_t ticks=0,reads=0;
static int txphase=-1,txbit=0,txbyte=0;
static std::vector<uint8_t> rx;
#ifndef UART_DIV
#define UART_DIV 8
#endif
constexpr int baud=UART_DIV;
void tick(){
    d.clk=0;
    d.rd_ready=((ticks%7)!=0);
    d.rd_valid=owe && !hold && lag==0;
    if(d.rd_valid) {
      if(address+32>image.size()) throw std::runtime_error("address range");
      std::memcpy(d.rd_data.data(),image.data()+address,32);
      if(int(address/4096)==bad_page && address%4096==0) d.rd_data[0]^=1;
    }
    d.eval();
    bool take=d.rd_req && d.rd_ready;
    if(d.rd_valid) owe=false;
    if(take) {
      if(owe) throw std::runtime_error("extra DDR request");
      #ifdef BOOT_TEST
      address=32*d.addr;
      if(d.wr){
        if(d.addr!=writes || address+32>image.size()) throw std::runtime_error("boot DDR write outside sequential image");
        std::memcpy(image.data()+address,d.write_data.data(),32);writes++;
      }else{
#else
      address=d.rd_byte_addr;
#endif
      reads++;
      lag=2+reads%6;owe=true;
#ifdef BOOT_TEST
      }
#endif
    }else if(owe && lag>0) lag--;
    if(txphase==-1){
      if(d.uart_tx==0){txphase=0;txbit=0;txbyte=0;}
    }else{
      txphase++;
      if(txphase==baud+baud/2+txbit*baud && txbit<8){ txbyte|=d.uart_tx<<txbit;txbit++;}
      if(txphase==9*baud+baud/2){
        if(!d.uart_tx) throw std::runtime_error("stop bit");
        rx.push_back(txbyte);txphase=-1;
      }
    }
    d.clk=1;d.eval();ticks++;
}
void clocks(unsigned n){while(n--)tick();}
uint8_t crc(std::array<uint8_t,5> f){int x=0;for(int i=0;i<4;i++){x^=f[i];for(int b=0;b<8;b++)x=((x<<1)^((x&128)?7:0))&255;}return x;}
void send_byte(uint8_t b){
    d.uart_rx=0;clocks(baud);
    for(unsigned i=0;i<8;i++){d.uart_rx=(b>>i)&1;clocks(baud);}
    d.uart_rx=1;clocks(baud);
}
void send(int op,int tok){
    std::array<uint8_t,5> f={0xa5,(uint8_t)op,(uint8_t)tok,(uint8_t)(tok>>8),0};f[4]=crc(f);
    for(auto b:f)send_byte(b);
}
void receive(int kind,int token){
    auto start=ticks;
    while(rx.size()<5 && ticks-start<30000000) tick();
    if(rx.size()!=5)throw std::runtime_error("timeout or stale bytes");
    std::array<uint8_t,5> f={0x5a,(uint8_t)kind,(uint8_t)token,(uint8_t)(token>>8),0};f[4]=crc(f);
    if(!std::equal(f.begin(),f.end(),rx.begin())) {
      std::cerr<<"Expected "<<kind<<":"<<token<<" got ";for(auto b:rx)std::cerr<<(int)b<<" ";std::cerr<<"\n";throw std::runtime_error("wrong public reply");
    }
    rx.clear();clocks(baud);
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    std::ifstream raw("model.bin",std::ios::binary|std::ios::ate);auto size=raw.tellg();raw.seekg(0);image.resize(size);raw.read((char*)image.data(),size);
    d.rst_n=0;d.uart_rx=1;clocks(10);d.rst_n=1;clocks(20);
#ifdef BOOT_TEST
    auto boot_ack=[](uint8_t byte){int n=4096;while(rx.empty()&&--n) tick();if(rx.size()!=1||rx[0]!=byte) throw std::runtime_error("boot ack");rx.clear();clocks(baud*2);};
    for(auto c:std::string("TLM1"))send_byte(c);
    boot_ack(0x42);
    source=image;std::fill(image.begin(),image.end(),0);
    if(std::getenv("BAD_BOOT_PAGE"))source[23*4096]^=1;
    for(unsigned i=0;i<source.size();i++){send_byte(source[i]);if((i&4095)==4095)boot_ack(0x79);}
    if(image!=source || writes!=98304) throw std::runtime_error("boot memory image mismatch");
    std::cout<<"boot_writes "<<writes<<" page_acks 768 changed_bytes "<<(std::getenv("BAD_BOOT_PAGE")?1:0)<<"\n";
#endif
    int op,tok,kind,payload;
    while(std::cin>>op>>tok>>kind>>payload){
      uint64_t before=ticks;
      if(op==-1){bad_page=tok;continue;}
      if(op==-3){
        send(1,0);send(2,0);receive(0x82,0);clocks(2000);
        if(!rx.empty()) throw std::runtime_error("stale token in paired probe");
        std::cout<<"paired_clear_cycles "<<ticks-before<<"\n";
        continue;
      }
      if(op==-2){
        send(1,0);
        while(!owe)tick(); hold=true;
        send(2,0); clocks(300);
        if(!owe || !rx.empty())throw std::runtime_error("CLEAR drain test invalid");
        hold=false;receive(0x82,0);clocks(800);if(!rx.empty())throw std::runtime_error("stale byte after release");
        std::cout<<"clear_outstanding "<<address<<" "<<ticks-before<<"\n";continue;
      }
      send(op,tok);receive(kind,payload);
      std::cout<<op<<" "<<tok<<" "<<kind<<" "<<payload<<" "<<ticks-before<<" "<<reads<<"\n";std::cout.flush();
    }
}
