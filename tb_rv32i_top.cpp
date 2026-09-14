#include <iostream>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>

// トップモジュール (tb_rv32i_top) の生成ヘッダー
#include "Vtb_rv32i_top.h"

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true); // 波形ダンプ有効

    // tb_rv32i_top を直接インスタンス化
    auto top = std::make_unique<Vtb_rv32i_top>();

    // VCD トレース設定
    auto tfp = std::make_unique<VerilatedVcdC>();
    top->trace(tfp.get(), 99);
    tfp->open("sim_output.vcd");

    // 初期化
    top->clk = 0;
    top->rst_n = 0;

    // クロック進行ヘルパー
    auto tick = [&]() {
        top->clk = 0;
        top->eval();
        tfp->dump(main_time);
        main_time += 5;

        top->clk = 1;
        top->eval();
        tfp->dump(main_time);
        main_time += 5;
    };

    std::cout << "[SIM] Starting simulation..." << std::endl;

    // 1. リセットアサート (2サイクル)
    tick();
    tick();

    // 2. リセット解除
    top->rst_n = 1;
    std::cout << "[SIM] Reset released." << std::endl;

    // 3. メインループ（$finish を検知するかタイムアウトするまで実行）
    int max_cycles = 200;
    int cycle = 0;

    // isFinished() から gotFinish() に修正
    while (!Verilated::gotFinish() && cycle < max_cycles) {
        tick();
        cycle++;
    }

    if (cycle >= max_cycles && !Verilated::gotFinish()) {
        std::cerr << "[ERROR] Simulation timed out after " << max_cycles << " cycles!" << std::endl;
    }

    // 後処理
    top->final();
    tfp->close();

    return 0;
}
