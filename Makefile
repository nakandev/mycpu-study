# コンパイラ設定
VERILATOR = verilator
VERILATOR_FLAGS = -Wall -Wno-fatal --trace --cc --exe

# ソースファイル
SV_SRCS = ahb_if.sv \
          rv32i_3stage_cpu.sv \
          rv32i_ahb_bridge.sv \
          rv32i_top.sv \
          ahb_sram.sv \
          sim_top.sv

CPP_SRC = tb_rv32i_top.cpp

TOP_MODULE = sim_top
BUILD_DIR = obj_dir

all: run

# VerilatorによるC++コード生成およびコンパイル
build:
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(SV_SRCS) $(CPP_SRC)
	make -C $(BUILD_DIR) -f V$(TOP_MODULE).mk V$(TOP_MODULE)

# シミュレーション実行
run: build
	./$(BUILD_DIR)/V$(TOP_MODULE)

# GTKWaveで波形確認
wave:
	gtkwave sim_output.vcd &

clean:
	rm -rf $(BUILD_DIR) sim_output.vcd

.PHONY: all build run wave clean
