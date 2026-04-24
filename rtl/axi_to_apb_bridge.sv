module axi_to_apb_bridge #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int APB_ADDR_WIDTH = 32,
    parameter int APB_DATA_WIDTH = 32
) (
    input  logic                         aclk,
    input  logic                         aresetn,

    // AXI4-Lite slave interface
    input  logic [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  logic                         s_axi_awvalid,
    output logic                         s_axi_awready,

    input  logic [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                         s_axi_wvalid,
    output logic                         s_axi_wready,

    output logic [1:0]                   s_axi_bresp,
    output logic                         s_axi_bvalid,
    input  logic                         s_axi_bready,

    input  logic [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  logic                         s_axi_arvalid,
    output logic                         s_axi_arready,

    output logic [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output logic [1:0]                   s_axi_rresp,
    output logic                         s_axi_rvalid,
    input  logic                         s_axi_rready,

    // APB master interface
    output logic [APB_ADDR_WIDTH-1:0]    paddr,
    output logic                         psel,
    output logic                         penable,
    output logic                         pwrite,
    output logic [APB_DATA_WIDTH-1:0]    pwdata,
    output logic [(APB_DATA_WIDTH/8)-1:0] pstrb,
    input  logic [APB_DATA_WIDTH-1:0]    prdata,
    input  logic                         pready,
    input  logic                         pslverr
);

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_W_SETUP,
        ST_W_ACCESS,
        ST_R_SETUP,
        ST_R_ACCESS,
        ST_R_RESP
    } state_t;

    state_t state, state_n;

    logic [AXI_ADDR_WIDTH-1:0] awaddr_q;
    logic [AXI_DATA_WIDTH-1:0] wdata_q;
    logic [(AXI_DATA_WIDTH/8)-1:0] wstrb_q;
    logic [AXI_ADDR_WIDTH-1:0] araddr_q;
    logic have_aw_q, have_w_q;

    // Write and read buffering for AXI4-Lite decoupled channels
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            awaddr_q   <= '0;
            wdata_q    <= '0;
            wstrb_q    <= '0;
            araddr_q   <= '0;
            have_aw_q  <= 1'b0;
            have_w_q   <= 1'b0;
        end else begin
            if (state == ST_IDLE) begin
                if (s_axi_awvalid && s_axi_awready) begin
                    awaddr_q  <= s_axi_awaddr;
                    have_aw_q <= 1'b1;
                end
                if (s_axi_wvalid && s_axi_wready) begin
                    wdata_q  <= s_axi_wdata;
                    wstrb_q  <= s_axi_wstrb;
                    have_w_q <= 1'b1;
                end
                if (s_axi_arvalid && s_axi_arready) begin
                    araddr_q <= s_axi_araddr;
                end
            end

            if (state == ST_W_SETUP) begin
                have_aw_q <= 1'b0;
                have_w_q  <= 1'b0;
            end
        end
    end

    // State machine
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= ST_IDLE;
        end else begin
            state <= state_n;
        end
    end

    always_comb begin
        state_n = state;

        unique case (state)
            ST_IDLE: begin
                if (have_aw_q && have_w_q) begin
                    state_n = ST_W_SETUP;
                end else if (s_axi_arvalid && !have_aw_q && !have_w_q) begin
                    state_n = ST_R_SETUP;
                end
            end

            ST_W_SETUP: begin
                state_n = ST_W_ACCESS;
            end

            ST_W_ACCESS: begin
                if (pready) begin
                    state_n = ST_IDLE;
                end
            end

            ST_R_SETUP: begin
                state_n = ST_R_ACCESS;
            end

            ST_R_ACCESS: begin
                if (pready) begin
                    state_n = ST_R_RESP;
                end
            end

            ST_R_RESP: begin
                if (s_axi_rready && s_axi_rvalid) begin
                    state_n = ST_IDLE;
                end
            end

            default: begin
                state_n = ST_IDLE;
            end
        endcase
    end

    // AXI output responses
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= RESP_OKAY;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= RESP_OKAY;
            s_axi_rdata  <= '0;
        end else begin
            if (state == ST_W_ACCESS && pready) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= pslverr ? RESP_SLVERR : RESP_OKAY;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (state == ST_R_ACCESS && pready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= pslverr ? RESP_SLVERR : RESP_OKAY;
                s_axi_rdata  <= prdata;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // AXI ready signaling
    always_comb begin
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;
        s_axi_arready = 1'b0;

        if (state == ST_IDLE) begin
            s_axi_awready = !have_aw_q;
            s_axi_wready  = !have_w_q;

            // Block reads when a write is partially collected, preserving ordering.
            if (!have_aw_q && !have_w_q) begin
                s_axi_arready = 1'b1;
            end
        end
    end

    // APB controls
    always_comb begin
        paddr   = '0;
        psel    = 1'b0;
        penable = 1'b0;
        pwrite  = 1'b0;
        pwdata  = '0;
        pstrb   = '0;

        unique case (state)
            ST_W_SETUP: begin
                paddr   = awaddr_q[APB_ADDR_WIDTH-1:0];
                psel    = 1'b1;
                penable = 1'b0;
                pwrite  = 1'b1;
                pwdata  = wdata_q[APB_DATA_WIDTH-1:0];
                pstrb   = wstrb_q[(APB_DATA_WIDTH/8)-1:0];
            end

            ST_W_ACCESS: begin
                paddr   = awaddr_q[APB_ADDR_WIDTH-1:0];
                psel    = 1'b1;
                penable = 1'b1;
                pwrite  = 1'b1;
                pwdata  = wdata_q[APB_DATA_WIDTH-1:0];
                pstrb   = wstrb_q[(APB_DATA_WIDTH/8)-1:0];
            end

            ST_R_SETUP: begin
                paddr   = araddr_q[APB_ADDR_WIDTH-1:0];
                psel    = 1'b1;
                penable = 1'b0;
                pwrite  = 1'b0;
            end

            ST_R_ACCESS: begin
                paddr   = araddr_q[APB_ADDR_WIDTH-1:0];
                psel    = 1'b1;
                penable = 1'b1;
                pwrite  = 1'b0;
            end

            default: ;
        endcase
    end

endmodule
