`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"


module execute_tb();

//Test Parameters
//parameter MEM_INIT_FILE = "./memory/autocons.hex";
//parameter MEM_INIT_FILE = "./memory/autocons2.hex";
//parameter MEM_INIT_FILE = "./memory/slot_tb.hex";
//parameter MEM_INIT_FILE = "./memory/constant_tb.hex";
//parameter MEM_INIT_FILE = "./memory/evaluate.hex";
//parameter MEM_INIT_FILE = "./memory/evaluate2.hex";
//parameter MEM_INIT_FILE = "./memory/evaluate3.hex";
//parameter MEM_INIT_FILE = "./memory/evaluate4.hex";
//parameter MEM_INIT_FILE = "./memory/inc_slot.hex";
//parameter MEM_INIT_FILE = "./memory/cell_tb.hex";
//parameter MEM_INIT_FILE = "./memory/cell_auto.hex";
//parameter MEM_INIT_FILE = "./memory/nested_increment.hex";
//parameter MEM_INIT_FILE = "./memory/increment.hex";
//parameter MEM_INIT_FILE = "./memory/opcode_5/yes_atom.hex";
//parameter MEM_INIT_FILE = "./memory/opcode_5/yes_cell.hex";
//parameter MEM_INIT_FILE = "./memory/opcode_5/yes_deep_cell.hex";
//parameter MEM_INIT_FILE = "./memory/opcode_5/nested_yes.hex";
//parameter MEM_INIT_FILE = "./memory/opcode_5/no_atom.hex";
//parameter MEM_INIT_FILE = "./memory/opcode_5/no_atom_cell.hex";
//parameter MEM_INIT_FILE = "./memory/opcode_5/no_deep_cell.hex";
//parameter MEM_INIT_FILE = "./memory/add_equal.hex";
//parameter MEM_INIT_FILE = "./memory/atom_incr.hex";
//parameter MEM_INIT_FILE = "./memory/if_ans2.hex";
//parameter MEM_INIT_FILE = "./memory/opcode7.hex";
//parameter MEM_INIT_FILE = "./memory/opcode8.hex";
//parameter MEM_INIT_FILE = "./memory/opcode8_nested.hex";
//parameter MEM_INIT_FILE = "./memory/opcode8_2.hex";
//parameter MEM_INIT_FILE = "./memory/opcode9_tmp.hex";
//parameter MEM_INIT_FILE = "./memory/opcode9.hex";
//parameter MEM_INIT_FILE = "./memory/opcode9_incr.hex";
//parameter MEM_INIT_FILE = "./memory/opcode9_9201.hex";
//parameter MEM_INIT_FILE = "./memory/wtf.hex";
parameter MEM_INIT_FILE = "./memory/decrement.hex";
parameter integer MAX_CYCLES = 0;
parameter DUMP_MEM_FILE = "";
//parameter MEM_INIT_FILE = "./memory/ackerman_1_2.hex";
//parameter MEM_INIT_FILE = "./memory/add.hex";
//parameter MEM_INIT_FILE = "./memory/cap.hex";
//parameter MEM_INIT_FILE = "./memory/opcode10.hex";
//parameter MEM_INIT_FILE = "./memory/opcode11_static.hex";
//parameter MEM_INIT_FILE = "./memory/opcode11_dynamic.hex";

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

wire mem_ready;

reg traversal_execute;
wire traversal_finished;

reg [`memory_addr_width - 1:0] start_addr;
wire [`memory_addr_width - 1:0] root_addr;

//GC signals

wire gc; // wire from MMU to MTU signaling a GC
wire gc_ready; // wire from MTU to MMU signaling MTU is ready for GC 
reg gc_seen;

//Signal from Control Mux to MTU 
wire [`memory_addr_width - 1:0] module_address;
wire [`memory_data_width - 1:0] module_data;
wire module_finished;
wire [3:0] return_sys_func;
wire [3:0] return_state;

// Signal from MTU to memory Mux
wire [1:0] mem_func_mtu;
wire mem_execute_mtu;
wire [`memory_addr_width - 1:0] address1_mtu;
wire [`memory_addr_width - 1:0] address2_mtu;
wire [`memory_data_width - 1:0] write_data_mtu;
wire [2:0] select;

//Signal from NEM (Nock Execution Module) to memory Mux
wire [1:0] mem_func_nem;
wire mem_execute_nem;
wire [`memory_addr_width - 1:0] address1_nem;
wire [`memory_addr_width - 1:0] address2_nem;
wire [`memory_data_width - 1:0] write_data_nem;
wire [`noun_width-1:0] hint;
wire hint_tag;

//Signal from MTU to NEM
wire [`memory_addr_width - 1:0] execute_address;
wire [`memory_data_width - 1:0] execute_data;
wire execute_finished;
wire [3:0] execute_return_sys_func;
wire [3:0] execute_return_state;
wire [`tag_width - 1:0] exec_error;//do we need?
wire [`tag_width - 1:0] traversal_error;
wire [`tag_width - 1:0] error;
assign error = (traversal_error != 0) ? traversal_error
             : (exec_error != 0) ? exec_error
             : incr_error;

//Signal from cell module to memory Mux
wire [1:0] mem_func_cell;
wire mem_execute_cell;
wire [`memory_addr_width - 1:0] address1_cell;
wire [`memory_addr_width - 1:0] address2_cell;
wire [`memory_data_width - 1:0] write_data_cell;

//Signal from MTU to cell Module
wire [`memory_addr_width - 1:0] cell_address;
wire [`memory_data_width - 1:0] cell_data;
wire cell_finished;
wire [3:0] cell_return_sys_func;
wire [3:0] cell_return_state;
wire [`tag_width - 1:0] cell_error;

//Signal from incr module to memory Mux
wire [1:0] mem_func_incr;
wire mem_execute_incr;
wire [`memory_addr_width - 1:0] address1_incr;
wire [`memory_addr_width - 1:0] address2_incr;
wire [`memory_data_width - 1:0] write_data_incr;

//Signal from MTU to incr Module
wire [`memory_addr_width - 1:0] incr_address;
wire [`memory_data_width - 1:0] incr_data;
wire incr_finished;
wire [3:0] incr_return_sys_func;
wire [3:0] incr_return_state;
wire [`tag_width - 1:0] incr_error;

//Signal from incr module to memory Mux
wire [1:0] mem_func_equal;
wire mem_execute_equal;
wire [`memory_addr_width - 1:0] address1_equal;
wire [`memory_addr_width - 1:0] address2_equal;
wire [`memory_data_width - 1:0] write_data_equal;

//Signal from MTU to equal Module
wire [`memory_addr_width - 1:0] equal_address;
wire [`memory_data_width - 1:0] equal_data;
wire equal_finished;
wire [3:0] equal_return_sys_func;
wire [3:0] equal_return_state;
wire [`tag_width - 1:0] equal_error;

//Signal from edit module to memory Mux
wire [1:0] mem_func_edit;
wire mem_execute_edit;
wire [`memory_addr_width - 1:0] address1_edit;
wire [`memory_addr_width - 1:0] address2_edit;
wire [`memory_data_width - 1:0] write_data_edit;

//Signal from MTU to edit Module
wire [`memory_addr_width - 1:0] edit_address;
wire [`memory_data_width - 1:0] edit_data;
wire edit_finished;
wire [3:0] edit_return_sys_func;
wire [3:0] edit_return_state;
wire [`tag_width - 1:0] edit_error;



// Instantiate Memory Unit
memory_unit mem(.func (mem_func),
                .execute (mem_execute),
                .address1 (address1),
                .address2 (address2),
                .write_data (write_data),
                .free_addr (free_addr),
                .free_ptr (free_ptr),
                .read_data1 (read_data1),
                .read_data2 (read_data2),
                .is_ready (mem_ready),
                .power (power),
                .clk (clk),
                .mem_data_out1 (mem_data_out1),
                .mem_data_out2 (mem_data_out2),
                .rst (reset),
                .gc (gc),
                .gc_ready (gc_ready));

// Instantiate Memory Mux
memory_mux memory_mux(.mem_func_a (mem_func_mtu),
                      .execute_a (mem_execute_mtu),
                      .address1_a (address1_mtu),
                      .address2_a (address2_mtu),
                      .write_data_a (write_data_mtu),
                      .mem_func_b (mem_func_nem),
                      .execute_b (mem_execute_nem),
                      .address1_b (address1_nem),
                      .address2_b (address2_nem),
                      .write_data_b (write_data_nem),
                      .mem_func_c (mem_func_cell),
                      .execute_c (mem_execute_cell),
                      .address1_c (address1_cell),
                      .address2_c (address2_cell),
                      .write_data_c (write_data_cell),
                      .mem_func_d (mem_func_incr),
                      .execute_d (mem_execute_incr),
                      .address1_d (address1_incr),
                      .address2_d (address2_incr),
                      .write_data_d (write_data_incr),
                      .mem_func_e (mem_func_equal),
                      .execute_e (mem_execute_equal),
                      .address1_e (address1_equal),
                      .address2_e (address2_equal),
                      .write_data_e (write_data_equal),
                      .mem_func_f (mem_func_edit),
                      .execute_f (mem_execute_edit),
                      .address1_f (address1_edit),
                      .address2_f (address2_edit),
                      .write_data_f (write_data_edit),
                      .sel (select),
                      .mem_func (mem_func),
                      .execute (mem_execute),
                      .address1 (address1),
                      .address2 (address2),
                      .write_data (write_data));

// Instantiate Control Mux
control_mux control_mux(.sel (select),
                        .finished (module_finished),
                        .return_sys_func (return_sys_func),
                        .return_state (return_state),
                        .module_address (module_address),
                        .module_data (module_data),
                        .execute_finished (execute_finished),
                        .execute_return_sys_func (execute_return_sys_func),
                        .execute_return_state (execute_return_state),
                        .execute_address (execute_address),
                        .execute_data (execute_data),
                        .cell_finished (cell_finished),
                        .cell_return_sys_func (cell_return_sys_func),
                        .cell_return_state (cell_return_state),
                        .cell_address (cell_address),
                        .cell_data (cell_data),
                        .incr_finished (incr_finished),
                        .incr_return_sys_func (incr_return_sys_func),
                        .incr_return_state (incr_return_state),
                        .incr_address (incr_address),
                        .incr_data (incr_data),
                        .equal_finished (equal_finished),
                        .equal_return_sys_func (equal_return_sys_func),
                        .equal_return_state (equal_return_state),
                        .equal_address (equal_address),
                        .equal_data (equal_data),
                        .edit_finished (edit_finished),
                        .edit_return_sys_func (edit_return_sys_func),
                        .edit_return_state (edit_return_state),
                        .edit_address (edit_address),
                        .edit_data (edit_data)
                      );
// Instantiate MTU
`ifdef NPU_STACKLESS_TRAV
mem_traversal_stackless traversal(.power (power),
                        .clk (clk),
                        .rst (reset),
                        .start_addr (start_addr),
                        .root_addr (root_addr),
                        .execute (traversal_execute),
                        .gc (gc),
                        .gc_ready (gc_ready),
                        .mem_ready (mem_ready),
                        .address1 (address1_mtu),
                        .address2 (address2_mtu),
                        .read_data1 (read_data1),
                        .read_data2 (read_data2),
                        .mem_execute (mem_execute_mtu),
                        .mem_func (mem_func_mtu),
                        .free_addr (free_addr),
                        .write_data (write_data_mtu),
                        .finished(traversal_finished),
                        .traversal_error(traversal_error),
                        .mux_controller(select),
                        .module_address(module_address),
                        .module_data(module_data),
                        .module_finished(module_finished),
                        .return_sys_func(return_sys_func),
                        .return_state(return_state));
`else
mem_traversal traversal(.power (power),
                        .clk (clk),
                        .rst (reset),
                        .start_addr (start_addr),
                        .root_addr (root_addr),
                        .execute (traversal_execute),
                        .gc (gc),
                        .gc_ready (gc_ready),
                        .mem_ready (mem_ready),
                        .address1 (address1_mtu),
                        .address2 (address2_mtu),
                        .read_data1 (read_data1),
                        .read_data2 (read_data2),
                        .mem_execute (mem_execute_mtu),
                        .mem_func (mem_func_mtu),
                        .free_addr (free_addr),
                        .write_data (write_data_mtu),
                        .finished(traversal_finished),
                        .traversal_error(traversal_error),
                        .mux_controller(select),
                        .module_address(module_address),
                        .module_data(module_data),
                        .module_finished(module_finished),
                        .return_sys_func(return_sys_func),
                        .return_state(return_state));
`endif

//Instantiate Nock Execute Module
execute execute(.clk(clk),
                .rst(reset),
                .error(exec_error),
                .execute_start(select),
                .execute_address(execute_address),
                .execute_data(execute_data),
                .gc(gc),
                .mem_ready(mem_ready),
                .mem_execute(mem_execute_nem),
                .mem_func(mem_func_nem),
                .address1(address1_nem),
                .address2(address2_nem),
                .free_addr(free_addr),
                .read_data1(read_data1),
                .read_data2(read_data2),
                .write_data(write_data_nem),
                .finished(execute_finished),
                .hint(hint),
                .hint_tag(hint_tag),
                .execute_return_sys_func(execute_return_sys_func),
                .execute_return_state(execute_return_state));

//Instantiate Nock cell Module
cell_block cell_block(.clk(clk),
                      .rst(reset),
                      .cell_error(cell_error),
                      .cell_start(select),
                      .cell_address(cell_address),
                      .cell_data(cell_data),
                      .mem_ready(mem_ready),
                      .mem_execute(mem_execute_cell),
                      .mem_func(mem_func_cell),
                      .address1(address1_cell),
                      .address2(address2_cell),
                      .free_addr(free_addr),
                      .read_data1(read_data1),
                      .read_data2(read_data2),
                      .write_data(write_data_cell),
                      .finished(cell_finished),
                      .cell_return_sys_func(cell_return_sys_func),
                      .cell_return_state(cell_return_state));

//Instantiate Nock increment Module
incr_block incr_block(.clk(clk),
                      .rst(reset),
                      .incr_error(incr_error),
                      .incr_start(select),
                      .incr_address(incr_address),
                      .incr_data(incr_data),
                      .mem_ready(mem_ready),
                      .gc(gc),
                      .mem_execute(mem_execute_incr),
                      .mem_func(mem_func_incr),
                      .address1(address1_incr),
                      .address2(address2_incr),
                      .free_addr(free_addr),
                      .read_data1(read_data1),
                      .read_data2(read_data2),
                      .write_data(write_data_incr),
                      .finished(incr_finished),
                      .incr_return_sys_func(incr_return_sys_func),
                      .incr_return_state(incr_return_state));

//Instantiate Nock Equal Module
equal_block equal_block(.clk(clk),
                        .rst(reset),
                        .equal_error(equal_error),
                        .equal_start(select),
                        .equal_address(equal_address),
                        .equal_data(equal_data),
                        .mem_ready(mem_ready),
                        .mem_execute(mem_execute_equal),
                        .mem_func(mem_func_equal),
                        .address1(address1_equal),
                        .address2(address2_equal),
                        .free_addr(free_addr),
                        .read_data1(read_data1),
                        .read_data2(read_data2),
                        .write_data(write_data_equal),
                        .finished(equal_finished),
                        .equal_return_sys_func(equal_return_sys_func),
                        .equal_return_state(equal_return_state));

//Instantiate Nock edit Module
edit_block edit_block(.clk(clk),
                      .rst(reset),
                      .edit_error(edit_error),
                      .edit_start(select),
                      .edit_address(edit_address),
                      .edit_data(edit_data),
                      .mem_ready(mem_ready),
                      .mem_execute(mem_execute_edit),
                      .mem_func(mem_func_edit),
                      .address1(address1_edit),
                      .address2(address2_edit),
                      .free_addr(free_addr),
                      .read_data1(read_data1),
                      .read_data2(read_data2),
                      .write_data(write_data_edit),
                      .finished(edit_finished),
                      .edit_return_sys_func(edit_return_sys_func),
                      .edit_return_state(edit_return_state));



// Setup Clock
initial begin
  MAX10_CLK1_50 =0;
  forever MAX10_CLK1_50 = #10 ~MAX10_CLK1_50;
end

integer cycle_count;
integer finish_cycle;
reg print_cycles;
reg stop_on_finish;

always @(posedge clk) begin
  if (!reset) begin
    cycle_count <= 0;
  end else begin
    cycle_count <= cycle_count + 1;
  end
end

`ifdef TRACE_GC
reg gc_prev;
reg gc_ready_prev;

always @(posedge clk) begin
  if (!reset) begin
    gc_prev <= 1'b0;
    gc_ready_prev <= 1'b0;
  end else begin
    if (gc && !gc_prev) begin
      $display("gc start cycle %0d free_addr %0d", cycle_count, free_addr);
    end
    if (!gc && gc_prev) begin
      $display("gc end cycle %0d free_addr %0d", cycle_count, free_addr);
    end
    if (gc_ready && !gc_ready_prev) begin
      $display("gc_ready asserted cycle %0d mem_addr %0d", cycle_count, address1_mtu);
    end
    if (!gc_ready && gc_ready_prev) begin
      $display("gc_ready deasserted cycle %0d", cycle_count);
    end
    gc_prev <= gc;
    gc_ready_prev <= gc_ready;
  end
end
`endif

`ifdef TRACE_PROGRESS
reg [2:0] select_prev;

always @(posedge clk) begin
  if (!reset) begin
    select_prev <= 0;
  end else if (select != select_prev) begin
    $display("time %0t select %0d", $time, select);
    select_prev <= select;
  end
end
`endif

`ifdef TRACE_ADDR19
always @(posedge clk) begin
  if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd19) begin
    $display("addr19 write sel %0d data %h", select, write_data);
  end
end
`endif

`ifdef TRACE_ADDR137
always @(posedge clk) begin
  if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd137) begin
    $display("addr137 write sel %0d data %h", select, write_data);
  end
end
`endif

`ifdef TRACE_ADDR130
always @(posedge clk) begin
  if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd130) begin
    $display("addr130 write sel %0d data %h", select, write_data);
  end
end
`endif

`ifdef TRACE_ADDR41
always @(posedge clk) begin
  if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd65) begin
    $display("addr41 write sel %0d data %h", select, write_data);
  end
end
`endif

`ifdef TRACE_SELF_REF
always @(posedge clk) begin
  if (mem_execute && mem_func == `SET_CONTENTS) begin
    if ((write_data[`hed_tag] == `CELL && write_data[`hed_start:`hed_end] == address1)
        || (write_data[`tel_tag] == `CELL && write_data[`tel_start:`tel_end] == address1)) begin
      $display("self ref write addr %0d sel %0d data %h", address1, select, write_data);
    end
  end
end
`endif

integer idx;
localparam integer MEM_DEPTH = 1 << `memory_addr_width;
localparam integer MEM_LAST = MEM_DEPTH - 1;
localparam integer SPACE_BASE = 1 << (`memory_addr_width - 1);
localparam integer MEMORY_MASK = 1 << (`memory_addr_width - 1);
localparam integer FORCE_FREE_DEFAULT = MEMORY_MASK - 1;
reg [8*256-1:0] mem_init_file;
reg [8*256-1:0] dump_mem_file;
integer max_cycles;
integer force_free_value;
reg force_free_valid;
reg force_gc;

always @(posedge clk or negedge reset) begin
  if (!reset) begin
    gc_seen <= 1'b0;
  end else if (gc) begin
    gc_seen <= 1'b1;
  end
end

// Perform Test
initial begin
  mem_init_file = MEM_INIT_FILE;
  dump_mem_file = DUMP_MEM_FILE;
  max_cycles = MAX_CYCLES;
  force_free_value = 0;
  force_free_valid = 1'b0;
  force_gc = 1'b0;
  if ($value$plusargs("mem=%s", mem_init_file)) begin
  end
  if ($value$plusargs("dump=%s", dump_mem_file)) begin
  end
  if ($value$plusargs("max_cycles=%d", max_cycles)) begin
  end
  print_cycles = 1'b0;
  if ($test$plusargs("print_cycles")) begin
    print_cycles = 1'b1;
  end
  stop_on_finish = 1'b0;
  if ($test$plusargs("stop_on_finish")) begin
    stop_on_finish = 1'b1;
  end

  if (mem_init_file != "") begin
    $readmemh(mem_init_file, mem.ram.ram, 0, MEM_LAST);
  end
  if ($value$plusargs("force_free=%d", force_free_value)) begin
    force_free_valid = 1'b1;
  end
  if ($test$plusargs("force_gc")) begin
    force_gc = 1'b1;
  end
  if (!force_free_valid && force_gc) begin
    force_free_value = FORCE_FREE_DEFAULT;
    force_free_valid = 1'b1;
  end
  if (force_free_valid) begin
    mem.ram.ram[0] = {`memory_data_width{1'b0}};
    mem.ram.ram[0][`memory_addr_width - 1:0] = force_free_value[`memory_addr_width - 1:0];
  end
`ifndef NO_VCD
  $dumpfile("waveform.vcd");
  $dumpvars(0, execute_tb);

  for (idx = 0; idx < MEM_DEPTH; idx = idx+1) begin
    $dumpvars(0,mem.ram.ram[idx]);
  end
`endif

  start_addr = 1;
  // Reset
  reset = 1'b0;
  repeat (2) @(posedge clk);
  reset = 1'b1;
  wait (mem_ready == 1'b1);

  traversal_execute = 1;

  if (max_cycles != 0) begin
    for (idx = 0; idx < max_cycles && traversal_finished != 1'b1; idx = idx + 1) begin
      @(posedge clk);
    end
    if (traversal_finished != 1'b1) begin
      $display("timeout: traversal_finished not asserted after %0d cycles", max_cycles);
      $display("debug: sel %0d trav_state %0d exec_func %0d exec_state %0d mem_state %0d mem_ready %0d mem_execute %0d mem_func %0d",
               select,
               traversal.state,
               execute.exec_func,
               execute.state,
               mem.state,
               mem_ready,
               mem_execute,
               mem_func);
      if (dump_mem_file != "") begin
        $writememh(dump_mem_file, mem.ram.ram, 0, MEM_LAST);
      end
      $finish;
    end
  end else begin
    wait (traversal_finished == 1'b1);
  end
  if (stop_on_finish) begin
    traversal_execute = 0;
  end
  finish_cycle = cycle_count;
  repeat (500) @(posedge clk);

  if (print_cycles) begin
    $display("cycles %0d", finish_cycle);
  end
  $display("ram[1] %x", mem.ram.ram[1]);
  $display("ram[%0d] %x", SPACE_BASE + 1, mem.ram.ram[SPACE_BASE + 1]);
  $display("error %x", error);
  $display("edit_error %x", edit_error);
  $display("hint %0d", hint);
  $display("hint_tag %0d", hint_tag);
  $display("root_ptr %0d", root_addr);
  $display("gc_seen %0d", gc_seen);
  if (dump_mem_file != "") begin
    $writememh(dump_mem_file, mem.ram.ram, 0, MEM_LAST);
  end

  $finish;
end

endmodule
