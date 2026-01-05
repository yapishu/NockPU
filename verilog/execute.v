`include "memory_unit.vh"
`include "memory_mux.vh"
`include "mem_traversal.vh"
`include "execute.vh"


module execute (
  input clk,
  input rst,
  output reg [7:0] error,
  input [2:0] execute_start,  // wire to begin execution (mux_conroller from traversal)
  input [`memory_addr_width - 1:0] execute_address,
  input [`memory_data_width - 1:0] execute_data,
  output reg [3:0] execute_return_sys_func,
  output reg [3:0] execute_return_state,
  input mem_ready,
  input gc,
  input [`memory_data_width - 1:0] read_data1,
  input [`memory_data_width - 1:0] read_data2,
  input [`memory_addr_width - 1:0] free_addr,
  output reg mem_execute,
  output reg [`memory_addr_width - 1:0] address1,
  output reg [`memory_addr_width - 1:0] address2,
  output reg [`memory_addr_width - 1:0] write_addr_reg,
  output reg [1:0] mem_func,
  output reg [`memory_data_width - 1:0] write_data,
  output wire finished,
  output reg [`noun_width-1:0] hint,
  output reg hint_tag
);
  reg [7:0] debug_sig;
  reg [7:0] count;

  initial count <=0;

  // Interface with memory traversal
  reg [2:0] execute_start_ff;
  reg is_finished_reg;
  assign finished = is_finished_reg;

  //Interface with memory unit
  reg [`memory_data_width - 1:0] read_data_reg;
  wire [7:0] execute_tag_clean;
  assign execute_tag_clean = execute_data[`tag_start:`tag_end] & 8'hF3;
  wire [`memory_data_width - 1:0] read_data1_clean;
  assign read_data1_clean = {read_data1[63:60], 2'b00, read_data1[57:0]};

  //Registers to treat opcodes as "Functions"
  reg [`noun_width - 1:0] a, opcode, b, c, d;
  reg a_tag, b_tag, c_tag, d_tag;
  reg [`memory_addr_width - 1:0] b_addr, c_addr, d_addr;
  reg [`noun_width - 1:0] func_addr;
  reg [3:0] func_return_exec_func;
  reg [3:0] func_return_state;
  // subject ois a useful register for nouns with a tag.
  // each opcode can use this howver
  reg [`noun_width - 1:0] subject;
  reg [`noun_tag_width - 1:0] subject_tag;
  reg [`noun_width - 1:0] tel_tel;
  reg [`memory_addr_width - 1:0] tel_tel_addr;
  reg [`noun_tag_width - 1:0] tel_tel_tag;

  //Internal Registers
  reg [`tag_width - 1:0] mem_tag;
  reg [`noun_width - 1:0] hed, tel;
  reg [`memory_addr_width - 1:0] mem_addr;
  reg [`memory_data_width - 1:0] mem_data;
  reg [`memory_addr_width - 1:0] execute_address_reg;
  wire [7:0] const_copy_tag;
  assign const_copy_tag = {3'b000, read_data1[`large_atom_bit], 2'b00, read_data1[`hed_tag], read_data1[`tel_tag]};

  // Traversal Registers needed
  reg [`noun_width - 1:0] trav_P;
  reg [`noun_width - 1:0] trav_B;

  // Large axis tracking for slot/edit
  reg la_axis_ready;
  reg la_axis_done;
  reg la_axis_scan_mode;
  reg [`noun_width - 1:0] la_axis_len;
  reg [`memory_addr_width - 1:0] la_axis_head_ptr;
  reg [`memory_addr_width - 1:0] la_axis_ptr;
  reg [`noun_width - 1:0] la_axis_target_idx;
  reg [`noun_width - 1:0] la_axis_scan_idx;
  reg [`noun_width - 1:0] la_axis_cur_idx;
  reg [`noun_width - 1:0] la_axis_val;
  reg [5:0] la_axis_bit;
  reg [`memory_data_width - 1:0] slot_subject_reg;
  reg [`noun_width - 1:0] axis_val;
  reg axis_tag;
  reg [`memory_data_width - 1:0] axis_header_reg;

  reg [3:0] exec_func;
  reg [3:0] state;

  //Execute Functions
  parameter EXE_FUNC_SLOT     = 4'h0,
            EXE_FUNC_CONSTANT = 4'h1,
            EXE_FUNC_EVAL     = 4'h2,
            EXE_FUNC_CELL     = 4'h3,
            EXE_FUNC_INCR     = 4'h4,
            EXE_FUNC_EQUAL    = 4'h5,
            EXE_FUNC_IF       = 4'h6,
            EXE_FUNC_COMPOSE  = 4'h7,
            EXE_FUNC_EXTEND   = 4'h8,
            EXE_FUNC_INVOKE   = 4'h9,
            EXE_FUNC_REPLACE  = 4'hA,
            EXE_FUNC_HINT     = 4'hB,
            EXE_FUNC_INIT     = 4'hC,
            EXE_FUNC_AUTOCONS = 4'hD,
            EXE_FUNC_ERROR    = 4'hF;

  // slot states
  parameter EXE_SLOT_INIT           = 4'h0,
            EXE_SLOT_INDIRECT       = 4'h1,
            EXE_SLOT_PREP           = 4'h2,
            EXE_SLOT_CHECK          = 4'h3,
            EXE_SLOT_DONE           = 4'h4,
            EXE_SLOT_CELL_OF_NIL    = 4'h5,
            EXE_SLOT_READ_INDIRECT  = 4'h6,
            EXE_SLOT_LA_INIT        = 4'h7,
            EXE_SLOT_LA_SCAN_READ   = 4'h8,
            EXE_SLOT_LA_SCAN_WAIT   = 4'h9,
            EXE_SLOT_LA_READ_SUBJECT= 4'hA,
            EXE_SLOT_LA_WAIT_SUBJECT= 4'hB,
            EXE_SLOT_LA_CHECK       = 4'hC;

  // Constant states
  parameter EXE_CONSTANT_INIT             = 4'h0, 
            EXE_CONSTANT_READ_B           = 4'h1,
            EXE_CONSTANT_WRITE_WAIT       = 4'h2,
            EXE_CONSTANT_READ_B_INDIRECT  = 4'h3;

  //eval states
  parameter EXE_EVAL_INIT           = 4'h0,
            EXE_EVAL_READ_TEL_TEL   = 4'h1,
            EXE_EVAL_WRIT_1_EXE     = 4'h2,
            EXE_EVAL_WRIT_2_EXE     = 4'h3,
            EXE_EVAL_WRIT_HED       = 4'h5,
            EXE_EVAL_DONE           = 4'h4;

  //cell states
  parameter EXE_CELL_INIT       = 4'h0, 
            EXE_CELL_CHECK      = 4'h1, 
            EXE_CELL_WRITE_WAIT = 4'h2;

  //increment states
  parameter EXE_INCR_INIT       = 4'h0, 
            EXE_INCR_FREE       = 4'h1,
            EXE_INCR_CHECK      = 4'h2, 
            EXE_INCR_WRITE_WAIT = 4'h3;

  //equal states
  parameter EXE_EQUAL_INIT          = 4'h0,
            EXE_EQUAL_WRITE_ROOT    = 4'h1,
            EXE_EQUAL_WRITE_COMP    = 4'h2,
            EXE_EQUAL_READ_TEL      = 4'h3,
            EXE_EQUAL_READ_TEL_TEL  = 4'h4,
            EXE_EQUAL_WRITE_TEL     = 4'h5,
            EXE_EQUAL_WRITE_TEL_TEL = 4'h6,
            EXE_EQUAL_WRITE_MEM     = 4'h7,
            EXE_EQUAL_DONE          = 4'h8;

  //if then else states
  parameter EXE_IF_INIT    = 4'h0,
            EXE_IF_READ_B  = 4'h1,
            EXE_IF_READ_C  = 4'h2,
            EXE_IF_READ_D  = 4'h3,
            EXE_IF_WRITE1  = 4'h4,
            EXE_IF_WRITE2  = 4'h5,
            EXE_IF_WRITE3  = 4'h6,
            EXE_IF_WRITE4  = 4'h7,
            EXE_IF_WRITE5  = 4'h8,
            EXE_IF_WRITE6  = 4'h9,
            EXE_IF_WRITE7  = 4'hA,
            EXE_IF_WRITE8  = 4'hB,
            EXE_IF_WRITE9  = 4'hC,
            EXE_IF_WRITE10 = 4'hD,
            EXE_IF_DONE    = 4'hE,
            EXE_IF_WRITE11 = 4'hF;

  //compose states
  parameter EXE_COMPOSE_INIT   = 4'h0,
            EXE_COMPOSE_FREE   = 4'h1,
            EXE_COMPOSE_READ   = 4'h2,
            EXE_COMPOSE_WRITE  = 4'h3,
            EXE_COMPOSE_DONE   = 4'h4;

  //extend states
  parameter EXE_EXTEND_INIT   = 4'h0,
            EXE_EXTEND_FREE   = 4'h1,
            EXE_EXTEND_READ1  = 4'h2,
            EXE_EXTEND_READ2  = 4'h3,
            EXE_EXTEND_WRITE1 = 4'h4,
            EXE_EXTEND_WRITE2 = 4'h5,
            EXE_EXTEND_WRITE3 = 4'h6,
            EXE_EXTEND_DONE   = 4'hF;

  //invoke states
  parameter EXE_INVOKE_INIT       = 4'h0,
            EXE_INVOKE_READ       = 4'h1,
            EXE_INVOKE_READ2      = 4'h2,
            EXE_INVOKE_WRITE      = 4'h3,
            EXE_INVOKE_WRITE2     = 4'h4,
            EXE_INVOKE_WRITE3     = 4'h5,
            EXE_INVOKE_WRITE4     = 4'h6,
            EXE_INVOKE_WRITE5     = 4'h7,
            EXE_INVOKE_WRITE6     = 4'h8,
            EXE_INVOKE_DONE       = 4'hF;

  //replace states
  parameter EXE_REPLACE_INIT       = 4'h0,
            EXE_REPLACE_READ       = 4'h1,
            EXE_REPLACE_READ2      = 4'h2,
            EXE_REPLACE_READ3      = 4'h3,
            EXE_REPLACE_WRITE      = 4'h4,
            EXE_REPLACE_WRITE2     = 4'h5,
            EXE_REPLACE_WRITE3     = 4'h6,
            EXE_REPLACE_WRITE4     = 4'h7,
            EXE_REPLACE_WRITE5     = 4'h8,
            EXE_REPLACE_WRITE6     = 4'h9,
            EXE_REPLACE_READ_AXIS  = 4'hA,
            EXE_REPLACE_DONE       = 4'hF;


  //eval states
  parameter EXE_HINT_INIT = 4'h0,
            EXE_HINT_READ       = 4'h1,
            EXE_HINT_READ2      = 4'h2,
            EXE_HINT_READ3      = 4'h3,
            EXE_HINT_WRITE      = 4'h4,
            EXE_HINT_WRITE2     = 4'h5,
            EXE_HINT_WRITE3     = 4'h6,
            EXE_HINT_WRITE4     = 4'h7,
            EXE_HINT_WRITE5     = 4'h8,
            EXE_HINT_DONE       = 4'hF;

  // Error States
  parameter EXE_ERROR_INIT = 4'h0;

  // Init States
  parameter EXE_INIT_INIT                 = 4'h0,
            EXE_INIT_READ_TEL             = 4'h1,
            EXE_INIT_DECODE               = 4'h2,
            EXE_INIT_WRIT_TEL             = 4'h3,
            EXE_INIT_WRIT_TEL_READ        = 4'h4,
            EXE_INIT_ATOM_WRITE           = 4'h5,
            EXE_INIT_FINISHED             = 4'hF;

  // Autocons States
  parameter EXE_AUTO_INIT                 = 4'h0,
            EXE_AUTO_WRITE_ROOT           = 4'h1,
            EXE_AUTO_READ_TEL             = 4'h2,
            EXE_AUTO_WRITE_TEL            = 4'h3,
            EXE_AUTO_WRITE_MEM            = 4'h4,
            EXE_AUTO_DONE                 = 4'h5;

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
    // Flip-flop to store the previous state of execute_start
    execute_start_ff <= execute_start;
  end

  always @(posedge clk or negedge rst) begin
    if (!rst || (execute_start==`MUX_EXECUTE && !(execute_start_ff==`MUX_EXECUTE))) begin
      exec_func <= EXE_FUNC_INIT;
      state <= EXE_INIT_INIT;
      trav_B <= `NIL;
      is_finished_reg <= 0;
      read_data_reg <= 0;
      execute_return_sys_func <= 0;
      execute_return_state <= 0;
      write_data <= 0;
      mem_execute<=0;
      debug_sig <= 0;
      address1 <=0;
      error <= 0;
      la_axis_ready <= 0;
      la_axis_done <= 0;
      la_axis_scan_mode <= 0;
      la_axis_len <= 0;
      la_axis_head_ptr <= 0;
      la_axis_ptr <= 0;
      la_axis_target_idx <= 0;
      la_axis_scan_idx <= 0;
      la_axis_cur_idx <= 0;
      la_axis_val <= 0;
      la_axis_bit <= 0;
      slot_subject_reg <= 0;
      axis_val <= 0;
      axis_tag <= 0;
      axis_header_reg <= 0;
    end 
    else if (execute_start == `MUX_EXECUTE) begin
      case (exec_func)
        EXE_FUNC_INIT: begin
          case (state)
            EXE_INIT_INIT: begin
              is_finished_reg <=0;
              error <= 0;
              if (execute_start == `MUX_EXECUTE) begin
                if (execute_data[`tel_tag] == `ATOM) begin
                  if (mem_ready) begin
                    address1 <= execute_address;
                    mem_func <= `SET_CONTENTS;
                    mem_execute <= 1;
                    write_data <= {8'b00000011,
                                   execute_data[`tel_start:`tel_end],
                                   `NIL};
                    state <= EXE_INIT_ATOM_WRITE;
                  end else begin
                    mem_func <= 0;
                    mem_execute <= 0;
                  end
                end else begin
                  if (mem_ready) begin
                    mem_tag <= execute_data[`tag_start:`tag_end];

                    execute_address_reg <= execute_address;
                    trav_P <= execute_address;

                    a <= execute_data[`hed_start:`hed_end];

                    address1 <= execute_data[`tel_start:`tel_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= EXE_INIT_READ_TEL;
                  end
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                is_finished_reg <= 0;
              end
            end

            EXE_INIT_READ_TEL: begin
              if (mem_ready) begin
                // if data is [cell NIL] read hed
                if(read_data1[`tel_start:`tel_end] ==`NIL && read_data1[`tel_tag] == `ATOM) begin
                  if(read_data1[`hed_tag] == `CELL) begin
                    address1 <= read_data1[`hed_start:`hed_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= EXE_INIT_WRIT_TEL;
                  end else if (read_data1[`hed_tag] == `ATOM) begin
                    address1 <= execute_address;
                    mem_func <= `SET_CONTENTS;
                    mem_execute <= 1;
                    write_data <= {8'b00000011,
                                   read_data1[`hed_start:`hed_end],
                                   `NIL};
                    state <= EXE_INIT_ATOM_WRITE;
                  end else begin
`ifdef TRACE_EXEC_ERR
                    $display("exec err tel list hed not cell addr %0d data %h read %h",
                             execute_address,
                             execute_data,
                             read_data1);
`endif
                    debug_sig <= 17;
                    error <= `ERROR_TEL_NOT_CELL;
                    exec_func <= EXE_FUNC_ERROR;
                    state <= EXE_ERROR_INIT;
                  end
                end else begin
                  mem_data <= read_data1;
                  mem_tag <= read_data1[`tag_start:`tag_end]; 
                  opcode <= read_data1[`hed_start:`hed_end];
                  b <= read_data1[`tel_start:`tel_end];
                  b_addr <= address1;
                  state <= EXE_INIT_DECODE;
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INIT_WRIT_TEL: begin
              if (mem_ready) begin
                write_addr_reg <= execute_address;
                mem_execute <= 1;
                write_data <= {
                        execute_tag_clean,
                        execute_data[`hed_start:`hed_end],
                        `ADDR_PAD,
                        address1};
                b_addr <= address1;
                address1 <= execute_address;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state <= EXE_INIT_WRIT_TEL_READ;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INIT_WRIT_TEL_READ: begin
              if (mem_ready) begin
                // if data is [cell NIL] error
                if(read_data1[`tel_start:`tel_end] ==`NIL && read_data1[`tel_tag] == `ATOM) begin
                  if (read_data1[`hed_tag] == `CELL) begin
                    address1 <= read_data1[`hed_start:`hed_end];
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                    state <= EXE_INIT_WRIT_TEL;
                  end else begin
`ifdef TRACE_EXEC_ERR
                    $display("exec err tel list hed not cell (rewrite) addr %0d data %h read %h",
                             execute_address,
                             execute_data,
                             read_data1);
`endif
                    debug_sig <= 18;
                    error <= `ERROR_TEL_NOT_CELL;
                    exec_func <= EXE_FUNC_ERROR;
                    state <= EXE_ERROR_INIT;
                  end
                end else begin
                  mem_data <= read_data1;
                  mem_tag <= read_data1[`tag_start:`tag_end]; 
                  opcode <= read_data1[`hed_start:`hed_end];
                  b <= read_data1[`tel_start:`tel_end];
                  state <= EXE_INIT_DECODE;
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INIT_ATOM_WRITE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INIT_DECODE: begin
              if (mem_data[`hed_tag] == `CELL) begin
                exec_func <= EXE_FUNC_AUTOCONS;
                state <= EXE_AUTO_INIT;
              end else begin
                if ((opcode < 0) || (opcode > 11)) begin  //If invalid opcode
                  error <= `ERROR_INVALID_OPCODE;
                  exec_func <= EXE_FUNC_ERROR;
                  state <= EXE_ERROR_INIT;
                end else begin
                  func_return_exec_func <= EXE_FUNC_INIT;
                  func_return_state <= EXE_INIT_FINISHED;
                  case (opcode)
                    `slot: begin
                      if (mem_tag[1] == `ATOM) begin  // if b is an atom
                        exec_func <= EXE_FUNC_SLOT;
                        state <= EXE_SLOT_INIT;
                        func_addr <= trav_P;
                        func_return_exec_func <= EXE_FUNC_INIT;
                        func_return_state <= EXE_INIT_FINISHED;
                      end else begin
                        // Throw error invalid increment formulation
                        error <= `ERROR_INVALID_SLOT;
                        exec_func <= EXE_FUNC_ERROR;
                        state <= EXE_ERROR_INIT;
                      end
                    end

                    `constant: begin
                      exec_func <= EXE_FUNC_CONSTANT;
                      state <= EXE_CONSTANT_INIT;
                      func_addr <= trav_P;
                      func_return_exec_func <= EXE_FUNC_INIT;
                      func_return_state <= EXE_INIT_FINISHED;
                    end

                    `evaluate: begin
                      exec_func <= EXE_FUNC_EVAL;
                      state <= EXE_EVAL_INIT;
                      func_addr <= trav_P;
                      func_return_exec_func <= EXE_FUNC_INIT;
                      func_return_state <= EXE_INIT_FINISHED;
                    end

                    `cell: begin
                      exec_func <= EXE_FUNC_CELL;
                      state <= EXE_CELL_INIT;
                      func_return_exec_func <= EXE_FUNC_INIT;
                      func_return_state <= EXE_INIT_FINISHED;
                     end

                    `increment: begin
                      exec_func <= EXE_FUNC_INCR;
                      state <= EXE_INCR_INIT;
                      func_return_exec_func <= EXE_FUNC_INIT;
                      func_return_state <= EXE_INIT_FINISHED;
                      count <= count +1;
                    end

                    `equality: begin
                      exec_func <= EXE_FUNC_EQUAL;
                      state <= EXE_EQUAL_INIT;
                    end

                    `if_then_else: begin
                      exec_func <= EXE_FUNC_IF;
                      state <= EXE_IF_INIT;
                    end

                    `compose: begin
                      exec_func <= EXE_FUNC_COMPOSE;
                      state <= EXE_COMPOSE_INIT;
                    end

                    `extend: begin
                      exec_func <= EXE_FUNC_EXTEND;
                      state <= EXE_EXTEND_INIT;
                    end

                    `invoke: begin
                      exec_func <= EXE_FUNC_INVOKE;
                      state <= EXE_INVOKE_INIT;
                      //if(count == 9) $stop;
                    end

                    `replace: begin
                      exec_func <= EXE_FUNC_REPLACE;
                      state <= EXE_REPLACE_INIT;
                    end

                    `hint: begin
                      exec_func <= EXE_FUNC_HINT;
                      state <= EXE_HINT_INIT;
                    end
                  endcase
                end
              end
            end

            EXE_INIT_FINISHED: begin
              if (execute_start != `MUX_EXECUTE) begin  // If still high don't do anything
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_INIT;
                trav_B <= `NIL;
                is_finished_reg <= 0;
                execute_return_sys_func <= 0;
                execute_return_state <= 0;
                mem_execute<=0;
              end else begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_INIT;
                trav_B <= `NIL;
                execute_return_sys_func <= 0;
                execute_return_state <= 0;
                mem_execute<=0;
                is_finished_reg <= 1;
              end
            end

          endcase
        end


        EXE_FUNC_SLOT: begin
          case (state)
            EXE_SLOT_INIT: begin
              la_axis_ready <= 0;
              la_axis_done <= 0;
              la_axis_scan_mode <= 0;
              if(read_data1[`tel_tag] == `ATOM) begin
                if (read_data1[`tel_start:`tel_end] == `noun_width'h0) begin
                  address1 <= func_addr;
                  write_addr_reg <= func_addr;
                  mem_func <= `SET_CONTENTS;
                  mem_execute <= 1;
                  state <= EXE_SLOT_DONE;
                  write_data <= {
                          6'b000000,
                          `ATOM,
                          `ATOM,
                          `noun_width'h0,
                          `NIL};
                end else begin
                  b <= (read_data1[`tel_start:`tel_end]<<1) | 1;
                  address1 <= execute_data[`hed_start:`hed_end]; // Read subject
                  subject <= execute_data[`hed_start:`hed_end];
                  subject_tag <= execute_data[`hed_tag];
                  state <= EXE_SLOT_PREP;
                  mem_execute <= 1;
                  mem_func <= `GET_CONTENTS;
                end
              end else begin
                address1 <= read_data1[`tel_start:`tel_end];
                subject <= execute_data[`hed_start:`hed_end];
                subject_tag <= execute_data[`hed_tag];
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state <= EXE_SLOT_INDIRECT;
              end
            end

            EXE_SLOT_INDIRECT: begin
              if (mem_ready) begin
                if (read_data1[`large_atom_bit]) begin
                  if (read_data1[`hed_tag] != `CELL || read_data1[`tel_tag] != `ATOM) begin
                    error <= `ERROR_INVALID_SLOT;
                    exec_func <= EXE_FUNC_ERROR;
                    state <= EXE_ERROR_INIT;
                  end else begin
                    la_axis_len <= read_data1[`tel_start:`tel_end];
                    la_axis_head_ptr <= read_data1[`hed_start:`hed_end];
                    state <= EXE_SLOT_LA_INIT;
                  end
                end else if (read_data1[`hed_tag] == `ATOM
                && read_data1[`tel_tag] == `ATOM
                && read_data1[`hed_start:`hed_end] == `noun_width'h0
                && read_data1[`tel_start:`tel_end] == `noun_width'h0) begin
                  address1 <= func_addr;
                  write_addr_reg <= func_addr;
                  mem_func <= `SET_CONTENTS;
                  mem_execute <= 1;
                  state <= EXE_SLOT_DONE;
                  write_data <= {
                          6'b000000,
                          `ATOM,
                          `ATOM,
                          `noun_width'h0,
                          `NIL};
                end else if(read_data1[`tel_start:`tel_end] == `NIL 
                && read_data1[`tel_tag] == `ATOM
                && read_data1[`hed_tag] == `ATOM) begin
                  b <= (read_data1[`hed_start:`hed_end]<<1) | 1;
                  address1 <= execute_data[`hed_start:`hed_end]; // Read subject
                  subject <= execute_data[`hed_start:`hed_end];
                  subject_tag <= execute_data[`hed_tag];
                  state <= EXE_SLOT_PREP;
                  mem_execute <= 1;
                  mem_func <= `GET_CONTENTS;
                end else begin
                  error <= `ERROR_INVALID_SLOT;
                  exec_func <= EXE_FUNC_ERROR;
                  state <= EXE_ERROR_INIT;
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_SLOT_PREP: begin
              if(b[`noun_width-1] == 1) begin
                state <= EXE_SLOT_CHECK;
              end
              b <= b << 1;
            end

            EXE_SLOT_LA_INIT: begin
              if (la_axis_len == 0) begin
                error <= `ERROR_INVALID_SLOT;
                exec_func <= EXE_FUNC_ERROR;
                state <= EXE_ERROR_INIT;
              end else begin
                la_axis_target_idx <= la_axis_len - 1'b1;
                la_axis_scan_idx <= 0;
                la_axis_ptr <= la_axis_head_ptr;
                la_axis_scan_mode <= 1'b0;
                state <= EXE_SLOT_LA_SCAN_READ;
              end
            end

            EXE_SLOT_LA_SCAN_READ: begin
              address1 <= la_axis_ptr;
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1;
              state <= EXE_SLOT_LA_SCAN_WAIT;
            end

            EXE_SLOT_LA_SCAN_WAIT: begin
              if (mem_ready) begin
                if (read_data1[`hed_tag] != `ATOM) begin
                  error <= `ERROR_INVALID_SLOT;
                  exec_func <= EXE_FUNC_ERROR;
                  state <= EXE_ERROR_INIT;
                end else if (la_axis_scan_idx == la_axis_target_idx) begin
                  if (la_axis_scan_mode == 1'b0) begin
                    if (read_data1[`tel_tag] != `ATOM
                    || read_data1[`tel_start:`tel_end] != `NIL) begin
                      error <= `ERROR_INVALID_SLOT;
                      exec_func <= EXE_FUNC_ERROR;
                      state <= EXE_ERROR_INIT;
                    end else if (msb_index(read_data1[`hed_start:`hed_end]) == 6'h3F) begin
                      error <= `ERROR_INVALID_SLOT;
                      exec_func <= EXE_FUNC_ERROR;
                      state <= EXE_ERROR_INIT;
                    end else if (msb_index(read_data1[`hed_start:`hed_end]) == 0) begin
                      if (la_axis_len == 1) begin
                        la_axis_done <= 1'b1;
                        la_axis_ready <= 1'b1;
                        state <= EXE_SLOT_LA_READ_SUBJECT;
                      end else begin
                        la_axis_cur_idx <= la_axis_len - 2'h2;
                        la_axis_ready <= 1'b0;
                        la_axis_scan_mode <= 1'b1;
                        la_axis_target_idx <= la_axis_len - 2'h2;
                        la_axis_scan_idx <= 0;
                        la_axis_ptr <= la_axis_head_ptr;
                        state <= EXE_SLOT_LA_SCAN_READ;
                      end
                    end else begin
                      la_axis_cur_idx <= la_axis_len - 1'b1;
                      la_axis_val <= read_data1[`hed_start:`hed_end];
                      la_axis_bit <= msb_index(read_data1[`hed_start:`hed_end]) - 1'b1;
                      la_axis_ready <= 1'b1;
                      la_axis_done <= 1'b0;
                      state <= EXE_SLOT_LA_READ_SUBJECT;
                    end
                  end else begin
                    la_axis_val <= read_data1[`hed_start:`hed_end];
                    la_axis_bit <= 6'd27;
                    la_axis_ready <= 1'b1;
                    state <= EXE_SLOT_LA_READ_SUBJECT;
                  end
                end else begin
                  if (read_data1[`tel_tag] != `CELL) begin
                    error <= `ERROR_INVALID_SLOT;
                    exec_func <= EXE_FUNC_ERROR;
                    state <= EXE_ERROR_INIT;
                  end else begin
                    la_axis_ptr <= read_data1[`tel_start:`tel_end];
                    la_axis_scan_idx <= la_axis_scan_idx + 1'b1;
                    state <= EXE_SLOT_LA_SCAN_READ;
                  end
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_SLOT_LA_READ_SUBJECT: begin
              if (subject_tag == `ATOM && !la_axis_done) begin
                exec_func <= EXE_FUNC_ERROR;
                state <= EXE_ERROR_INIT;
                error <= `ERROR_INVALID_SLOT;
              end else if (subject_tag == `ATOM) begin
                state <= EXE_SLOT_LA_CHECK;
              end else begin
                address1 <= subject;
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state <= EXE_SLOT_LA_WAIT_SUBJECT;
              end
            end

            EXE_SLOT_LA_WAIT_SUBJECT: begin
              if (mem_ready) begin
                slot_subject_reg <= read_data1;
                state <= EXE_SLOT_LA_CHECK;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_SLOT_LA_CHECK: begin
              if (la_axis_done) begin
                if (subject_tag == `CELL) begin
                  state <= EXE_SLOT_CELL_OF_NIL;
                  address1 <= subject;
                  mem_func <= `GET_CONTENTS;
                  mem_execute <= 1;
                end else begin
                  state <= EXE_SLOT_DONE;
                  mem_func <= `SET_CONTENTS;
                  address1 <= func_addr;
                  write_addr_reg <= func_addr;
                  mem_execute <= 1;
                  write_data <= {
                          6'b000000,
                          subject_tag,
                          1'b1,
                          subject,
                          `NIL};
                end
              end else if (subject_tag == `ATOM) begin
                exec_func <= EXE_FUNC_ERROR;
                state <= EXE_ERROR_INIT;
                error <= `ERROR_INVALID_SLOT;
              end else if (slot_subject_reg[`large_atom_bit]) begin
                exec_func <= EXE_FUNC_ERROR;
                state <= EXE_ERROR_INIT;
                if (la_axis_val[la_axis_bit] == 1'b0) begin
                  error <= `ERROR_INVALID_SLOT_HED;
                end else begin
`ifdef TRACE_SLOT_ERR
                  $display("slot la error tel large_atom subject %h axis_val %h bit %0d exec_func %0d state %0d",
                           slot_subject_reg,
                           la_axis_val,
                           la_axis_bit,
                           exec_func,
                           state);
`endif
                  error <= `ERROR_INVALID_SLOT_TEL;
                end
              end else begin
                if (la_axis_val[la_axis_bit] == 1'b0) begin
                  if (slot_subject_reg[`hed_tag] == `CELL) begin
                    subject <= slot_subject_reg[`hed_start:`hed_end];
                    subject_tag <= `CELL;
                    if (la_axis_cur_idx == 0 && la_axis_bit == 0) begin
                      la_axis_done <= 1'b1;
                      state <= EXE_SLOT_LA_READ_SUBJECT;
                    end else if (la_axis_bit == 0) begin
                      la_axis_cur_idx <= la_axis_cur_idx - 1'b1;
                      la_axis_ready <= 1'b0;
                      la_axis_scan_mode <= 1'b1;
                      la_axis_target_idx <= la_axis_cur_idx - 1'b1;
                      la_axis_scan_idx <= 0;
                      la_axis_ptr <= la_axis_head_ptr;
                      state <= EXE_SLOT_LA_SCAN_READ;
                    end else begin
                      la_axis_bit <= la_axis_bit - 1'b1;
                      state <= EXE_SLOT_LA_READ_SUBJECT;
                    end
                  end else if (la_axis_cur_idx == 0 && la_axis_bit == 0) begin
                    state <= EXE_SLOT_DONE;
                    mem_func <= `SET_CONTENTS;
                    address1 <= func_addr;
                    write_addr_reg <= func_addr;
                    mem_execute <= 1;
                    write_data <= {
                      6'b000000,
                      slot_subject_reg[`hed_tag],
                      1'b1,
                      slot_subject_reg[`hed_start:`hed_end],
                      `NIL};
                  end else begin
                    exec_func <= EXE_FUNC_ERROR;
                    state <= EXE_ERROR_INIT;
                    error <= `ERROR_INVALID_SLOT_HED;
                  end
                end else begin
                  if (slot_subject_reg[`tel_tag] == `CELL) begin
                    subject <= slot_subject_reg[`tel_start:`tel_end];
                    subject_tag <= `CELL;
                    if (la_axis_cur_idx == 0 && la_axis_bit == 0) begin
                      la_axis_done <= 1'b1;
                      state <= EXE_SLOT_LA_READ_SUBJECT;
                    end else if (la_axis_bit == 0) begin
                      la_axis_cur_idx <= la_axis_cur_idx - 1'b1;
                      la_axis_ready <= 1'b0;
                      la_axis_scan_mode <= 1'b1;
                      la_axis_target_idx <= la_axis_cur_idx - 1'b1;
                      la_axis_scan_idx <= 0;
                      la_axis_ptr <= la_axis_head_ptr;
                      state <= EXE_SLOT_LA_SCAN_READ;
                    end else begin
                      la_axis_bit <= la_axis_bit - 1'b1;
                      state <= EXE_SLOT_LA_READ_SUBJECT;
                    end
                  end else if (la_axis_cur_idx == 0 && la_axis_bit == 0) begin
                    state <= EXE_SLOT_DONE;
                    mem_func <= `SET_CONTENTS;
                    address1 <= func_addr;
                    write_addr_reg <= func_addr;
                    mem_execute <= 1;
                    write_data <= {
                      6'b000000,
                      slot_subject_reg[`tel_tag],
                      1'b1,
                      slot_subject_reg[`tel_start:`tel_end],
                      `NIL};
                  end else begin
                    exec_func <= EXE_FUNC_ERROR;
                    state <= EXE_ERROR_INIT;
`ifdef TRACE_SLOT_ERR
                    $display("slot la error tel tag %h axis_val %h bit %0d exec_func %0d state %0d",
                             slot_subject_reg,
                             la_axis_val,
                             la_axis_bit,
                             exec_func,
                             state);
`endif
                    error <= `ERROR_INVALID_SLOT_TEL;
                  end
                end
              end
            end

            EXE_SLOT_READ_INDIRECT: begin
              if (mem_ready) begin
                if(read_data1[`hed_tag] == `CELL
                && read_data1[`tel_tag] == `ATOM
                && read_data1[`tel_start:`tel_end] == `NIL) begin
                  address1 <= read_data1[`hed_start:`hed_end];
                  mem_func <= `GET_CONTENTS;
                  mem_execute <= 1;
                  state <= EXE_SLOT_READ_INDIRECT;
                end else begin
                  address1 <= func_addr;
                  write_addr_reg <= func_addr;
                  mem_func <= `SET_CONTENTS;
                  mem_execute <= 1;
                  state <= EXE_SLOT_DONE;
                  write_data <= read_data1_clean;
               end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

            EXE_SLOT_CELL_OF_NIL: begin
              if (mem_ready) begin

                if(read_data1[`tel_start:`tel_end] == `NIL 
                && read_data1[`tel_tag] == `ATOM) begin
                  if(read_data1[`hed_tag] == `CELL) begin
                    state <= EXE_SLOT_READ_INDIRECT;
                    mem_func <= `GET_CONTENTS;
                    address1 <= read_data1[`hed_start:`hed_end];
                    mem_execute <= 1;
                  end else begin
                    mem_func <= `SET_CONTENTS;
                    address1 <= func_addr;
                    write_addr_reg <= func_addr;
                    mem_execute <= 1;
                    state <= EXE_SLOT_DONE;
                    write_data <= {
                            6'b000000,
                            read_data1[`hed_tag],
                            1'b1,
                            read_data1[`hed_start:`hed_end],
                            `NIL};
                  end
                end else begin
                  if(subject_tag == `CELL) begin
                    state <= EXE_SLOT_READ_INDIRECT;
                    mem_func <= `GET_CONTENTS;
                    address1 <= subject;
                    mem_execute <= 1;
                  end else begin
                    mem_func <= `SET_CONTENTS;
                    address1 <= func_addr;
                    write_addr_reg <= func_addr;
                    mem_execute <= 1;
                    state <= EXE_SLOT_DONE;
                    write_data <= {
                            6'b000000,
                            subject_tag,
                            1'b1,
                            subject,
                            `NIL};
                 end
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            // [[32 33] [42 43]] [0 4]
            EXE_SLOT_CHECK: begin
              if (mem_ready) begin
                if ( b == 28'h8000000) begin
                  // need to do check to make sure the cell isn't [atom NIL]
                  if(subject_tag == `CELL) begin
                    state <= EXE_SLOT_CELL_OF_NIL;
                    address1 <= subject;
                    mem_func <= `GET_CONTENTS;
                    mem_execute <= 1;
                  end else begin
                    state <= EXE_SLOT_DONE;
                    mem_func <= `SET_CONTENTS;
                    address1 <= func_addr;
                    write_addr_reg <= func_addr;
                    mem_execute <= 1;
                    write_data <= {
                            6'b000000,
                            subject_tag,
                            1'b1,
                            subject,
                            `NIL};
                    state <= EXE_SLOT_DONE;
                    a<=1;
                  end
                end
                else if (execute_data[`hed_tag] == `ATOM) begin
                  exec_func <= EXE_FUNC_ERROR;
                  state <= EXE_ERROR_INIT;
                  error <= `ERROR_INVALID_SLOT;
                end
                else begin
                    if (read_data1[`large_atom_bit]) begin
                      exec_func <= EXE_FUNC_ERROR;
                      state <= EXE_ERROR_INIT;
                      if (b[`noun_width-1] == 0) begin
`ifdef TRACE_SLOT_ERR
                        $display("slot error hed large_atom read %h b %h subject %h exec_addr %0d exec_data %h",
                                 read_data1,
                                 b,
                                 subject,
                                 execute_address,
                                 execute_data);
`endif
                        error <= `ERROR_INVALID_SLOT_HED;
                      end else begin
`ifdef TRACE_SLOT_ERR
                        $display("slot error tel large_atom read %h b %h subject %h exec_func %0d state %0d",
                                 read_data1,
                                 b,
                                 subject,
                                 exec_func,
                                 state);
`endif
                        error <= `ERROR_INVALID_SLOT_TEL;
                      end
                    end else begin
                    if (b[`noun_width-1] == 0) begin
                      if(read_data1[`hed_tag] == `CELL) begin
                        address1 <= read_data1[`hed_start:`hed_end];
                        subject <= read_data1[`hed_start:`hed_end];
                        subject_tag <= read_data1[`hed_tag];
                        mem_func <= `GET_CONTENTS;
                        mem_execute <= 1;
                        state <= EXE_SLOT_CHECK;
                      end else if(b == 28'h4000000) begin
                        state <= EXE_SLOT_DONE;
                        mem_func <= `SET_CONTENTS;
                        address1 <= func_addr;
                        write_addr_reg <= func_addr;
                        mem_execute <= 1;
                        write_data <= {
                          6'b000000,
                          read_data1[`hed_tag],
                          1'b1,
                          read_data1[`hed_start:`hed_end],
                          `NIL};
                        state <= EXE_SLOT_DONE;
                      end else begin
                        exec_func <= EXE_FUNC_ERROR;
                        state <= EXE_ERROR_INIT;
`ifdef TRACE_SLOT_ERR
                        $display("slot error hed read %h b %h subject %h exec_addr %0d exec_data %h",
                                 read_data1,
                                 b,
                                 subject,
                                 execute_address,
                                 execute_data);
`endif
                        error <= `ERROR_INVALID_SLOT_HED;
                      end
                    end else begin
                      if(read_data1[`tel_tag] == `CELL) begin
                        address1 <= read_data1[`tel_start:`tel_end];
                        subject <= read_data1[`tel_start:`tel_end];
                        subject_tag <= read_data1[`tel_tag];
                        mem_func <= `GET_CONTENTS;
                        mem_execute <= 1;
                        state <= EXE_SLOT_CHECK;
                      end else if(b == 28'hC000000) begin
                        state <= EXE_SLOT_DONE;
                        mem_func <= `SET_CONTENTS;
                        address1 <= func_addr;
                        write_addr_reg <= func_addr;
                        mem_execute <= 1;
                        write_data <= {
                          6'b000000,
                          read_data1[`tel_tag],
                          1'b1,
                          read_data1[`tel_start:`tel_end],
                          `NIL};
                        state <= EXE_SLOT_DONE;
                      end else begin
                        debug_sig <= 12;
                        exec_func <= EXE_FUNC_ERROR;
                        state <= EXE_ERROR_INIT;
`ifdef TRACE_SLOT_ERR
                        $display("slot error tel read %h b %h subject %h exec_func %0d state %0d exec_addr %0d exec_data %h",
                                 read_data1,
                                 b,
                                 subject,
                                 exec_func,
                                 state,
                                 execute_address,
                                 execute_data);
`endif
                        error <= `ERROR_INVALID_SLOT_TEL;
                      end
                    end
                  b <= b << 1;
                  end
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
           end

           EXE_SLOT_DONE: begin
             if (mem_ready) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
             end else begin
               mem_func <= 0;
               mem_execute <= 0;
             end
           end

          endcase
        end

        EXE_FUNC_CONSTANT: begin
          case (state)
            EXE_CONSTANT_INIT: begin
              if (read_data1[`tel_tag] == `CELL) begin
                address1 <= b;
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                exec_func <= EXE_FUNC_CONSTANT;
                state <= EXE_CONSTANT_READ_B;
              end else begin
                address1 <= func_addr;
                write_addr_reg <= func_addr;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                exec_func <= EXE_FUNC_CONSTANT;
                state <= EXE_CONSTANT_WRITE_WAIT;
                write_data <= {8'b00000011, b, `NIL};
              end
            end

            EXE_CONSTANT_READ_B: begin
              if (mem_ready) begin
                address1 <= func_addr;
                write_addr_reg <= func_addr;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state <= EXE_CONSTANT_WRITE_WAIT;
                write_data <= {const_copy_tag,
                               read_data1[`hed_start:`hed_end],
                               read_data1[`tel_start:`tel_end]};
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

            EXE_CONSTANT_READ_B_INDIRECT: begin
              if (mem_ready) begin
                address1 <= func_addr;
                write_addr_reg <= func_addr;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state <= EXE_CONSTANT_WRITE_WAIT;
                write_data <= {const_copy_tag,
                               read_data1[`hed_start:`hed_end],
                               read_data1[`tel_start:`tel_end]};
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

            EXE_CONSTANT_WRITE_WAIT: begin
              if (mem_ready) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

          endcase
        end


        EXE_FUNC_EVAL: begin
          case(state)
            EXE_EVAL_INIT: begin
              subject <= execute_data[`hed_start:`hed_end];
              subject_tag <= execute_data[`hed_tag];
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1;
              address1 <= read_data1[`tel_start:`tel_end];
              state <= EXE_EVAL_READ_TEL_TEL;
            end

            EXE_EVAL_READ_TEL_TEL: begin
              if (mem_ready) begin
                b <= read_data1[`hed_start:`hed_end];
                b_tag <= read_data1[`hed_tag];
                c <= read_data1[`tel_start:`tel_end];
                c_tag <= read_data1[`tel_tag];
                // Allocate fresh exec nodes to keep arg lists intact during traversal.
                mem_func <= `GET_FREE;
                mem_execute <= 1;
                write_data <= 2;
                state <= EXE_EVAL_WRIT_HED;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EVAL_WRIT_HED: begin
              if (mem_ready) begin
                a <= free_addr;
                address1 <= free_addr;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= {6'b100000,
                               subject_tag,
                               b_tag,
                               subject,
                               b};
                state <= EXE_EVAL_WRIT_1_EXE;
              end else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EVAL_WRIT_1_EXE: begin
              if (mem_ready) begin
                address1 <= a + 1'h1;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= {6'b100000,
                               subject_tag,
                               c_tag,
                               subject,
                               c};
                state <= EXE_EVAL_WRIT_2_EXE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EVAL_WRIT_2_EXE: begin
              if (mem_ready) begin
                address1 <= execute_address;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= {6'b100000,
                               `CELL,
                               `CELL,
                               a,
                               a + 1'h1};
                state <= EXE_EVAL_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EVAL_DONE: begin
              if (mem_ready) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

          endcase
        end

        EXE_FUNC_CELL: begin
          case(state)
            EXE_CELL_INIT: begin
              if (mem_ready) begin
                //rewrite value in addr to *[a tel]
                address1 <= address1;
                state <= EXE_CELL_CHECK;
                mem_execute <= 1;
                mem_func <= `SET_CONTENTS;
                write_data <= {
                        6'b100000, // add execute
                        execute_data[`hed_tag], 
                        read_data1[`tel_tag], // Mark as CELL
                        execute_data[`hed_start:`hed_end],
                        read_data1[`tel_start:`tel_end]};
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

            EXE_CELL_CHECK: begin
              if (mem_ready) begin
                address1 <= execute_address;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= {
                        6'b110000, // mark stack bit
                        `ATOM, 
                        `CELL,
                        `noun_width'h3,//opcode 3
                        `ADDR_PAD,
                        address1};
                state <= EXE_CELL_WRITE_WAIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

            EXE_CELL_WRITE_WAIT: begin
              if (mem_ready) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

          endcase
        end

        EXE_FUNC_INCR: begin
          case(state)
            EXE_INCR_INIT: begin
              if (mem_ready) begin
                state <= EXE_INCR_FREE;
                mem_execute <= 1;
                mem_func <= `GET_FREE;
                write_data <= 1;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INCR_FREE: begin
              if (mem_ready) begin
`ifdef TRACE_INCR_FREE
                $display("incr free exec_addr %0d read %h",
                         execute_address,
                         read_data1);
`endif
                //rewrite value in addr to *[a tel]
                address1 <= free_addr;
                state <= EXE_INCR_CHECK;
                mem_execute <= 1;
                mem_func <= `SET_CONTENTS;
                write_data <= {
                        6'b100000, // add execute
                        execute_data[`hed_tag], 
                        read_data1[`tel_tag], // Mark as CELL
                        execute_data[`hed_start:`hed_end],
                        read_data1[`tel_start:`tel_end]};
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

            EXE_INCR_CHECK: begin
              if (mem_ready) begin
                address1 <= execute_address;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= {
                        6'b110000, // mark stack bit
                        `ATOM, 
                        `CELL,
                        `noun_width'h4,//opcode 4
                        `ADDR_PAD,
                        free_addr};
                state <= EXE_INCR_WRITE_WAIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end

            EXE_INCR_WRITE_WAIT: begin
              if (mem_ready) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
                read_data_reg <= read_data1;
              end
            end
          endcase
        end

        EXE_FUNC_EQUAL: begin
          case(state)
            EXE_EQUAL_INIT: begin
              if (mem_ready) begin
                mem_func <= `GET_FREE;
                write_data <= 3;
                mem_execute <= 1;
                state<= EXE_EQUAL_WRITE_ROOT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EQUAL_WRITE_ROOT: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= execute_address;
                a<= free_addr;
                b_addr <= execute_data[`tel_start:`tel_end];
                mem_execute <= 1;
                write_data <= {
                        6'b110000, // mark as execute opcode
                        `ATOM, // Mark as ATOM
                        `CELL, // Mark as CELL
                        `noun_width'h5,
                        `ADDR_PAD,
                        free_addr};
                state <= EXE_EQUAL_READ_TEL;
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EQUAL_READ_TEL: begin
              if (mem_ready) begin
                mem_func <= `GET_CONTENTS;
                address1 <= b_addr;
                mem_execute <= 1;
                state <= EXE_EQUAL_READ_TEL_TEL;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EQUAL_READ_TEL_TEL: begin
              if (mem_ready) begin
                mem_func <= `GET_CONTENTS;
                c_addr <= read_data1[`tel_start:`tel_end];
                address1 <= read_data1[`tel_start:`tel_end];
                mem_execute <= 1;
                state <= EXE_EQUAL_WRITE_TEL;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end


            EXE_EQUAL_WRITE_TEL: begin
              if (mem_ready) begin
                b <= read_data1[`hed_start:`hed_end];
                b_tag <= read_data1[`hed_tag];
                c <= read_data1[`tel_start:`tel_end];
                c_tag <= read_data1[`tel_tag];
                mem_func <= `SET_CONTENTS;
                address1 <= a;
                mem_execute <= 1;
                write_data <= {
                        6'b000000,
                        `CELL,
                        `CELL,
                        a + 1'h1,
                        a + 2'h2};
                state <= EXE_EQUAL_WRITE_TEL_TEL;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EQUAL_WRITE_TEL_TEL: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a + 1'h1;
                mem_execute <= 1;
                write_data <= {
                        6'b100000, // mark as execute opcode
                        execute_data[`hed_tag],
                        b_tag,
                        execute_data[`hed_start:`hed_end],
                        b};
                state <= EXE_EQUAL_WRITE_MEM;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EQUAL_WRITE_MEM: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a + 2'h2;
                mem_execute <= 1;
                write_data <= {
                        6'b100000, // mark as execute opcode
                        execute_data[`hed_tag],
                        c_tag,
                        execute_data[`hed_start:`hed_end],
                        c};
                state <= EXE_EQUAL_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EQUAL_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

          endcase
        end

        /*
          EXE_IF_INIT    = 4'h0,
          EXE_IF_READ_B  = 4'h1,
          EXE_IF_READ_C  = 4'h2,
          EXE_IF_READ_D  = 4'h3,
          EXE_IF_WRITE1  = 4'h4,
          EXE_IF_WRITE2  = 4'h5,
          EXE_IF_WRITE3  = 4'h6,
          EXE_IF_WRITE4  = 4'h7,
          EXE_IF_WRITE5  = 4'h8,
          EXE_IF_WRITE6  = 4'h9,
          EXE_IF_WRITE7  = 4'hA,
          EXE_IF_WRITE8  = 4'hB,
          EXE_IF_WRITE9  = 4'hC,
          EXE_IF_WRITE10 = 4'hD,
          EXE_IF_DONE    = 4'hE,
          EXE_IF_WRITE11 = 4'hF;
        */
        EXE_FUNC_IF: begin
          case(state)
            EXE_IF_INIT: begin
              if (mem_ready) begin
                write_data <= 9;
                mem_func <= `GET_FREE;
                mem_execute <= 1;
                state<= EXE_IF_READ_B;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_READ_B: begin
              if (mem_ready) begin
                a <= free_addr;
                c_addr <= read_data1[`tel_start:`tel_end];
                d_addr <= execute_data[`tel_start:`tel_end];
                address1 <= read_data1[`tel_start:`tel_end];
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_READ_C;
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_READ_C: begin
              if (mem_ready) begin
                if (read_data1[`tel_tag] != `CELL) begin
`ifdef TRACE_EXEC_ERR
                  $display("if err bcd tail not cell exec_addr %0d exec_data %h bcd_addr %0d bcd_data %h",
                           execute_address,
                           execute_data,
                           c_addr,
                           read_data1);
`endif
                  error <= `ERROR_INVALID_B_CELL;
                  exec_func <= EXE_FUNC_ERROR;
                  state <= EXE_ERROR_INIT;
                  mem_func <= 0;
                  mem_execute <= 0;
                end else begin
                b <= read_data1[`hed_start:`hed_end];
                b_tag <= read_data1[`hed_tag];
                b_addr <= read_data1[`tel_start:`tel_end];
                address1 <= read_data1[`tel_start:`tel_end];
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_READ_D;
`ifdef TRACE_IF_B
                if (read_data1[`hed_tag] == `CELL
                && read_data1[`hed_start:`hed_end] == `noun_width'h10) begin
                  $display("if b ptr 0x10 exec_addr %0d exec_data %h bcd_addr %0d bcd_data %h",
                           execute_address,
                           execute_data,
                           c_addr,
                           read_data1);
                end
`endif
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_READ_D: begin
              if (mem_ready) begin
                c <= read_data1[`hed_start:`hed_end];
                c_tag <= read_data1[`hed_tag];
                d <= read_data1[`tel_start:`tel_end];
                d_tag <= read_data1[`tel_tag];
                state<= EXE_IF_WRITE1;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE1: begin
              if (mem_ready) begin
                address1 <= a;
                write_data <= { 6'b000000,
                                c_tag,
                                d_tag,
                                c,
                                d};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE2;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE2: begin
              if (mem_ready) begin
                address1 <= a + 1'h1;
                write_data <= { 6'b000000,
                                `ATOM,
                                `ATOM,
                                `noun_width'h2,
                                `noun_width'h3};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE3;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE3: begin
              if (mem_ready) begin
                address1 <= a + 2'h2;
                write_data <= { 6'b000000,
                                `ATOM,
                                b_tag,
                                `noun_width'h4,
                                b};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE4;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE4: begin
              if (mem_ready) begin
                address1 <= a + 2'h3;
                write_data <= { 6'b000000,
                                `ATOM,
                                `CELL,
                                `noun_width'h4,
                                a + 2'h2};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE5;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE5: begin
              if (mem_ready) begin
                address1 <= a + 3'h4;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                `CELL,
                                execute_data[`hed_start:`hed_end],
                                a + 2'h3};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE6;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE6: begin
              if (mem_ready) begin
                address1 <= a + 3'h5;
                write_data <= { 6'b000000,
                                `ATOM,
                                `CELL,
                                `noun_width'h0,
                                a + 3'h4};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE7;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE7: begin
              if (mem_ready) begin
                address1 <= a + 3'h6;
                write_data <= { 6'b100000,
                                `CELL,
                                `CELL,
                                a + 1'h1,
                                a + 3'h5};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE8;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE8: begin
              if (mem_ready) begin
                address1 <= a + 3'h7;
                write_data <= { 6'b000000,
                                `ATOM,
                                `CELL,
                                `noun_width'h0,
                                a + 3'h6};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE9;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE9: begin
              if (mem_ready) begin
                address1 <= a + 4'h8;
                write_data <= { 6'b100000,
                                `CELL,
                                `CELL,
                                a,
                                a + 3'h7};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_WRITE10;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_WRITE10: begin
              if (mem_ready) begin
                address1 <= execute_address;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                `CELL,
                                execute_data[`hed_start:`hed_end],
                                a + 4'h8};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_IF_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_IF_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

          endcase
        end

        EXE_FUNC_COMPOSE: begin
          case(state)
            EXE_COMPOSE_INIT: begin
              if (mem_ready) begin
                mem_func <= `GET_FREE;
                write_data <= 1;
                mem_execute <= 1;
                state<= EXE_COMPOSE_FREE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_COMPOSE_FREE: begin
              if (mem_ready) begin
                a <= free_addr;
                b_addr <= address1;
                address1 <= read_data1[`tel_start:`tel_end];
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_COMPOSE_READ;
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_COMPOSE_READ: begin
              if (mem_ready) begin
                read_data_reg <= read_data1;
                address1 <= a;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                read_data1[`hed_tag],
                                execute_data[`hed_start:`hed_end],
                                read_data1[`hed_start:`hed_end]};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_COMPOSE_WRITE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_COMPOSE_WRITE: begin
              if (mem_ready) begin
                address1 <= execute_address;
                write_data <= { 6'b100000,
                                `CELL,
                                read_data_reg[`tel_tag],
                                a,
                                read_data_reg[`tel_start:`tel_end]};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_COMPOSE_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_COMPOSE_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end

        EXE_FUNC_EXTEND: begin
          case(state)
            EXE_EXTEND_INIT: begin
              if (mem_ready) begin
                mem_func <= `GET_FREE;
                write_data <= 2;
                mem_execute <= 1;
                state<= EXE_EXTEND_FREE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EXTEND_FREE: begin
              if (mem_ready) begin
                a <= free_addr;
                address1 <= execute_data[`tel_start:`tel_end];
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_EXTEND_READ1;
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EXTEND_READ1: begin
              if (mem_ready) begin
                address1 <= read_data1[`tel_start:`tel_end];
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_EXTEND_READ2;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EXTEND_READ2: begin
              if (mem_ready) begin
                read_data_reg <= read_data1;
                address1 <= execute_address;
                write_data <= { 6'b100000,
                                `CELL,
                                read_data1[`tel_tag],
                                a,
                                read_data1[`tel_start:`tel_end]};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_EXTEND_WRITE1;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EXTEND_WRITE3: begin
              if (mem_ready) begin
                address1 <= execute_address;
                write_data <= { 6'b100000,
                                `CELL,
                                `CELL,
                                a,
                                `ADDR_PAD,
                                c_addr};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_EXTEND_WRITE2;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EXTEND_WRITE1: begin
              if (mem_ready) begin
                address1 <= a;
                a<= a+1;
                write_data <= { 6'b000000,
                                `CELL,
                                execute_data[`hed_tag],
                                a+1'h1,
                                execute_data[`hed_start:`hed_end]};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_EXTEND_WRITE2;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EXTEND_WRITE2: begin
              if (mem_ready) begin
                address1 <= a;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                read_data_reg[`hed_tag],
                                execute_data[`hed_start:`hed_end],
                                read_data_reg[`hed_start:`hed_end]};
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                state<= EXE_EXTEND_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_EXTEND_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end

        EXE_FUNC_INVOKE: begin
          case(state)
            EXE_INVOKE_INIT: begin
              if (mem_ready) begin
                mem_func <= `GET_FREE;
                write_data <= 5;
                mem_execute <= 1;
                state <= EXE_INVOKE_READ;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_READ: begin
              if (mem_ready) begin
                a <= free_addr;
                mem_func <= `GET_CONTENTS;
                address1 <= execute_data[`tel_start:`tel_end];
                mem_execute <= 1;
                state <= EXE_INVOKE_READ2;
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_READ2: begin
              if (mem_ready) begin
                mem_func <= `GET_CONTENTS;
                b <= read_data1[`tel_start:`tel_end];
                address1 <= read_data1[`tel_start:`tel_end];
                mem_execute <= 1;
                state <= EXE_INVOKE_WRITE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_WRITE: begin
              if (mem_ready) begin
                read_data_reg <= read_data1;
                mem_func <= `SET_CONTENTS;
                address1 <= execute_address;
                mem_execute <= 1;
                write_data <= { 6'b100000,
                                `CELL, 
                                `CELL,
                                a,
                                a+1'h1};
                state <= EXE_INVOKE_WRITE2;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_WRITE2: begin
              if (mem_ready) begin
                a <= a+1;
                mem_func <= `SET_CONTENTS;
                address1 <= a;
                mem_execute <= 1;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag], //a
                                read_data_reg[`tel_tag],//c
                                execute_data[`hed_start:`hed_end],
                                read_data_reg[`tel_start:`tel_end]};  
                state <= EXE_INVOKE_WRITE3;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_WRITE3: begin
              if (mem_ready) begin
                a <= a+1;
                mem_func <= `SET_CONTENTS;
                address1 <= a;
                mem_execute <= 1;
                write_data <= { 6'b000000,
                                `ATOM,
                                `CELL,
                                `noun_width'h2,
                                a+1'h1};
                state <= EXE_INVOKE_WRITE4;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_WRITE4: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a;
                a <= a+1;
                mem_execute <= 1;
                state <= EXE_INVOKE_WRITE5;
                write_data <= { 6'b000000,
                                `CELL,
                                `CELL,
                                a+1'h1,
                                a+2'h2};
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_WRITE5: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a;
                a<= a+1;
                mem_execute <= 1;
                write_data <= { 6'b000000,
                                `ATOM,
                                `ATOM,
                                `noun_width'h0,
                                `noun_width'h1};
                state <= EXE_INVOKE_WRITE6;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_WRITE6: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a;
                mem_execute <= 1;
                write_data <= { 6'b000000,
                                `ATOM,
                                read_data_reg[`hed_tag], //b
                                `noun_width'h0,
                                read_data_reg[`hed_start:`hed_end]}; //b
                state <= EXE_INVOKE_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_INVOKE_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end

        EXE_FUNC_REPLACE: begin
          case(state)
            EXE_REPLACE_INIT: begin
              if(mem_ready) begin
                mem_func <= `GET_FREE;
                write_data <= 5;
                mem_execute <= 1;
                state <= EXE_REPLACE_READ;
              end else begin
                mem_func<=0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_READ: begin
              if (mem_ready) begin
                a <= free_addr;
                mem_func <= `GET_CONTENTS;
                address1 <= b;
                mem_execute <= 1;
                state <= EXE_REPLACE_READ2;
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_READ2: begin
              if (mem_ready) begin
                mem_func <= `GET_CONTENTS;
                c <= read_data1[`tel_start:`tel_end];
                c_tag <= read_data1[`tel_tag];
                address1 <= read_data1[`hed_start:`hed_end];
                mem_execute <= 1;
                state <= EXE_REPLACE_READ3;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_READ3: begin
              if (mem_ready) begin
                axis_tag <= read_data1[`hed_tag];
                axis_val <= read_data1[`hed_start:`hed_end];
                b_tag <= read_data1[`tel_tag];
                b <= read_data1[`tel_start:`tel_end];
                if (read_data1[`hed_tag] == `CELL) begin
                  mem_func <= `GET_CONTENTS;
                  address1 <= read_data1[`hed_start:`hed_end];
                  mem_execute <= 1;
                  state <= EXE_REPLACE_READ_AXIS;
                end else begin
                  state <= EXE_REPLACE_WRITE;
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end

            end

            EXE_REPLACE_READ_AXIS: begin
              if (mem_ready) begin
                axis_header_reg <= read_data1;
                state <= EXE_REPLACE_WRITE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_WRITE: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= execute_address;
                mem_execute <= 1;
                write_data <= { 6'b110000,
                                `ATOM, 
                                `CELL,
                                `noun_width'hA,
                                a + 1'h1};
                state <= EXE_REPLACE_WRITE2;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_WRITE2: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a;
                mem_execute <= 1;
                if (axis_tag == `CELL) begin
                  write_data <= {2'b00,
                                  axis_header_reg[61:60],
                                  2'b00,
                                  axis_header_reg[57:0]};
                end else begin
                  write_data <= { 6'b000000,
                                  `ATOM,
                                  `ATOM,
                                  axis_val,
                                  `NIL};
                end
                state <= EXE_REPLACE_WRITE3;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_WRITE3: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a + 1'h1;
                mem_execute <= 1;
                write_data <= { 6'b000000,
                                `CELL,
                                `CELL,
                                a,
                                a+2'h2};
                state <= EXE_REPLACE_WRITE4;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_WRITE4: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a + 2'h2;
                mem_execute <= 1;
                state <= EXE_REPLACE_WRITE5;
                write_data <= { 6'b000000,
                                `CELL,
                                `CELL,
                                a+3'h3,
                                a+3'h4};
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_WRITE5: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a + 2'h3;
                mem_execute <= 1;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                b_tag,
                                execute_data[`hed_start:`hed_end],
                                b};
                state <= EXE_REPLACE_WRITE6;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_WRITE6: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a + 3'h4;
                mem_execute <= 1;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                c_tag,
                                execute_data[`hed_start:`hed_end],
                                c};
                state <= EXE_REPLACE_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_REPLACE_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end

        EXE_FUNC_HINT: begin
          case(state)
          EXE_HINT_INIT: begin
              if(mem_ready) begin
                mem_func <= `GET_CONTENTS;
                address1 <= execute_data[`tel_start:`tel_end];
                mem_execute <= 1;
                state <= EXE_HINT_READ;
              end else begin
                mem_func<=0;
                mem_execute <= 0;
              end
            end

            EXE_HINT_READ: begin
              if (mem_ready) begin
                mem_func <= `GET_CONTENTS;
                address1 <= read_data1[`tel_start:`tel_end];
                mem_execute <= 1;
                state <= EXE_HINT_READ2;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_HINT_READ2: begin
              if (mem_ready) begin
                if(read_data1[`hed_tag] == `ATOM) begin //if static hint
                  mem_func <= `SET_CONTENTS;
                  address1 <= execute_address;
                  write_data <= { 6'b100000,
                                  execute_data[`hed_tag],
                                  read_data1[`tel_tag],
                                  execute_data[`hed_start:`hed_end],
                                  read_data1[`tel_start:`tel_end]};
                  hint <= read_data1[`hed_start:`hed_end];
                  hint_tag <= read_data1[`hed_tag];
                  state <= EXE_HINT_DONE;
                  mem_execute <= 1;
                end else begin
                  mem_func <= `GET_CONTENTS;
                  address1 <= read_data1[`hed_start:`hed_end];
                  d <= read_data1[`tel_start:`tel_end];
                  d_tag <= read_data1[`tel_tag];
                  mem_execute <= 1;
                  state <= EXE_HINT_READ3;
                end
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_HINT_READ3: begin
              if (mem_ready) begin
                hint <= read_data1[`hed_start:`hed_end];
                hint_tag <= read_data1[`hed_tag];
                c <= read_data1[`tel_start:`tel_end];
                c_tag <= read_data1[`tel_tag];
                mem_func <= `GET_FREE;
                mem_execute <= 1;
                write_data <= 4;
                state <= EXE_HINT_WRITE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end

            end

            EXE_HINT_WRITE: begin
              if (mem_ready) begin
                a <= free_addr;
                mem_func <= `SET_CONTENTS;
                address1 <= execute_address;
                mem_execute <= 1;
                write_data <= { 6'b100000,
                                `CELL, 
                                `CELL,
                                `ADDR_PAD,
                                free_addr,
                                `ADDR_PAD,
                                free_addr+2'h1};
                state <= EXE_HINT_WRITE2;
              end
              else if (gc) begin
                exec_func <= func_return_exec_func;
                state <= func_return_state;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_HINT_WRITE2: begin
              if (mem_ready) begin
                address1 <= a;
                a <= a + 1'h1;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= { 6'b000000,
                                `CELL, 
                                `CELL,
                                a + 2'h2,
                                a + 2'h3};
                state <= EXE_HINT_WRITE3;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_HINT_WRITE3: begin
              if (mem_ready) begin
                address1 <= a;
                a <= a + 1'h1;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= { 6'b000000,
                                `ATOM, 
                                `ATOM,
                                `noun_width'h0,
                                `noun_width'h3};
                state <= EXE_HINT_WRITE4;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end


            EXE_HINT_WRITE4: begin
              if (mem_ready) begin
                address1 <= a;
                a <= a + 1'h1;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                c_tag,
                                execute_data[`hed_start:`hed_end],
                                c};
                state <= EXE_HINT_WRITE5;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end


            EXE_HINT_WRITE5: begin
              if (mem_ready) begin
                address1 <= a;
                a <= a + 1'h1;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= { 6'b100000,
                                execute_data[`hed_tag],
                                d_tag,
                                execute_data[`hed_start:`hed_end],
                                d};
                state <= EXE_HINT_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end


            EXE_HINT_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end
        
        EXE_FUNC_AUTOCONS: begin
          case(state)
            EXE_AUTO_INIT: begin
              if (mem_ready) begin
                mem_func <= `GET_CONTENTS;
                address1 <= execute_data[`tel_start:`tel_end];
                mem_execute <= 1;
                state<= EXE_AUTO_READ_TEL;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_AUTO_WRITE_ROOT: begin
              if (mem_ready) begin
                a <= free_addr;
                address1 <= free_addr;
                mem_func <= `SET_CONTENTS;
                mem_execute <= 1;
                write_data <= {
                        6'b100000, // mark as execute
                        execute_data[`hed_tag],
                        b_tag,
                        execute_data[`hed_start:`hed_end],
                        b};
                state <= EXE_AUTO_WRITE_TEL;
              end
              else if (gc) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
            
            EXE_AUTO_READ_TEL: begin
              if (mem_ready) begin
                b <= read_data1[`hed_start:`hed_end];
                b_tag <= read_data1[`hed_tag];
                c <= read_data1[`tel_start:`tel_end];
                c_tag <= read_data1[`tel_tag];
                // Allocate fresh exec nodes to avoid clobbering the formula cell.
                mem_func <= `GET_FREE;
                write_data <= 2;
                mem_execute <= 1;
                state <= EXE_AUTO_WRITE_ROOT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
            
            EXE_AUTO_WRITE_TEL: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= a + 1'h1;
                mem_execute <= 1;
                write_data <= {
                        6'b100000, // mark as execute
                        execute_data[`hed_tag],
                        c_tag,
                        execute_data[`hed_start:`hed_end],
                        c};
                state <= EXE_AUTO_WRITE_MEM;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_AUTO_WRITE_MEM: begin
              if (mem_ready) begin
                mem_func <= `SET_CONTENTS;
                address1 <= execute_address;
                mem_execute <= 1;
                write_data <= {
                        6'b000000, // clear execute
                        `CELL,
                        `CELL,
                        a,
                        a + 1'h1};
                state <= EXE_AUTO_DONE;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end

            EXE_AUTO_DONE: begin
              if (mem_ready) begin
                exec_func <= EXE_FUNC_INIT;
                state <= EXE_INIT_FINISHED;
                execute_return_sys_func <= `SYS_FUNC_READ;
                execute_return_state <= `SYS_READ_INIT;
              end else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end

        EXE_FUNC_ERROR: begin
          execute_return_sys_func <= `SYS_FUNC_EXECUTE;
          execute_return_state <= `SYS_EXECUTE_ERROR;
          is_finished_reg <= 1;
        end
      endcase

    end
  end

`ifdef TRACE_GC
  reg gc_prev;
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      gc_prev <= 1'b0;
    end else begin
      if (gc && !gc_prev) begin
        $display("exe gc edge exec_func %0d state %0d mem_func %0d mem_execute %0d",
                 exec_func, state, mem_func, mem_execute);
      end
      gc_prev <= gc;
    end
  end
`endif

`ifdef TRACE_ADDR19
  always @(posedge clk) begin
    if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd19) begin
      $display("exe write addr19 exec_func %0d state %0d data %h", exec_func, state, write_data);
    end
  end
`endif

`ifdef TRACE_EXEC_ADDR137
  always @(posedge clk) begin
    if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd137) begin
      $display("exe write addr137 exec_func %0d state %0d data %h", exec_func, state, write_data);
    end
  end
`endif

`ifdef TRACE_EXEC_ADDR130
  always @(posedge clk) begin
    if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd130) begin
      $display("exe write addr130 exec_func %0d state %0d data %h", exec_func, state, write_data);
    end
  end
`endif

`ifdef TRACE_EXEC_ADDR41
  always @(posedge clk) begin
    if (mem_execute && mem_func == `SET_CONTENTS && address1 == 11'd65) begin
      $display("exe write addr41 exec_func %0d state %0d a %0d free_addr %0d data %h",
               exec_func,
               state,
               a,
               free_addr,
               write_data);
    end
  end
`endif

`ifdef TRACE_EXEC_FORMULA10
  always @(posedge clk) begin
    if (mem_execute && mem_func == `SET_CONTENTS
    && write_data[`execute_bit]
    && write_data[`tel_tag] == `CELL
    && write_data[`tel_start:`tel_end] == `noun_width'h10) begin
      $display("exec formula10 write addr %0d exec_func %0d state %0d data %h",
               address1,
               exec_func,
               state,
               write_data);
    end
  end
`endif

`ifdef TRACE_SLOT_ERR
  reg [7:0] slot_err_prev;
  always @(posedge clk) begin
    if (!rst) begin
      slot_err_prev <= 0;
    end else begin
      if (error != slot_err_prev
      && (error == `ERROR_INVALID_SLOT
          || error == `ERROR_INVALID_SLOT_HED
          || error == `ERROR_INVALID_SLOT_TEL)) begin
        $display("slot error %h exec_func %0d state %0d b %h b_addr %h mem_tag %h subject %h subject_tag %0d",
                 error,
                 exec_func,
                 state,
                 b,
                 b_addr,
                 mem_tag,
                 subject,
                 subject_tag);
      end
      slot_err_prev <= error;
    end
  end
`endif
endmodule
