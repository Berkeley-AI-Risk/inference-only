// Software expectation ONLY. Never drives a numerical-engine input.
#pragma once
#include <cstdint>
#include <stdexcept>
#include <vector>

template<class ReadWord>
std::vector<uint8_t> expected_kv_page(unsigned position,bool protected_store,
                                   const std::vector<uint8_t>& previous,ReadWord word){
    if(position>=32768 || previous.size()!=65536)throw std::runtime_error("Bad page-monitor geometry");
    std::vector<uint8_t> expected=protected_store ? std::vector<uint8_t>(65536,0) : previous;
    unsigned first=protected_store ? position/16*16 : position;
    for(unsigned p=first;p<=position;++p)for(unsigned node=0;node<16;++node)for(unsigned i=0;i<128;++i){
        uint16_t value=word(p,node*128+i);
        unsigned offset=node*4096+(p%16)*256+2*i;
        expected[offset]=uint8_t(value);expected[offset+1]=uint8_t(value>>8);
    }
    return expected;
}
