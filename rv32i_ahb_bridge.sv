`timescale 1ns/1ps

module rv32i_ahb_bridge (
    input  logic        clk,
    input  logic        rst_n,

    // CPU側 インターフェース
    input  logic [31:0] cpu_haddr,
    input  logic [31:0] cpu_hwdata,
    input  logic        cpu_hwrite,
    input  logic        cpu_req,
    output logic [31:0] cpu_hrdata,
    output logic        cpu_hready,

    // AHB Master インターフェース (ahb_if)
    ahb_if.master       ahb
);

    // データフェーズ追跡用フラグ
    logic data_phase;
    logic is_write_phase;
    logic [31:0] hwdata_reg;

    // -------------------------------------------------------------------------
    // 1. フェーズ管理 & データパイプライン
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_phase     <= 1'b0;
            is_write_phase <= 1'b0;
            hwdata_reg     <= 32'd0;
        end else begin
            if (ahb.hready) begin
                if (cpu_req && !data_phase) begin
                    // アドレスフェーズ開始 -> 次サイクルはデータフェーズ
                    data_phase     <= 1'b1;
                    is_write_phase <= cpu_hwrite;
                    hwdata_reg     <= cpu_hwdata;
                end else begin
                    // データフェーズ完了
                    data_phase     <= 1'b0;
                    is_write_phase <= 1'b0;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. AHB バス出力制御
    // -------------------------------------------------------------------------
    // アドレスフェーズのサイクルでのみ NONSEQ を出力
    assign ahb.htrans = (cpu_req && !data_phase) ? 2'b10 : 2'b00;
    assign ahb.haddr  = cpu_haddr;
    assign ahb.hwrite = cpu_hwrite;
    assign ahb.hwdata = hwdata_reg;

    // -------------------------------------------------------------------------
    // 3. CPU側 応答制御 (ストール制御)
    // -------------------------------------------------------------------------
    // 読み出しの場合、データフェーズ(data_phase == 1)で ahb.hready が立つまで CPU をウェイトさせる
    // 書き込みの場合も、データフェーズ完了まで引き伸ばす
    assign cpu_hready = data_phase && ahb.hready;
    assign cpu_hrdata = ahb.hrdata;

endmodule
