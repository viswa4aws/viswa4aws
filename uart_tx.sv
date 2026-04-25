module uart_tx (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       en,
  input  logic       baud_tick,
  input  logic       cts_i,
  input  logic       tx_fifo_empty,
  input  logic [7:0] tx_fifo_rdata,
  output logic       tx_fifo_rd,
  output logic       uart_tx,
  output logic       busy
);
  typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;
  tx_state_t state;
  logic [7:0] shreg;
  logic [2:0] bit_idx;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= TX_IDLE;
      shreg     <= 8'h00;
      bit_idx   <= 3'd0;
      tx_fifo_rd<= 1'b0;
      uart_tx   <= 1'b1;
      busy      <= 1'b0;
    end else begin
      tx_fifo_rd <= 1'b0;
      if (!en) begin
        state   <= TX_IDLE;
        uart_tx <= 1'b1;
        busy    <= 1'b0;
      end else if (baud_tick) begin
        case (state)
          TX_IDLE: begin
            uart_tx <= 1'b1;
            busy    <= 1'b0;
            if (!tx_fifo_empty && cts_i) begin
              shreg     <= tx_fifo_rdata;
              tx_fifo_rd<= 1'b1;
              state     <= TX_START;
              busy      <= 1'b1;
            end
          end
          TX_START: begin
            uart_tx <= 1'b0;
            bit_idx <= 3'd0;
            state   <= TX_DATA;
          end
          TX_DATA: begin
            uart_tx <= shreg[bit_idx];
            if (bit_idx == 3'd7)
              state <= TX_STOP;
            else
              bit_idx <= bit_idx + 1'b1;
          end
          TX_STOP: begin
            uart_tx <= 1'b1;
            state   <= TX_IDLE;
          end
          default: state <= TX_IDLE;
        endcase
      end
    end
  end
endmodule
