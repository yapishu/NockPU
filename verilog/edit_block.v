`include "memory_unit.vh"
`include "memory_mux.vh"
`include "mem_traversal.vh"
`include "execute.vh"


module edit_block (
  input clk,
  input rst,
  output reg [7:0] edit_error,
  input [2:0] edit_start,  // wire to begin execution (mux_conroller from traversal)
  input [`memory_addr_width - 1:0] edit_address,
  input [`memory_data_width - 1:0] edit_data,
  output reg [3:0] edit_return_sys_func,
  output reg [3:0] edit_return_state,
  input mem_ready,
  input [`memory_data_width - 1:0] read_data1,
  input [`memory_data_width - 1:0] read_data2,
  input [`memory_addr_width - 1:0] free_addr,
  output reg mem_execute,
  output reg [`memory_addr_width - 1:0] address1,
  output reg [`memory_addr_width - 1:0] address2,
  output reg [1:0] mem_func,
  output reg [`memory_data_width - 1:0] write_data,
  output wire finished
);

  reg [7:0] debug_sig;
  // Interface with memory traversal
  reg [2:0] edit_start_ff;
  reg is_finished_reg;
  assign finished = is_finished_reg;

  reg [`noun_width - 1:0] tree_addr;
  reg [`noun_width - 1:0] new_val;
  reg [`memory_data_width - 1:0] new_val_reg;
  reg [`noun_width - 1:0] target;
  reg new_val_tag;
  reg target_tag;
  reg axis_large;
  reg [`noun_width - 1:0] la_axis_len;
  reg [`memory_addr_width - 1:0] la_axis_head_ptr;
  reg [`memory_addr_width - 1:0] la_axis_ptr;
  reg [`noun_width - 1:0] la_axis_target_idx;
  reg [`noun_width - 1:0] la_axis_scan_idx;
  reg [`noun_width - 1:0] la_axis_cur_idx;
  reg [`noun_width - 1:0] la_axis_val;
  reg [5:0] la_axis_bit;
  reg la_axis_done;
  reg la_axis_scan_mode;
  reg [`memory_addr_width - 1:0] command_tel_addr;
  reg [`memory_addr_width - 1:0] la_next_addr;

  // State Machine Stuff
  reg [4:0] state;
  parameter INIT                = 4'h0,
            READ_COMMAND        = 4'h1,
            PREP_TREE           = 4'h2,
            SLOT_CHECK          = 4'h3,
            SLOT_CHECK_INDIRECT = 4'h4,
            READ_INIT           = 4'h5,
            CELL_OF_NIL         = 4'h6,
            READ_TREE           = 4'h7,
            WRITE_ROOT          = 4'h8,
            DONE                = 4'h9,
            PAUSE               = 4'hA,
            ERROR               = 4'hF,
            AXIS_INDIRECT       = 5'h10,
            LA_INIT             = 5'h11,
            LA_SCAN_READ        = 5'h12,
            LA_SCAN_WAIT        = 5'h13,
            SLOT_CHECK_LA       = 5'h14;

  function [5:0] msb_index;
    input [`noun_width - 1:0] value;
    integer i;
    reg found;
    begin
      msb_index = 6'h3F;
      found = 1'b0;
      for (i = `noun_width - 1; i >= 0; i = i - 1) begin
        if (!found && value[i]) begin
          msb_index = i[5:0];
          found = 1'b1;
        end
      end
    end
  endfunction

  always @(posedge clk) begin
    // Flip-flop to store the previous state of edit_start                        
    edit_start_ff <= edit_start;
  end
 
  always @(posedge clk or negedge rst) begin
    if (!rst || (edit_start==`MUX_EDIT && !(edit_start_ff==`MUX_EDIT))) begin
      write_data <= 0;
      mem_execute<=0;
      address1 <=0;
      state <= INIT;
      debug_sig <=0;
      is_finished_reg <= 0;
      edit_error <= 0;
      edit_return_sys_func <= 0;
      edit_return_state <= 0;
      axis_large <= 0;
      la_axis_len <= 0;
      la_axis_head_ptr <= 0;
      la_axis_ptr <= 0;
      la_axis_target_idx <= 0;
      la_axis_scan_idx <= 0;
      la_axis_cur_idx <= 0;
      la_axis_val <= 0;
      la_axis_bit <= 0;
      la_axis_done <= 0;
      la_axis_scan_mode <= 0;
      command_tel_addr <= 0;
      la_next_addr <= 0;
    end 
    else if (edit_start == `MUX_EDIT) begin
      case (state)
        INIT: begin
          address1 <= edit_data[`tel_start:`tel_end];
          mem_execute <= 1;
          mem_func <= `GET_CONTENTS;
          state <= READ_COMMAND;
        end

        READ_COMMAND: begin
          if (mem_ready) begin
            command_tel_addr <= read_data1[`tel_start:`tel_end];
            la_axis_done <= 0;
            if (read_data1[`hed_tag] == `ATOM) begin
              axis_large <= 0;
              state <= PREP_TREE;
              tree_addr <= (read_data1[`hed_start:`hed_end]<<1) | 1;
              address1 <= read_data1[`tel_start:`tel_end];
              mem_execute <= 1;
              mem_func <= `GET_CONTENTS;
            end else begin
              axis_large <= 1'b0;
              address1 <= read_data1[`hed_start:`hed_end];
              mem_execute <= 1;
              mem_func <= `GET_CONTENTS;
              state <= AXIS_INDIRECT;
            end
          end else begin
            mem_execute <= 0;
            mem_func <=0;
          end
        end

        AXIS_INDIRECT: begin
          if (mem_ready) begin
            if (read_data1[`large_atom_bit]) begin
              if (read_data1[`hed_tag] != `CELL || read_data1[`tel_tag] != `ATOM) begin
                debug_sig <= 3;
                state <= ERROR;
              end else begin
                axis_large <= 1'b1;
                la_axis_len <= read_data1[`tel_start:`tel_end];
                la_axis_head_ptr <= read_data1[`hed_start:`hed_end];
                state <= LA_INIT;
              end
            end else if (read_data1[`tel_start:`tel_end] == `NIL
            && read_data1[`tel_tag] == `ATOM
            && read_data1[`hed_tag] == `ATOM) begin
              axis_large <= 1'b0;
              state <= PREP_TREE;
              tree_addr <= (read_data1[`hed_start:`hed_end]<<1) | 1;
              address1 <= command_tel_addr;
              mem_execute <= 1;
              mem_func <= `GET_CONTENTS;
            end else begin
              debug_sig <= 3;
              state <= ERROR;
            end
          end else begin
            mem_execute <= 0;
            mem_func <=0;
          end
        end

        LA_INIT: begin
          if (la_axis_len == 0) begin
            debug_sig <= 3;
            state <= ERROR;
          end else begin
            la_axis_target_idx <= la_axis_len - 1'b1;
            la_axis_scan_idx <= 0;
            la_axis_ptr <= la_axis_head_ptr;
            la_axis_scan_mode <= 1'b0;
            state <= LA_SCAN_READ;
          end
        end

        LA_SCAN_READ: begin
          address1 <= la_axis_ptr;
          mem_func <= `GET_CONTENTS;
          mem_execute <= 1;
          state <= LA_SCAN_WAIT;
        end

        LA_SCAN_WAIT: begin
          if (mem_ready) begin
            if (read_data1[`hed_tag] != `ATOM) begin
              debug_sig <= 3;
              state <= ERROR;
            end else if (la_axis_scan_idx == la_axis_target_idx) begin
              if (la_axis_scan_mode == 1'b0) begin
                if (read_data1[`tel_tag] != `ATOM
                || read_data1[`tel_start:`tel_end] != `NIL) begin
                  debug_sig <= 3;
                  state <= ERROR;
                end else if (msb_index(read_data1[`hed_start:`hed_end]) == 6'h3F) begin
                  debug_sig <= 3;
                  state <= ERROR;
                end else if (msb_index(read_data1[`hed_start:`hed_end]) == 0) begin
                  if (la_axis_len == 1) begin
                    la_axis_done <= 1'b1;
                    address1 <= command_tel_addr;
                    mem_execute <= 1;
                    mem_func <= `GET_CONTENTS;
                    state <= READ_INIT;
                  end else begin
                    la_axis_cur_idx <= la_axis_len - 2'h2;
                    la_axis_scan_mode <= 1'b1;
                    la_axis_target_idx <= la_axis_len - 2'h2;
                    la_axis_scan_idx <= 0;
                    la_axis_ptr <= la_axis_head_ptr;
                    state <= LA_SCAN_READ;
                  end
                end else begin
                  la_axis_cur_idx <= la_axis_len - 1'b1;
                  la_axis_val <= read_data1[`hed_start:`hed_end];
                  la_axis_bit <= msb_index(read_data1[`hed_start:`hed_end]) - 1'b1;
                  address1 <= command_tel_addr;
                  mem_execute <= 1;
                  mem_func <= `GET_CONTENTS;
                  state <= READ_INIT;
                end
              end else begin
                la_axis_val <= read_data1[`hed_start:`hed_end];
                la_axis_bit <= 6'd27;
                if (la_next_addr != 0) begin
                  address1 <= la_next_addr;
                  la_next_addr <= 0;
                  mem_execute <= 1;
                  mem_func <= `GET_CONTENTS;
                  state <= SLOT_CHECK_LA;
                end else begin
                  address1 <= command_tel_addr;
                  mem_execute <= 1;
                  mem_func <= `GET_CONTENTS;
                  state <= READ_INIT;
                end
              end
            end else begin
              if (read_data1[`tel_tag] != `CELL) begin
                debug_sig <= 3;
                state <= ERROR;
              end else begin
                la_axis_ptr <= read_data1[`tel_start:`tel_end];
                la_axis_scan_idx <= la_axis_scan_idx + 1'b1;
                state <= LA_SCAN_READ;
              end
            end
          end else begin
            mem_execute <= 0;
            mem_func <=0;
          end
        end

        PREP_TREE: begin
          if(tree_addr[`noun_width-1] == 1) begin
            state <= READ_INIT;
          end
          tree_addr <= tree_addr << 1;
        end
        
        READ_INIT: begin
          if (mem_ready) begin
            new_val_tag <= read_data1[`hed_tag];
            new_val <= read_data1[`hed_start:`hed_end];
            target_tag <= read_data1[`tel_tag];
            target <= read_data1[`tel_start:`tel_end];
            
            if(read_data1[`hed_tag] ==`CELL) begin
              address1 <= read_data1[`hed_start:`hed_end];
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1;
              state <= SLOT_CHECK_INDIRECT;
            end else begin 
              if (axis_large) begin
                state <= SLOT_CHECK_LA;
              end else begin
                state <= SLOT_CHECK;
              end
              address1 <= read_data1[`tel_start:`tel_end];
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1;
            end
          end else begin
            mem_execute <= 0;
            mem_func <=0;
          end
        end

        SLOT_CHECK_INDIRECT: begin
          if (mem_ready) begin
            new_val_reg <= read_data1;
            if (axis_large) begin
              state <= SLOT_CHECK_LA;
            end else begin
              state <= SLOT_CHECK;
            end
            address1 <= target[`tel_start:`tel_end];
            mem_func <= `GET_CONTENTS;
            mem_execute <= 1;
            if(read_data1[`tel_start:`tel_end] == `NIL 
            && read_data1[`tel_tag] == `ATOM
            && read_data1[`hed_tag] == `ATOM) begin
              new_val <= read_data1[`hed_start:`hed_end];
              new_val_tag <= read_data1[`hed_tag];
            end
          end else begin
            mem_execute <= 0;
            mem_func <=0;
          end
        end

        SLOT_CHECK: begin
          if (mem_ready) begin
            if ( tree_addr == 28'h8000000) begin
              mem_func <= `SET_CONTENTS;
              address1 <= address1;
              mem_execute <= 1;
              state <= READ_TREE;
              if(new_val_tag == `CELL) begin
                write_data <= new_val_reg;
              end else begin
                write_data <= {
                6'b000000,
                `ATOM,
                `ATOM,
                new_val,
                `NIL};
              end
            end else begin
              if (read_data1[`large_atom_bit]) begin
                if (tree_addr[`noun_width-1] == 0) begin
                  debug_sig <= 1;
                end else begin
                  debug_sig <= 2;
                end
                state <= ERROR;
              end else begin
                if (tree_addr[`noun_width-1] == 0) begin
                  if(tree_addr == 28'h4000000) begin
                    mem_func <= `SET_CONTENTS;
                    address1 <= address1;
                    mem_execute <= 1;
                    write_data <= {
                      read_data1[`execute_bit],
                      5'b00000,
                      new_val_tag,
                      read_data1[`tel_tag],
                      new_val,
                      read_data1[`tel_start:`tel_end]};
                    state <= READ_TREE;
                  end else if(read_data1[`hed_tag] == `CELL) begin
                    address1 <= read_data1[`hed_start:`hed_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= SLOT_CHECK;
                  end else begin
                    debug_sig <= 1;
                    state <= ERROR;
                  end
                end else begin
                  if(tree_addr == 28'hC000000) begin
                    mem_func <= `SET_CONTENTS;
                    address1 <= address1;
                    mem_execute <= 1;
                    write_data <= {
                      read_data1[`execute_bit],
                      5'b00000,
                      read_data1[`hed_tag],
                      new_val_tag,
                      read_data1[`hed_start:`hed_end],
                      new_val};
                    state <= READ_TREE;
                  end else if(read_data1[`tel_tag] == `CELL) begin
                    address1 <= read_data1[`tel_start:`tel_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= SLOT_CHECK;
                  end else begin
                    debug_sig <= 2;
                    state <= ERROR;
                  end
                end
                tree_addr <= tree_addr << 1;
              end
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        SLOT_CHECK_LA: begin
          if (mem_ready) begin
            if (la_axis_done) begin
              mem_func <= `SET_CONTENTS;
              address1 <= address1;
              mem_execute <= 1;
              state <= READ_TREE;
              if(new_val_tag == `CELL) begin
                write_data <= new_val_reg;
              end else begin
                write_data <= {
                6'b000000,
                `ATOM,
                `ATOM,
                new_val,
                `NIL};
              end
            end else begin
              if (read_data1[`large_atom_bit]) begin
                debug_sig <= 3;
                state <= ERROR;
              end else if (la_axis_val[la_axis_bit] == 1'b0) begin
                if (la_axis_cur_idx == 0 && la_axis_bit == 0
                && read_data1[`hed_tag] == `ATOM) begin
                  mem_func <= `SET_CONTENTS;
                  address1 <= address1;
                  mem_execute <= 1;
                  write_data <= {
                    read_data1[`execute_bit],
                    5'b00000,
                    new_val_tag,
                    read_data1[`tel_tag],
                    new_val,
                    read_data1[`tel_start:`tel_end]};
                  state <= READ_TREE;
                end else if (read_data1[`hed_tag] == `CELL) begin
                  if (la_axis_cur_idx == 0 && la_axis_bit == 0) begin
                    la_axis_done <= 1'b1;
                    address1 <= read_data1[`hed_start:`hed_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= SLOT_CHECK_LA;
                  end else if (la_axis_bit == 0) begin
                    la_axis_cur_idx <= la_axis_cur_idx - 1'b1;
                    la_axis_scan_mode <= 1'b1;
                    la_axis_target_idx <= la_axis_cur_idx - 1'b1;
                    la_axis_scan_idx <= 0;
                    la_axis_ptr <= la_axis_head_ptr;
                    la_next_addr <= read_data1[`hed_start:`hed_end];
                    state <= LA_SCAN_READ;
                  end else begin
                    la_axis_bit <= la_axis_bit - 1'b1;
                    address1 <= read_data1[`hed_start:`hed_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= SLOT_CHECK_LA;
                  end
                end else begin
                  debug_sig <= 1;
                  state <= ERROR;
                end
              end else begin
                if (la_axis_cur_idx == 0 && la_axis_bit == 0
                && read_data1[`tel_tag] == `ATOM) begin
                  mem_func <= `SET_CONTENTS;
                  address1 <= address1;
                  mem_execute <= 1;
                  write_data <= {
                    read_data1[`execute_bit],
                    5'b00000,
                    read_data1[`hed_tag],
                    new_val_tag,
                    read_data1[`hed_start:`hed_end],
                    new_val};
                  state <= READ_TREE;
                end else if (read_data1[`tel_tag] == `CELL) begin
                  if (la_axis_cur_idx == 0 && la_axis_bit == 0) begin
                    la_axis_done <= 1'b1;
                    address1 <= read_data1[`tel_start:`tel_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= SLOT_CHECK_LA;
                  end else if (la_axis_bit == 0) begin
                    la_axis_cur_idx <= la_axis_cur_idx - 1'b1;
                    la_axis_scan_mode <= 1'b1;
                    la_axis_target_idx <= la_axis_cur_idx - 1'b1;
                    la_axis_scan_idx <= 0;
                    la_axis_ptr <= la_axis_head_ptr;
                    la_next_addr <= read_data1[`tel_start:`tel_end];
                    state <= LA_SCAN_READ;
                  end else begin
                    la_axis_bit <= la_axis_bit - 1'b1;
                    address1 <= read_data1[`tel_start:`tel_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= SLOT_CHECK_LA;
                  end
                end else begin
                  debug_sig <= 2;
                  state <= ERROR;
                end
              end
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        READ_TREE: begin
          if (mem_ready) begin
            mem_func <= `GET_CONTENTS;
            address1 <= target ;
            mem_execute <= 1;
            state <= WRITE_ROOT;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        WRITE_ROOT: begin
          if (mem_ready) begin
            mem_func <= `SET_CONTENTS;
            address1 <= edit_address;
            mem_execute <= 1;
            write_data <= read_data1;
            state <= DONE;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        DONE: begin
          if (mem_ready) begin
            edit_return_sys_func <= `SYS_FUNC_READ;
            edit_return_state <= `SYS_READ_INIT;
            is_finished_reg <= 1;
            state <= PAUSE;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end
        PAUSE: begin
          is_finished_reg <=0;
          if (edit_start == `MUX_EDIT) state<= INIT;
        end

        ERROR: begin
          mem_execute <= 0;
          case (debug_sig)
            8'h1: edit_error <= `ERROR_INVALID_SLOT_HED;
            8'h2: edit_error <= `ERROR_INVALID_SLOT_TEL;
            default: edit_error <= `ERROR_INVALID_SLOT;
          endcase
          edit_return_sys_func <= `SYS_FUNC_EXECUTE;
          edit_return_state <= `SYS_EXECUTE_ERROR;
          is_finished_reg <= 1;
        end
      endcase
    end
  end
endmodule
 
