#include <iostream>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>

#include "Vtb_rv32i_top.h"

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    auto top = std::make_unique<Vtb_rv32i_top>();

    auto tfp = std::make_unique<VerilatedVcdC>();
    top->trace(tfp.get(), 99);
    tfp->open("sim_output.vcd");

    top->clk = 0;
    top->rst_n = 0;

    // クロック進行関数
    auto tick = [&]() {
        // 立ち下がり (1 -> 0)
        top->clk = 0;
        top->eval();
        tfp->dump(main_time);
        main_time += 5;

        // 立ち上がり (0 -> 1)
        top->clk = 1;
        top->eval(); // ここで RTL 側の posedge clk が実行され $display や $finish が評価される
        tfp->dump(main_time);
        main_time += 5;
    };

    std::cout << "[SIM] Starting simulation..." << std::endl;

    // リセットアサート
    tick();
    tick();

    // リセット解除
    top->rst_n = 1;
    std::cout << "[SIM] Reset released." << std::endl;

    // メインループ
    int max_cycles = 200;
    int cycle = 0;

    while (cycle < max_cycles) {
        tick(); // 1サイクル進める ($display などの出力が行われる)
        
        // クロック評価直後に gotFinish() をチェック
        if (Verilated::gotFinish()) {
            std::cout << "[SIM] $finish detected from SystemVerilog." << std::endl;
            break;
        }
        cycle++;
    }

    if (cycle >= max_cycles && !Verilated::gotFinish()) {
        std::cerr << "[ERROR] Simulation timed out after " << max_cycles << " cycles!" << std::endl;
    }

    top->final();
    tfp->close();

    return 0;
}
