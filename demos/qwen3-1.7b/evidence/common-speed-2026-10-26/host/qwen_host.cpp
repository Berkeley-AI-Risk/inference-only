// Linux x86-64 AWS SDK client. No AFI loading, clock control, generic memory
// reads, K/V writes, model updates, or cloud provisioning is implemented here.
#include "qwen_host_protocol.h"
#include <fpga_pci.h>
#include <openssl/evp.h>
#include <atomic>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <sys/file.h>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>
using namespace qwen_host;
static void check(bool okay,const std::string& message){if(!okay)throw std::runtime_error(message);}
static void sdk(int rc,const char* activity){if(rc)throw std::runtime_error(std::string(activity)+" failed, SDK code="+std::to_string(rc));}
static uint32_t number(const std::string& text,uint32_t maximum) {
    check(!text.empty()&&text.find_first_not_of("0123456789")==std::string::npos,"Expected an unsigned decimal integer");
    size_t used=0;auto n=std::stoull(text,&used);check(used==text.size()&&n<=maximum,"Integer outside allowed range");return uint32_t(n);
}
struct SlotLock {
    int descriptor=-1;
    explicit SlotLock(unsigned slot) {
        // A cooperative local-user lock; it is not a hardware security boundary.
        std::string name="/tmp/qwen-fixed-slot-"+std::to_string(slot)+".lock";
        descriptor=open(name.c_str(),O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);
        check(descriptor>=0,"Cannot open local slot lock");
        struct stat st{};
        if(fstat(descriptor,&st)||!S_ISREG(st.st_mode)||st.st_uid!=geteuid()||flock(descriptor,LOCK_EX|LOCK_NB)) {
            close(descriptor);descriptor=-1;throw std::runtime_error("Slot lock unavailable (another process or different owner)");
        }
    }
    ~SlotLock(){if(descriptor>=0)close(descriptor);}
};
struct AwsTransport final:Transport {
    pci_bar_handle_t ocl=PCI_BAR_HANDLE_INIT,pcis=PCI_BAR_HANDLE_INIT;
    explicit AwsTransport(unsigned slot,bool loading) {
#if !defined(__linux__) || !defined(__x86_64__)
        throw std::runtime_error("Hardware access requires the supported Linux x86-64 AWS environment");
#endif
        sdk(fpga_pci_init(),"PCI initialization");
        fpga_pci_resource_map map{};sdk(fpga_pci_get_resource_map(int(slot),FPGA_APP_PF,&map),"Read PCI identity");
        check(map.vendor_id==0x1d0f&&map.device_id==0xf004&&map.subsystem_vendor_id==0xfedc&&map.subsystem_device_id==0x1d51,
              "PCI device identity does not match the Qwen build");
        sdk(fpga_pci_attach(int(slot),FPGA_APP_PF,APP_PF_BAR0,0,&ocl),"Attach token OCL BAR");
        if(loading) {
            int rc=fpga_pci_attach(int(slot),FPGA_APP_PF,APP_PF_BAR4,0,&pcis);
            if(rc){fpga_pci_detach(ocl);ocl=PCI_BAR_HANDLE_INIT;sdk(rc,"Attach fixed-image PCIS BAR");}
        }
    }
    ~AwsTransport(){if(pcis!=PCI_BAR_HANDLE_INIT)fpga_pci_detach(pcis);if(ocl!=PCI_BAR_HANDLE_INIT)fpga_pci_detach(ocl);}
    uint32_t read_ocl(uint32_t address)override {
        std::atomic_thread_fence(std::memory_order_seq_cst);
        uint32_t value=0;sdk(fpga_pci_peek(ocl,address,&value),"OCL read");return value;
    }
    void write_ocl(uint32_t address,uint32_t value)override {
        sdk(fpga_pci_poke(ocl,address,value),"OCL write");std::atomic_thread_fence(std::memory_order_seq_cst);
    }
    void write_pcis_words(uint32_t offset,const uint32_t* words,size_t count)override {
        check(pcis!=PCI_BAR_HANDLE_INIT&&offset%4==0&&count&&count<=256&&offset+4*count<=4096,"Invalid loader transaction");
        // Uncached BAR mapping (flags=0), explicit aligned DWORD calls. Do not
        // replace with write-combining/memcpy without qualifying store order.
        for(size_t n=0;n<count;++n)sdk(fpga_pci_poke(pcis,offset+4*n,words[n]),"PCIS model DWORD");
        std::atomic_thread_fence(std::memory_order_seq_cst);
    }
    uint64_t now_ns()override {
        return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count());
    }
    void idle()override {std::this_thread::sleep_for(std::chrono::microseconds(100));}
};
static void verify_image(std::ifstream& image) {
    image.seekg(0,std::ios::end);check(image.tellg()==std::streampos(IMAGE_BYTES),"Wrong fixed model-image size");image.seekg(0);
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    check(bool(context)&&EVP_DigestInit_ex(context.get(),EVP_sha256(),nullptr)==1,"Cannot initialize SHA-256");
    std::vector<char> data(1024*1024);uint64_t bytes=0;
    while(image.read(data.data(),data.size())||image.gcount()) {
        size_t n=size_t(image.gcount());bytes+=n;check(EVP_DigestUpdate(context.get(),data.data(),n)==1,"SHA-256 update failed");
    }
    check(image.eof()&&bytes==IMAGE_BYTES,"Model-image read failed");
    unsigned char digest[EVP_MAX_MD_SIZE];unsigned size=0;
    check(EVP_DigestFinal_ex(context.get(),digest,&size)==1&&size==32,"SHA-256 finalization failed");
    std::ostringstream hex;hex<<std::hex<<std::setfill('0');for(unsigned i=0;i<size;++i)hex<<std::setw(2)<<unsigned(digest[i]);
    check(hex.str()==IMAGE_SHA256,"Wrong fixed model-image SHA-256; no FPGA upload was attempted");
    image.clear();image.seekg(0);check(bool(image),"Cannot rewind model image");
}
static void okay(const Result& result) {
    check(result.status==0,"FPGA operation returned status "+std::to_string(result.status));
}
int main(int argc,char** argv){try {
    if(argc<4||std::string(argv[1])!="--slot") {
        std::cerr<<"Usage: qwen_host --slot N status|clear|append TOKEN|step|load IMAGE|generate TOKEN[,TOKEN...] COUNT|generate-until-end TOKEN[,TOKEN...] MAX_COUNT|self-test\n";return 2;
    }
    unsigned slot=number(argv[2],FPGA_SLOT_MAX-1);std::string action=argv[3];
    bool loading=action=="load";
    bool stop_at_end=action=="generate-until-end";
    bool generating=action=="generate"||stop_at_end;
    check(action=="status"||action=="clear"||action=="append"||action=="step"||loading||generating||action=="self-test","Unknown command");
    int expected=loading||action=="append"?5:generating?6:4;check(argc==expected,"Wrong argument count");
    std::vector<uint32_t> prompt;unsigned output_count=0;
    if(generating) {
        std::string input=argv[4];check(!input.empty()&&input.back()!=',',"Empty prompt token");
        std::stringstream tokens(input);std::string token;while(std::getline(tokens,token,','))prompt.push_back(number(token,VOCAB_SIZE-1));
        output_count=number(argv[5],CONTEXT_LIMIT);check(output_count>0&&!prompt.empty()&&prompt.size()+output_count<=CONTEXT_LIMIT,"Prompt/output exceeds fixed token tape");
    } else if(action=="self-test"){prompt={9707};output_count=3;}
    uint32_t append_token=action=="append"?number(argv[4],VOCAB_SIZE-1):0;
    std::ifstream image;
    if(loading) {image.open(argv[4],std::ios::binary);check(bool(image),"Cannot open model image");verify_image(image);}
    SlotLock lock(slot);AwsTransport transport(slot,loading);Client client(transport);client.identify();
    if(action=="status") {
        auto s=client.status();std::cout<<"{\"flags\":"<<s.flags<<",\"credits\":"<<s.credits<<",\"received_bytes\":"<<s.received_bytes<<"}\n";
    } else if(loading) {
        client.begin_load();uint64_t start=transport.now_ns();uint8_t data[1024];uint32_t next_report=64*1024*1024;
        while(client.uploaded_bytes()<IMAGE_BYTES) {
            size_t count=std::min<uint32_t>(sizeof(data),IMAGE_BYTES-client.uploaded_bytes());
            image.read(reinterpret_cast<char*>(data),count);check(size_t(image.gcount())==count,"Image changed/truncated during upload");
            client.upload_chunk(data,count);
            if(client.uploaded_bytes()>=next_report){std::cerr<<"Uploaded "<<client.uploaded_bytes()<<" / "<<IMAGE_BYTES<<" bytes\n";next_report+=64*1024*1024;}
        }
        client.finish_load();std::cout<<"{\"model_ready\":true,\"image_bytes\":"<<IMAGE_BYTES<<",\"elapsed_ns\":"<<transport.now_ns()-start<<"}\n";
    } else if(generating||action=="self-test") {
        Result clear_reply=client.command(Operation::Clear);okay(clear_reply);
        std::cerr<<"{\"matched_benchmark_clear\":true,\"id\":"<<clear_reply.id<<",\"status\":"<<clear_reply.status<<",\"elapsed_ns\":"<<clear_reply.elapsed_ns<<"}\n";
        uint64_t prompt_start=transport.now_ns();
        for(auto token:prompt)okay(client.command(Operation::Append,token));
        uint64_t generation_start=transport.now_ns();const uint32_t expected_tokens[3]={25,358,1184};
        for(unsigned i=0;i<output_count;++i) {
            Result r=client.command(Operation::Step);okay(r);const uint64_t validated_reply_ns=transport.now_ns();
            if(action=="self-test")check(r.token==expected_tokens[i],"FPGA token disagrees with fixed numerical oracle");
            std::cout<<"{\"index\":"<<i<<",\"token\":"<<r.token<<",\"step_ns\":"<<r.elapsed_ns
                <<",\"generation_elapsed_ns\":"<<validated_reply_ns-generation_start
                <<",\"prompt_elapsed_ns\":"<<validated_reply_ns-prompt_start<<"}\n"<<std::flush;
            // A host-side stopping rule, not an additional hardware command.
            // The terminating STEP has completed before releasing the slot lock.
            if(stop_at_end&&(r.token==151643u||r.token==151645u))break;
        }
    } else {
        Operation op=action=="clear"?Operation::Clear:action=="append"?Operation::Append:Operation::Step;
        auto r=client.command(op,append_token);okay(r);
        std::cout<<"{\"id\":"<<r.id<<",\"status\":"<<r.status<<",\"token\":"<<r.token<<",\"elapsed_ns\":"<<r.elapsed_ns<<"}\n";
    }
    return 0;
}catch(const std::exception& e){std::cerr<<"Error: "<<e.what()<<"\n";return 1;}}
