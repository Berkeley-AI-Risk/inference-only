// Token/boot client for the fixed AWS Qwen design. The hardware, not this host
// program, enforces model identity and the absence of tensor/arithmetic APIs.
#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <stdexcept>
#include <string>

namespace qwen_host {
inline constexpr uint32_t DESIGN_ID=0x51494f31,ABI=1,IMAGE_BYTES=2354380800u;
inline constexpr uint32_t VOCAB_SIZE=151936,CONTEXT_LIMIT=32768;
inline constexpr const char* IMAGE_SHA256="90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1";
enum class Operation {Append,Step,Clear};
struct Result {uint32_t id,status,token;uint64_t elapsed_ns;};
struct Status {uint32_t flags,credits,received_bytes;};
struct Transport {
    virtual ~Transport()=default;
    virtual uint32_t read_ocl(uint32_t address)=0;
    virtual void write_ocl(uint32_t address,uint32_t value)=0;
    // Transport must issue these DWORDs in ascending address order, without
    // overlapping or reordering stores. No PCIS read operation exists here.
    virtual void write_pcis_words(uint32_t offset,const uint32_t* words,size_t count)=0;
    virtual uint64_t now_ns()=0;
    virtual void idle()=0;
};
class Client {
    Transport& io;
    uint64_t timeout_ns;
    uint32_t uploaded=0;
    bool loading_started=false;
    static void require(bool okay,const std::string& message) {
        if(!okay)throw std::runtime_error(message);
    }
    void deadline(uint64_t start,const char* activity) {
        if(io.now_ns()-start>=timeout_ns)
            throw std::runtime_error(std::string(activity)+" timed out; no automatic retry or reset was issued");
    }
    uint32_t flags() {
        uint32_t value=io.read_ocl(0x008);
        require((value&~255u)==0,"Invalid status word (wrong image, reset or PCIe timeout)");
        require(!(value&0xc0),"FPGA reports model/ingress failure; incomplete loads cannot be resumed");
        return value;
    }
public:
    explicit Client(Transport& transport,uint64_t timeout=1800000000000ull):io(transport),timeout_ns(timeout) {
        require(timeout_ns>0,"Timeout must be positive");
    }
    void identify() {
        require(io.read_ocl(0x000)==DESIGN_ID,"Wrong or unavailable FPGA design ID");
        require(io.read_ocl(0x004)==ABI,"Unsupported FPGA ABI");
        require(io.read_ocl(0x024)==IMAGE_BYTES,"FPGA fixed model-image size differs");
    }
    Status status() {
        identify();Status s{flags(),io.read_ocl(0x018),io.read_ocl(0x01c)};
        require(s.credits<=256&&s.received_bytes<=IMAGE_BYTES,"Invalid ingress counters");
        return s;
    }
    void begin_load() {
        Status s=status();
        require(!(s.flags&0x10),"Model is already loaded; loading is not a runtime model-update operation");
        require(s.received_bytes==0,"Partial upload present; refusing to replay or resume a stream");
        require(!loading_started,"This client already started a load");
        uploaded=0;loading_started=true;
    }
    // A small reusable operation lets RTL tests exercise real ordered uploads
    // without pretending a shortened model is a production boot. No size/hash
    // override is exposed by the client or production command-line program.
    void upload_chunk(const uint8_t* bytes,size_t count) {
        require(loading_started,"begin_load must precede upload");
        require(bytes&&count&&count<=1024&&count%4==0,"Upload chunk must contain 1..256 complete DWORDs");
        require(count<=IMAGE_BYTES-uploaded&&count<=4096-uploaded%4096,"Upload crosses fixed image/aperture boundary");
        uint64_t start=io.now_ns();
        for(;;) {
            require(!(flags()&0x10),"Unexpected early model readiness during upload");
            require(io.read_ocl(0x01c)==uploaded,"Ingress position changed (another writer or reset)");
            uint32_t credit=io.read_ocl(0x018);require(credit<=256,"Invalid ingress credits");
            // Worst case: one AXI transaction per DWORD. Each transaction
            // reserves a complete 64-byte FIFO block until it is processed.
            if(credit>=count/4)break;
            deadline(start,"Waiting for upload credits");io.idle();
        }
        uint32_t words[256];
        for(size_t i=0;i<count/4;++i)words[i]=uint32_t(bytes[4*i])|(uint32_t(bytes[4*i+1])<<8)
            |(uint32_t(bytes[4*i+2])<<16)|(uint32_t(bytes[4*i+3])<<24);
        io.write_pcis_words(uploaded%4096,words,count/4);
        uint32_t expected=uploaded+uint32_t(count);
        for(;;) {
            uint32_t state=flags(),received=io.read_ocl(0x01c);
            require(received>=uploaded&&received<=expected,"Unexpected ingress position after posted writes");
            require(!(state&0x10)||expected==IMAGE_BYTES,"FPGA became ready before the full image");
            if(received==expected)break;
            deadline(start,"Waiting for posted-write receipt");io.idle();
        }
        uploaded=expected;
    }
    void finish_load() {
        require(loading_started&&uploaded==IMAGE_BYTES,"Cannot seal an incomplete fixed image");
        uint64_t start=io.now_ns();
        for(;;) {
            uint32_t state=flags();
            require(io.read_ocl(0x01c)==IMAGE_BYTES,"Full upload count was lost");
            if(state&0x10) {
                require(!(state&0x20),"FPGA simultaneously reports loading and ready");
                loading_started=false;return;
            }
            deadline(start,"Waiting for full-image hash and memory completion");io.idle();
        }
    }
    uint32_t uploaded_bytes()const{return uploaded;}
    uint32_t submit(Operation operation,uint32_t token=0) {
        require(operation==Operation::Append||operation==Operation::Step||operation==Operation::Clear,"Invalid operation");
        require(operation==Operation::Append ? token<VOCAB_SIZE : token==0,"Invalid operation payload");
        identify();uint64_t start=io.now_ns();uint32_t credit=operation==Operation::Clear?2u:1u;
        for(;;) {
            uint32_t state=flags();
            if(operation==Operation::Step)require(state&0x10,"Model is not ready for STEP");
            if(state&credit)break;
            deadline(start,"Waiting for token-command credit");io.idle();
        }
        uint32_t previous=io.read_ocl(0x010),expected=previous+1u;
        uint32_t address=operation==Operation::Append?0x100:operation==Operation::Step?0x104:0x108;
        io.write_ocl(address,token);
        for(;;) {
            flags();uint32_t current=io.read_ocl(0x010);
            require(current==previous||current==expected,"Command ID changed unexpectedly (another writer or reset)");
            if(current==expected) {
                require(io.read_ocl(0x00c)==0,"Token command was rejected");
                return current;
            }
            deadline(start,"Waiting for posted token-command acceptance");io.idle();
        }
    }
    Result wait_result(uint32_t id,Operation operation) {
        uint64_t start=io.now_ns();
        for(;;) {
            uint32_t state=flags();
            require(io.read_ocl(0x010)==id,"Command was cancelled, replaced or reset");
            if(state&8u) {
                uint32_t word=io.read_ocl(0x020),reply_id=io.read_ocl(0x014);
                require((word&0x80000000u)&&!(word&0x7fc00000u)&&reply_id==id,"Malformed or mismatched token response");
                uint32_t status=(word>>18)&15,token=word&0x3ffff;
                require(status<=6,"Unknown token result status");
                require(operation==Operation::Step&&status==0 ? token<VOCAB_SIZE : token==0,"Invalid token response payload");
                return {id,status,token,io.now_ns()-start};
            }
            deadline(start,"Waiting for token result");io.idle();
        }
    }
    Result command(Operation operation,uint32_t token=0) {
        uint64_t start=io.now_ns();uint32_t id=submit(operation,token);
        Result result=wait_result(id,operation);result.elapsed_ns=io.now_ns()-start;return result;
    }
};
}
