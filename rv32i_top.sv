module rv32i_top (
    input logic clk,
    input logic rst_n,

    // AHB Master Interfaces
    ahb_if.master ahb_i,
    ahb_if.master ahb_d
);

    // CPU - Bridge 間の内部接続ワイヤ
    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_we;
    logic [3:0]  dmem_be;

    // CPUコア インスタンス
    rv32i_3stage_cpu u_cpu (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .dmem_we    (dmem_we),
        .dmem_be    (dmem_be)
    );

    // AHB Bridge インスタンス
    rv32i_ahb_bridge u_ahb_bridge (
        .cpu_imem_addr  (imem_addr),
        .cpu_imem_rdata (imem_rdata),
        .cpu_dmem_addr  (dmem_addr),
        .cpu_dmem_wdata (dmem_wdata),
        .cpu_dmem_rdata (dmem_rdata),
        .cpu_dmem_we    (dmem_we),
        .cpu_dmem_be    (dmem_be),
        // AHB インターフェースの接続
        .ahb_i          (ahb_i),
        .ahb_d          (ahb_d)
    );

endmodule
