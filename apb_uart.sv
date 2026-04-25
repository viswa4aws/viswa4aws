module sync_fifo #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16,
  localparam int ADDR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             full,
  output logic             empty,
  output logic [ADDR_W:0]  level
);
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] wptr, rptr;
  logic [ADDR_W:0]   count;

  assign full   = (count == DEPTH);
  assign empty  = (count == 0);
  assign level  = count;
  assign rd_data = mem[rptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr  <= '0;
      rptr  <= '0;
      count <= '0;
    end else begin
      case ({wr_en && !full, rd_en && !empty})
        2'b10: begin
          mem[wptr] <= wr_data;
          wptr      <= (wptr == DEPTH-1) ? '0 : (wptr + 1'b1);
          count     <= count + 1'b1;
        end
        2'b01: begin
          rptr      <= (rptr == DEPTH-1) ? '0 : (rptr + 1'b1);
          count     <= count - 1'b1;
        end
        2'b11: begin
          mem[wptr] <= wr_data;
          wptr      <= (wptr == DEPTH-1) ? '0 : (wptr + 1'b1);
          rptr      <= (rptr == DEPTH-1) ? '0 : (rptr + 1'b1);
        end
        default: ;
      endcase
    end
  end
endmodule

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
  localparam logic [7:0] ADDR_DATA   = 8'h00;
  localparam logic [7:0] ADDR_STATUS = 8'h04;
  localparam logic [7:0] ADDR_CTRL   = 8'h08;
  localparam logic [7:0] ADDR_BAUD   = 8'h0C;

  localparam int FIFO_LVL_W = (FIFO_DEPTH <= 2) ? 2 : ($clog2(FIFO_DEPTH) + 1);

  logic        uart_en, tx_en, rx_en, irq_en;
  logic [15:0] baud_div;

  logic [7:0] tx_fifo_rdata, rx_fifo_rdata;
  logic       tx_fifo_full, tx_fifo_empty, rx_fifo_full, rx_fifo_empty;
  logic [FIFO_LVL_W-1:0] tx_level, rx_level;
  logic tx_fifo_wr, tx_fifo_rd, rx_fifo_wr, rx_fifo_rd;

  wire apb_wr = psel && penable && pwrite;
  wire apb_rd = psel && penable && !pwrite;

  assign pready  = 1'b1;
  assign pslverr = 1'b0;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      uart_en  <= 1'b1;
      tx_en    <= 1'b1;
      rx_en    <= 1'b1;
      irq_en   <= 1'b0;
      baud_div <= (CLK_HZ / BAUD_DEFAULT);
    end else if (apb_wr) begin
      case (paddr)
        ADDR_CTRL: begin
          uart_en <= pwdata[0];
          tx_en   <= pwdata[1];
          rx_en   <= pwdata[2];
          irq_en  <= pwdata[3];
        end
        ADDR_BAUD: begin
          if (pwdata[15:0] != 16'd0)
            baud_div <= pwdata[15:0];
        end
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
        prdata[0]    = tx_fifo_full;
        prdata[1]    = tx_fifo_empty;
        prdata[2]    = rx_fifo_full;
        prdata[3]    = rx_fifo_empty;
        prdata[4]    = cts_i;
        prdata[5]    = rts_o;
        prdata[15:8] = tx_level[7:0];
        prdata[23:16]= rx_level[7:0];
      end
      ADDR_CTRL:   prdata = {28'h0, irq_en, rx_en, tx_en, uart_en};
      ADDR_BAUD:   prdata = {16'h0, baud_div};
      default:     prdata = 32'h0;
    endcase
  end

  sync_fifo #(
    .WIDTH(8),
    .DEPTH(FIFO_DEPTH)
  ) u_tx_fifo (
    .clk     (pclk),
    .rst_n   (presetn),
    .wr_en   (tx_fifo_wr),
    .wr_data (pwdata[7:0]),
    .rd_en   (tx_fifo_rd),
    .rd_data (tx_fifo_rdata),
    .full    (tx_fifo_full),
    .empty   (tx_fifo_empty),
    .level   (tx_level)
  );

  logic [7:0] rx_byte;
  sync_fifo #(
    .WIDTH(8),
    .DEPTH(FIFO_DEPTH)
  ) u_rx_fifo (
    .clk     (pclk),
    .rst_n   (presetn),
    .wr_en   (rx_fifo_wr),
    .wr_data (rx_byte),
    .rd_en   (rx_fifo_rd),
    .rd_data (rx_fifo_rdata),
    .full    (rx_fifo_full),
    .empty   (rx_fifo_empty),
    .level   (rx_level)
  );

  // RTS asserted when receiver can accept more data.
  assign rts_o = (rx_level < (FIFO_DEPTH-2));

  // Shared baud-rate pulse.
  logic [15:0] baud_cnt;
  logic        baud_tick;
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

  typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;
  tx_state_t tx_state;
  logic [7:0] tx_shift;
  logic [2:0] tx_bitcnt;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_state   <= TX_IDLE;
      tx_shift   <= 8'h00;
      tx_bitcnt  <= 3'd0;
      uart_tx    <= 1'b1;
      tx_fifo_rd <= 1'b0;
    end else begin
      tx_fifo_rd <= 1'b0;
      if (!uart_en || !tx_en) begin
        tx_state  <= TX_IDLE;
        uart_tx   <= 1'b1;
      end else if (baud_tick) begin
        case (tx_state)
          TX_IDLE: begin
            uart_tx <= 1'b1;
            if (!tx_fifo_empty && cts_i) begin
              tx_fifo_rd <= 1'b1;
              tx_shift   <= tx_fifo_rdata;
              tx_state   <= TX_START;
            end
          end
          TX_START: begin
            uart_tx   <= 1'b0;
            tx_bitcnt <= 3'd0;
            tx_state  <= TX_DATA;
          end
          TX_DATA: begin
            uart_tx  <= tx_shift[tx_bitcnt];
            if (tx_bitcnt == 3'd7)
              tx_state <= TX_STOP;
            else
              tx_bitcnt <= tx_bitcnt + 1'b1;
          end
          TX_STOP: begin
            uart_tx  <= 1'b1;
            tx_state <= TX_IDLE;
          end
          default: tx_state <= TX_IDLE;
        endcase
      end
    end
  end

  typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
  rx_state_t rx_state;
  logic [7:0] rx_shift;
  logic [2:0] rx_bitcnt;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      rx_state   <= RX_IDLE;
      rx_shift   <= 8'h00;
      rx_bitcnt  <= 3'd0;
      rx_byte    <= 8'h00;
      rx_fifo_wr <= 1'b0;
    end else begin
      rx_fifo_wr <= 1'b0;
      if (!uart_en || !rx_en) begin
        rx_state <= RX_IDLE;
      end else if (baud_tick) begin
        case (rx_state)
          RX_IDLE: begin
            if (!uart_rx)
              rx_state <= RX_START;
          end
          RX_START: begin
            if (!uart_rx) begin
              rx_bitcnt <= 3'd0;
              rx_state  <= RX_DATA;
            end else begin
              rx_state  <= RX_IDLE;
            end
          end
          RX_DATA: begin
            rx_shift[rx_bitcnt] <= uart_rx;
            if (rx_bitcnt == 3'd7)
              rx_state <= RX_STOP;
            else
              rx_bitcnt <= rx_bitcnt + 1'b1;
          end
          RX_STOP: begin
            if (uart_rx && !rx_fifo_full) begin
              rx_byte    <= rx_shift;
              rx_fifo_wr <= 1'b1;
            end
            rx_state <= RX_IDLE;
          end
          default: rx_state <= RX_IDLE;
        endcase
      end
    end
  end

  assign irq = irq_en && (!rx_fifo_empty || rx_fifo_full || tx_fifo_full);

endmodule
