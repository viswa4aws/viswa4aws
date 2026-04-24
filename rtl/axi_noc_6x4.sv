`include "axi_if.sv"

module axi_noc_6x4 #(
  parameter int AXI_ADDR_W = 32,
  parameter int AXI_DATA_W = 128,
  parameter int AXI_ID_W   = 4,
  parameter logic [AXI_ADDR_W-1:0] S0_BASE = 32'h0000_0000,
  parameter logic [AXI_ADDR_W-1:0] S0_MASK = 32'hF000_0000,
  parameter logic [AXI_ADDR_W-1:0] S1_BASE = 32'h1000_0000,
  parameter logic [AXI_ADDR_W-1:0] S1_MASK = 32'hF000_0000,
  parameter logic [AXI_ADDR_W-1:0] S2_BASE = 32'h2000_0000,
  parameter logic [AXI_ADDR_W-1:0] S2_MASK = 32'hF000_0000,
  parameter logic [AXI_ADDR_W-1:0] S3_BASE = 32'h3000_0000,
  parameter logic [AXI_ADDR_W-1:0] S3_MASK = 32'hF000_0000
)(
  input logic aclk,
  input logic aresetn,
  axi_if.slave  m_axi [6],
  axi_if.master s_axi [4]
);
  localparam int M = 6;
  localparam int S = 4;

  logic [S-1:0] aw_req [M-1:0];
  logic [S-1:0] ar_req [M-1:0];
  logic [M-1:0] aw_grant [S-1:0];
  logic [M-1:0] ar_grant [S-1:0];
  logic [M-1:0] aw_gnt_valid;
  logic [M-1:0] ar_gnt_valid;
  logic [$clog2(M)-1:0] aw_sel [S-1:0];
  logic [$clog2(M)-1:0] ar_sel [S-1:0];

  function automatic logic [S-1:0] decode_addr(input logic [AXI_ADDR_W-1:0] addr);
    logic [S-1:0] hit;
    begin
      hit[0] = ((addr & S0_MASK) == S0_BASE);
      hit[1] = ((addr & S1_MASK) == S1_BASE);
      hit[2] = ((addr & S2_MASK) == S2_BASE);
      hit[3] = ((addr & S3_MASK) == S3_BASE);
      decode_addr = hit;
    end
  endfunction

  genvar i, j;
  generate
    for (i = 0; i < M; i++) begin : GEN_DECODE
      always_comb begin
        aw_req[i] = decode_addr(m_axi[i].awaddr) & {S{m_axi[i].awvalid}};
        ar_req[i] = decode_addr(m_axi[i].araddr) & {S{m_axi[i].arvalid}};
      end
    end

    for (j = 0; j < S; j++) begin : GEN_ARB
      logic [M-1:0] aw_req_j;
      logic [M-1:0] ar_req_j;
      always_comb begin
        for (int k = 0; k < M; k++) begin
          aw_req_j[k] = aw_req[k][j];
          ar_req_j[k] = ar_req[k][j];
        end
      end

      rr_arbiter #(.N(M)) u_aw_arb (
        .clk(aclk),
        .rst_n(aresetn),
        .req(aw_req_j),
        .grant_accept(s_axi[j].awready),
        .grant(aw_grant[j]),
        .grant_valid(aw_gnt_valid[j]),
        .grant_idx(aw_sel[j])
      );

      rr_arbiter #(.N(M)) u_ar_arb (
        .clk(aclk),
        .rst_n(aresetn),
        .req(ar_req_j),
        .grant_accept(s_axi[j].arready),
        .grant(ar_grant[j]),
        .grant_valid(ar_gnt_valid[j]),
        .grant_idx(ar_sel[j])
      );
    end
  endgenerate

  always_comb begin
    for (int m = 0; m < M; m++) begin
      m_axi[m].awready = 1'b0;
      m_axi[m].wready  = 1'b0;
      m_axi[m].bid     = '0;
      m_axi[m].bresp   = 2'b00;
      m_axi[m].bvalid  = 1'b0;
      m_axi[m].arready = 1'b0;
      m_axi[m].rid     = '0;
      m_axi[m].rdata   = '0;
      m_axi[m].rresp   = 2'b00;
      m_axi[m].rlast   = 1'b0;
      m_axi[m].rvalid  = 1'b0;
    end

    for (int s = 0; s < S; s++) begin
      s_axi[s].awid    = '0;
      s_axi[s].awaddr  = '0;
      s_axi[s].awlen   = '0;
      s_axi[s].awsize  = '0;
      s_axi[s].awburst = '0;
      s_axi[s].awlock  = 1'b0;
      s_axi[s].awcache = '0;
      s_axi[s].awprot  = '0;
      s_axi[s].awqos   = '0;
      s_axi[s].awvalid = 1'b0;
      s_axi[s].wdata   = '0;
      s_axi[s].wstrb   = '0;
      s_axi[s].wlast   = 1'b0;
      s_axi[s].wvalid  = 1'b0;
      s_axi[s].bready  = 1'b0;
      s_axi[s].arid    = '0;
      s_axi[s].araddr  = '0;
      s_axi[s].arlen   = '0;
      s_axi[s].arsize  = '0;
      s_axi[s].arburst = '0;
      s_axi[s].arlock  = 1'b0;
      s_axi[s].arcache = '0;
      s_axi[s].arprot  = '0;
      s_axi[s].arqos   = '0;
      s_axi[s].arvalid = 1'b0;
      s_axi[s].rready  = 1'b0;

      if (aw_gnt_valid[s]) begin
        s_axi[s].awid    = m_axi[aw_sel[s]].awid;
        s_axi[s].awaddr  = m_axi[aw_sel[s]].awaddr;
        s_axi[s].awlen   = m_axi[aw_sel[s]].awlen;
        s_axi[s].awsize  = m_axi[aw_sel[s]].awsize;
        s_axi[s].awburst = m_axi[aw_sel[s]].awburst;
        s_axi[s].awlock  = m_axi[aw_sel[s]].awlock;
        s_axi[s].awcache = m_axi[aw_sel[s]].awcache;
        s_axi[s].awprot  = m_axi[aw_sel[s]].awprot;
        s_axi[s].awqos   = m_axi[aw_sel[s]].awqos;
        s_axi[s].awvalid = m_axi[aw_sel[s]].awvalid;

        s_axi[s].wdata   = m_axi[aw_sel[s]].wdata;
        s_axi[s].wstrb   = m_axi[aw_sel[s]].wstrb;
        s_axi[s].wlast   = m_axi[aw_sel[s]].wlast;
        s_axi[s].wvalid  = m_axi[aw_sel[s]].wvalid;
        s_axi[s].bready  = m_axi[aw_sel[s]].bready;

        m_axi[aw_sel[s]].awready = s_axi[s].awready;
        m_axi[aw_sel[s]].wready  = s_axi[s].wready;
        m_axi[aw_sel[s]].bid     = s_axi[s].bid;
        m_axi[aw_sel[s]].bresp   = s_axi[s].bresp;
        m_axi[aw_sel[s]].bvalid  = s_axi[s].bvalid;
      end

      if (ar_gnt_valid[s]) begin
        s_axi[s].arid    = m_axi[ar_sel[s]].arid;
        s_axi[s].araddr  = m_axi[ar_sel[s]].araddr;
        s_axi[s].arlen   = m_axi[ar_sel[s]].arlen;
        s_axi[s].arsize  = m_axi[ar_sel[s]].arsize;
        s_axi[s].arburst = m_axi[ar_sel[s]].arburst;
        s_axi[s].arlock  = m_axi[ar_sel[s]].arlock;
        s_axi[s].arcache = m_axi[ar_sel[s]].arcache;
        s_axi[s].arprot  = m_axi[ar_sel[s]].arprot;
        s_axi[s].arqos   = m_axi[ar_sel[s]].arqos;
        s_axi[s].arvalid = m_axi[ar_sel[s]].arvalid;
        s_axi[s].rready  = m_axi[ar_sel[s]].rready;

        m_axi[ar_sel[s]].arready = s_axi[s].arready;
        m_axi[ar_sel[s]].rid     = s_axi[s].rid;
        m_axi[ar_sel[s]].rdata   = s_axi[s].rdata;
        m_axi[ar_sel[s]].rresp   = s_axi[s].rresp;
        m_axi[ar_sel[s]].rlast   = s_axi[s].rlast;
        m_axi[ar_sel[s]].rvalid  = s_axi[s].rvalid;
      end
    end
  end
endmodule
