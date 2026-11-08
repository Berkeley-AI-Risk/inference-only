// Verilator host adapter. Each Handle owns a separate instance of the same RTL.
#include "Vrank_model.h"
#include <array>
#include <cstdint>
#include <cstring>
#include <memory>

struct Handle {
    VerilatedContext context;
    Vrank_model m{&context};
    uint64_t edges = 0;
    void tick() {
        m.clk=0; m.eval(); m.clk=1; m.eval(); ++edges;
    }
};
static int64_t signed_bits(uint64_t x, int n) {
    return int64_t(x & ((1ULL << n)-1)) - ((x >> (n-1)) & 1)*(1LL << n);
}
extern "C" {
void* create_rank(int peer, int role) {
    auto *h = new Handle;
    auto &m = h->m;
    m.peer_config=peer; m.peer_role=role; m.tx_start=0; m.tx_take=0; m.local_load=0; m.compute=0; m.receive=0;
    m.reset=1; h->tick(); m.reset=0;
    return h;
}
void destroy_rank(Handle *h) { delete h; }
void load(Handle *h, int base, int n, const uint8_t *data) {
    auto &m = h->m;
    std::memset(&m.payload[0],0,128); std::memcpy(&m.payload[0],data,n*2);
    m.base=base; m.valid_elements=n; m.local_load=1; h->tick(); m.local_load=0;
}
void dot_tile(Handle *h, int rows, int width, int stride,
              const int16_t *weights, int64_t *out) {
    auto &m = h->m;
    m.compute=1;
    for (int row=0; row<rows; ++row) {
        for (int col=0; col<width; col+=16) {
            int lanes = std::min(16,width-col);
            for (int lane=0; lane<16; ++lane)
                m.weight_i[lane] = lane < lanes ? weights[row*stride+col+lane] & 1023 : 0;
            m.base=col; m.valid_elements=lanes; m.row_slot=row;
            m.first_beat= col==0; m.last_beat= col+lanes==width; h->tick();
        }
        out[row]=signed_bits(m.partial[row],35);
    }
    m.compute=0;
}
int publish(Handle *h, int sum, int n, uint64_t expected, const uint8_t *activation,
            uint64_t *header, uint8_t *body, int stall) {
    auto &m=h->m;
    std::memset(&m.payload[0],0,128);
    if (!sum) std::memcpy(&m.payload[0],activation,n*2);
    m.sum_frame=sum; m.expected_descriptor=expected; m.tx_start=1;
    h->tick(); m.tx_start=0;
    if (!m.tx_valid) return 0;
    header[0]=m.tx_descriptor; header[1]=m.tx_sequence;
    std::memcpy(body,&m.tx_payload[0],128);
    for (int edge=0; edge<stall; ++edge) {
        // Competing descriptor cannot displace a full, backpressured slot.
        m.tx_start=1; m.expected_descriptor=expected^1;
        h->tick(); m.tx_start=0;
        if (!m.tx_valid || m.tx_descriptor!=header[0] || m.tx_sequence!=header[1] ||
            std::memcmp(body,&m.tx_payload[0],128)!=0) return -1;
    }
    m.tx_take=1; h->tick(); m.tx_take=0;
    return !m.tx_valid && m.tx_count==header[1]+1 ? 1 : -1;
}
int deliver(Handle *h, int sum, int base, int n, uint64_t desc, uint64_t expected,
            uint64_t seq, int tag, const uint8_t *payload) {
    auto &m = h->m;
    std::memset(&m.payload[0],0,128); std::memcpy(&m.payload[0],payload,n*(sum?8:2));
    m.base=base; m.valid_elements=n; m.sum_frame=sum; m.rx_descriptor=desc;
    m.expected_descriptor=expected; m.rx_sequence=seq; m.tag_ok=tag;
    m.receive=1; h->tick(); m.receive=0;
    return int(m.accepted)-int(m.rejected);
}
void inspect(Handle *h, uint64_t *counters, int64_t *reduced) {
    auto &m=h->m;
    counters[0]=m.next_sequence; counters[1]=m.sum_writes;
    counters[2]=m.activation_writes; counters[3]=h->edges; counters[4]=m.tx_count;
    for (int i=0;i<16;i++) reduced[i]=signed_bits(m.reduced[i],36);
}
}
