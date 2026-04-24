module rr_arbiter #(
  parameter int N = 6
)(
  input  logic         clk,
  input  logic         rst_n,
  input  logic [N-1:0] req,
  input  logic         grant_accept,
  output logic [N-1:0] grant,
  output logic         grant_valid,
  output logic [$clog2(N)-1:0] grant_idx
);
  logic [$clog2(N)-1:0] last_grant;
  logic [N-1:0] masked_req;
  logic [N-1:0] rotated_req;
  logic [N-1:0] rotated_grant;
  int i;

  always_comb begin
    masked_req = '0;
    for (i = 0; i < N; i++) begin
      if (req[i]) masked_req[i] = 1'b1;
    end

    rotated_req = '0;
    for (i = 0; i < N; i++) begin
      rotated_req[i] = masked_req[(i + last_grant + 1) % N];
    end

    rotated_grant = '0;
    grant_valid   = 1'b0;
    for (i = 0; i < N; i++) begin
      if (!grant_valid && rotated_req[i]) begin
        rotated_grant[i] = 1'b1;
        grant_valid      = 1'b1;
      end
    end

    grant = '0;
    for (i = 0; i < N; i++) begin
      grant[(i + last_grant + 1) % N] = rotated_grant[i];
    end

    grant_idx = '0;
    for (i = 0; i < N; i++) begin
      if (grant[i]) grant_idx = i[$clog2(N)-1:0];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_grant <= '0;
    end else if (grant_accept && grant_valid) begin
      last_grant <= grant_idx;
    end
  end
endmodule
