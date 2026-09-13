#include <iostream>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>

// Verilatorが自動生成するトップモジュールのヘッダー
#include "Vrv32i_top.h"
#include "Vrv32i_top_rv32i_top.h"
#include "Vrv32i_top_rv32i_3stage_cpu.h"
#include "Vrv32i_top_ahb_sram__M400.h" // メモリモデル内部へのアクセス用

vluint64_t main_time = 0; // シミュレーション時刻

// Verilator用の時刻取得関数
double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true); // VCDダンプを有効化

    // トップモジュールのインスタンス化
    auto top = std::make_unique<Vrv32i_top>();

    // VCD波形設定
    auto tfp = std::make_unique<VerilatedVcdC>();
    top->trace(tfp.get(), 99);
    tfp->open("sim_output.vcd");

    // 初期化
    top->clk = 0;
    top->rst_n = 0;

    // クロック駆動用ヘルパー関数
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

    // -------------------------------------------------------------------------
    // 1. テストプログラムのロード (メモリへ直接書き込み)
    // -------------------------------------------------------------------------
    // 0: addi x1, x0, 5    (0x00500093)
    // 4: addi x2, x0, 10   (0x00a00113)
    // 8: add  x3, x1, x2   (0x002081b3)
    // c: sw   x3, 0(x0)    (0x00302023)
    //10: lw   x4, 0(x0)    (0x00002203)
    //14: jal  x0, 0        (0x0000006f) 無限ループ
    
    // Verilator内部構造を経由して命令メモリへ書き込み
    top->rv32i_top->u_imem->mem[0] = 0x00500093;
    top->rv32i_top->u_imem->mem[1] = 0x00a00113;
    top->rv32i_top->u_imem->mem[2] = 0x002081b3;
    top->rv32i_top->u_imem->mem[3] = 0x00302023;
    top->rv32i_top->u_imem->mem[4] = 0x00002203;
    top->rv32i_top->u_imem->mem[5] = 0x0000006f;

    std::cout << "[SIM] Memory loaded with test program." << std::endl;

    // -------------------------------------------------------------------------
    // 2. リセットシーケンス
    // -------------------------------------------------------------------------
    tick();
    tick();
    top->rst_n = 1; // リセット解除
    std::cout << "[SIM] Reset released." << std::endl;

    // -------------------------------------------------------------------------
    // 3. シミュレーション実行と検証
    // -------------------------------------------------------------------------
    bool success = false;
    for (int i = 0; i < 100; ++i) { // 最大100サイクル実行
        tick();

        // データメモリ Mem[0] == 15 (0xF) かつ CPU レジスタ x4 == 15 を監視
        uint32_t mem0_val = top->rv32i_top->u_dmem->mem[0];
        uint32_t x4_val   = top->rv32i_top->u_cpu->rf[4];

        if (mem0_val == 15 && x4_val == 15) {
            std::cout << "[SUCCESS] Cycle " << i << ": Mem[0] = " << mem0_val 
                      << ", Reg x4 = " << x4_val << std::endl;
            success = true;
            break;
        }
    }

    if (!success) {
        std::cerr << "[ERROR] Simulation timed out without reaching target state!" << std::endl;
    }

    // 後処理
    top->final();
    tfp->close();

    return success ? 0 : 1;
}
