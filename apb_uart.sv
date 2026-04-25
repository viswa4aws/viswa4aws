module apb_uart #(
  parameter int CLK_HZ       = 50_000_000,
  parameter int BAUD_DEFAULT = 115200,
  parameter int FIFO_DEPTH   = 16,
  parameter int ADDR_WIDTH   = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH)
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

  logic uart_en, tx_en, rx_en, irq_en;
  logic [15:0] baud_div;

  // Internal TX FIFO storage
  logic [7:0] tx_mem [0:FIFO_DEPTH-1];
  logic [ADDR_WIDTH-1:0] tx_wptr, tx_rptr;
  logic [ADDR_WIDTH:0] tx_count;
  logic tx_fifo_full, tx_fifo_empty;
  logic [7:0] tx_fifo_rdata;

  // Internal RX FIFO storage
  logic [7:0] rx_mem [0:FIFO_DEPTH-1];
  logic [ADDR_WIDTH-1:0] rx_wptr, rx_rptr;
  logic [ADDR_WIDTH:0] rx_count;
  logic rx_fifo_full, rx_fifo_empty;
  logic [7:0] rx_fifo_rdata;

  logic tx_push, tx_pop, rx_push, rx_pop;
  logic [7:0] rx_push_data;

  wire apb_wr = psel && penable && pwrite;
  wire apb_rd = psel && penable && !pwrite;

  assign pready  = 1'b1;
  assign pslverr = 1'b0;

  assign tx_fifo_full  = (tx_count == FIFO_DEPTH);
  assign tx_fifo_empty = (tx_count == 0);
  assign rx_fifo_full  = (rx_count == FIFO_DEPTH);
  assign rx_fifo_empty = (rx_count == 0);

  assign tx_fifo_rdata = tx_mem[tx_rptr];
  assign rx_fifo_rdata = rx_mem[rx_rptr];

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

  // APB DATA access
  assign tx_push = apb_wr && (paddr == ADDR_DATA) && !tx_fifo_full;
  assign rx_pop  = apb_rd && (paddr == ADDR_DATA) && !rx_fifo_empty;

  always_comb begin
    prdata = 32'h0;
    case (paddr)
      ADDR_DATA: begin
        prdata[7:0] = rx_fifo_rdata;
      end
      ADDR_STATUS: begin
        prdata[0]     = tx_fifo_full;
        prdata[1]     = tx_fifo_empty;
        prdata[2]     = rx_fifo_full;
        prdata[3]     = rx_fifo_empty;
        prdata[4]     = cts_i;
        prdata[5]     = rts_o;
        prdata[15:8]  = tx_count[7:0];
        prdata[23:16] = rx_count[7:0];
      end
      ADDR_CTRL: prdata = {28'h0, irq_en, rx_en, tx_en, uart_en};
      ADDR_BAUD: prdata = {16'h0, baud_div};
      default:   prdata = 32'h0;
    endcase
  end

  // TX FIFO update
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_wptr  <= '0;
      tx_rptr  <= '0;
      tx_count <= '0;
    end else begin
      case ({tx_push, tx_pop})
        2'b10: begin
          tx_mem[tx_wptr] <= pwdata[7:0];
          tx_wptr <= (tx_wptr == FIFO_DEPTH-1) ? '0 : tx_wptr + 1'b1;
          tx_count <= tx_count + 1'b1;
        end
        2'b01: begin
          tx_rptr <= (tx_rptr == FIFO_DEPTH-1) ? '0 : tx_rptr + 1'b1;
          tx_count <= tx_count - 1'b1;
        end
        2'b11: begin
          tx_mem[tx_wptr] <= pwdata[7:0];
          tx_wptr <= (tx_wptr == FIFO_DEPTH-1) ? '0 : tx_wptr + 1'b1;
          tx_rptr <= (tx_rptr == FIFO_DEPTH-1) ? '0 : tx_rptr + 1'b1;
        end
        default: ;
      endcase
    end
  end

  // RX FIFO update
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      rx_wptr  <= '0;
      rx_rptr  <= '0;
      rx_count <= '0;
    end else begin
      case ({rx_push, rx_pop})
        2'b10: begin
          rx_mem[rx_wptr] <= rx_push_data;
          rx_wptr <= (rx_wptr == FIFO_DEPTH-1) ? '0 : rx_wptr + 1'b1;
          rx_count <= rx_count + 1'b1;
        end
        2'b01: begin
          rx_rptr <= (rx_rptr == FIFO_DEPTH-1) ? '0 : rx_rptr + 1'b1;
          rx_count <= rx_count - 1'b1;
        end
        2'b11: begin
          rx_mem[rx_wptr] <= rx_push_data;
          rx_wptr <= (rx_wptr == FIFO_DEPTH-1) ? '0 : rx_wptr + 1'b1;
          rx_rptr <= (rx_rptr == FIFO_DEPTH-1) ? '0 : rx_rptr + 1'b1;
        end
        default: ;
      endcase
    end
  end

  // Flow control: ready-to-receive asserted while RX FIFO has headroom.
  assign rts_o = (rx_count < (FIFO_DEPTH-2));

  // Shared baud pulse.
  logic [15:0] baud_cnt;
  logic        baud_tick;
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      baud_cnt  <= 16'd0;
      baud_tick <= 1'b0;
    end else if (!uart_en) begin
      baud_cnt  <= 16'd0;
      baud_tick <= 1'b0;
    end else if (baud_cnt == baud_div - 1'b1) begin
      baud_cnt  <= 16'd0;
      baud_tick <= 1'b1;
    end else begin
      baud_cnt  <= baud_cnt + 1'b1;
      baud_tick <= 1'b0;
    end
  end

  // UART TX datapath (8N1)
  typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;
  tx_state_t tx_state;
  logic [7:0] tx_shift;
  logic [2:0] tx_bit_idx;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_state   <= TX_IDLE;
      tx_shift   <= 8'h00;
      tx_bit_idx <= 3'd0;
      tx_pop     <= 1'b0;
      uart_tx    <= 1'b1;
    end else begin
      tx_pop <= 1'b0;
      if (!uart_en || !tx_en) begin
        tx_state <= TX_IDLE;
        uart_tx  <= 1'b1;
      end else if (baud_tick) begin
        case (tx_state)
          TX_IDLE: begin
            uart_tx <= 1'b1;
            if (!tx_fifo_empty && cts_i) begin
              tx_shift <= tx_fifo_rdata;
              tx_pop   <= 1'b1;
              tx_state <= TX_START;
            end
          end
          TX_START: begin
            uart_tx    <= 1'b0;
            tx_bit_idx <= 3'd0;
            tx_state   <= TX_DATA;
          end
          TX_DATA: begin
            uart_tx <= tx_shift[tx_bit_idx];
            if (tx_bit_idx == 3'd7)
              tx_state <= TX_STOP;
            else
              tx_bit_idx <= tx_bit_idx + 1'b1;
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

  // UART RX datapath (8N1, baud-tick sampling)
  typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
  rx_state_t rx_state;
  logic [7:0] rx_shift;
  logic [2:0] rx_bit_idx;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      rx_state     <= RX_IDLE;
      rx_shift     <= 8'h00;
      rx_bit_idx   <= 3'd0;
      rx_push      <= 1'b0;
      rx_push_data <= 8'h00;
    end else begin
      rx_push <= 1'b0;
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
              rx_bit_idx <= 3'd0;
              rx_state   <= RX_DATA;
            end else begin
              rx_state   <= RX_IDLE;
            end
          end
          RX_DATA: begin
            rx_shift[rx_bit_idx] <= uart_rx;
            if (rx_bit_idx == 3'd7)
              rx_state <= RX_STOP;
            else
              rx_bit_idx <= rx_bit_idx + 1'b1;
          end
          RX_STOP: begin
            if (uart_rx && !rx_fifo_full) begin
              rx_push      <= 1'b1;
              rx_push_data <= rx_shift;
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
