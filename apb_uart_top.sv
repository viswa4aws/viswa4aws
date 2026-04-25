module apb_uart_top #(
  parameter int CLK_HZ       = 50_000_000,
  parameter int BAUD_DEFAULT = 115200,
  parameter int FIFO_DEPTH   = 16,
  parameter int FIFO_ADDR_W  = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH),
  parameter int FIFO_LVL_W   = (FIFO_DEPTH <= 2) ? 2 : ($clog2(FIFO_DEPTH)+1)
) (
  input  logic        pclk,
  input  logic        presetn,
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [7:0]  paddr,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  input  logic        uart_rx,
  output logic        uart_tx,
  input  logic        cts_i,
  output logic        rts_o,

  output logic        irq
);
  logic uart_en, tx_en, rx_en, irq_en;
  logic [15:0] baud_div;

  logic tx_fifo_wr, tx_fifo_rd, rx_fifo_wr, rx_fifo_rd;
  logic [7:0] tx_fifo_wdata, tx_fifo_rdata;
  logic [7:0] rx_fifo_wdata, rx_fifo_rdata;
  logic tx_fifo_full, tx_fifo_empty, rx_fifo_full, rx_fifo_empty;
  logic [FIFO_LVL_W-1:0] tx_level, rx_level;

  logic [15:0] baud_cnt;
  logic baud_tick;

  logic tx_busy;
  logic rx_valid;

  // APB control/register block
  uart_ctrl_apb #(
    .CLK_HZ(CLK_HZ),
    .BAUD_DEFAULT(BAUD_DEFAULT),
    .FIFO_DEPTH(FIFO_DEPTH),
    .FIFO_LVL_W(FIFO_LVL_W)
  ) u_ctrl (
    .pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable), .pwrite(pwrite),
    .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .cts_i(cts_i), .rts_o(rts_o),
    .tx_fifo_full(tx_fifo_full), .tx_fifo_empty(tx_fifo_empty),
    .rx_fifo_full(rx_fifo_full), .rx_fifo_empty(rx_fifo_empty),
    .tx_level(tx_level), .rx_level(rx_level), .rx_fifo_rdata(rx_fifo_rdata),
    .uart_en(uart_en), .tx_en(tx_en), .rx_en(rx_en), .irq_en(irq_en),
    .baud_div(baud_div), .tx_fifo_wr(tx_fifo_wr), .tx_fifo_wdata(tx_fifo_wdata), .rx_fifo_rd(rx_fifo_rd),
    .irq(irq)
  );

  // TX FIFO external module
  uart_fifo #(
    .WIDTH(8),
    .DEPTH(FIFO_DEPTH),
    .ADDR_W(FIFO_ADDR_W)
  ) u_tx_fifo (
    .clk(pclk), .rst_n(presetn),
    .wr_en(tx_fifo_wr), .wr_data(tx_fifo_wdata),
    .rd_en(tx_fifo_rd), .rd_data(tx_fifo_rdata),
    .full(tx_fifo_full), .empty(tx_fifo_empty), .level(tx_level)
  );

  // RX FIFO external module
  uart_fifo #(
    .WIDTH(8),
    .DEPTH(FIFO_DEPTH),
    .ADDR_W(FIFO_ADDR_W)
  ) u_rx_fifo (
    .clk(pclk), .rst_n(presetn),
    .wr_en(rx_fifo_wr), .wr_data(rx_fifo_wdata),
    .rd_en(rx_fifo_rd), .rd_data(rx_fifo_rdata),
    .full(rx_fifo_full), .empty(rx_fifo_empty), .level(rx_level)
  );

  assign rts_o = (rx_level < (FIFO_DEPTH-2));

  // Shared baud generator
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      baud_cnt  <= 16'd0;
      baud_tick <= 1'b0;
    end else if (!uart_en) begin
      baud_cnt  <= 16'd0;
      baud_tick <= 1'b0;
    end else if (baud_cnt == (baud_div - 1'b1)) begin
      baud_cnt  <= 16'd0;
      baud_tick <= 1'b1;
    end else begin
      baud_cnt  <= baud_cnt + 1'b1;
      baud_tick <= 1'b0;
    end
  end

  // UART TX submodule
  uart_tx u_tx (
    .clk(pclk), .rst_n(presetn), .en(uart_en && tx_en), .baud_tick(baud_tick),
    .cts_i(cts_i), .tx_fifo_empty(tx_fifo_empty), .tx_fifo_rdata(tx_fifo_rdata),
    .tx_fifo_rd(tx_fifo_rd), .uart_tx(uart_tx), .busy(tx_busy)
  );

  // UART RX submodule
  uart_rx u_rx (
    .clk(pclk), .rst_n(presetn), .en(uart_en && rx_en), .baud_tick(baud_tick),
    .uart_rx(uart_rx), .rx_data(rx_fifo_wdata), .rx_valid(rx_valid)
  );

  assign rx_fifo_wr = rx_valid && !rx_fifo_full;

endmodule
