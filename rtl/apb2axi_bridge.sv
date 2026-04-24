module apb2axi_bridge #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int STRB_WIDTH = DATA_WIDTH/8
) (
  input  logic                     pclk,
  input  logic                     presetn,

  // APB slave side
  input  logic                     psel,
  input  logic                     penable,
  input  logic                     pwrite,
  input  logic [ADDR_WIDTH-1:0]    paddr,
  input  logic [DATA_WIDTH-1:0]    pwdata,
  input  logic [STRB_WIDTH-1:0]    pstrb,
  output logic [DATA_WIDTH-1:0]    prdata,
  output logic                     pready,
  output logic                     pslverr,

  // AXI4-Lite master side
  output logic [ADDR_WIDTH-1:0]    m_axi_awaddr,
  output logic [2:0]               m_axi_awprot,
  output logic                     m_axi_awvalid,
  input  logic                     m_axi_awready,

  output logic [DATA_WIDTH-1:0]    m_axi_wdata,
  output logic [STRB_WIDTH-1:0]    m_axi_wstrb,
  output logic                     m_axi_wvalid,
  input  logic                     m_axi_wready,

  input  logic [1:0]               m_axi_bresp,
  input  logic                     m_axi_bvalid,
  output logic                     m_axi_bready,

  output logic [ADDR_WIDTH-1:0]    m_axi_araddr,
  output logic [2:0]               m_axi_arprot,
  output logic                     m_axi_arvalid,
  input  logic                     m_axi_arready,

  input  logic [DATA_WIDTH-1:0]    m_axi_rdata,
  input  logic [1:0]               m_axi_rresp,
  input  logic                     m_axi_rvalid,
  output logic                     m_axi_rready
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_WR_ADDR,
    S_WR_RESP,
    S_RD_ADDR,
    S_RD_DATA,
    S_APB_RESP
  } state_t;

  state_t state_q, state_d;

  logic [ADDR_WIDTH-1:0] apb_addr_q;
  logic [DATA_WIDTH-1:0] apb_wdata_q;
  logic [STRB_WIDTH-1:0] apb_strb_q;
  logic                  apb_write_q;
  logic [DATA_WIDTH-1:0] apb_rdata_q;
  logic                  apb_slverr_q;

  logic aw_done_q, w_done_q;

  wire apb_setup = psel && !penable;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      state_q      <= S_IDLE;
      apb_addr_q   <= '0;
      apb_wdata_q  <= '0;
      apb_strb_q   <= '0;
      apb_write_q  <= 1'b0;
      apb_rdata_q  <= '0;
      apb_slverr_q <= 1'b0;
      aw_done_q    <= 1'b0;
      w_done_q     <= 1'b0;
    end else begin
      state_q <= state_d;

      if (apb_setup && state_q == S_IDLE) begin
        apb_addr_q  <= paddr;
        apb_wdata_q <= pwdata;
        apb_strb_q  <= pstrb;
        apb_write_q <= pwrite;
      end

      if (state_q == S_WR_ADDR) begin
        if (m_axi_awvalid && m_axi_awready) aw_done_q <= 1'b1;
        if (m_axi_wvalid  && m_axi_wready)  w_done_q  <= 1'b1;
      end else begin
        aw_done_q <= 1'b0;
        w_done_q  <= 1'b0;
      end

      if (state_q == S_WR_RESP && m_axi_bvalid && m_axi_bready) begin
        apb_slverr_q <= (m_axi_bresp != 2'b00);
      end

      if (state_q == S_RD_DATA && m_axi_rvalid && m_axi_rready) begin
        apb_rdata_q  <= m_axi_rdata;
        apb_slverr_q <= (m_axi_rresp != 2'b00);
      end

      if (state_q == S_IDLE) begin
        apb_slverr_q <= 1'b0;
      end
    end
  end

  always_comb begin
    state_d = state_q;

    pready  = 1'b0;
    pslverr = 1'b0;
    prdata  = apb_rdata_q;

    m_axi_awaddr  = apb_addr_q;
    m_axi_awprot  = 3'b000;
    m_axi_awvalid = 1'b0;

    m_axi_wdata   = apb_wdata_q;
    m_axi_wstrb   = apb_strb_q;
    m_axi_wvalid  = 1'b0;

    m_axi_bready  = 1'b0;

    m_axi_araddr  = apb_addr_q;
    m_axi_arprot  = 3'b000;
    m_axi_arvalid = 1'b0;

    m_axi_rready  = 1'b0;

    case (state_q)
      S_IDLE: begin
        if (apb_setup) begin
          if (pwrite) state_d = S_WR_ADDR;
          else        state_d = S_RD_ADDR;
        end
      end

      S_WR_ADDR: begin
        m_axi_awvalid = !aw_done_q;
        m_axi_wvalid  = !w_done_q;
        if ((aw_done_q || (m_axi_awvalid && m_axi_awready)) &&
            (w_done_q  || (m_axi_wvalid  && m_axi_wready))) begin
          state_d = S_WR_RESP;
        end
      end

      S_WR_RESP: begin
        m_axi_bready = 1'b1;
        if (m_axi_bvalid) begin
          state_d = S_APB_RESP;
        end
      end

      S_RD_ADDR: begin
        m_axi_arvalid = 1'b1;
        if (m_axi_arready) begin
          state_d = S_RD_DATA;
        end
      end

      S_RD_DATA: begin
        m_axi_rready = 1'b1;
        if (m_axi_rvalid) begin
          state_d = S_APB_RESP;
        end
      end

      S_APB_RESP: begin
        pready  = 1'b1;
        pslverr = apb_slverr_q;
        if (!psel) begin
          state_d = S_IDLE;
        end
      end

      default: state_d = S_IDLE;
    endcase
  end

endmodule
