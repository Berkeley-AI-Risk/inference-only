using Bytes=std::vector<uint8_t>;using Digest=std::array<uint8_t,32>;
static void require(bool ok,const std::string& why){if(!ok)throw std::runtime_error(why);}
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
