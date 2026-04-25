module uart_ctrl_apb #(
  parameter int CLK_HZ       = 50_000_000,
  parameter int BAUD_DEFAULT = 115200,
  parameter int FIFO_DEPTH   = 16,
  parameter int FIFO_LVL_W   = (FIFO_DEPTH <= 2) ? 2 : ($clog2(FIFO_DEPTH)+1)
) (
  input  logic                   pclk,
  input  logic                   presetn,
  input  logic                   psel,
  input  logic                   penable,
  input  logic                   pwrite,
  input  logic [7:0]             paddr,
  input  logic [31:0]            pwdata,
  output logic [31:0]            prdata,
  output logic                   pready,
  output logic                   pslverr,

  input  logic                   cts_i,
  input  logic                   rts_o,
  input  logic                   tx_fifo_full,
  input  logic                   tx_fifo_empty,
  input  logic                   rx_fifo_full,
  input  logic                   rx_fifo_empty,
  input  logic [FIFO_LVL_W-1:0]  tx_level,
  input  logic [FIFO_LVL_W-1:0]  rx_level,
  input  logic [7:0]             rx_fifo_rdata,

  output logic                   uart_en,
  output logic                   tx_en,
  output logic                   rx_en,
  output logic                   irq_en,
  output logic [15:0]            baud_div,
  output logic                   tx_fifo_wr,
  output logic [7:0]             tx_fifo_wdata,
  output logic                   rx_fifo_rd,
  output logic                   irq
);
  localparam logic [7:0] ADDR_DATA   = 8'h00;
  localparam logic [7:0] ADDR_STATUS = 8'h04;
  localparam logic [7:0] ADDR_CTRL   = 8'h08;
  localparam logic [7:0] ADDR_BAUD   = 8'h0C;

  wire apb_wr = psel && penable && pwrite;
  wire apb_rd = psel && penable && !pwrite;

  assign pready      = 1'b1;
  assign pslverr     = 1'b0;
  assign tx_fifo_wdata = pwdata[7:0];

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      uart_en  <= 1'b1;
      tx_en    <= 1'b1;
      rx_en    <= 1'b1;
      irq_en   <= 1'b0;
      baud_div <= CLK_HZ / BAUD_DEFAULT;
    end else if (apb_wr) begin
      case (paddr)
        ADDR_CTRL: begin
          uart_en <= pwdata[0];
          tx_en   <= pwdata[1];
          rx_en   <= pwdata[2];
          irq_en  <= pwdata[3];
        end
        ADDR_BAUD: if (pwdata[15:0] != 16'd0) baud_div <= pwdata[15:0];
        default: ;
      endcase
    end
  end

  assign tx_fifo_wr = apb_wr && (paddr == ADDR_DATA) && !tx_fifo_full;
  assign rx_fifo_rd = apb_rd && (paddr == ADDR_DATA) && !rx_fifo_empty;

  always_comb begin
    prdata = 32'h0;
    case (paddr)
      ADDR_DATA:   prdata = {24'h0, rx_fifo_rdata};
      ADDR_STATUS: begin
        prdata[0]     = tx_fifo_full;
        prdata[1]     = tx_fifo_empty;
        prdata[2]     = rx_fifo_full;
        prdata[3]     = rx_fifo_empty;
        prdata[4]     = cts_i;
        prdata[5]     = rts_o;
        prdata[15:8]  = tx_level[7:0];
        prdata[23:16] = rx_level[7:0];
      end
      ADDR_CTRL: prdata = {28'h0, irq_en, rx_en, tx_en, uart_en};
      ADDR_BAUD: prdata = {16'h0, baud_div};
      default:   prdata = 32'h0;
    endcase
  end

  assign irq = irq_en && (!rx_fifo_empty || rx_fifo_full || tx_fifo_full);
endmodule
