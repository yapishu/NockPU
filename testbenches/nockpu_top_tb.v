`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"

module nockpu_top_tb();

parameter MEM_INIT_FILE = "./memory/constant_tb.hex";
parameter integer MAX_CYCLES = 1000000;

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
  .hint_tag (hint_tag)
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
`ifdef TRACE_HOST
    $display("host_read start addr %0d", addr);
`endif
    host_addr = addr;
    host_we = 1'b0;
    host_req = 1'b1;
`ifdef TRACE_HOST
    $display("host_req asserted time %0t ready %0d", $time, host_ready);
`endif
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
`ifdef TRACE_HOST
    $display("host_read done addr %0d data %h", addr, data);
`endif
  end
endtask

reg [`memory_data_width - 1:0] read_word;
reg [8*256-1:0] mem_init_file;
integer cycle_count;
integer wait_cycles;

initial begin
  mem_init_file = MEM_INIT_FILE;
  if ($value$plusargs("mem=%s", mem_init_file)) begin
  end
  if (mem_init_file != "") begin
    $readmemh(mem_init_file, dut.mem.ram.ram, 0, 2047);
  end

  start_addr = 1;
  start = 1'b0;
  host_req = 1'b0;
  host_we = 1'b0;
  host_addr = 0;
  host_wdata = 0;

  cycle_count = 0;
  rst = 1'b0;
  repeat (2) @(posedge clk);
  rst = 1'b1;

  wait (host_ready);
  host_read(1, read_word);
`ifdef TRACE_HOST
  $display("initial ram[1] %h", read_word);
`endif

  start = 1'b1;
  @(posedge clk);
  start = 1'b0;
  wait_cycles = 0;
  while (!done && wait_cycles < MAX_CYCLES) begin
    @(posedge clk);
    wait_cycles = wait_cycles + 1;
  end
  if (!done) begin
    $display("FAIL done timeout");
    $finish;
  end

  host_read(1, read_word);
  if (read_word !== 64'h0300000a400000ae) begin
    $display("FAIL expected 0300000a400000ae got %h", read_word);
    $finish;
  end
  $display("PASS");
  $finish;
end

always @(posedge clk) begin
  if (rst) begin
    cycle_count <= cycle_count + 1;
  end else begin
    cycle_count <= 0;
  end
end

`ifdef TRACE_HOST
reg host_ready_prev;
reg host_busy_prev;
reg host_rvalid_prev;
always @(host_req) begin
  $display("time %0t host_req %0d", $time, host_req);
end
always @(posedge clk) begin
  if (!rst) begin
    host_ready_prev <= 1'b0;
    host_busy_prev <= 1'b0;
    host_rvalid_prev <= 1'b0;
  end else begin
    if (host_ready != host_ready_prev
        || dut.host_busy != host_busy_prev
        || host_rvalid != host_rvalid_prev
        || host_req
        || host_we
        || start) begin
      $display("cycle %0d ready %0d req %0d we %0d exec %0d busy %0d mem_ready %0d rvalid %0d done %0d",
               cycle_count,
               host_ready,
               host_req,
               host_we,
               dut.host_exec,
               dut.host_busy,
               dut.mem_ready,
               host_rvalid,
               done);
    end
    host_ready_prev <= host_ready;
    host_busy_prev <= dut.host_busy;
    host_rvalid_prev <= host_rvalid;
  end
end
`endif

endmodule
