module rv32i_3stage_cpu (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,      // AHBウェイト用ストール信号

    // 命令メモリ インターフェース
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // データメモリ インターフェース
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    output logic        dmem_we,
    output logic [3:0]  dmem_be
);

    // =========================================================================
    // 1. IF Stage (Instruction Fetch)
    // =========================================================================
    logic [31:0] pc, pc_next;
    logic        flush_if_ex;

    // 分岐/ジャンプ信号 (EXステージからフィードバック)
    logic        ex_take_branch;
    logic [31:0] ex_target_pc;

    always_comb begin
        if (ex_take_branch) begin
            pc_next = ex_target_pc;
        end else begin
            pc_next = pc + 32'd4;
        end
    end

    // stall 時は PC の更新をブロック
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h0000_0000;
        end else if (!stall) begin
            pc <= pc_next;
        end
    end

    assign imem_addr   = pc;
    assign flush_if_ex = ex_take_branch;

    // IF/EX パイプラインレジスタ
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] inst;
    } if_ex_reg_t;

    if_ex_reg_t if_ex;

    // stall 時は IF/EX レジスタの値を保持
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_ex.pc   <= 32'h0000_0000;
            if_ex.inst <= 32'h0000_0013; // NOP (addi x0, x0, 0)
        end else if (!stall) begin
            if (flush_if_ex) begin
                if_ex.pc   <= 32'h0000_0000;
                if_ex.inst <= 32'h0000_0013; // NOP
            end else begin
                if_ex.pc   <= pc;
                if_ex.inst <= imem_rdata;
            end
        end
    end

    // =========================================================================
    // 2. EX Stage (Decode / Execute)
    // =========================================================================
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

    assign opcode   = if_ex.inst[6:0];
    assign funct3   = if_ex.inst[14:12];
    assign funct7   = if_ex.inst[31:25];
    assign rs1_addr = if_ex.inst[19:15];
    assign rs2_addr = if_ex.inst[24:20];
    assign rd_addr  = if_ex.inst[11:7];

    // 即値生成
    assign imm_i = {{20{if_ex.inst[31]}}, if_ex.inst[31:20]};
    assign imm_s = {{20{if_ex.inst[31]}}, if_ex.inst[31:25], if_ex.inst[11:7]};
    assign imm_b = {{19{if_ex.inst[31]}}, if_ex.inst[31], if_ex.inst[7], if_ex.inst[30:25], if_ex.inst[11:8], 1'b0};
    assign imm_u = {if_ex.inst[31:12], 12'b0};
    assign imm_j = {{11{if_ex.inst[31]}}, if_ex.inst[31], if_ex.inst[19:12], if_ex.inst[20], if_ex.inst[30:21], 1'b0};

    // レジスタファイル
    logic [31:0] rf [31:0];
    logic [31:0] rf_rs1_data, rf_rs2_data;

    assign rf_rs1_data = (rs1_addr == 5'd0) ? 32'd0 : rf[rs1_addr];
    assign rf_rs2_data = (rs2_addr == 5'd0) ? 32'd0 : rf[rs2_addr];

    // フォワーディング
    logic [31:0] ex_rs1_data, ex_rs2_data;
    logic [31:0] wb_final_data;
    logic        ex_wb_reg_write;
    logic [4:0]  ex_wb_rd_addr;

    always_comb begin
        if (ex_wb_reg_write && (ex_wb_rd_addr != 0) && (ex_wb_rd_addr == rs1_addr))
            ex_rs1_data = wb_final_data;
        else
            ex_rs1_data = rf_rs1_data;

        if (ex_wb_reg_write && (ex_wb_rd_addr != 0) && (ex_wb_rd_addr == rs2_addr))
            ex_rs2_data = wb_final_data;
        else
            ex_rs2_data = rf_rs2_data;
    end

    // ALU
    logic [31:0] alu_operand_a, alu_operand_b;
    logic [31:0] alu_result;

    always_comb begin
        case (opcode)
            7'b0110111: alu_operand_a = 32'd0;       // LUI
            7'b0010111: alu_operand_a = if_ex.pc;    // AUIPC
            default:    alu_operand_a = ex_rs1_data;
        endcase
    end

    always_comb begin
        case (opcode)
            7'b0010011, 7'b0000011, 7'b0110111, 7'b0010111: alu_operand_b = imm_i; // OP-IMM, Load, LUI, AUIPC
            7'b0100011: alu_operand_b = imm_s;                                    // Store
            default:    alu_operand_b = ex_rs2_data;                              // OP, Branch
        endcase
    end

    always_comb begin
        case (opcode)
            7'b0110111, 7'b0010111: alu_result = alu_operand_a + alu_operand_b; // LUI, AUIPC
            7'b0010011, 7'b0110011: begin
                case (funct3)
                    3'b000: alu_result = (opcode == 7'b0110011 && funct7[5]) ? (alu_operand_a - alu_operand_b) : (alu_operand_a + alu_operand_b);
                    3'b001: alu_result = alu_operand_a << alu_operand_b[4:0];
                    3'b010: alu_result = ($signed(alu_operand_a) < $signed(alu_operand_b)) ? 32'd1 : 32'd0;
                    3'b011: alu_result = (alu_operand_a < alu_operand_b) ? 32'd1 : 32'd0;
                    3'b100: alu_result = alu_operand_a ^ alu_operand_b;
                    3'b101: alu_result = funct7[5] ? ($signed(alu_operand_a) >>> alu_operand_b[4:0]) : (alu_operand_a >> alu_operand_b[4:0]);
                    3'b110: alu_result = alu_operand_a | alu_operand_b;
                    3'b111: alu_result = alu_operand_a & alu_operand_b;
                endcase
            end
            7'b0000011, 7'b0100011: alu_result = alu_operand_a + alu_operand_b; // Load/Store address
            default: alu_result = 32'd0;
        endcase
    end

    // 分岐制御
    always_comb begin
        ex_take_branch = 1'b0;
        ex_target_pc   = 32'd0;
        case (opcode)
            7'b1101111: begin
                ex_take_branch = 1'b1;
                ex_target_pc   = if_ex.pc + imm_j;
            end
            7'b1100111: begin
                ex_take_branch = 1'b1;
                ex_target_pc   = (ex_rs1_data + imm_i) & ~32'd1;
            end
            7'b1100011: begin
                ex_target_pc = if_ex.pc + imm_b;
                case (funct3)
                    3'b000: ex_take_branch = (ex_rs1_data == ex_rs2_data);                  // BEQ
                    3'b001: ex_take_branch = (ex_rs1_data != ex_rs2_data);                  // BNE
                    3'b100: ex_take_branch = ($signed(ex_rs1_data) < $signed(ex_rs2_data)); // BLT
                    3'b101: ex_take_branch = ($signed(ex_rs1_data) >= $signed(ex_rs2_data));// BGE
                    3'b110: ex_take_branch = (ex_rs1_data < ex_rs2_data);                   // BLTU
                    3'b111: ex_take_branch = (ex_rs1_data >= ex_rs2_data);                  // BGEU
                    default: ex_take_branch = 1'b0;
                endcase
            end
            default: begin
                ex_take_branch = 1'b0;
                ex_target_pc   = 32'd0;
            end
        endcase
    end

    // データメモリインターフェース
    assign dmem_addr  = alu_result;
    assign dmem_wdata = ex_rs2_data;
    assign dmem_we    = (opcode == 7'b0100011);

    always_comb begin
        if (opcode == 7'b0100011) begin
            case (funct3[1:0])
                2'b00: dmem_be = 4'b0001 << alu_result[1:0]; // SB
                2'b01: dmem_be = 4'b0011 << alu_result[1:0]; // SH
                2'b10: dmem_be = 4'b1111;                    // SW
                default: dmem_be = 4'b0000;
            endcase
        end else begin
            dmem_be = 4'b0000;
        end
    end

    // EX/WB パイプラインレジスタ
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] alu_result;
        logic [4:0]  rd_addr;
        logic [6:0]  opcode;
        logic [2:0]  funct3;
        logic        reg_write;
    } ex_wb_reg_t;

    ex_wb_reg_t ex_wb;

    logic reg_write_candidate;
    assign reg_write_candidate = (opcode == 7'b0110011) || (opcode == 7'b0010011) ||
                                 (opcode == 7'b0000011) || (opcode == 7'b0110111) ||
                                 (opcode == 7'b0010111) || (opcode == 7'b1101111) ||
                                 (opcode == 7'b1100111);

    // stall 時は EX/WB レジスタの更新を抑制
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_wb.pc         <= 32'd0;
            ex_wb.alu_result <= 32'd0;
            ex_wb.rd_addr    <= 5'd0;
            ex_wb.opcode     <= 7'd0;
            ex_wb.funct3     <= 3'd0;
            ex_wb.reg_write  <= 1'b0;
        end else if (!stall) begin
            ex_wb.pc         <= if_ex.pc;
            ex_wb.alu_result <= alu_result;
            ex_wb.rd_addr    <= rd_addr;
            ex_wb.opcode     <= opcode;
            ex_wb.funct3     <= funct3;
            ex_wb.reg_write  <= reg_write_candidate;
        end
    end

    assign ex_wb_reg_write = ex_wb.reg_write;
    assign ex_wb_rd_addr   = ex_wb.rd_addr;

    // =========================================================================
    // 3. WB Stage (Write Back)
    // =========================================================================
    logic [31:0] load_data;

    always_comb begin
        case (ex_wb.funct3)
            3'b000: begin // LB
                case (ex_wb.alu_result[1:0])
                    2'b00: load_data = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
                    2'b01: load_data = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                    2'b10: load_data = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                    2'b11: load_data = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (ex_wb.alu_result[1])
                    1'b0: load_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
                    1'b1: load_data = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                endcase
            end
            3'b010: load_data = dmem_rdata; // LW
            3'b100: begin // LBU
                case (ex_wb.alu_result[1:0])
                    2'b00: load_data = {24'd0, dmem_rdata[7:0]};
                    2'b01: load_data = {24'd0, dmem_rdata[15:8]};
                    2'b10: load_data = {24'd0, dmem_rdata[23:16]};
                    2'b11: load_data = {24'd0, dmem_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (ex_wb.alu_result[1])
                    1'b0: load_data = {16'd0, dmem_rdata[15:0]};
                    1'b1: load_data = {16'd0, dmem_rdata[31:16]};
                endcase
            end
            default: load_data = dmem_rdata;
        endcase
    end

    always_comb begin
        if (ex_wb.opcode == 7'b0000011) begin
            wb_final_data = load_data;               // LOAD
        end else if (ex_wb.opcode == 7'b1101111 || ex_wb.opcode == 7'b1100111) begin
            wb_final_data = ex_wb.pc + 32'd4;        // JAL / JALR (戻りアドレス)
        end else begin
            wb_final_data = ex_wb.alu_result;        // ALU演算 / LUI / AUIPC
        end
    end

    // stall 時はレジスタ書き込みも抑制
    always_ff @(posedge clk) begin
        if (!stall && ex_wb.reg_write && (ex_wb.rd_addr != 5'd0)) begin
            rf[ex_wb.rd_addr] <= wb_final_data;
        end
    end

endmodule
