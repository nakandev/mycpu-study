interface ahb_if (input logic HCLK, input logic HRESETn);
    logic [31:0] haddr;
    logic [1:0]  htrans;
    logic        hwrite;
    logic [31:0] hwdata;
    logic [31:0] hrdata;
    logic        hready;
    logic        hresp;
    logic        hsel;

    modport master (
        input  HCLK, HRESETn,
        output haddr, htrans, hwrite, hwdata,
        input  hrdata, hready, hresp
    );

    modport slave (
        input  HCLK, HRESETn,
        input  haddr, htrans, hwrite, hwdata, hsel,
        output hrdata, hready, hresp
    );
endinterface
