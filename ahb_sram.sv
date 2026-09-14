`timescale 1ns/1ps

module ahb_sram #(
    parameter int MEM_SIZE    = 16384, // メモリサイズ (32-bit ワード数 / デフォルト 16K words = 64KB)
    parameter int WAIT_CYCLES = 0      // 挿入するウェイトサイクル数 (0でノーウェイト)
) (
    // AHB Slave インターフェース
    ahb_if.slave ahb
);

    initial begin
        // ファイルが存在すればロード（初期設定）
        $readmemh("prog.hex", mem);
    end

    // メモリ本体 (32-bit ワード構成)
    logic [31:0] mem [0:MEM_SIZE-1];

    // -------------------------------------------------------------------------
    // 1. パイプライン制御用レジスタ（アドレスフェーズ -> データフェーズ伝達）
    // -------------------------------------------------------------------------
    logic [31:0] addr_reg;
    logic        write_reg;
    logic        active_reg;

    // ウェイト制御用カウンタ
    int unsigned wait_cnt;

    // バス上の有効な転送要求の判定 (hsel かつ HTRANS が NONSEQ(2'b10) または SEQ(2'b11))
    logic valid_req;
    assign valid_req = ahb.hsel && ahb.htrans[1];

    // -------------------------------------------------------------------------
    // 2. アドレスフェーズ信号のラッチ & ウェイト制御
    // -------------------------------------------------------------------------
    always_ff @(posedge ahb.HCLK or negedge ahb.HRESETn) begin
        if (!ahb.HRESETn) begin
            addr_reg   <= 32'd0;
            write_reg  <= 1'b0;
            active_reg <= 1'b0;
            wait_cnt   <= '0;
        end else begin
            if (ahb.hready) begin
                // 前回の転送が完了(hready=1)したタイミングで次のアクセス要求を取り込む
                if (valid_req) begin
                    addr_reg   <= ahb.haddr;
                    write_reg  <= ahb.hwrite;
                    active_reg <= 1'b1;
                    wait_cnt   <= WAIT_CYCLES;
                end else begin
                    active_reg <= 1'b0;
                    wait_cnt   <= '0;
                end
            end else begin
                // ウェイト実行中: カウントダウン
                if (wait_cnt > 0) begin
                    wait_cnt <= wait_cnt - 1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. 応答信号 (hready, hresp) の出力制御
    // -------------------------------------------------------------------------
    // データフェーズ中かつウェイトカウンタ残存時は hready = 0
    assign ahb.hready = (WAIT_CYCLES == 0) ? 1'b1 : !(active_reg && (wait_cnt > 0));
    assign ahb.hresp  = 1'b0; // 常時 OKAY 応答

    // -------------------------------------------------------------------------
    // 4. データフェーズの処理（書き込み & 読み出し）
    // -------------------------------------------------------------------------
    logic [31:0] word_addr;
    assign word_addr = addr_reg[31:2]; // Word-aligned address

    // 【書き込み処理】
    // active_reg & write_reg がアサートされているデータフェーズのクロック立ち上がりで、
    // ブリッジから1サイクル遅れで正しく出力されている ahb.hwdata をメモリに書き込む
    always_ff @(posedge ahb.HCLK) begin
        if (active_reg && write_reg && ahb.hready) begin
            if (word_addr < MEM_SIZE) begin
                mem[word_addr] <= ahb.hwdata;
            end
        end
    end

    // 【読み出し処理】
    // データフェーズ中、かつ hready == 1 の完了タイミングでデータを確定してバスへ出力
    // assign ahb.hrdata = (active_reg && !write_reg && ahb.hready && (word_addr < MEM_SIZE))
    //                     ? mem[word_addr]
    //                     : 32'd0;
    // 
    // 【読み出し処理】 active_reg (データフェーズ) の間、ラッチ済みアドレス mem[addr_reg] を組合せ回路で直接出力
    //  (A) シミュレーション向け
    assign ahb.hrdata = (active_reg && !write_reg && (word_addr < MEM_SIZE))
                        ? mem[word_addr]
                        : 32'd0;

    // //   (B) FPGA BRAM向け
    // logic [31:0] rdata_reg;
    // // クロック同期でメモリから読み出し (BRAM 推論パターン)
    // always_ff @(posedge ahb.HCLK) begin
    //     if (ahb.hready && valid_req && !ahb.hwrite) begin
    //         rdata_reg <= mem[ahb.haddr[31:2]]; // アドレスフェーズで読み出し開始
    //     end
    // end
    // assign ahb.hrdata = rdata_reg;

endmodule
