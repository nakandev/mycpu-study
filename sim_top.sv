module sim_top (
    input logic clk,
    input logic rst_n
);

    // インターフェースのインスタンス化
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

    // 命令SRAM (ウェイト1サイクル)
    ahb_sram #(
        .MEM_SIZE(1024),
        .WAIT_CYCLES(1)
    ) u_imem (
        .ahb (ahb_i_if.slave)
    );

    // データSRAM (ウェイト2サイクル)
    ahb_sram #(
        .MEM_SIZE(1024),
        .WAIT_CYCLES(2)
    ) u_dmem (
        .ahb (ahb_d_if.slave)
    );

endmodule
