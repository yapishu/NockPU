`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"

module gc_pressure_tb();

parameter MEM_INIT_FILE = "./memory/increment.hex";
parameter integer MAX_CYCLES = 200000;

reg clk;
reg rst;
reg start;
reg [`memory_addr_width - 1:0] start_addr;
reg host_req;
reg host_we;
reg [`memory_addr_width - 1:0] host_addr;
reg [`memory_data_width - 1:0] host_wdata;
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

nockpu_top dut(
  .clk (clk),
  .rst (rst),
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

initial begin
  clk = 0;
  forever #10 clk = ~clk;
end

task host_read;
  input [`memory_addr_width - 1:0] addr;
  output [`memory_data_width - 1:0] data;
  integer wait_cycles;
  begin
    host_addr = addr;
    host_we = 1'b0;
    host_req = 1'b1;
    wait_cycles = 0;
    while (!host_ready && wait_cycles < MAX_CYCLES) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!host_ready) begin
      $display("FAIL host_ready timeout");
      $finish;
    end
    @(posedge clk);
    @(posedge clk);
    host_req = 1'b0;
    wait_cycles = 0;
    while (!host_rvalid && wait_cycles < MAX_CYCLES) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!host_rvalid) begin
      $display("FAIL host_rvalid timeout");
      $finish;
    end
    data = host_rdata;
  end
endtask

localparam integer MEM_DEPTH = 1 << `memory_addr_width;
localparam integer MEM_LAST = MEM_DEPTH - 1;
localparam integer MEMORY_MASK = 1 << (`memory_addr_width - 1);
localparam [`memory_addr_width - 1:0] FORCE_FREE = MEMORY_MASK - 1;
localparam [`memory_data_width - 1:0] EXPECTED_ROOT = 64'h030000097fffffff;

reg [8*256-1:0] mem_init_file;
reg [`memory_data_width - 1:0] read_word;
integer wait_cycles;
reg gc_seen;
reg busy_seen;

always @(posedge clk or negedge rst) begin
  if (!rst) begin
    gc_seen <= 1'b0;
    busy_seen <= 1'b0;
  end else if (dut.mem.gc) begin
    gc_seen <= 1'b1;
    if (busy) begin
      busy_seen <= 1'b1;
    end
  end else if (busy) begin
    busy_seen <= 1'b1;
  end
end

initial begin
  mem_init_file = MEM_INIT_FILE;
  if ($value$plusargs("mem=%s", mem_init_file)) begin
  end
  if (mem_init_file != "") begin
    $readmemh(mem_init_file, dut.mem.ram.ram, 0, MEM_LAST);
  end

  dut.mem.ram.ram[0] = {`memory_data_width{1'b0}};
  dut.mem.ram.ram[0][`memory_addr_width - 1:0] = FORCE_FREE;

  start_addr = 1;
  start = 1'b0;
  host_req = 1'b0;
  host_we = 1'b0;
  host_addr = 0;
  host_wdata = 0;

  rst = 1'b0;
  repeat (2) @(posedge clk);
  rst = 1'b1;

  wait (host_ready);
  start = 1'b1;
  @(posedge clk);
  @(negedge clk);
  start = 1'b0;

  wait_cycles = 0;
  while (!busy && wait_cycles < MAX_CYCLES) begin
    @(posedge clk);
    wait_cycles = wait_cycles + 1;
  end
  if (!busy) begin
    $display("FAIL busy timeout");
    $display("debug: start %0d host_busy %0d running %0d host_ready %0d mem_ready %0d busy_seen %0d", start, dut.host_busy, dut.running, host_ready, dut.mem_ready, busy_seen);
    $finish;
  end

  wait_cycles = 0;
  while (!done && wait_cycles < MAX_CYCLES) begin
    @(posedge clk);
    wait_cycles = wait_cycles + 1;
  end
  if (!done) begin
    $display("FAIL done timeout");
    $display("debug: sel %0d trav_state %0d exec_func %0d exec_state %0d mem_state %0d mem_gc_state %0d mem_ready %0d mem_execute %0d mem_func %0d gc %0d gc_ready %0d gc_seen %0d",
             dut.select,
             dut.traversal.state,
             dut.execute.exec_func,
             dut.execute.state,
             dut.mem.state,
             dut.mem.gc_state,
             dut.mem_ready,
             dut.mem_execute,
             dut.mem_func,
             dut.gc,
             dut.traversal.gc_ready,
             gc_seen);
    $finish;
  end
  if (!gc_seen) begin
    $display("FAIL gc not observed");
    $finish;
  end
  if (error !== 8'h00 || edit_error !== 8'h00) begin
    $display("FAIL error %h edit_error %h", error, edit_error);
    $finish;
  end

  host_read(root_ptr, read_word);
  if (read_word !== EXPECTED_ROOT) begin
    $display("FAIL expected %h got %h root_ptr %0d", EXPECTED_ROOT, read_word, root_ptr);
    $finish;
  end

  $display("PASS");
  $finish;
end

endmodule
