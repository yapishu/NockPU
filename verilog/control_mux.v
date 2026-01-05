/*
This module will allow a control signal to pick signals to give control to different submodules
*/

`include "memory_unit.vh"
`include "memory_mux.vh"

module control_mux(
  input [2:0] sel,
  // Signals to/from traversal
  output reg finished,
  output reg [3:0] return_sys_func,
  output reg [3:0] return_state,
  input [`memory_addr_width - 1:0] module_address,
  input [`memory_data_width - 1:0] module_data,
  // Signals to/from modules
  input execute_finished,
  input [3:0] execute_return_sys_func,
  input [3:0] execute_return_state,
  output reg [`memory_addr_width - 1:0] execute_address,
  output reg [`memory_data_width - 1:0] execute_data,
  input cell_finished,
  input [3:0] cell_return_sys_func,
  input [3:0] cell_return_state,
  output reg [`memory_addr_width - 1:0] cell_address,
  output reg [`memory_data_width - 1:0] cell_data,
  input incr_finished,
  input [3:0] incr_return_sys_func,
  input [3:0] incr_return_state,
  output reg [`memory_addr_width - 1:0] incr_address,
  output reg [`memory_data_width - 1:0] incr_data,
  input equal_finished,
  input [3:0] equal_return_sys_func,
  input [3:0] equal_return_state,
  output reg [`memory_addr_width - 1:0] equal_address,
  output reg [`memory_data_width - 1:0] equal_data,
  input edit_finished,
  input [3:0] edit_return_sys_func,
  input [3:0] edit_return_state,
  output reg [`memory_addr_width - 1:0] edit_address,
  output reg [`memory_data_width - 1:0] edit_data
);

always @(*) begin
  finished = 1'b0;
  return_sys_func = 4'b0000;
  return_state = 4'b0000;
  execute_address = {`memory_addr_width{1'b0}};
  execute_data = {`memory_data_width{1'b0}};
  cell_address = {`memory_addr_width{1'b0}};
  cell_data = {`memory_data_width{1'b0}};
  incr_address = {`memory_addr_width{1'b0}};
  incr_data = {`memory_data_width{1'b0}};
  equal_address = {`memory_addr_width{1'b0}};
  equal_data = {`memory_data_width{1'b0}};
  edit_address = {`memory_addr_width{1'b0}};
  edit_data = {`memory_data_width{1'b0}};

  case(sel)
    `MUX_EXECUTE: begin
      finished = execute_finished;
      return_sys_func = execute_return_sys_func;
      return_state = execute_return_state;
      execute_address = module_address;
      execute_data = module_data;
    end
    `MUX_CELL: begin
      finished = cell_finished;
      return_sys_func = cell_return_sys_func;
      return_state = cell_return_state;
      cell_address = module_address;
      cell_data = module_data;
    end
    `MUX_INCR: begin
      finished = incr_finished;
      return_sys_func = incr_return_sys_func;
      return_state = incr_return_state;
      incr_address = module_address;
      incr_data = module_data;
    end
    `MUX_EQUAL: begin
      finished = equal_finished;
      return_sys_func = equal_return_sys_func;
      return_state = equal_return_state;
      equal_address = module_address;
      equal_data = module_data;
    end
    `MUX_EDIT: begin
      finished = edit_finished;
      return_sys_func = edit_return_sys_func;
      return_state = edit_return_state;
      edit_address = module_address;
      edit_data = module_data;
    end
    default: begin // Default case can be used to handle unexpected values
    end
  endcase
end

endmodule
