`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"


module memory_unit_tb();

//Test Parameters
parameter MEM_INIT_FILE = "./memory/memory.hex";
parameter MEM_WRITE_DATA = 64'hDEADBEEF;
localparam integer MEM_DEPTH = 1 << `memory_addr_width;
localparam integer MEM_LAST = MEM_DEPTH - 1;
localparam [`memory_addr_width - 1:0] FREE_INIT_ADDR = `memory_addr_width'd1500;
localparam [`memory_addr_width - 1:0] SPACE_BASE =
  (1 << (`memory_addr_width - 1));

//Signal Declarations
reg MAX10_CLK1_50;

wire clk;
assign clk = MAX10_CLK1_50;

reg reset;


reg [1:0] mem_func;

reg mem_execute;
wire power;
assign power = 1'b1;

reg [`memory_addr_width - 1:0] addr1;
reg [`memory_addr_width - 1:0] addr2;

reg [`memory_data_width - 1:0] write_data;
wire [`memory_addr_width - 1:0] free_addr;
wire [`memory_addr_width - 1:0] free_ptr;
wire [`memory_data_width - 1:0] read_data1;
wire [`memory_data_width - 1:0] read_data2;
wire [`memory_data_width - 1:0] mem_data_out1;
wire [`memory_data_width - 1:0] mem_data_out2;
wire gc;
reg gc_ready;

reg [`memory_addr_width - 1:0] free_addr_reg;

wire mem_ready;


// Instantiate Memory Unit
memory_unit mem(.func (mem_func),
                .execute (mem_execute),
                .address1 (addr1),
                .address2 (addr2),
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

// Setup Clock
initial begin
  MAX10_CLK1_50 =0;
  forever MAX10_CLK1_50 = #10 ~MAX10_CLK1_50;
end

always @(posedge clk) begin
  if ($test$plusargs("debug")) begin
    $display("t=%0t state=%0d exec=%b func=%b mem_req=%b mem_write=%b mem_ready=%b addr1=%0d",
             $time, mem.state, mem_execute, mem_func, mem.mem_req, mem.mem_write,
             mem_ready, mem.mem_addr1);
  end
end

integer idx;

task mem_request;
  input [1:0] func;
  input [`memory_addr_width - 1:0] a1;
  input [`memory_addr_width - 1:0] a2;
  input [`memory_data_width - 1:0] wdata;
  begin
    mem_func = func;
    addr1 = a1;
    addr2 = a2;
    write_data = wdata;
    mem_execute = 1'b1;
    @(posedge clk);
    @(posedge clk);
    mem_execute = 1'b0;
    wait (mem_ready == 1'b1);
  end
endtask

// Perform Test
initial begin
  if (MEM_INIT_FILE != "") begin
    $readmemh(MEM_INIT_FILE, mem.ram.ram, 0, MEM_LAST);
  end
  mem.ram.ram[0] = FREE_INIT_ADDR;
  if ($test$plusargs("dump")) begin
    $dumpfile("memory_unit_tb.vcd");
    $dumpvars(0, memory_unit_tb);
  end


  mem_execute = 0;
  gc_ready = 1'b1;
  addr1 = 0;
  addr2 = 0;
  // Reset
  reset = 1'b0;
  repeat (2) @(posedge clk);
  reset = 1'b1;
  wait (mem_ready == 1'b1);
  if (free_addr !== FREE_INIT_ADDR) begin
    $display("FAIL free init expected %0d got %0d", FREE_INIT_ADDR, free_addr);
    $finish;
  end
  mem.old_root = SPACE_BASE;
  mem.new_root = `memory_addr_width'd1;


  // Get Next Free Memory Location
  mem_request(`GET_FREE, 0, 0, 1);
  free_addr_reg = free_addr;


  // Write to Free Addr
  mem_request(`SET_CONTENTS, free_addr_reg, 0, MEM_WRITE_DATA);
  if ($test$plusargs("debug")) begin
    $display("debug mem[%0d] %h", free_addr_reg, mem.ram.ram[free_addr_reg]);
  end
  mem_request(`GET_CONTENTS, free_addr_reg, 0, 0);
  if (read_data1 !== MEM_WRITE_DATA) begin
    $display("FAIL mem readback expected %h got %h", MEM_WRITE_DATA, read_data1);
    $finish;
  end

  // Get Next Free Memory Location
  mem_request(`GET_FREE, 0, 0, 4);
  if (free_addr !== free_addr_reg + 1'b1) begin
    $display("FAIL free addr expected %0d got %0d", free_addr_reg + 1'b1, free_addr);
    $finish;
  end
  free_addr_reg = free_addr;
  $display("PASS");
  $finish;
end

endmodule
