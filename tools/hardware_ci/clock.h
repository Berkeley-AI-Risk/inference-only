// Deterministic digital clocks only; no analog/metastability model.
#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
inline void require(bool condition, const std::string& label) {
    if (!condition) throw std::runtime_error(label);
}
struct ClockPlan {
    unsigned source_half, destination_half, phase;
    bool source_edge(uint64_t time) const { return (time+1)%source_half==0; }
    bool destination_edge(uint64_t time) const { return (time+1+phase)%destination_half==0; }
};
