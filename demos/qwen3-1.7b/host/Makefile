# Run after sourcing the separately installed AWS SDK setup on Linux x86-64.
CXX ?= c++
CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++17 -Wall -Wextra -Werror -pthread
CPPFLAGS += -I$(SDK_DIR)/userspace/include
LDFLAGS += -L$(SDK_DIR)/userspace/lib/so -Wl,-rpath,$(SDK_DIR)/userspace/lib/so
LDLIBS += -lfpga_mgmt -lcrypto -pthread

.PHONY: all
all: qwen_host

qwen_host: qwen_host.cpp qwen_host_protocol.h
	@test -n "$(SDK_DIR)" || (echo "Source sdk_setup.sh first"; exit 1)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) qwen_host.cpp $(LDFLAGS) $(LDLIBS) -o $@
