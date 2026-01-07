`include "memory_unit.vh"
`include "memory_mux.vh"
`include "mem_traversal.vh"
`include "execute.vh"


module equal_block #(
  parameter integer STACK_DEPTH = 2048
) (
  input clk,
  input rst,
  output reg [7:0] equal_error,
  input [2:0] equal_start,  // wire to begin execution (mux_conroller from traversal)
  input [`memory_addr_width - 1:0] equal_address,
  input [`memory_data_width - 1:0] equal_data,
  output reg [3:0] equal_return_sys_func,
  output reg [3:0] equal_return_state,
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

  // Interface with memory traversal
  reg [2:0] equal_start_ff;
  reg is_finished_reg;
  assign finished = is_finished_reg;

  reg [`memory_addr_width - 1:0] cmp_stack1 [0:STACK_DEPTH - 1];
  reg [`memory_addr_width - 1:0] cmp_stack2 [0:STACK_DEPTH - 1];
  localparam integer STACK_PTR_WIDTH = $clog2(STACK_DEPTH + 1);
  reg [STACK_PTR_WIDTH - 1:0] cmp_stack_ptr;
  wire [STACK_PTR_WIDTH - 1:0] cmp_stack_top_idx;
  assign cmp_stack_top_idx = cmp_stack_ptr - 1'b1;

  reg [`memory_addr_width - 1:0] mem_addr1;
  reg [`memory_addr_width - 1:0] mem_addr2;
  reg [`memory_data_width - 1:0] read_data1_reg;
  reg [`memory_data_width - 1:0] read_data2_reg;

  reg [`noun_width - 1:0] la_len1;
  reg [`noun_width - 1:0] la_len2;
  reg [`memory_addr_width - 1:0] la_ptr1;
  reg [`memory_addr_width - 1:0] la_ptr2;
  reg [`noun_width - 1:0] la_index;
  reg [`noun_width - 1:0] la_small_value;
  reg la_compare_small;

  reg [`noun_width-1:0] write_value;

  // State Machine Stuff
  reg [3:0] state;
  localparam INIT_READ_ROOT = 4'h0,
             INIT_WAIT      = 4'h1,
             POP_PAIR       = 4'h2,
             READ_PAIR      = 4'h3,
             READ_WAIT      = 4'h4,
             DECODE_PAIR    = 4'h5,
             LA_INIT        = 4'h6,
             LA_READ        = 4'h7,
             LA_WAIT        = 4'h8,
             RETURN_INIT    = 4'h9,
             RETURN_WAIT    = 4'hA,
             RETURN_PAUSE   = 4'hB;

  integer sp;

  always @(posedge clk) begin
    // Flip-flop to store the previous state of equal_start
    equal_start_ff <= equal_start;
  end

  always @(posedge clk or negedge rst) begin
    if (!rst || (equal_start==`MUX_EQUAL && !(equal_start_ff==`MUX_EQUAL))) begin
      write_data <= 0;
      mem_execute <= 0;
      address1 <= 0;
      address2 <= 0;
      mem_addr1 <= 0;
      mem_addr2 <= 0;
      state <= INIT_READ_ROOT;
      is_finished_reg <= 0;
      equal_error <= 0;
      equal_return_sys_func <= 0;
      equal_return_state <= 0;
      cmp_stack_ptr <= 0;
      la_len1 <= 0;
      la_len2 <= 0;
      la_ptr1 <= 0;
      la_ptr2 <= 0;
      la_index <= 0;
      la_small_value <= 0;
      la_compare_small <= 0;
    end
    else if (equal_start == `MUX_EQUAL) begin
      case (state)
        INIT_READ_ROOT: begin
          mem_func <= `GET_CONTENTS;
          mem_execute <= 1'b1;
          address1 <= equal_data[`tel_start:`tel_end];
          address2 <= 0;
          state <= INIT_WAIT;
        end

        INIT_WAIT: begin
          if (mem_ready) begin
            if (read_data1[`hed_tag] != `CELL || read_data1[`tel_tag] != `CELL) begin
              write_value <= `NO;
              state <= RETURN_INIT;
            end else begin
              cmp_stack1[0] <= read_data1[`hed_start:`hed_end];
              cmp_stack2[0] <= read_data1[`tel_start:`tel_end];
              cmp_stack_ptr <= 1;
              state <= POP_PAIR;
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        POP_PAIR: begin
          if (cmp_stack_ptr == 0) begin
            write_value <= `YES;
            state <= RETURN_INIT;
          end else begin
            mem_addr1 <= cmp_stack1[cmp_stack_top_idx];
            mem_addr2 <= cmp_stack2[cmp_stack_top_idx];
            cmp_stack_ptr <= cmp_stack_ptr - 1'b1;
            state <= READ_PAIR;
          end
        end

        READ_PAIR: begin
          address1 <= mem_addr1;
          address2 <= mem_addr2;
          mem_func <= `GET_CONTENTS;
          mem_execute <= 1'b1;
          state <= READ_WAIT;
        end

        READ_WAIT: begin
          if (mem_ready) begin
            read_data1_reg <= read_data1;
            read_data2_reg <= read_data2;
            state <= DECODE_PAIR;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        DECODE_PAIR: begin
          if (read_data1_reg[`large_atom_bit] || read_data2_reg[`large_atom_bit]) begin
            if (read_data1_reg[`large_atom_bit] && read_data2_reg[`large_atom_bit]) begin
              if (read_data1_reg[`hed_tag] != `CELL || read_data1_reg[`tel_tag] != `ATOM
              || read_data2_reg[`hed_tag] != `CELL || read_data2_reg[`tel_tag] != `ATOM) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else begin
                la_len1 <= read_data1_reg[`tel_start:`tel_end];
                la_len2 <= read_data2_reg[`tel_start:`tel_end];
                la_ptr1 <= read_data1_reg[`hed_start:`hed_end];
                la_ptr2 <= read_data2_reg[`hed_start:`hed_end];
                la_index <= 0;
                la_compare_small <= 1'b0;
                state <= LA_INIT;
              end
            end else if (read_data1_reg[`large_atom_bit]) begin
              if (read_data1_reg[`hed_tag] != `CELL || read_data1_reg[`tel_tag] != `ATOM) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else if (read_data2_reg[`hed_tag] == `ATOM && read_data2_reg[`tel_tag] == `ATOM
              && read_data2_reg[`tel_start:`tel_end] == `NIL) begin
                la_len1 <= read_data1_reg[`tel_start:`tel_end];
                la_ptr1 <= read_data1_reg[`hed_start:`hed_end];
                la_ptr2 <= 0;
                la_index <= 0;
                la_small_value <= read_data2_reg[`hed_start:`hed_end];
                la_compare_small <= 1'b1;
                state <= LA_INIT;
              end else begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end
            end else begin
              if (read_data2_reg[`hed_tag] != `CELL || read_data2_reg[`tel_tag] != `ATOM) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else if (read_data1_reg[`hed_tag] == `ATOM && read_data1_reg[`tel_tag] == `ATOM
              && read_data1_reg[`tel_start:`tel_end] == `NIL) begin
                la_len1 <= read_data2_reg[`tel_start:`tel_end];
                la_ptr1 <= read_data2_reg[`hed_start:`hed_end];
                la_ptr2 <= 0;
                la_index <= 0;
                la_small_value <= read_data1_reg[`hed_start:`hed_end];
                la_compare_small <= 1'b1;
                state <= LA_INIT;
              end else begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end
            end
          end else begin
            if (read_data1_reg[`hed_tag] != read_data2_reg[`hed_tag]
            || read_data1_reg[`tel_tag] != read_data2_reg[`tel_tag]) begin
              write_value <= `NO;
              state <= RETURN_INIT;
            end else if (read_data1_reg[`hed_tag] == `ATOM
            && read_data1_reg[`tel_tag] == `ATOM
            && read_data1_reg[`tel_start:`tel_end] == `NIL) begin
              if (read_data1_reg[`hed_start:`hed_end]
              != read_data2_reg[`hed_start:`hed_end]) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else begin
                state <= POP_PAIR;
              end
            end else begin
              if (read_data1_reg[`hed_tag] == `ATOM
              && read_data1_reg[`hed_start:`hed_end]
              != read_data2_reg[`hed_start:`hed_end]) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else if (read_data1_reg[`tel_tag] == `ATOM
              && read_data1_reg[`tel_start:`tel_end]
              != read_data2_reg[`tel_start:`tel_end]) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else begin
                sp = cmp_stack_ptr;
                if (read_data1_reg[`tel_tag] == `CELL) begin
                  if (sp == STACK_DEPTH) begin
                    write_value <= `NO;
                    state <= RETURN_INIT;
                  end else begin
                    cmp_stack1[sp] <= read_data1_reg[`tel_start:`tel_end];
                    cmp_stack2[sp] <= read_data2_reg[`tel_start:`tel_end];
                    sp = sp + 1;
                  end
                end

                if (state == DECODE_PAIR) begin
                  if (read_data1_reg[`hed_tag] == `CELL) begin
                    if (sp == STACK_DEPTH) begin
                      write_value <= `NO;
                      state <= RETURN_INIT;
                    end else begin
                      cmp_stack1[sp] <= read_data1_reg[`hed_start:`hed_end];
                      cmp_stack2[sp] <= read_data2_reg[`hed_start:`hed_end];
                      sp = sp + 1;
                    end
                  end
                end

                if (state == DECODE_PAIR) begin
                  cmp_stack_ptr <= sp;
                  state <= POP_PAIR;
                end
              end
            end
          end
        end

        LA_INIT: begin
          if (la_compare_small) begin
            if (la_len1 != `noun_width'h1) begin
              write_value <= `NO;
              state <= RETURN_INIT;
            end else begin
              state <= LA_READ;
            end
          end else begin
            if (la_len1 != la_len2 || la_len1 == 0) begin
              write_value <= `NO;
              state <= RETURN_INIT;
            end else begin
              state <= LA_READ;
            end
          end
        end

        LA_READ: begin
          address1 <= la_ptr1;
          address2 <= la_ptr2;
          mem_func <= `GET_CONTENTS;
          mem_execute <= 1'b1;
          state <= LA_WAIT;
        end

        LA_WAIT: begin
          if (mem_ready) begin
            if (la_compare_small) begin
              if (read_data1[`hed_tag] != `ATOM
              || read_data1[`hed_start:`hed_end] != la_small_value
              || read_data1[`tel_tag] != `ATOM
              || read_data1[`tel_start:`tel_end] != `NIL) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else begin
                state <= POP_PAIR;
              end
            end else begin
              if (read_data1[`hed_tag] != `ATOM
              || read_data2[`hed_tag] != `ATOM
              || read_data1[`hed_start:`hed_end]
              != read_data2[`hed_start:`hed_end]) begin
                write_value <= `NO;
                state <= RETURN_INIT;
              end else if (la_index == la_len1 - 1) begin
                if (read_data1[`tel_tag] != `ATOM
                || read_data1[`tel_start:`tel_end] != `NIL
                || read_data2[`tel_tag] != `ATOM
                || read_data2[`tel_start:`tel_end] != `NIL) begin
                  write_value <= `NO;
                  state <= RETURN_INIT;
                end else begin
                  state <= POP_PAIR;
                end
              end else begin
                if (read_data1[`tel_tag] != `CELL
                || read_data2[`tel_tag] != `CELL) begin
                  write_value <= `NO;
                  state <= RETURN_INIT;
                end else begin
                  la_ptr1 <= read_data1[`tel_start:`tel_end];
                  la_ptr2 <= read_data2[`tel_start:`tel_end];
                  la_index <= la_index + 1'b1;
                  state <= LA_READ;
                end
              end
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        RETURN_INIT: begin
          write_data <= {
            6'b000000,
            `ATOM,
            `ATOM,
            write_value,
            `NIL};
          address1 <= equal_address;
          mem_func <= `SET_CONTENTS;
          mem_execute <= 1'b1;
          state <= RETURN_WAIT;
        end

        RETURN_WAIT: begin
          if (mem_ready) begin
            equal_return_sys_func <= `SYS_FUNC_READ;
            equal_return_state <= `SYS_READ_INIT;
            is_finished_reg <= 1'b1;
            state <= RETURN_PAUSE;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        RETURN_PAUSE: begin
          if (mem_ready) begin
            is_finished_reg <= 1'b0;
          end
        end

        default: begin
          state <= INIT_READ_ROOT;
        end
      endcase
    end
  end
endmodule
