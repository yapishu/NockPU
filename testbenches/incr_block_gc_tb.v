`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"
`include "../verilog/memory_mux.vh"
`include "../verilog/execute.vh"

module incr_block_gc_tb();
  reg clk;
  reg rst;
  reg [2:0] incr_start;
  reg [`memory_addr_width - 1:0] incr_address;
  reg [`memory_data_width - 1:0] incr_data;
  wire [3:0] incr_return_sys_func;
  wire [3:0] incr_return_state;
  reg mem_ready;
  reg gc;
  reg [`memory_data_width - 1:0] read_data1;
  reg [`memory_data_width - 1:0] read_data2;
  reg [`memory_addr_width - 1:0] free_addr;
  wire mem_execute;
  wire [`memory_addr_width - 1:0] address1;
  wire [`memory_addr_width - 1:0] address2;
  wire [1:0] mem_func;
  wire [`memory_data_width - 1:0] write_data;
  wire finished;
  wire [7:0] incr_error;

  localparam [`noun_width-1:0] ATOM_MAX = {`noun_width{1'b1}};

  incr_block dut(
    .clk (clk),
    .rst (rst),
    .incr_error (incr_error),
    .incr_start (incr_start),
    .incr_address (incr_address),
    .incr_data (incr_data),
    .incr_return_sys_func (incr_return_sys_func),
    .incr_return_state (incr_return_state),
    .mem_ready (mem_ready),
    .gc (gc),
    .read_data1 (read_data1),
    .read_data2 (read_data2),
    .free_addr (free_addr),
    .mem_execute (mem_execute),
    .address1 (address1),
    .address2 (address2),
    .mem_func (mem_func),
    .write_data (write_data),
    .finished (finished)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  reg saw_get_free;
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      mem_ready <= 1'b0;
      gc <= 1'b0;
      saw_get_free <= 1'b0;
    end else begin
      gc <= 1'b0;
      mem_ready <= 1'b1;
      if (mem_execute && mem_func == `GET_FREE && !saw_get_free) begin
        saw_get_free <= 1'b1;
      end else if (saw_get_free) begin
        gc <= 1'b1;
        mem_ready <= 1'b0;
        saw_get_free <= 1'b0;
      end
    end
  end

  integer cycles;
  initial begin
    rst = 1'b0;
    incr_start = 3'b000;
    incr_address = {`memory_addr_width{1'b0}};
    incr_data = {`memory_data_width{1'b0}};
    read_data1 = {`memory_data_width{1'b0}};
    read_data2 = {`memory_data_width{1'b0}};
    free_addr = {`memory_addr_width{1'b0}};

    repeat (2) @(posedge clk);
    rst = 1'b1;

    incr_start = `MUX_INCR;
    incr_address = {`memory_addr_width{1'b1}};
    incr_data = {6'b000000, `ATOM, `ATOM, `noun_width'h0, ATOM_MAX};

    cycles = 0;
    while (!finished && cycles < 50) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (!finished) begin
      $display("FAIL incr_block gc timeout");
      $finish;
    end

    if (incr_return_sys_func !== `SYS_FUNC_READ
        || incr_return_state !== `SYS_READ_INIT) begin
      $display("FAIL incr_block gc return mismatch");
      $finish;
    end

    if (incr_error !== 8'h00) begin
      $display("FAIL incr_block gc error %h", incr_error);
      $finish;
    end

    $display("PASS");
    $finish;
  end
endmodule
