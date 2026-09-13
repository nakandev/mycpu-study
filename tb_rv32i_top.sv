`timescale 1ns/1ps

module tb_rv32i_top;

    logic clk;
    logic rst_n;

    // クロック生成 (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // AHB バス インターフェースのインスタンス
    ahb_if ahb_i_if (clk, rst_n); // 命令バス
    ahb_if ahb_d_if (clk, rst_n); // データバス

    // 単純化のため hsel を常時 1 (単一スレーブ構成) に設定
    assign ahb_i_if.hsel = 1'b1;
    assign ahb_d_if.hsel = 1'b1;

    // CPU Top インスタンス
    rv32i_top u_top (
        .clk   (clk),
        .rst_n (rst_n),
        .ahb_i (ahb_i_if.master),
        .ahb_d (ahb_d_if.master)
    );

    // 命令用 AHB SRAM (1サイクルのウェイトを入れるテスト)
    ahb_sram #(
        .MEM_SIZE(1024),
        .WAIT_CYCLES(1) // 命令フェッチ時に1サイクルウェイト挿入
    ) u_imem (
        .ahb (ahb_i_if.slave)
    );

    // データ用 AHB SRAM (2サイクルのウェイトを入れるテスト)
    ahb_sram #(
        .MEM_SIZE(1024),
        .WAIT_CYCLES(2) // データロード/ストア時に2サイクルウェイト挿入
    ) u_dmem (
        .ahb (ahb_d_if.slave)
    );

    // テストシナリオ
    initial begin
        // 1. テストプログラムの初期化 (命令メモリへ書き込み)
        u_imem.mem[0] = 32'h00500093; // addi x1, x0, 5
        u_imem.mem[1] = 32'h00a00113; // addi x2, x0, 10
        u_imem.mem[2] = 32'h002081b3; // add  x3, x1, x2
        u_imem.mem[3] = 32'h00302023; // sw   x3, 0(x0)
        u_imem.mem[4] = 32'h00002203; // lw   x4, 0(x0)
        u_imem.mem[5] = 32'h0000006f; // jal  x0, 0 (無限ループ)

        // 2. リセット処理
        rst_n = 0;
        #20;
        rst_n = 1;

        $display("--- Simulation Started ---");

        // 3. 実行監視
        // SW命令でメモリの 0 番地に 15 (0xF) が書き込まれるのを確認
        wait (u_dmem.mem[0] == 32'd15);
        $display("[SUCCESS] Memory Write Detected: Mem[0] = %d", u_dmem.mem[0]);

        // 4. LW命令で レジスタ x4 に 15 が書き戻されるのを監視
        wait (u_top.u_cpu.rf[4] == 32'd15);
        $display("[SUCCESS] Register Write Detected: x4 = %d", u_top.u_cpu.rf[4]);

        #50;
        $display("--- Simulation Passed Successfully ---");
        $finish;
    end

    // 波形ダンプ (EPWave / GTKWave用)
    initial begin
        $dumpfile("rv32i_ahb_tb.vcd");
        $dumpvars(0, tb_rv32i_top);
    end

endmodule
