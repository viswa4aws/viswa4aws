module uart_fifo #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16,
  parameter int ADDR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              wr_en,
  input  logic [WIDTH-1:0]  wr_data,
  input  logic              rd_en,
  output logic [WIDTH-1:0]  rd_data,
  output logic              full,
  output logic              empty,
  output logic [ADDR_W:0]   level
);
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] wptr, rptr;
  logic [ADDR_W:0] count;

  assign rd_data = mem[rptr];
  assign full  = (count == DEPTH);
  assign empty = (count == 0);
  assign level = count;

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
