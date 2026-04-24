module jtag_apb_bridge #(
  parameter int IR_LEN         = 4,
  parameter logic [31:0] IDCODE= 32'h1495_11C3
) (
  // JTAG pins
  input  logic               tck,
  input  logic               tms,
  input  logic               tdi,
  input  logic               trst_n,
  output logic               tdo,

  // APB clock/reset
  input  logic               pclk,
  input  logic               preset_n,

  // APB master signals
  output logic               psel,
  output logic               penable,
  output logic               pwrite,
  output logic [31:0]        paddr,
  output logic [31:0]        pwdata,
  input  logic [31:0]        prdata,
  input  logic               pready,
  input  logic               pslverr
);

  // ------------------------------------------------------------
  // IEEE 1149.1 TAP controller
  // ------------------------------------------------------------
  typedef enum logic [3:0] {
    TEST_LOGIC_RESET = 4'd0,
    RUN_TEST_IDLE    = 4'd1,
    SELECT_DR_SCAN   = 4'd2,
    CAPTURE_DR       = 4'd3,
    SHIFT_DR         = 4'd4,
    EXIT1_DR         = 4'd5,
    PAUSE_DR         = 4'd6,
    EXIT2_DR         = 4'd7,
    UPDATE_DR        = 4'd8,
    SELECT_IR_SCAN   = 4'd9,
    CAPTURE_IR       = 4'd10,
    SHIFT_IR         = 4'd11,
    EXIT1_IR         = 4'd12,
    PAUSE_IR         = 4'd13,
    EXIT2_IR         = 4'd14,
    UPDATE_IR        = 4'd15
  } tap_state_t;

  tap_state_t tap_state, tap_state_n;

  always_comb begin
    tap_state_n = tap_state;
    unique case (tap_state)
      TEST_LOGIC_RESET: tap_state_n = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
      RUN_TEST_IDLE:    tap_state_n = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      SELECT_DR_SCAN:   tap_state_n = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
      CAPTURE_DR:       tap_state_n = tms ? EXIT1_DR         : SHIFT_DR;
      SHIFT_DR:         tap_state_n = tms ? EXIT1_DR         : SHIFT_DR;
      EXIT1_DR:         tap_state_n = tms ? UPDATE_DR        : PAUSE_DR;
      PAUSE_DR:         tap_state_n = tms ? EXIT2_DR         : PAUSE_DR;
      EXIT2_DR:         tap_state_n = tms ? UPDATE_DR        : SHIFT_DR;
      UPDATE_DR:        tap_state_n = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      SELECT_IR_SCAN:   tap_state_n = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
      CAPTURE_IR:       tap_state_n = tms ? EXIT1_IR         : SHIFT_IR;
      SHIFT_IR:         tap_state_n = tms ? EXIT1_IR         : SHIFT_IR;
      EXIT1_IR:         tap_state_n = tms ? UPDATE_IR        : PAUSE_IR;
      PAUSE_IR:         tap_state_n = tms ? EXIT2_IR         : PAUSE_IR;
      EXIT2_IR:         tap_state_n = tms ? UPDATE_IR        : SHIFT_IR;
      UPDATE_IR:        tap_state_n = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      default:          tap_state_n = TEST_LOGIC_RESET;
    endcase
  end

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) tap_state <= TEST_LOGIC_RESET;
    else         tap_state <= tap_state_n;
  end

  logic capture_dr, shift_dr, update_dr;
  logic capture_ir, shift_ir, update_ir;

  assign capture_dr = (tap_state == CAPTURE_DR);
  assign shift_dr   = (tap_state == SHIFT_DR);
  assign update_dr  = (tap_state == UPDATE_DR);
  assign capture_ir = (tap_state == CAPTURE_IR);
  assign shift_ir   = (tap_state == SHIFT_IR);
  assign update_ir  = (tap_state == UPDATE_IR);

  // ------------------------------------------------------------
  // JTAG instruction + data registers
  // ------------------------------------------------------------
  localparam logic [IR_LEN-1:0] IR_BYPASS = {IR_LEN{1'b1}};
  localparam logic [IR_LEN-1:0] IR_IDCODE = 4'b0010;
  localparam logic [IR_LEN-1:0] IR_APBACC = 4'b1000;

  // APBACC DR layout (LSB shifted first):
  // [0]     : write_not_read
  // [32:1]  : APB address
  // [64:33] : APB write data
  localparam int APBACC_DR_LEN = 65;

  logic [IR_LEN-1:0] ir_reg, ir_shift_reg;
  logic              bypass_reg;
  logic [31:0]       idcode_reg;

  logic [APBACC_DR_LEN-1:0] apbacc_shift_reg;
  logic [31:0]              apb_rsp_rdata_tck;
  logic                     apb_rsp_err_tck;

  // IR path
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_reg       <= IR_IDCODE;
      ir_shift_reg <= '0;
    end else begin
      if (capture_ir) begin
        // Per IEEE 1149.1: IR capture has b"01" in LSB bits.
        ir_shift_reg <= {{(IR_LEN-2){1'b0}}, 2'b01};
      end else if (shift_ir) begin
        ir_shift_reg <= {tdi, ir_shift_reg[IR_LEN-1:1]};
      end else if (update_ir) begin
        ir_reg <= ir_shift_reg;
      end
    end
  end

  // DR path
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      bypass_reg      <= 1'b0;
      idcode_reg      <= IDCODE;
      apbacc_shift_reg<= '0;
    end else begin
      if (capture_dr) begin
        unique case (ir_reg)
          IR_BYPASS: bypass_reg <= 1'b0;
          IR_IDCODE: idcode_reg <= IDCODE;
          IR_APBACC: begin
            apbacc_shift_reg[0]      <= 1'b0;
            apbacc_shift_reg[32:1]   <= 32'h0;
            apbacc_shift_reg[64:33]  <= apb_rsp_rdata_tck;
          end
          default: bypass_reg <= 1'b0;
        endcase
      end else if (shift_dr) begin
        unique case (ir_reg)
          IR_BYPASS: bypass_reg       <= tdi;
          IR_IDCODE: idcode_reg       <= {tdi, idcode_reg[31:1]};
          IR_APBACC: apbacc_shift_reg <= {tdi, apbacc_shift_reg[APBACC_DR_LEN-1:1]};
          default:   bypass_reg       <= tdi;
        endcase
      end
    end
  end

  // ------------------------------------------------------------
  // APB request launch from UPDATE-DR in TCK domain
  // ------------------------------------------------------------
  logic        apb_req_write_tck;
  logic [31:0] apb_req_addr_tck;
  logic [31:0] apb_req_wdata_tck;
  logic        apb_req_toggle_tck;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      apb_req_write_tck  <= 1'b0;
      apb_req_addr_tck   <= '0;
      apb_req_wdata_tck  <= '0;
      apb_req_toggle_tck <= 1'b0;
    end else if (update_dr && (ir_reg == IR_APBACC)) begin
      apb_req_write_tck  <= apbacc_shift_reg[0];
      apb_req_addr_tck   <= apbacc_shift_reg[32:1];
      apb_req_wdata_tck  <= apbacc_shift_reg[64:33];
      apb_req_toggle_tck <= ~apb_req_toggle_tck;
    end
  end

  // ------------------------------------------------------------
  // CDC: TCK -> PCLK for request
  // ------------------------------------------------------------
  logic [1:0] req_sync_ff;
  logic       req_toggle_pclk_d;
  logic       req_pulse_pclk;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      req_sync_ff       <= 2'b00;
      req_toggle_pclk_d <= 1'b0;
    end else begin
      req_sync_ff       <= {req_sync_ff[0], apb_req_toggle_tck};
      req_toggle_pclk_d <= req_sync_ff[1];
    end
  end

  assign req_pulse_pclk = req_sync_ff[1] ^ req_toggle_pclk_d;

  // Latch request payload in PCLK domain when request pulse arrives.
  logic        req_write_pclk;
  logic [31:0] req_addr_pclk;
  logic [31:0] req_wdata_pclk;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      req_write_pclk <= 1'b0;
      req_addr_pclk  <= '0;
      req_wdata_pclk <= '0;
    end else if (req_pulse_pclk) begin
      req_write_pclk <= apb_req_write_tck;
      req_addr_pclk  <= apb_req_addr_tck;
      req_wdata_pclk <= apb_req_wdata_tck;
    end
  end

  // ------------------------------------------------------------
  // APB master sequencer
  // ------------------------------------------------------------
  typedef enum logic [1:0] {
    APB_IDLE   = 2'd0,
    APB_SETUP  = 2'd1,
    APB_ACCESS = 2'd2
  } apb_state_t;

  apb_state_t apb_state;

  logic [31:0] apb_rsp_rdata_pclk;
  logic        apb_rsp_err_pclk;
  logic        apb_rsp_toggle_pclk;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      apb_state          <= APB_IDLE;
      psel               <= 1'b0;
      penable            <= 1'b0;
      pwrite             <= 1'b0;
      paddr              <= '0;
      pwdata             <= '0;
      apb_rsp_rdata_pclk <= '0;
      apb_rsp_err_pclk   <= 1'b0;
      apb_rsp_toggle_pclk<= 1'b0;
    end else begin
      unique case (apb_state)
        APB_IDLE: begin
          psel    <= 1'b0;
          penable <= 1'b0;
          if (req_pulse_pclk) begin
            paddr   <= req_addr_pclk;
            pwdata  <= req_wdata_pclk;
            pwrite  <= req_write_pclk;
            psel    <= 1'b1;
            penable <= 1'b0;
            apb_state <= APB_SETUP;
          end
        end

        APB_SETUP: begin
          psel     <= 1'b1;
          penable  <= 1'b1;
          apb_state<= APB_ACCESS;
        end

        APB_ACCESS: begin
          psel    <= 1'b1;
          penable <= 1'b1;
          if (pready) begin
            apb_rsp_rdata_pclk  <= prdata;
            apb_rsp_err_pclk    <= pslverr;
            apb_rsp_toggle_pclk <= ~apb_rsp_toggle_pclk;
            psel                <= 1'b0;
            penable             <= 1'b0;
            apb_state           <= APB_IDLE;
          end
        end

        default: apb_state <= APB_IDLE;
      endcase
    end
  end

  // ------------------------------------------------------------
  // CDC: PCLK -> TCK for response
  // ------------------------------------------------------------
  logic [1:0] rsp_sync_ff;
  logic       rsp_toggle_tck_d;
  logic       rsp_pulse_tck;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      rsp_sync_ff      <= 2'b00;
      rsp_toggle_tck_d <= 1'b0;
      apb_rsp_rdata_tck<= '0;
      apb_rsp_err_tck  <= 1'b0;
    end else begin
      rsp_sync_ff      <= {rsp_sync_ff[0], apb_rsp_toggle_pclk};
      rsp_toggle_tck_d <= rsp_sync_ff[1];
      if (rsp_pulse_tck) begin
        apb_rsp_rdata_tck <= apb_rsp_rdata_pclk;
        apb_rsp_err_tck   <= apb_rsp_err_pclk;
      end
    end
  end

  assign rsp_pulse_tck = rsp_sync_ff[1] ^ rsp_toggle_tck_d;

  // ------------------------------------------------------------
  // TDO mux (LSB-first shifting)
  // ------------------------------------------------------------
  logic tdo_pre;

  always_comb begin
    if (shift_ir) begin
      tdo_pre = ir_shift_reg[0];
    end else if (shift_dr) begin
      unique case (ir_reg)
        IR_BYPASS: tdo_pre = bypass_reg;
        IR_IDCODE: tdo_pre = idcode_reg[0];
        IR_APBACC: tdo_pre = apbacc_shift_reg[0];
        default:   tdo_pre = bypass_reg;
      endcase
    end else begin
      tdo_pre = 1'b0;
    end
  end

  // Drive TDO on falling edge of TCK (common JTAG timing convention)
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) tdo <= 1'b0;
    else         tdo <= tdo_pre;
  end

endmodule
