`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"


module mem_traversal_tb();

//Test Parameters
parameter MEM_INIT_FILE = "./memory/memory.hex";
parameter integer MAX_CYCLES = 200000;
localparam integer MEM_DEPTH = 1 << `memory_addr_width;
localparam integer MEM_LAST = MEM_DEPTH - 1;

//Signal Declarations
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
wire [7:0] error;
wire module_finished;
wire [3:0] execute_return_sys_func;
wire [3:0] execute_return_state;
wire [`memory_addr_width - 1:0] module_address;
wire [`memory_data_width - 1:0] module_data;
wire [2:0] mux_controller;
assign error = 8'b0;
assign module_finished = 1'b1;
assign execute_return_sys_func = 4'b0;
assign execute_return_state = 4'b0;


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

mem_traversal traversal(.power (power),
                        .clk (clk),
                        .rst (reset),
                        .start_addr (start_addr),
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
                        .finished(traversal_finished),
                        .error (error),
                        .module_address (module_address),
                        .module_data (module_data),
                        .mux_controller (mux_controller),
                        .module_finished (module_finished),
                        .execute_return_sys_func (execute_return_sys_func),
                        .execute_return_state (execute_return_state));

// Setup Clock
initial begin
  MAX10_CLK1_50 =0;
  forever MAX10_CLK1_50 = #10 ~MAX10_CLK1_50;
end


// Perform Test
initial begin
  if (MEM_INIT_FILE != "") begin
    $readmemh(MEM_INIT_FILE, mem.ram.ram, 0, MEM_LAST);
  end

  start_addr = 1;
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
  repeat (2) @(posedge clk);

  $display("PASS");
  $finish;
end

endmodule
