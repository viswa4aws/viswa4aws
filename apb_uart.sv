module apb_uart #(
  parameter int CLK_HZ       = 50_000_000,
  parameter int BAUD_DEFAULT = 115200,
  parameter int FIFO_DEPTH   = 16
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
  apb_uart_top #(
    .CLK_HZ(CLK_HZ),
    .BAUD_DEFAULT(BAUD_DEFAULT),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) u_top (
    .pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable), .pwrite(pwrite),
    .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .uart_rx(uart_rx), .uart_tx(uart_tx), .cts_i(cts_i), .rts_o(rts_o), .irq(irq)
  );
endmodule
