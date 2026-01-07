`include "memory_unit.vh"
`include "memory_mux.vh"
`include "execute.vh"

module nockpu_top #(
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
  input clk,
  input rst,
  input start,
  input [`memory_addr_width - 1:0] start_addr,
  input host_req,
  input host_we,
  input [`memory_addr_width - 1:0] host_addr,
  input [`memory_data_width - 1:0] host_wdata,
  output host_ready,
  output reg [`memory_data_width - 1:0] host_rdata,
  output reg host_rvalid,
  output busy,
  output reg done,
  output [7:0] error,
  output [7:0] edit_error,
  output [`noun_width-1:0] hint,
  output hint_tag,
  output [`memory_addr_width - 1:0] free_ptr,
  output [`memory_addr_width - 1:0] root_ptr
);
  wire power = 1'b1;

  // Core control.
  reg running;
  reg [`memory_addr_width - 1:0] start_addr_reg;
  assign busy = running;

  // Host memory access (idle core only).
  reg host_busy;
  reg host_is_read;
  reg host_exec;
  reg [1:0] host_mem_func;
  reg [`memory_addr_width - 1:0] host_address1;
  reg [`memory_data_width - 1:0] host_write_data;

  assign host_ready = !running && !host_busy && mem_ready;
  wire host_active = host_busy || host_exec;

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      running <= 1'b0;
      done <= 1'b0;
      start_addr_reg <= {`memory_addr_width{1'b0}};
    end else begin
      if (!running) begin
        if (start && !host_busy) begin
          running <= 1'b1;
          done <= 1'b0;
          start_addr_reg <= start_addr;
        end
      end else if (traversal_finished) begin
        running <= 1'b0;
        done <= 1'b1;
      end
    end
  end

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      host_busy <= 1'b0;
      host_is_read <= 1'b0;
      host_exec <= 1'b0;
      host_mem_func <= 2'b00;
      host_address1 <= {`memory_addr_width{1'b0}};
      host_write_data <= {`memory_data_width{1'b0}};
      host_rdata <= {`memory_data_width{1'b0}};
      host_rvalid <= 1'b0;
    end else begin
      host_exec <= 1'b0;
      host_rvalid <= 1'b0;

      if (running) begin
        host_busy <= 1'b0;
      end else if (!host_busy) begin
        if (host_req && mem_ready) begin
          host_mem_func <= host_we ? `SET_CONTENTS : `GET_CONTENTS;
          host_address1 <= host_addr;
          host_write_data <= host_wdata;
          host_is_read <= !host_we;
          host_exec <= 1'b1;
          host_busy <= 1'b1;
        end
      end else if (mem_ready) begin
        if (host_is_read) begin
          host_rdata <= read_data1;
          host_rvalid <= 1'b1;
        end
        host_busy <= 1'b0;
      end
    end
  end

  // Memory bus wiring.
  wire [1:0] mem_func_core;
  wire mem_execute_core;
  wire [`memory_addr_width - 1:0] address1_core;
  wire [`memory_addr_width - 1:0] address2_core;
  wire [`memory_data_width - 1:0] write_data_core;

  wire [1:0] mem_func_host;
  wire mem_execute_host;
  wire [`memory_addr_width - 1:0] address1_host;
  wire [`memory_addr_width - 1:0] address2_host;
  wire [`memory_data_width - 1:0] write_data_host;

  assign mem_func_host = host_mem_func;
  assign mem_execute_host = host_exec;
  assign address1_host = host_address1;
  assign address2_host = {`memory_addr_width{1'b0}};
  assign write_data_host = host_write_data;

  wire [1:0] mem_func;
  wire mem_execute;
  wire [`memory_addr_width - 1:0] address1;
  wire [`memory_addr_width - 1:0] address2;
  wire [`memory_data_width - 1:0] write_data;

  assign mem_func = host_active ? mem_func_host : mem_func_core;
  assign mem_execute = host_active ? mem_execute_host : mem_execute_core;
  assign address1 = host_active ? address1_host : address1_core;
  assign address2 = host_active ? address2_host : address2_core;
  assign write_data = host_active ? write_data_host : write_data_core;

  wire mem_ready;
  wire [`memory_addr_width - 1:0] free_addr;
  wire [`memory_data_width - 1:0] read_data1;
  wire [`memory_data_width - 1:0] read_data2;
  wire [`memory_data_width - 1:0] mem_data_out1;
  wire [`memory_data_width - 1:0] mem_data_out2;
  wire gc;
  wire gc_ready;

  // Memory Unit.
  memory_unit mem(
    .func (mem_func),
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
    .rst (rst),
    .gc (gc),
    .gc_ready (gc_ready)
  );

  // Memory mux and traversal wiring.
  wire [1:0] mem_func_mtu;
  wire mem_execute_mtu;
  wire [`memory_addr_width - 1:0] address1_mtu;
  wire [`memory_addr_width - 1:0] address2_mtu;
  wire [`memory_data_width - 1:0] write_data_mtu;
  wire [2:0] select;

  wire [1:0] mem_func_nem;
  wire mem_execute_nem;
  wire [`memory_addr_width - 1:0] address1_nem;
  wire [`memory_addr_width - 1:0] address2_nem;
  wire [`memory_data_width - 1:0] write_data_nem;

  wire [1:0] mem_func_cell;
  wire mem_execute_cell;
  wire [`memory_addr_width - 1:0] address1_cell;
  wire [`memory_addr_width - 1:0] address2_cell;
  wire [`memory_data_width - 1:0] write_data_cell;

  wire [1:0] mem_func_incr;
  wire mem_execute_incr;
  wire [`memory_addr_width - 1:0] address1_incr;
  wire [`memory_addr_width - 1:0] address2_incr;
  wire [`memory_data_width - 1:0] write_data_incr;

  wire [1:0] mem_func_equal;
  wire mem_execute_equal;
  wire [`memory_addr_width - 1:0] address1_equal;
  wire [`memory_addr_width - 1:0] address2_equal;
  wire [`memory_data_width - 1:0] write_data_equal;

  wire [1:0] mem_func_edit;
  wire mem_execute_edit;
  wire [`memory_addr_width - 1:0] address1_edit;
  wire [`memory_addr_width - 1:0] address2_edit;
  wire [`memory_data_width - 1:0] write_data_edit;

  // Memory mux (core side).
  memory_mux memory_mux(
    .mem_func_a (mem_func_mtu),
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
    .mem_func (mem_func_core),
    .execute (mem_execute_core),
    .address1 (address1_core),
    .address2 (address2_core),
    .write_data (write_data_core)
  );

  // Control mux.
  wire [`memory_addr_width - 1:0] module_address;
  wire [`memory_data_width - 1:0] module_data;
  wire module_finished;
  wire [3:0] return_sys_func;
  wire [3:0] return_state;

  wire [`memory_addr_width - 1:0] execute_address;
  wire [`memory_data_width - 1:0] execute_data;
  wire execute_finished;
  wire [3:0] execute_return_sys_func;
  wire [3:0] execute_return_state;
  wire [7:0] exec_error;

  wire [`memory_addr_width - 1:0] cell_address;
  wire [`memory_data_width - 1:0] cell_data;
  wire cell_finished;
  wire [3:0] cell_return_sys_func;
  wire [3:0] cell_return_state;
  wire [7:0] cell_error;

  wire [`memory_addr_width - 1:0] incr_address;
  wire [`memory_data_width - 1:0] incr_data;
  wire incr_finished;
  wire [3:0] incr_return_sys_func;
  wire [3:0] incr_return_state;
  wire [7:0] incr_error;

  assign error = (exec_error != 0) ? exec_error : incr_error;

  wire [`memory_addr_width - 1:0] equal_address;
  wire [`memory_data_width - 1:0] equal_data;
  wire equal_finished;
  wire [3:0] equal_return_sys_func;
  wire [3:0] equal_return_state;
  wire [7:0] equal_error;

  wire [`memory_addr_width - 1:0] edit_address;
  wire [`memory_data_width - 1:0] edit_data;
  wire edit_finished;
  wire [3:0] edit_return_sys_func;
  wire [3:0] edit_return_state;

  control_mux control_mux(
    .sel (select),
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

  // Traversal.
  wire traversal_finished;

  mem_traversal #(
    .STACK_DEPTH (STACK_DEPTH_TRAV)
  ) traversal(
    .power (power),
    .clk (clk),
    .rst (rst),
    .start_addr (start_addr_reg),
    .root_addr (root_ptr),
    .execute (running),
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
    .finished (traversal_finished),
    .error (error),
    .mux_controller (select),
    .module_address (module_address),
    .module_data (module_data),
    .module_finished (module_finished),
    .return_sys_func (return_sys_func),
    .return_state (return_state)
  );

  // Execute module.
  execute execute(
    .clk (clk),
    .rst (rst),
    .error (exec_error),
    .execute_start (select),
    .execute_address (execute_address),
    .execute_data (execute_data),
    .gc (gc),
    .mem_ready (mem_ready),
    .mem_execute (mem_execute_nem),
    .mem_func (mem_func_nem),
    .address1 (address1_nem),
    .address2 (address2_nem),
    .free_addr (free_addr),
    .read_data1 (read_data1),
    .read_data2 (read_data2),
    .write_data (write_data_nem),
    .finished (execute_finished),
    .hint (hint),
    .hint_tag (hint_tag),
    .execute_return_sys_func (execute_return_sys_func),
    .execute_return_state (execute_return_state)
  );

  // Cell module.
  cell_block cell_block(
    .clk (clk),
    .rst (rst),
    .cell_error (cell_error),
    .cell_start (select),
    .cell_address (cell_address),
    .cell_data (cell_data),
    .mem_ready (mem_ready),
    .mem_execute (mem_execute_cell),
    .mem_func (mem_func_cell),
    .address1 (address1_cell),
    .address2 (address2_cell),
    .free_addr (free_addr),
    .read_data1 (read_data1),
    .read_data2 (read_data2),
    .write_data (write_data_cell),
    .finished (cell_finished),
    .cell_return_sys_func (cell_return_sys_func),
    .cell_return_state (cell_return_state)
  );

  // Increment module.
  incr_block incr_block(
    .clk (clk),
    .rst (rst),
    .incr_error (incr_error),
    .incr_start (select),
    .incr_address (incr_address),
    .incr_data (incr_data),
    .mem_ready (mem_ready),
    .gc (gc),
    .mem_execute (mem_execute_incr),
    .mem_func (mem_func_incr),
    .address1 (address1_incr),
    .address2 (address2_incr),
    .free_addr (free_addr),
    .read_data1 (read_data1),
    .read_data2 (read_data2),
    .write_data (write_data_incr),
    .finished (incr_finished),
    .incr_return_sys_func (incr_return_sys_func),
    .incr_return_state (incr_return_state)
  );

  // Equality module.
  equal_block #(
    .STACK_DEPTH (STACK_DEPTH_EQUAL)
  ) equal_block(
    .clk (clk),
    .rst (rst),
    .equal_error (equal_error),
    .equal_start (select),
    .equal_address (equal_address),
    .equal_data (equal_data),
    .mem_ready (mem_ready),
    .mem_execute (mem_execute_equal),
    .mem_func (mem_func_equal),
    .address1 (address1_equal),
    .address2 (address2_equal),
    .free_addr (free_addr),
    .read_data1 (read_data1),
    .read_data2 (read_data2),
    .write_data (write_data_equal),
    .finished (equal_finished),
    .equal_return_sys_func (equal_return_sys_func),
    .equal_return_state (equal_return_state)
  );

  // Edit module.
  edit_block edit_block(
    .clk (clk),
    .rst (rst),
    .edit_error (edit_error),
    .edit_start (select),
    .edit_address (edit_address),
    .edit_data (edit_data),
    .mem_ready (mem_ready),
    .mem_execute (mem_execute_edit),
    .mem_func (mem_func_edit),
    .address1 (address1_edit),
    .address2 (address2_edit),
    .free_addr (free_addr),
    .read_data1 (read_data1),
    .read_data2 (read_data2),
    .write_data (write_data_edit),
    .finished (edit_finished),
    .edit_return_sys_func (edit_return_sys_func),
    .edit_return_state (edit_return_state)
  );

endmodule
