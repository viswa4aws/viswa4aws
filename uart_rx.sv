module uart_rx (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       en,
  input  logic       baud_tick,
  input  logic       uart_rx,
  output logic [7:0] rx_data,
  output logic       rx_valid
);
  typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
  rx_state_t state;
  logic [7:0] shreg;
  logic [2:0] bit_idx;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= RX_IDLE;
      shreg    <= 8'h00;
      bit_idx  <= 3'd0;
      rx_data  <= 8'h00;
      rx_valid <= 1'b0;
    end else begin
      rx_valid <= 1'b0;
      if (!en) begin
        state <= RX_IDLE;
      end else if (baud_tick) begin
        case (state)
          RX_IDLE: begin
            if (!uart_rx)
              state <= RX_START;
          end
          RX_START: begin
            if (!uart_rx) begin
              bit_idx <= 3'd0;
              state   <= RX_DATA;
            end else begin
              state   <= RX_IDLE;
            end
          end
          RX_DATA: begin
            shreg[bit_idx] <= uart_rx;
            if (bit_idx == 3'd7)
              state <= RX_STOP;
            else
              bit_idx <= bit_idx + 1'b1;
          end
          RX_STOP: begin
            if (uart_rx) begin
              rx_data  <= shreg;
              rx_valid <= 1'b1;
            end
            state <= RX_IDLE;
          end
          default: state <= RX_IDLE;
        endcase
      end
    end
  end
endmodule
