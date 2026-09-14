VERILATOR = verilator
VERILATOR_FLAGS = -Wall -Wno-fatal -Wno-lint --trace --cc --exe
# VERILATOR_FLAGS = -Wall -Wno-fatal -Wno-lint --trace --cc --exe --public-flat-rw

# ソースファイル
SV_SRCS = ahb_if.sv \
          rv32i_3stage_cpu.sv \
          rv32i_ahb_bridge.sv \
          rv32i_top.sv \
          ahb_sram.sv \
          tb_rv32i_top.sv

CPP_SRC = tb_rv32i_top.cpp

TOP_MODULE = tb_rv32i_top
BUILD_DIR = obj_dir

all: run

build:
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(SV_SRCS) $(CPP_SRC)
	make -C $(BUILD_DIR) -f V$(TOP_MODULE).mk V$(TOP_MODULE)

run: build
	./$(BUILD_DIR)/V$(TOP_MODULE)

wave:
	gtkwave sim_output.vcd &

clean:
	rm -rf $(BUILD_DIR) sim_output.vcd

.PHONY: all build run wave clean
