module ahb_sram #(
    parameter int MEM_SIZE = 1024, // ワード数 (4KB)
    parameter int WAIT_CYCLES = 0  // 固定ウェイト数 (0ならウェイトなし)
)(
    ahb_if.slave ahb
);

    // メモリアレイ (32-bit x MEM_SIZE)
    logic [31:0] mem [0:MEM_SIZE-1];

    // パイプライン制御用内部信号
    logic [31:0] addr_reg;
    logic        write_reg;
    logic [1:0]  trans_reg;
    logic        sel_reg;

    // ウェイト制御用カウンタ
    int wait_cnt;

    // アドレスフェーズのラッチ
    always_ff @(posedge ahb.HCLK or negedge ahb.HRESETn) begin
        if (!ahb.HRESETn) begin
            addr_reg  <= 32'd0;
            write_reg <= 1'b0;
            trans_reg <= 2'b00;
            sel_reg   <= 1'b0;
        end else if (ahb.hready) begin
            addr_reg  <= ahb.haddr;
            write_reg <= ahb.hwrite;
            trans_reg <= ahb.htrans;
            sel_reg   <= ahb.hsel;
        end
    end

    // ウェイト（hready）制御
    always_ff @(posedge ahb.HCLK or negedge ahb.HRESETn) begin
        if (!ahb.HRESETn) begin
            wait_cnt   <= 0;
            ahb.hready <= 1'b1;
        end else begin
            if (ahb.hready) begin
                // トランザクション発生時にウェイトを開始
                if (ahb.hsel && (ahb.htrans[1] == 1'b1) && (WAIT_CYCLES > 0)) begin
                    wait_cnt   <= WAIT_CYCLES;
                    ahb.hready <= 1'b0;
                end else begin
                    ahb.hready <= 1'b1;
                end
            end else begin
                // ウェイト処理中
                if (wait_cnt > 1) begin
                    wait_cnt   <= wait_cnt - 1;
                    ahb.hready <= 1 meb0;
                end else begin
                    wait_cnt   <= 0;
                    ahb.hready <= 1'b1; // アクセス完了
                end
            end
        end
    end

    // データ書き込み（データフェーズ）
    logic [31:0] word_addr;
    assign word_addr = addr_reg[31:2];

    always_ff @(posedge ahb.HCLK) begin
        if (ahb.hready && sel_reg && write_reg && (trans_reg[1] == 1'b1)) begin
            mem[word_addr] <= ahb.hwdata;
        end
    end

    // データ読み出し（データフェーズ）
    assign ahb.hrdata = (sel_reg && !write_reg) ? mem[word_addr] : 32'd0;
    assign ahb.hresp  = 1'b0; // OKAY応答

endmodule
