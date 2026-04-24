`include "axi_if.sv"

module soc_axi_noc_top #(
  parameter int AXI_ADDR_W = 32,
  parameter int AXI_DATA_W = 128,
  parameter int AXI_ID_W   = 4
)(
  input logic aclk,
  input logic aresetn,
  axi_if.slave  m_axi [6],
  axi_if.master s_axi [4]
);
  // Master-port logical mapping:
  // m_axi[0] -> PCIe Controller
  // m_axi[1] -> DDR4 path 0
  // m_axi[2] -> DDR4 path 1
  // m_axi[3] -> DDR4 path 2
  // m_axi[4] -> External Scheduler
  // m_axi[5] -> AXI-to-APB bridge

  // Slave-port logical mapping:
  // s_axi[0] -> PCIe Controller target
  // s_axi[1] -> L2 Cache 0
  // s_axi[2] -> L2 Cache 1
  // s_axi[3] -> APB-to-AXI bridge

  axi_noc_6x4 #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .AXI_ID_W(AXI_ID_W)
  ) u_axi_noc_6x4 (
    .aclk(aclk),
    .aresetn(aresetn),
    .m_axi(m_axi),
    .s_axi(s_axi)
  );
endmodule
