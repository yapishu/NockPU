`timescale 1ns/1ns
`include "memory_unit.vh"

module NPU_UI(CLOCK_50);
  input CLOCK_50;

  // Test Parameters
  parameter MEM_INIT_FILE = "../memory/constant_tb.hex";

  wire clk;
  assign clk = CLOCK_50;

  reg reset;
  reg start;
  reg [`memory_addr_width - 1:0] start_addr;

  wire host_ready;
  wire [`memory_data_width - 1:0] host_rdata;
  wire host_rvalid;
  wire busy;
  wire done;
  wire [7:0] error;
  wire [7:0] edit_error;
wire [`noun_width-1:0] hint;
wire hint_tag;
wire [`memory_addr_width - 1:0] free_ptr;
wire [`memory_addr_width - 1:0] root_ptr;

  wire host_req;
  wire host_we;
  wire [`memory_addr_width - 1:0] host_addr;
  wire [`memory_data_width - 1:0] host_wdata;
  assign host_req = 1'b0;
  assign host_we = 1'b0;
  assign host_addr = {`memory_addr_width{1'b0}};
  assign host_wdata = {`memory_data_width{1'b0}};

  nockpu_top dut(
    .clk (clk),
    .rst (reset),
    .start (start),
    .start_addr (start_addr),
    .host_req (host_req),
    .host_we (host_we),
    .host_addr (host_addr),
    .host_wdata (host_wdata),
    .host_ready (host_ready),
    .host_rdata (host_rdata),
    .host_rvalid (host_rvalid),
    .busy (busy),
    .done (done),
    .error (error),
    .edit_error (edit_error),
    .hint (hint),
    .hint_tag (hint_tag),
    .free_ptr (free_ptr),
    .root_ptr (root_ptr)
  );

  localparam integer MEM_DEPTH = 1 << `memory_addr_width;
  localparam integer MEM_LAST = MEM_DEPTH - 1;

  // Perform Test
  initial begin
    start_addr = 1;
    start = 1'b0;

    if (MEM_INIT_FILE != "") begin
      $readmemh(MEM_INIT_FILE, dut.mem.ram.ram, 0, MEM_LAST);
    end

    reset = 1'b0;
    repeat (2) @(posedge clk);
    reset = 1'b1;
    wait (host_ready == 1'b1);

    @(posedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    wait (done == 1'b1);
    repeat (2) @(posedge clk);

    $stop;
  end

endmodule
