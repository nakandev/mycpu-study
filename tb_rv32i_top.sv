`timescale 1ns/1ps

module tb_rv32i_top (
    input logic clk,
    input logic rst_n
);

    // AHB バス インターフェース
    ahb_if ahb_i_if (clk, rst_n);
    ahb_if ahb_d_if (clk, rst_n);

    assign ahb_i_if.hsel = 1'b1;
    assign ahb_d_if.hsel = 1'b1;

    // CPU Top
    rv32i_top u_top (
        .clk   (clk),
        .rst_n (rst_n),
        .ahb_i (ahb_i_if.master),
        .ahb_d (ahb_d_if.master)
    );

    // 命令用 SRAM (ウェイト1サイクル)
    ahb_sram #(
        .MEM_SIZE(1024),
        .WAIT_CYCLES(1)
    ) u_imem (
        .ahb (ahb_i_if.slave)
    );

    // データ用 SRAM (ウェイト2サイクル)
    ahb_sram #(
        .MEM_SIZE(1024),
        .WAIT_CYCLES(5)
    ) u_dmem (
        .ahb (ahb_d_if.slave)
    );

    // テストプログラムのロード
    // initial begin
    //     u_imem.mem[0] = 32'h00500093; // addi x1, x0, 5
    //     u_imem.mem[1] = 32'h00a00113; // addi x2, x0, 10
    //     u_imem.mem[2] = 32'h002081b3; // add  x3, x1, x2
    //     u_imem.mem[3] = 32'h00302023; // sw   x3, 0(x0)
    //     u_imem.mem[4] = 32'h00002203; // lw   x4, 0(x0)
    //     u_imem.mem[5] = 32'h0000006f; // jal  x0, 0
    // end

    // 結果判定モジュール
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // 目的のデータが書き込まれたら表示して終了
            if (u_dmem.mem[0] == 32'd15 && u_top.u_cpu.rf[4] == 32'd15) begin
                $display("\n===========================================");
                $display("[SUCCESS] Memory Write & Readback Verified!");
                $display("  Mem[0] = %d, Reg x4 = %d", u_dmem.mem[0], u_top.u_cpu.rf[4]);
                $display("===========================================\n");
                $finish;
            end
        end
    end

endmodule
