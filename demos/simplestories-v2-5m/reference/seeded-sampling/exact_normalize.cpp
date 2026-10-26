// Integer-only acceleration of the pinned Python reference's BFP normalization.
// __int128 preserves Python intermediate width; conversion overflows reject.
#include <cstdint>
#include <cstddef>
#include <limits>

static __int128 shift_even(int64_t value, int shift, bool &ok) {
    __int128 wide=value;
    if(shift<0) {
        if(-shift>62) {ok=false;return 0;}
        return wide*(__int128(1)<<-shift);
    }
    if(shift==0) return wide;
    if(shift>62) return 0;
    bool negative=wide<0;
    __int128 magnitude=negative?-wide:wide;
    __int128 denominator=__int128(1)<<shift;
    __int128 quotient=magnitude/denominator,remainder=magnitude%denominator;
    if(remainder*2>denominator || (remainder*2==denominator && (quotient&1))) ++quotient;
    return negative?-quotient:quotient;
}
static int bits(uint64_t value) {return value?64-__builtin_clzll(value):0;}
extern "C" int normalize(const int64_t *values,const int16_t *exponents,size_t n,
                         int16_t *output,int *exponent_out,size_t *saturations) {
    bool any=false,ok=true;
    int candidate=-32;
    for(size_t i=0;i<n;++i) if(values[i]) {
        any=true;
        uint64_t magnitude=values[i]<0?uint64_t(-__int128(values[i])):uint64_t(values[i]);
        int need=int(exponents[i])+bits(magnitude)-15;
        if(need>candidate) candidate=need;
    }
    if(!any) candidate=0;
    else {
        if(candidate>31)candidate=31;
        auto fits=[&](int e) {
            for(size_t i=0;i<n;++i) if(values[i]) {
                __int128 v=shift_even(values[i],e-int(exponents[i]),ok);
                if(!ok || v < -32767 || v > 32767) return false;
            }
            return true;
        };
        while(!fits(candidate)) {if(!ok || ++candidate>31)return 1;}
        while(candidate>-32 && fits(candidate-1))--candidate;
        if(!ok)return 2;
    }
    size_t sat=0;
    for(size_t i=0;i<n;++i) {
        __int128 v=shift_even(values[i],candidate-int(exponents[i]),ok);
        if(!ok)return 3;
        if(v>32767){v=32767;++sat;} else if(v < -32767){v=-32767;++sat;}
        output[i]=int16_t(v);
    }
    *exponent_out=candidate;*saturations=sat;return 0;
}
extern "C" int round_shift(const int64_t *values,size_t n,int shift,int64_t *output) {
    bool ok=true;
    for(size_t i=0;i<n;++i) {
        __int128 v=shift_even(values[i],shift,ok);
        if(!ok || v<std::numeric_limits<int64_t>::min() || v>std::numeric_limits<int64_t>::max())return 1;
        output[i]=int64_t(v);
    }
    return 0;
}
