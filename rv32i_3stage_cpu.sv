`timescale 1ns/1ps

module rv32i_3stage_cpu (
    input  logic        clk,
    input  logic        rst_n,

    // 命令用メモリアクセス・インターフェース
    output logic [31:0] i_haddr,
    output logic        i_req,
    input  logic [31:0] i_hrdata,
    input  logic        i_hready,

    // データ用メモリアクセス・インターフェース
    output logic [31:0] d_haddr,
    output logic [31:0] d_hwdata,
    output logic        d_hwrite,
    output logic        d_req,
    input  logic [31:0] d_hrdata,
    input  logic        d_hready
);

    // =========================================================================
    // 1. パイプラインレジスタ & 内部信号定義
    // =========================================================================
    
    // PC (Program Counter)
    logic [31:0] pc, next_pc;

    // IF/ID パイプラインレジスタ
    logic [31:0] if_id_pc;
    logic [31:0] if_id_inst;

    // ID/EX パイプラインレジスタ
    logic [31:0] ex_pc;
    logic [31:0] ex_rs1_data;
    logic [31:0] ex_rs2_data;
    logic [31:0] ex_imm;
    logic [4:0]  ex_rd_addr;
    logic        ex_reg_write;
    logic        ex_mem_to_reg;
    logic        ex_mem_read;
    logic        ex_mem_write;
    logic [2:0]  ex_alu_op;

    // レジスタファイル (32-bit x 32)
    logic [31:0] rf [0:31];

    // デコード信号
    logic [6:0]  opcode;
    logic [4:0]  rd_addr, rs1_addr, rs2_addr;
    logic [2:0]  funct3;
    logic [31:0] imm;
    logic        reg_write;
    logic        mem_to_reg;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  alu_op;

    // ストール・イネーブル信号
    logic imem_stall;
    logic dmem_stall;
    logic pc_en;
    logic if_id_en;
    logic id_ex_en;
    logic id_ex_flush;

    // =========================================================================
    // 2. ストール & パイプライン制御ロジック
    // =========================================================================

    // 命令・データそれぞれのバス状態からストール条件を判定
    assign i_req      = 1'b1; // 常時フェッチ要求
    assign imem_stall = i_req && !i_hready;
    assign dmem_stall = d_req && !d_hready;

    // イネーブル（更新許可）制御
    // dmem_stall 発生時は最優先で全パイプラインを保持
    assign pc_en    = !dmem_stall && !imem_stall;
    assign if_id_en = !dmem_stall && !imem_stall;
    assign id_ex_en = !dmem_stall;

    // imem_stall 発生時（データウェイトは無し）は、デコード済みの空信号（NOP）をEXに挿入
    assign id_ex_flush = imem_stall && !dmem_stall;

    // =========================================================================
    // 3. IFステージ (Instruction Fetch)
    // =========================================================================

    assign i_haddr = pc;
    assign next_pc = pc + 32'd4; // ※分岐未実装時の単純インクリメント

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h0000_0000;
        end else if (pc_en) begin
            pc <= next_pc;
        end
    end

    // IF/ID パイプラインレジスタ更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc   <= 32'd0;
            if_id_inst <= 32'h0000_0013; // NOP (addi x0, x0, 0)
        end else if (if_id_en) begin
            if_id_pc   <= pc;
            if_id_inst <= i_hrdata;
        end
    end

    // =========================================================================
    // 4. IDステージ (Instruction Decode & Register Read)
    // =========================================================================

    assign opcode   = if_id_inst[6:0];
    assign rd_addr  = if_id_inst[11:7];   // ★正しいrd抽出位置 [11:7]
    assign funct3   = if_id_inst[14:12];
    assign rs1_addr = if_id_inst[19:15];
    assign rs2_addr = if_id_inst[24:20];

    // 即値生成 (Imm Gen)
    always_comb begin
        case (opcode)
            7'b0010011, // I-type (addi, etc)
            7'b0000011: // Load (lw, etc)
                imm = {{20{if_id_inst[31]}}, if_id_inst[31:20]};
            7'b0100011: // Store (sw, etc)
                imm = {{20{if_id_inst[31]}}, if_id_inst[31:25], if_id_inst[11:7]};
            default:
                imm = 32'd0;
        endcase
    end

    // デコード制御信号
    always_comb begin
        reg_write  = 1'b0;
        mem_to_reg = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        alu_op     = 3'b000; // 000: ADD

        case (opcode)
            7'b0010011: begin // OP-IMM (addi)
                reg_write = 1'b1;
            end
            7'b0110011: begin // OP (add)
                reg_write = 1'b1;
            end
            7'b0000011: begin // LOAD (lw)
                reg_write  = 1'b1;
                mem_to_reg = 1'b1;
                mem_read   = 1'b1;
            end
            7'b0100011: begin // STORE (sw)
                mem_write  = 1'b1;
            end
            default: ;
        endcase
    end

    // ID/EX パイプラインレジスタ更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || id_ex_flush) begin
            ex_pc          <= 32'd0;
            ex_rs1_data    <= 32'd0;
            ex_rs2_data    <= 32'd0;
            ex_imm         <= 32'd0;
            ex_rd_addr     <= 5'd0;
            ex_reg_write   <= 1'b0;
            ex_mem_to_reg  <= 1'b0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
            ex_alu_op      <= 3'b000;
        end else if (id_ex_en) begin
            ex_pc          <= if_id_pc;
            ex_rs1_data    <= (rs1_addr == 5'd0) ? 32'd0 : rf[rs1_addr];
            ex_rs2_data    <= (rs2_addr == 5'd0) ? 32'd0 : rf[rs2_addr];
            ex_imm         <= imm;
            ex_rd_addr     <= rd_addr;
            ex_reg_write   <= reg_write;
            ex_mem_to_reg  <= mem_to_reg;
            ex_mem_read    <= mem_read;
            ex_mem_write   <= mem_write;
            ex_alu_op      <= alu_op;
        end
    end

    // =========================================================================
    // 5. EX / MEM / WB ステージ (Execute & Memory & Writeback)
    // =========================================================================

    // ALU 演算処理
    logic [31:0] alu_in2;
    logic [31:0] alu_result;

    assign alu_in2    = (ex_mem_read || ex_mem_write || (ex_rd_addr != 0 && !ex_mem_to_reg && ex_imm != 0)) 
                         ? ex_imm : ex_rs2_data; // 簡易判定
    assign alu_result = ex_rs1_data + alu_in2;

    // データメモリ（AHB Bridge）へ指示
    assign d_req   = (ex_mem_read || ex_mem_write);
    assign d_haddr = alu_result;
    assign d_hwdata = ex_rs2_data;
    assign d_hwrite = ex_mem_write;

    // ライトバック用データの選択
    logic [31:0] rf_wdata;
    assign rf_wdata = ex_mem_to_reg ? d_hrdata : alu_result;

    // レジスタファイルへの書き込み（dmem_stall中以外かつhready完了時）
    always_ff @(posedge clk) begin
        if (ex_reg_write && (ex_rd_addr != 5'd0) && !dmem_stall) begin
            rf[ex_rd_addr] <= rf_wdata;
        end
    end

endmodule
