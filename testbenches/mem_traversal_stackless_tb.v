`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"

module mem_traversal_stackless_tb();

// Test Parameters
parameter MEM_INIT_FILE = "./memory/traversal_only.hex";
parameter integer MAX_CYCLES = 200000;
localparam integer MEM_DEPTH = 1 << `memory_addr_width;
localparam integer MEM_LAST = MEM_DEPTH - 1;

// Signal Declarations
reg MAX10_CLK1_50;

wire clk;
assign clk = MAX10_CLK1_50;

reg reset;

wire power;
assign power = 1'b1;

wire [1:0] mem_func;
wire mem_execute;
wire [`memory_addr_width - 1:0] address1;
wire [`memory_addr_width - 1:0] address2;
wire [`memory_data_width - 1:0] write_data;
wire [`memory_addr_width - 1:0] free_addr;
wire [`memory_addr_width - 1:0] free_ptr;
wire [`memory_data_width - 1:0] read_data1;
wire [`memory_data_width - 1:0] read_data2;
wire [`memory_data_width - 1:0] mem_data_out1;
wire [`memory_data_width - 1:0] mem_data_out2;
wire gc;
wire gc_ready;

wire mem_ready;

reg traversal_execute;
wire traversal_finished;

reg [`memory_addr_width - 1:0] start_addr;
wire [`memory_addr_width - 1:0] root_addr;
wire [7:0] traversal_error;
wire module_finished;
wire [3:0] return_sys_func;
wire [3:0] return_state;
wire [`memory_addr_width - 1:0] module_address;
wire [`memory_data_width - 1:0] module_data;
wire [2:0] mux_controller;
assign module_finished = 1'b1;
assign return_sys_func = 4'b0;
assign return_state = 4'b0;

// Instantiate MTU
memory_unit mem(.func (mem_func),
                .execute (mem_execute),
                .address1 (address1),
                .address2 (address2),
                .write_data (write_data),
                .free_addr (free_addr),
                .free_ptr (free_ptr),
                .read_data1 (read_data1),
                .read_data2 (read_data2),
                .gc (gc),
                .gc_ready (gc_ready),
                .is_ready (mem_ready),
                .power (power),
                .clk (clk),
                .mem_data_out1 (mem_data_out1),
                .mem_data_out2 (mem_data_out2),
                .rst (reset));

mem_traversal_stackless traversal(.power (power),
                        .clk (clk),
                        .rst (reset),
                        .start_addr (start_addr),
                        .root_addr (root_addr),
                        .execute (traversal_execute),
                        .gc (gc),
                        .gc_ready (gc_ready),
                        .mem_ready (mem_ready),
                        .address1 (address1),
                        .address2 (address2),
                        .read_data1 (read_data1),
                        .read_data2 (read_data2),
                        .mem_execute (mem_execute),
                        .mem_func (mem_func),
                        .free_addr (free_addr),
                        .write_data (write_data),
                        .finished (traversal_finished),
                        .traversal_error (traversal_error),
                        .module_address (module_address),
                        .module_data (module_data),
                        .mux_controller (mux_controller),
                        .module_finished (module_finished),
                        .return_sys_func (return_sys_func),
                        .return_state (return_state));

// Setup Clock
initial begin
  MAX10_CLK1_50 = 0;
  forever MAX10_CLK1_50 = #10 ~MAX10_CLK1_50;
end

// Perform Test
initial begin
  for (integer idx = 0; idx < MEM_DEPTH; idx = idx + 1) begin
    mem.ram.ram[idx] = {`memory_data_width{1'b0}};
  end
  if (MEM_INIT_FILE != "") begin
    $readmemh(MEM_INIT_FILE, mem.ram.ram);
  end

  start_addr = 1;
  traversal_execute = 0;

  // Reset
  reset = 1'b0;
  repeat (2) @(posedge clk);
  reset = 1'b1;
  wait (mem_ready == 1'b1);

  traversal_execute = 1;

  for (integer cycles = 0; cycles < MAX_CYCLES && !traversal_finished; cycles = cycles + 1) begin
    @(posedge clk);
  end
  if (!traversal_finished) begin
    $display("FAIL traversal timeout");
    $finish;
  end
  if (traversal_error !== 8'h00) begin
    $display("FAIL traversal_error %h", traversal_error);
    $finish;
  end
  repeat (2) @(posedge clk);

  $display("PASS");
  $finish;
end

endmodule
