`include "memory_unit.vh"
`include "memory_mux.vh"
`include "mem_traversal.vh"
`include "execute.vh"


module incr_block (
  input clk,
  input rst,
  output reg [7:0] incr_error,
  input [2:0] incr_start,  // wire to begin execution (mux_conroller from traversal)
  input [`memory_addr_width - 1:0] incr_address,
  input [`memory_data_width - 1:0] incr_data,
  output reg [3:0] incr_return_sys_func,
  output reg [3:0] incr_return_state,
  input mem_ready,
  input gc,
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

  reg [7:0] incr_debug_sig;
  // Interface with memory traversal
  reg [2:0] incr_start_ff;
  reg is_finished_reg;
  assign finished = is_finished_reg;
  reg [`noun_width-1:0] write_value;
  reg [`noun_width-1:0] la_len;
  reg [`noun_width-1:0] la_new_len;
  reg [`noun_width-1:0] la_index;
  reg [`memory_addr_width-1:0] la_head_ptr;
  reg [`memory_addr_width-1:0] la_old_ptr;
  reg [`memory_addr_width-1:0] la_new_ptr;
  reg [`memory_addr_width-1:0] la_new_base;
  reg la_carry;
  reg la_need_extra;
  reg la_small_overflow;
  reg [`noun_width:0] la_sum;
  wire [`noun_width:0] la_add;
  localparam [`noun_width-1:0] ATOM_MAX = {`noun_width{1'b1}};
  assign la_add = {1'b0, read_data1[`hed_start:`hed_end]} + la_carry;

  // State Machine Stuff
  reg [4:0] state;
  parameter INIT                = 5'h0,
            WRITE               = 5'h1,
            WRITE_WAIT          = 5'h2,
            READ_TEL            = 5'h3,
            PAUSE               = 5'h4,
            INCR_ERROR          = 5'h5,
            LA_PASS1_READ       = 5'h6,
            LA_PASS1_EVAL       = 5'h7,
            LA_ALLOC            = 5'h8,
            LA_ALLOC_WAIT       = 5'h9,
            LA_PASS2_READ       = 5'hA,
            LA_PASS2_WRITE      = 5'hB,
            LA_PASS2_WRITE_WAIT = 5'hC,
            LA_WRITE_EXTRA      = 5'hD,
            LA_WRITE_EXTRA_WAIT = 5'hE,
            LA_WRITE_HDR        = 5'hF,
            LA_SMALL_WRITE0     = 5'h10,
            LA_SMALL_WRITE0_WAIT= 5'h11;

  always @(posedge clk) begin
    // Flip-flop to store the previous state of incr_start
    incr_start_ff <= incr_start;
  end

  always @(posedge clk or negedge rst) begin
    if (!rst || (incr_start==`MUX_INCR && !(incr_start_ff==`MUX_INCR))) begin
      write_data <= 0;
      mem_execute<=0;
      address1 <=0;
      state <= INIT;
      is_finished_reg <=0;
      incr_debug_sig <=0;
      incr_error <= 0;
      incr_return_sys_func <= 0;
      incr_return_state <= 0;
      la_len <= 0;
      la_new_len <= 0;
      la_index <= 0;
      la_head_ptr <= 0;
      la_old_ptr <= 0;
      la_new_ptr <= 0;
      la_new_base <= 0;
      la_carry <= 0;
      la_need_extra <= 0;
      la_small_overflow <= 0;
      la_sum <= 0;
    end 
    else if (incr_start == `MUX_INCR) begin
      case (state)
        INIT: begin
          if(incr_data[`tel_tag] == `ATOM) begin
            if (incr_data[`tel_start:`tel_end] == ATOM_MAX) begin
              la_new_len <= `noun_width'h2;
              la_small_overflow <= 1'b1;
              state <= LA_ALLOC;
            end else begin
              write_value <= incr_data[`tel_start:`tel_end]+`noun_width'h1;
              state <= WRITE;
            end
          end else begin
            address1 <= incr_data[`tel_start:`tel_end];
            mem_func <= `GET_CONTENTS;
            mem_execute <= 1;
            state <= READ_TEL;
          end
        end

        READ_TEL: begin
          if (mem_ready) begin
            if (read_data1[`large_atom_bit]) begin
              if (read_data1[`hed_tag] != `CELL || read_data1[`tel_tag] != `ATOM) begin
                incr_error <= `ERROR_INVALID_B_INCR;
                state <= INCR_ERROR;
              end else begin
                la_len <= read_data1[`tel_start:`tel_end];
                la_head_ptr <= read_data1[`hed_start:`hed_end];
                la_old_ptr <= read_data1[`hed_start:`hed_end];
                la_index <= 0;
                la_carry <= 1'b1;
                la_need_extra <= 1'b0;
                la_small_overflow <= 1'b0;
                state <= LA_PASS1_READ;
              end
            end else if(read_data1[`tel_start:`tel_end] ==`NIL && read_data1[`tel_tag] == `ATOM && read_data1[`hed_tag] == `ATOM) begin
              if (read_data1[`hed_start:`hed_end] == ATOM_MAX) begin
                la_new_len <= `noun_width'h2;
                la_small_overflow <= 1'b1;
                state <= LA_ALLOC;
              end else begin
                write_value <= read_data1[`hed_start:`hed_end]+`noun_width'h1;
                state <= WRITE;
              end
            end else begin
              incr_error <= `ERROR_INVALID_B_INCR;
              state <= INCR_ERROR;
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        WRITE: begin
          write_data <= {
            6'b000000,
            `ATOM,
            `ATOM,
            write_value,
            `NIL};
          address1 <= incr_address;
          mem_func <= `SET_CONTENTS;
          mem_execute <= 1;
          state <= WRITE_WAIT;
        end

        LA_PASS1_READ: begin
          if (la_len == 0) begin
            incr_error <= `ERROR_INVALID_B_INCR;
            state <= INCR_ERROR;
          end else begin
            address1 <= la_old_ptr;
            mem_func <= `GET_CONTENTS;
            mem_execute <= 1;
            state <= LA_PASS1_EVAL;
          end
        end

        LA_PASS1_EVAL: begin
          if (mem_ready) begin
            if (read_data1[`hed_tag] != `ATOM) begin
              incr_error <= `ERROR_INVALID_B_INCR;
              state <= INCR_ERROR;
            end else begin
              la_sum <= la_add;
              la_carry <= la_add[`noun_width];
              if (la_index == la_len - 1) begin
                la_need_extra <= la_add[`noun_width];
                la_new_len <= la_len + la_add[`noun_width];
                la_small_overflow <= 1'b0;
                state <= LA_ALLOC;
              end else begin
                if (read_data1[`tel_tag] != `CELL) begin
                  incr_error <= `ERROR_INVALID_B_INCR;
                  state <= INCR_ERROR;
                end else begin
                  la_old_ptr <= read_data1[`tel_start:`tel_end];
                  la_index <= la_index + 1'b1;
                  state <= LA_PASS1_READ;
                end
              end
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_ALLOC: begin
          if (mem_ready) begin
            mem_func <= `GET_FREE;
            write_data <= la_new_len;
            mem_execute <= 1;
            state <= LA_ALLOC_WAIT;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_ALLOC_WAIT: begin
          if (mem_ready) begin
            la_new_base <= free_addr;
            la_new_ptr <= free_addr;
            la_old_ptr <= la_head_ptr;
            la_index <= 0;
            la_carry <= 1'b1;
            if (la_small_overflow) begin
              state <= LA_SMALL_WRITE0;
            end else begin
              state <= LA_PASS2_READ;
            end
          end else if (gc) begin
            mem_execute <= 0;
            mem_func <= 0;
            incr_return_sys_func <= `SYS_FUNC_READ;
            incr_return_state <= `SYS_READ_INIT;
            is_finished_reg <= 1'b1;
            state <= PAUSE;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_PASS2_READ: begin
          if (la_index < la_len) begin
            address1 <= la_old_ptr;
            mem_func <= `GET_CONTENTS;
            mem_execute <= 1;
            state <= LA_PASS2_WRITE;
          end else if (la_need_extra) begin
            la_carry <= 1'b1;
            state <= LA_WRITE_EXTRA;
          end else begin
            state <= LA_WRITE_HDR;
          end
        end

        LA_PASS2_WRITE: begin
          if (mem_ready) begin
            if (read_data1[`hed_tag] != `ATOM) begin
              incr_error <= `ERROR_INVALID_B_INCR;
              state <= INCR_ERROR;
            end else begin
              la_sum <= la_add;
              write_data <= {
                6'b000000,
                `ATOM,
                (la_index == la_new_len - 1) ? `ATOM : `CELL,
                la_add[`noun_width-1:0],
                (la_index == la_new_len - 1) ? `NIL : {`ADDR_PAD, la_new_ptr + 1'b1}
              };
              address1 <= la_new_ptr;
              mem_func <= `SET_CONTENTS;
              mem_execute <= 1;
              la_carry <= la_add[`noun_width];
              la_new_ptr <= la_new_ptr + 1'b1;
              if (la_index < la_len - 1) begin
                if (read_data1[`tel_tag] != `CELL) begin
                  incr_error <= `ERROR_INVALID_B_INCR;
                  state <= INCR_ERROR;
                end else begin
                  la_old_ptr <= read_data1[`tel_start:`tel_end];
                end
              end
              la_index <= la_index + 1'b1;
              state <= LA_PASS2_WRITE_WAIT;
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_PASS2_WRITE_WAIT: begin
          if (mem_ready) begin
            if (la_index < la_len) begin
              state <= LA_PASS2_READ;
            end else if (la_need_extra) begin
              state <= LA_WRITE_EXTRA;
            end else begin
              state <= LA_WRITE_HDR;
            end
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_SMALL_WRITE0: begin
          if (mem_ready) begin
            write_data <= {
              6'b000000,
              `ATOM,
              `CELL,
              `noun_width'h0,
              {`ADDR_PAD, la_new_ptr + 1'b1}
            };
            address1 <= la_new_ptr;
            mem_func <= `SET_CONTENTS;
            mem_execute <= 1;
            state <= LA_SMALL_WRITE0_WAIT;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_SMALL_WRITE0_WAIT: begin
          if (mem_ready) begin
            la_new_ptr <= la_new_ptr + 1'b1;
            la_carry <= 1'b1;
            la_need_extra <= 1'b0;
            state <= LA_WRITE_EXTRA;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_WRITE_EXTRA: begin
          if (mem_ready) begin
            write_data <= {
              6'b000000,
              `ATOM,
              `ATOM,
              {{(`noun_width-1){1'b0}}, la_carry},
              `NIL
            };
            address1 <= la_new_ptr;
            mem_func <= `SET_CONTENTS;
            mem_execute <= 1;
            state <= LA_WRITE_EXTRA_WAIT;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_WRITE_EXTRA_WAIT: begin
          if (mem_ready) begin
            state <= LA_WRITE_HDR;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        LA_WRITE_HDR: begin
          if (mem_ready) begin
            write_data <= {
              6'b000100,
              `CELL,
              `ATOM,
              `ADDR_PAD,
              la_new_base,
              la_new_len
            };
            address1 <= incr_address;
            mem_func <= `SET_CONTENTS;
            mem_execute <= 1;
            state <= WRITE_WAIT;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        WRITE_WAIT: begin
          if (mem_ready) begin
            incr_return_sys_func <= `SYS_FUNC_READ;
            incr_return_state <= `SYS_READ_INIT;
            is_finished_reg <= 1;
            state <= PAUSE;
          end else begin
            mem_func <= 0;
            mem_execute <= 0;
          end
        end

        PAUSE: begin
          is_finished_reg <=0;
          if (incr_start == `MUX_INCR) state<= INIT;
        end

        INCR_ERROR: begin
          mem_execute <= 0;
          incr_return_sys_func <= `SYS_FUNC_EXECUTE;
          incr_return_state <= `SYS_EXECUTE_ERROR;
          is_finished_reg <= 1;
        end
      endcase
    end
  end
endmodule
 
