module rv32i_ahb_bridge (
    // CPU Interface
    input  logic [31:0] cpu_imem_addr,
    output logic [31:0] cpu_imem_rdata,

    input  logic [31:0] cpu_dmem_addr,
    input  logic [31:0] cpu_dmem_wdata,
    output logic [31:0] cpu_dmem_rdata,
    input  logic        cpu_dmem_we,
    input  logic [3:0]  cpu_dmem_be,

    output logic        stall, // CPUへ出力するストール信号

    // AHB Master Interfaces
    ahb_if.master       ahb_i,
    ahb_if.master       ahb_d
);

    localparam HTRANS_IDLE   = 2'b00;
    localparam HTRANS_NONSEQ = 2'b10;

    // 命令バス側またはデータバス側のいずれかがウェイト中であれば CPU をストール
    assign stall = (!ahb_i.hready) || (dmem_req && !ahb_d.hready);

    // Instruction Bus
    assign ahb_i.haddr  = cpu_imem_addr;
    assign ahb_i.htrans = HTRANS_NONSEQ;
    assign ahb_i.hwrite = 1'b0;
    assign ahb_i.hwdata = 32'd0;

    assign cpu_imem_rdata = ahb_i.hrdata;

    // Data Bus
    logic dmem_req;
    assign dmem_req = cpu_dmem_we || (cpu_dmem_be != 4'b0000);

    assign ahb_d.haddr  = cpu_dmem_addr;
    assign ahb_d.htrans = dmem_req ? HTRANS_NONSEQ : HTRANS_IDLE;
    assign ahb_d.hwrite = cpu_dmem_we;

    logic [31:0] aligned_wdata;
    always_comb begin
        case (cpu_dmem_be)
            4'b0001: aligned_wdata = {4{cpu_dmem_wdata[7:0]}};
            4'b0010: aligned_wdata = {2{cpu_dmem_wdata[7:0], 8'd0}};
            4'b0100: aligned_wdata = {2{8'd0, cpu_dmem_wdata[7:0]}};
            4'b1000: aligned_wdata = {cpu_dmem_wdata[7:0], 24'd0};
            4'b0011: aligned_wdata = {2{cpu_dmem_wdata[15:0]}};
            4'b1100: aligned_wdata = {cpu_dmem_wdata[15:0], 16'd0};
            default: aligned_wdata = cpu_dmem_wdata;
        endcase
    end

    logic [31:0] hwdata_reg;
    always_ff @(posedge ahb_d.HCLK or negedge ahb_d.HRESETn) begin
        if (!ahb_d.HRESETn) begin
            hwdata_reg <= 32'd0;
        end else if (ahb_d.hready) begin
            hwdata_reg <= aligned_wdata;
        end
    end

    assign ahb_d.hwdata   = hwdata_reg;
    assign cpu_dmem_rdata = ahb_d.hrdata;

endmodule
