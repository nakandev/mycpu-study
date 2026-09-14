`timescale 1ns/1ps

module rv32i_top (
    input  logic clk,
    input  logic rst_n,

    // AHB インターフェース (命令用)
    ahb_if.master ahb_i,

    // AHB インターフェース (データ用)
    ahb_if.master ahb_d
);

    // -------------------------------------------------------------------------
    // 内部接続シグナル (CPU <-> 命令用 AHB Bridge)
    // -------------------------------------------------------------------------
    logic [31:0] i_haddr;
    logic        i_req;
    logic [31:0] i_hrdata;
    logic        i_hready;

    // -------------------------------------------------------------------------
    // 内部接続シグナル (CPU <-> データ用 AHB Bridge)
    // -------------------------------------------------------------------------
    logic [31:0] d_haddr;
    logic [31:0] d_hwdata;
    logic        d_hwrite;
    logic        d_req;
    logic [31:0] d_hrdata;
    logic        d_hready;

    // =========================================================================
    // 1. CPU コア インスタンス
    // =========================================================================
    rv32i_3stage_cpu u_cpu (
        .clk      (clk),
        .rst_n    (rst_n),

        // 命令バス
        .i_haddr  (i_haddr),
        .i_req    (i_req),
        .i_hrdata (i_hrdata),
        .i_hready (i_hready),

        // データバス
        .d_haddr  (d_haddr),
        .d_hwdata (d_hwdata),
        .d_hwrite (d_hwrite),
        .d_req    (d_req),
        .d_hrdata (d_hrdata),
        .d_hready (d_hready)
    );

    // =========================================================================
    // 2. 命令用 AHB ブリッジ インスタンス
    // =========================================================================
    rv32i_ahb_bridge u_bridge_i (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpu_haddr  (i_haddr),
        .cpu_hwdata (32'd0),   // 命令フェッチは読み出し専用
        .cpu_hwrite (1'b0),
        .cpu_req    (i_req),
        .cpu_hrdata (i_hrdata),
        .cpu_hready (i_hready),
        .ahb        (ahb_i)
    );

    // =========================================================================
    // 3. データ用 AHB ブリッジ インスタンス
    // =========================================================================
    rv32i_ahb_bridge u_bridge_d (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpu_haddr  (d_haddr),
        .cpu_hwdata (d_hwdata),
        .cpu_hwrite (d_hwrite),
        .cpu_req    (d_req),
        .cpu_hrdata (d_hrdata),
        .cpu_hready (d_hready),
        .ahb        (ahb_d)
    );

endmodule
