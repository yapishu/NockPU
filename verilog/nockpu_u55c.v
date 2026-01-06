module nockpu_u55c #(
  parameter integer AXI_ADDR_WIDTH = 12,
`ifdef NPU_STACK_DEPTH_TRAV
  parameter integer STACK_DEPTH_TRAV = `NPU_STACK_DEPTH_TRAV,
`else
  parameter integer STACK_DEPTH_TRAV = 2048,
`endif
`ifdef NPU_STACK_DEPTH_EQUAL
  parameter integer STACK_DEPTH_EQUAL = `NPU_STACK_DEPTH_EQUAL
`else
  parameter integer STACK_DEPTH_EQUAL = 2048
`endif
)(
  input ap_clk,
  input ap_rst_n,
  // AXI4-Lite control interface.
  input [AXI_ADDR_WIDTH-1:0] s_axi_control_awaddr,
  input s_axi_control_awvalid,
  output wire s_axi_control_awready,
  input [31:0] s_axi_control_wdata,
  input [3:0] s_axi_control_wstrb,
  input s_axi_control_wvalid,
  output wire s_axi_control_wready,
  output wire [1:0] s_axi_control_bresp,
  output wire s_axi_control_bvalid,
  input s_axi_control_bready,
  input [AXI_ADDR_WIDTH-1:0] s_axi_control_araddr,
  input s_axi_control_arvalid,
  output wire s_axi_control_arready,
  output wire [31:0] s_axi_control_rdata,
  output wire [1:0] s_axi_control_rresp,
  output wire s_axi_control_rvalid,
  input s_axi_control_rready,
  // AXI4-Stream input for bulk memory writes.
  input [63:0] s_axis_mem_tdata,
  input s_axis_mem_tvalid,
  input s_axis_mem_tlast,
  output wire s_axis_mem_tready,
  output wire interrupt
);
  wire core_done;

  nockpu_axi_lite #(
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .STACK_DEPTH_TRAV (STACK_DEPTH_TRAV),
    .STACK_DEPTH_EQUAL (STACK_DEPTH_EQUAL)
  ) core (
    .clk (ap_clk),
    .rst (ap_rst_n),
    .s_axi_awaddr (s_axi_control_awaddr),
    .s_axi_awvalid (s_axi_control_awvalid),
    .s_axi_awready (s_axi_control_awready),
    .s_axi_wdata (s_axi_control_wdata),
    .s_axi_wstrb (s_axi_control_wstrb),
    .s_axi_wvalid (s_axi_control_wvalid),
    .s_axi_wready (s_axi_control_wready),
    .s_axi_bresp (s_axi_control_bresp),
    .s_axi_bvalid (s_axi_control_bvalid),
    .s_axi_bready (s_axi_control_bready),
    .s_axi_araddr (s_axi_control_araddr),
    .s_axi_arvalid (s_axi_control_arvalid),
    .s_axi_arready (s_axi_control_arready),
    .s_axi_rdata (s_axi_control_rdata),
    .s_axi_rresp (s_axi_control_rresp),
    .s_axi_rvalid (s_axi_control_rvalid),
    .s_axi_rready (s_axi_control_rready),
    .s_axis_tdata (s_axis_mem_tdata),
    .s_axis_tvalid (s_axis_mem_tvalid),
    .s_axis_tlast (s_axis_mem_tlast),
    .s_axis_tready (s_axis_mem_tready),
    .core_done (core_done)
  );

  assign interrupt = core_done;
endmodule
