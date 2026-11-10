// Testbench-only independent per-lane AXI memory. Actual bridge/child RTL is
// between the store and these pins. No direct raw response substitution.
template<class W> static uint64_t bits(const W& w,unsigned start,unsigned count) {
    require(count>0 && count<64,"Packed field extraction width");
    if constexpr(std::is_integral<W>::value) {
        require(start+count<=sizeof(W)*8,"Scalar field extraction bound");
        return (uint64_t(w)>>start)&((uint64_t(1)<<count)-1);
    } else {
        uint64_t v=0;for(unsigned i=0;i<count;i++)v|=uint64_t((w[(start+i)/32]>>((start+i)%32))&1)<<i;return v;
    }
}
template<class W> static void put(W& w,unsigned start,unsigned count,uint64_t value) {
    for(unsigned i=0;i<count;i++){unsigned b=start+i;uint32_t mask=uint32_t(1)<<(b%32);w[b/32]=(w[b/32]&~mask)|(((value>>i)&1)?mask:0);}
}
struct ReadBurst {uint64_t address,due;unsigned words,beat=0;};
struct WriteBeat {std::array<uint8_t,32> data;bool last;};
struct AxiLane {
    std::deque<ReadBurst> reads;
    std::optional<std::pair<uint64_t,unsigned>> aw;
    std::vector<WriteBeat> words;
    bool rheld=false,bpending=false;
    uint64_t bdue=0;
    std::array<uint32_t,8> rword{};
    bool rlast=false;
};
std::array<AxiLane,8> lanes;
uint64_t axi_reads=0,axi_writes=0,axi_read_words=0,axi_write_words=0;
static uint64_t logical(uint64_t physical) {
    uint64_t pc=physical>>29,offset=physical&((1ULL<<29)-1);
    return ((offset>>13)<<18)|((pc>>3)<<16)|(((offset>>5)&255)<<8)|((pc&7)<<5)|(offset&31);
}
void axi_drive() {
    if(cycle==0) {
        const std::array<uint32_t,3> packed{{0x89abcdefu,0x01234567u,0xdeadbeefu}};
        require(bits(uint32_t(0xfedcba98u),16,8)==0xdcu,"Scalar32 accessor control");
        require(bits(uint64_t(0x0123456789abcdefULL),32,16)==0x4567u,"Scalar64 accessor control");
        require(bits(packed,31,2)==3 && bits(packed,28,8)==0x78u && bits(packed,60,8)==0xf0u,"Cross-word accessor controls");
    }
    dut.axi_arready=0;dut.axi_awready=0;dut.axi_wready=0;
    dut.axi_rvalid=0;dut.axi_rlast=0;dut.axi_bvalid=0;
    for(unsigned i=0;i<128;i++)dut.axi_rdata[i]=0;
    for(unsigned i=0;i<3;i++){dut.axi_rid[i]=0;dut.axi_bid[i]=0;}
    dut.axi_rresp=0;dut.axi_bresp=0;
    for(unsigned i=0;i<8;i++) {
        auto& l=lanes[i];
        if(l.reads.size()<8 && (cycle+3*i)%7!=0)dut.axi_arready|=1u<<i;
        if(!l.aw&&!l.bpending&&(cycle+2*i)%5!=0)dut.axi_awready|=1u<<i;
        if(!l.bpending&&l.words.size()<16&&(cycle+i)%3!=0)dut.axi_wready|=1u<<i;
        if(!l.rheld&&!l.reads.empty()&&cycle>=l.reads.front().due&&(cycle+i)%4!=0) {
            const auto& r=l.reads.front();uint64_t address=logical(r.address+32*r.beat);
            for(unsigned w=0;w<8;w++){uint32_t value=0;for(unsigned b=0;b<4;b++)value|=uint32_t(byte(address+w*4+b))<<(8*b);l.rword[w]=value;}
            l.rlast=r.beat+1==r.words;l.rheld=true;
        }
        if(l.rheld){dut.axi_rvalid|=1u<<i;if(l.rlast)dut.axi_rlast|=1u<<i;for(unsigned w=0;w<8;w++)dut.axi_rdata[i*8+w]=l.rword[w];}
        if(l.bpending&&cycle>=l.bdue)dut.axi_bvalid|=1u<<i;
    }
}
void axi_consume() {
    require(!(dut.axi_arvalid&0xff00)&&!(dut.axi_awvalid&0xff00)&&!(dut.axi_wvalid&0xff00),"Dormant second master group activated");
    for(unsigned i=0;i<8;i++) {
        auto& l=lanes[i];unsigned mask=1u<<i;
        if(dut.axi_bvalid&dut.axi_bready&mask){require(l.bpending,"Unowned B");l.bpending=false;}
        if(dut.axi_rvalid&dut.axi_rready&mask) {
            require(l.rheld&&!l.reads.empty(),"Unowned R");l.rheld=false;axi_read_words++;
            if(++l.reads.front().beat==l.reads.front().words)l.reads.pop_front();
            else l.reads.front().due=cycle+1;
        }
        if(dut.axi_arvalid&dut.axi_arready&mask) {
            require(bits(dut.axi_arid,i*6,6)==0&&bits(dut.axi_arsize,i*3,3)==5&&bits(dut.axi_arburst,i*2,2)==1,"AR identity/shape");
            uint64_t a=bits(dut.axi_araddr,i*34,34);unsigned n=bits(dut.axi_arlen,i*4,4)+1;
            require((a&31)==0&&(a&4095)+32*n<=4096,"AR alignment/boundary");
            l.reads.push_back({a,cycle+2+i%3,n,0});axi_reads++;
        }
        if(dut.axi_awvalid&dut.axi_awready&mask) {
            require(!l.aw&&bits(dut.axi_awid,i*6,6)==0&&bits(dut.axi_awsize,i*3,3)==5&&bits(dut.axi_awburst,i*2,2)==1,"AW identity/owner");
            uint64_t a=bits(dut.axi_awaddr,i*34,34);unsigned n=bits(dut.axi_awlen,i*4,4)+1;
            require((a&31)==0&&(a&4095)+32*n<=4096,"AW alignment/boundary");l.aw={{a,n}};axi_writes++;
        }
        if(dut.axi_wvalid&dut.axi_wready&mask) {
            require(bits(dut.axi_wstrb,i*32,32)==0xffffffff,"W strobe");WriteBeat w;
            for(unsigned b=0;b<32;b++)w.data[b]=bits(dut.axi_wdata,i*256+b*8,8);
            w.last=dut.axi_wlast&mask;l.words.push_back(w);axi_write_words++;
        }
        if(l.aw&&l.words.size()==l.aw->second) {
            require(!l.bpending,"Two B owners");
            for(unsigned j=0;j<l.words.size();j++) {
                require(l.words[j].last==(j+1==l.words.size()),"WLAST");
                uint64_t a=logical(l.aw->first+32*j);
                for(unsigned b=0;b<32;b++)store_byte(a+b,l.words[j].data[b]);
            }
            l.aw.reset();l.words.clear();l.bpending=true;l.bdue=cycle+2+i%4;
        }
    }
}
