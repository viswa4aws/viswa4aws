package axi_pkg;
  parameter int AXI_ADDR_W = 32;
  parameter int AXI_DATA_W = 128;
  parameter int AXI_ID_W   = 4;
  parameter int AXI_STRB_W = AXI_DATA_W/8;

  typedef struct packed {
    logic [AXI_ID_W-1:0]    id;
    logic [AXI_ADDR_W-1:0]  addr;
    logic [7:0]             len;
    logic [2:0]             size;
    logic [1:0]             burst;
    logic                   lock;
    logic [3:0]             cache;
    logic [2:0]             prot;
    logic [3:0]             qos;
    logic [3:0]             region;
    logic [AXI_ID_W-1:0]    user;
  } axi_aw_t;

  typedef axi_aw_t axi_ar_t;

  typedef struct packed {
    logic [AXI_DATA_W-1:0]  data;
    logic [AXI_STRB_W-1:0]  strb;
    logic                   last;
  } axi_w_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0]    id;
    logic [1:0]             resp;
  } axi_b_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0]    id;
    logic [AXI_DATA_W-1:0]  data;
    logic [1:0]             resp;
    logic                   last;
  } axi_r_t;
endpackage
