interface axi_if #(
  parameter int AXI_ADDR_W = 32,
  parameter int AXI_DATA_W = 128,
  parameter int AXI_ID_W   = 4
)(
  input logic aclk,
  input logic aresetn
);
  localparam int AXI_STRB_W = AXI_DATA_W/8;

  logic [AXI_ID_W-1:0]   awid;
  logic [AXI_ADDR_W-1:0] awaddr;
  logic [7:0]            awlen;
  logic [2:0]            awsize;
  logic [1:0]            awburst;
  logic                  awlock;
  logic [3:0]            awcache;
  logic [2:0]            awprot;
  logic [3:0]            awqos;
  logic                  awvalid;
  logic                  awready;

  logic [AXI_DATA_W-1:0] wdata;
  logic [AXI_STRB_W-1:0] wstrb;
  logic                  wlast;
  logic                  wvalid;
  logic                  wready;

  logic [AXI_ID_W-1:0]   bid;
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;

  logic [AXI_ID_W-1:0]   arid;
  logic [AXI_ADDR_W-1:0] araddr;
  logic [7:0]            arlen;
  logic [2:0]            arsize;
  logic [1:0]            arburst;
  logic                  arlock;
  logic [3:0]            arcache;
  logic [2:0]            arprot;
  logic [3:0]            arqos;
  logic                  arvalid;
  logic                  arready;

  logic [AXI_ID_W-1:0]   rid;
  logic [AXI_DATA_W-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rlast;
  logic                  rvalid;
  logic                  rready;

  modport master (
    output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
    output wdata, wstrb, wlast, wvalid,
    output bready,
    output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
    output rready,
    input  awready, wready, bid, bresp, bvalid, arready, rid, rdata, rresp, rlast, rvalid
  );

  modport slave (
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
    input  wdata, wstrb, wlast, wvalid,
    input  bready,
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
    input  rready,
    output awready, wready, bid, bresp, bvalid, arready, rid, rdata, rresp, rlast, rvalid
  );
endinterface
