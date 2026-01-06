`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"

module nockpu_axi_lite_tb();

parameter MEM_INIT_FILE = "./memory/constant_tb.hex";
parameter integer MAX_CYCLES = 200000;
localparam integer AXI_ADDR_WIDTH = 12;

localparam [AXI_ADDR_WIDTH-1:0] REG_CONTROL      = 12'h000;
localparam [AXI_ADDR_WIDTH-1:0] REG_STATUS       = 12'h004;
localparam [AXI_ADDR_WIDTH-1:0] REG_START_ADDR   = 12'h008;
localparam [AXI_ADDR_WIDTH-1:0] REG_MEM_ADDR     = 12'h00C;
localparam [AXI_ADDR_WIDTH-1:0] REG_MEM_WDATA_LO = 12'h010;
localparam [AXI_ADDR_WIDTH-1:0] REG_MEM_WDATA_HI = 12'h014;
localparam [AXI_ADDR_WIDTH-1:0] REG_MEM_CMD      = 12'h018;
localparam [AXI_ADDR_WIDTH-1:0] REG_MEM_STATUS   = 12'h01C;
localparam [AXI_ADDR_WIDTH-1:0] REG_MEM_RDATA_LO = 12'h020;
localparam [AXI_ADDR_WIDTH-1:0] REG_MEM_RDATA_HI = 12'h024;
localparam [AXI_ADDR_WIDTH-1:0] REG_STREAM_CTRL  = 12'h02C;
localparam [AXI_ADDR_WIDTH-1:0] REG_STREAM_STATUS = 12'h030;
localparam [AXI_ADDR_WIDTH-1:0] REG_FREE_PTR     = 12'h034;

reg clk;
reg rst;

reg [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
reg s_axi_awvalid;
wire s_axi_awready;
reg [31:0] s_axi_wdata;
reg [3:0] s_axi_wstrb;
reg s_axi_wvalid;
wire s_axi_wready;
wire [1:0] s_axi_bresp;
wire s_axi_bvalid;
reg s_axi_bready;
reg [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
reg s_axi_arvalid;
wire s_axi_arready;
wire [31:0] s_axi_rdata;
wire [1:0] s_axi_rresp;
wire s_axi_rvalid;
reg s_axi_rready;
reg [63:0] s_axis_tdata;
reg s_axis_tvalid;
reg s_axis_tlast;
wire s_axis_tready;
wire core_done;

nockpu_axi_lite #(
  .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH)
) dut(
  .clk (clk),
  .rst (rst),
  .s_axi_awaddr (s_axi_awaddr),
  .s_axi_awvalid (s_axi_awvalid),
  .s_axi_awready (s_axi_awready),
  .s_axi_wdata (s_axi_wdata),
  .s_axi_wstrb (s_axi_wstrb),
  .s_axi_wvalid (s_axi_wvalid),
  .s_axi_wready (s_axi_wready),
  .s_axi_bresp (s_axi_bresp),
  .s_axi_bvalid (s_axi_bvalid),
  .s_axi_bready (s_axi_bready),
  .s_axi_araddr (s_axi_araddr),
  .s_axi_arvalid (s_axi_arvalid),
  .s_axi_arready (s_axi_arready),
  .s_axi_rdata (s_axi_rdata),
  .s_axi_rresp (s_axi_rresp),
  .s_axi_rvalid (s_axi_rvalid),
  .s_axi_rready (s_axi_rready),
  .s_axis_tdata (s_axis_tdata),
  .s_axis_tvalid (s_axis_tvalid),
  .s_axis_tlast (s_axis_tlast),
  .s_axis_tready (s_axis_tready),
  .core_done (core_done)
);

initial begin
  clk = 0;
  forever #5 clk = ~clk;
end

task axi_write;
  input [AXI_ADDR_WIDTH-1:0] addr;
  input [31:0] data;
  integer wait_cycles;
  begin
    @(posedge clk);
    s_axi_awaddr = addr;
    s_axi_awvalid = 1'b1;
    s_axi_wdata = data;
    s_axi_wstrb = 4'hF;
    s_axi_wvalid = 1'b1;
    s_axi_bready = 1'b0;
    wait_cycles = 0;
    while (!(s_axi_awready && s_axi_wready) && wait_cycles < MAX_CYCLES) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!(s_axi_awready && s_axi_wready)) begin
      $display("FAIL axi_write ready timeout");
      $finish;
    end
    @(posedge clk);
    s_axi_awvalid = 1'b0;
    s_axi_wvalid = 1'b0;
    wait_cycles = 0;
    while (!s_axi_bvalid && wait_cycles < MAX_CYCLES) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!s_axi_bvalid) begin
      $display("FAIL axi_write bvalid timeout");
      $finish;
    end
    s_axi_bready = 1'b1;
    @(posedge clk);
    s_axi_bready = 1'b0;
  end
endtask

task axi_read;
  input [AXI_ADDR_WIDTH-1:0] addr;
  output [31:0] data;
  integer wait_cycles;
  begin
    @(posedge clk);
    s_axi_araddr = addr;
    s_axi_arvalid = 1'b1;
    s_axi_rready = 1'b0;
    wait_cycles = 0;
    while (!s_axi_arready && wait_cycles < MAX_CYCLES) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!s_axi_arready) begin
      $display("FAIL axi_read arready timeout");
      $finish;
    end
    @(posedge clk);
    s_axi_arvalid = 1'b0;
    wait_cycles = 0;
    while (!s_axi_rvalid && wait_cycles < MAX_CYCLES) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!s_axi_rvalid) begin
      $display("FAIL axi_read rvalid timeout");
      $finish;
    end
    data = s_axi_rdata;
    s_axi_rready = 1'b1;
    @(posedge clk);
    s_axi_rready = 1'b0;
  end
endtask

task axis_send;
  input [63:0] data;
  input last;
  integer wait_cycles;
  begin
    s_axis_tdata = data;
    s_axis_tlast = last;
    s_axis_tvalid = 1'b1;
    wait_cycles = 0;
    while (!s_axis_tready && wait_cycles < MAX_CYCLES) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!s_axis_tready) begin
      $display("FAIL axis_send tready timeout");
      $finish;
    end
    @(posedge clk);
    @(negedge clk);
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
    s_axis_tdata = 64'b0;
  end
endtask

integer cycles;
reg [31:0] status;
reg [31:0] lo;
reg [31:0] hi;
reg [8*256-1:0] mem_init_file;
reg [`memory_addr_width - 1:0] expected_free;
localparam integer MEM_DEPTH = 1 << `memory_addr_width;
localparam integer MEM_LAST = MEM_DEPTH - 1;
initial begin
  mem_init_file = MEM_INIT_FILE;
  if ($value$plusargs("mem=%s", mem_init_file)) begin
  end
  if (mem_init_file != "") begin
    $readmemh(mem_init_file, dut.core.mem.ram.ram, 0, MEM_LAST);
  end

  s_axi_awaddr = 0;
  s_axi_awvalid = 0;
  s_axi_wdata = 0;
  s_axi_wstrb = 0;
  s_axi_wvalid = 0;
  s_axi_bready = 0;
  s_axi_araddr = 0;
  s_axi_arvalid = 0;
  s_axi_rready = 0;
  s_axis_tdata = 0;
  s_axis_tvalid = 0;
  s_axis_tlast = 0;

  rst = 1'b0;
  repeat (4) @(posedge clk);
  rst = 1'b1;

  cycles = 0;
  do begin
    axi_read(REG_STATUS, status);
    cycles = cycles + 1;
  end while (!status[2] && cycles < MAX_CYCLES);
  if (!status[2]) begin
    $display("FAIL host_ready timeout");
    $finish;
  end
  expected_free = dut.core.mem.ram.ram[0][`memory_addr_width - 1:0];
  axi_read(REG_FREE_PTR, lo);
  if (lo[`memory_addr_width - 1:0] !== expected_free) begin
    $display("FAIL free_ptr expected %0d got %0d", expected_free, lo[`memory_addr_width - 1:0]);
    $finish;
  end

  // Read memory word at address 1 via host read command.
  axi_write(REG_MEM_ADDR, 32'd1);
  axi_write(REG_MEM_CMD, 32'h1);
  cycles = 0;
  do begin
    axi_read(REG_MEM_STATUS, status);
    cycles = cycles + 1;
  end while (!status[1] && cycles < MAX_CYCLES);
  if (!status[1]) begin
    $display("FAIL mem read timeout");
    $finish;
  end
  axi_read(REG_MEM_RDATA_LO, lo);
  axi_read(REG_MEM_RDATA_HI, hi);
  if ({hi, lo} !== 64'h8000000020000003) begin
    $display("FAIL initial mem read expected 8000000020000003 got %h%h", hi, lo);
    $finish;
  end

  // Host write/readback sanity.
  axi_write(REG_MEM_STATUS, 32'h1);
  axi_write(REG_MEM_ADDR, 32'd20);
  axi_write(REG_MEM_WDATA_LO, 32'h89abcdef);
  axi_write(REG_MEM_WDATA_HI, 32'h01234567);
  axi_write(REG_MEM_CMD, 32'h2);
  cycles = 0;
  do begin
    axi_read(REG_MEM_STATUS, status);
    cycles = cycles + 1;
  end while (!status[1] && cycles < MAX_CYCLES);
  if (!status[1]) begin
    $display("FAIL mem write timeout");
    $finish;
  end
  axi_write(REG_MEM_STATUS, 32'h1);
  axi_write(REG_MEM_CMD, 32'h1);
  cycles = 0;
  do begin
    axi_read(REG_MEM_STATUS, status);
    cycles = cycles + 1;
  end while (!status[1] && cycles < MAX_CYCLES);
  if (!status[1]) begin
    $display("FAIL mem read timeout after write");
    $finish;
  end
  axi_read(REG_MEM_RDATA_LO, lo);
  axi_read(REG_MEM_RDATA_HI, hi);
  if ({hi, lo} !== 64'h0123456789abcdef) begin
    $display("FAIL mem write readback expected 0123456789abcdef got %h%h", hi, lo);
    $finish;
  end

  // Stream loader write/readback sanity.
  axi_write(REG_STREAM_STATUS, 32'h1);
  axi_write(REG_MEM_ADDR, 32'd30);
  axi_write(REG_STREAM_CTRL, 32'h1);
  axis_send(64'h1111222233334444, 1'b0);
  axis_send(64'h5555666677778888, 1'b1);
  cycles = 0;
  do begin
    axi_read(REG_STREAM_STATUS, status);
    cycles = cycles + 1;
  end while (!status[2] && cycles < MAX_CYCLES);
  if (!status[2]) begin
    $display("FAIL stream done timeout");
    $finish;
  end
  if (status[3]) begin
    $display("FAIL stream status error set");
    $finish;
  end

  axi_write(REG_MEM_STATUS, 32'h1);
  axi_write(REG_MEM_ADDR, 32'd30);
  axi_write(REG_MEM_CMD, 32'h1);
  cycles = 0;
  do begin
    axi_read(REG_MEM_STATUS, status);
    cycles = cycles + 1;
  end while (!status[1] && cycles < MAX_CYCLES);
  if (!status[1]) begin
    $display("FAIL stream mem read timeout");
    $finish;
  end
  axi_read(REG_MEM_RDATA_LO, lo);
  axi_read(REG_MEM_RDATA_HI, hi);
  if ({hi, lo} !== 64'h1111222233334444) begin
    $display("FAIL stream readback expected 1111222233334444 got %h%h", hi, lo);
    $finish;
  end

  axi_write(REG_MEM_STATUS, 32'h1);
  axi_write(REG_MEM_ADDR, 32'd31);
  axi_write(REG_MEM_CMD, 32'h1);
  cycles = 0;
  do begin
    axi_read(REG_MEM_STATUS, status);
    cycles = cycles + 1;
  end while (!status[1] && cycles < MAX_CYCLES);
  if (!status[1]) begin
    $display("FAIL stream mem read timeout second word");
    $finish;
  end
  axi_read(REG_MEM_RDATA_LO, lo);
  axi_read(REG_MEM_RDATA_HI, hi);
  if ({hi, lo} !== 64'h5555666677778888) begin
    $display("FAIL stream readback expected 5555666677778888 got %h%h", hi, lo);
    $finish;
  end

  // Start execution.
  axi_write(REG_START_ADDR, 32'd1);
  axi_write(REG_CONTROL, 32'h1);

  cycles = 0;
  do begin
    axi_read(REG_STATUS, status);
    cycles = cycles + 1;
  end while (!status[1] && cycles < MAX_CYCLES);
  if (!status[1]) begin
    $display("FAIL done timeout");
    $finish;
  end

  // Read result at address 1.
  axi_write(REG_MEM_STATUS, 32'h1);
  axi_write(REG_MEM_ADDR, 32'd1);
  axi_write(REG_MEM_CMD, 32'h1);
  cycles = 0;
  do begin
    axi_read(REG_MEM_STATUS, status);
    cycles = cycles + 1;
  end while (!status[1] && cycles < MAX_CYCLES);
  if (!status[1]) begin
    $display("FAIL mem read timeout after run");
    $finish;
  end
  axi_read(REG_MEM_RDATA_LO, lo);
  axi_read(REG_MEM_RDATA_HI, hi);
  if ({hi, lo} !== 64'h0300000a400000ae) begin
    $display("FAIL result expected 0300000a400000ae got %h%h", hi, lo);
    $finish;
  end

  $display("PASS");
  $finish;
end

endmodule
