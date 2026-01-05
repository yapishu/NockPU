`include "memory_unit.vh"
`include "mem_traversal.vh"
`include "execute.vh"


module mem_traversal(
  input power, clk, rst,
  input [`memory_addr_width - 1:0] start_addr,
  input execute,
  output wire finished,
  input mem_ready,
  input [`memory_data_width - 1:0] read_data1,
  input [`memory_data_width - 1:0] read_data2,
  input [`memory_addr_width - 1:0] free_addr,
  input gc,
  output reg gc_ready,
  output reg mem_execute,
  output reg [`memory_addr_width - 1:0] address1,
  output reg [`memory_addr_width - 1:0] address2,
  output reg [1:0] mem_func,
  output reg [`memory_data_width - 1:0] write_data,
  input [7:0] error,
  output reg [`memory_addr_width - 1:0] module_address,
  output reg [`memory_data_width - 1:0] module_data,
  output reg [2:0] mux_controller,
  input module_finished,
  input [3:0] execute_return_sys_func,
  input [3:0] execute_return_state
);
  // finish signal
  reg is_finished_reg;
  assign finished = is_finished_reg;

  // Internal registers needed
  reg [3:0] sys_func;
  reg [3:0] state;
  reg [`tag_width - 1:0] mem_tag;
  reg [`noun_width - 1:0] hed, tel;
  reg [`memory_addr_width - 1:0] mem_addr;
  reg [`memory_data_width - 1:0] mem_data;
  reg [`memory_addr_width - 1:0] exec_addr_reg;
  reg [7:0] debug_sig;
  reg mem_ready_prev;
  wire mem_ready_edge;
  wire is_running;
  assign is_running = !finished && execute;
  assign mem_ready_edge = mem_ready && !mem_ready_prev;
  localparam integer STACK_DEPTH = 2048;
  reg [`memory_addr_width - 1:0] stack_addr [0:STACK_DEPTH - 1];
  reg [`memory_addr_width - 1:0] stack_return [0:STACK_DEPTH - 1];
  reg [`memory_addr_width:0] stack_ptr;
  reg stack_exec_pending;
  wire [`memory_addr_width:0] stack_top_idx;
  assign stack_top_idx = stack_ptr - 1'b1;

  // General Purpose Regsiters
  reg [`memory_addr_width - 1:0] address_gp;
  reg [`memory_data_width - 1:0] mem_data_gp;
  reg [`noun_width - 1:0] noun_gp;
  reg [`noun_tag_width - 1:0] noun_tag_gp;

  // Traversal Registers needed
  reg [`noun_width - 1:0] trav_P;
  reg [`noun_width - 1:0] trav_B;

  // Write Registers needed
  reg [3:0] write_return_sys_func;
  reg [3:0] write_return_state;

  //System Level Functions
  parameter SYS_FUNC_READ     = 4'h0,
            SYS_FUNC_WRITE    = 4'h1,
            SYS_FUNC_TRAVERSE = 4'h2,
            SYS_FUNC_EXECUTE  = 4'h3,
            SYS_FUNC_OPER     = 4'h4;

  // Read States
  parameter SYS_READ_INIT   = 4'h0,
            SYS_READ_WAIT   = 4'h1,
            SYS_READ_DECODE = 4'h2,
            SYS_READ_GC_WAIT= 4'h3;

  // Write States
  parameter SYS_WRITE_INIT = 4'h0,
            SYS_WRITE_WAIT = 4'h1;

  // Traverse States
  parameter SYS_TRAVERSE_INIT  = 4'h0,
            SYS_TRAVERSE_PUSH  = 4'h1,
            SYS_TRAVERSE_POP   = 4'h2,
            SYS_TRAVERSE_TEL   = 4'h3;

  // Execute States
  parameter SYS_EXECUTE_INIT       = 4'h0,
            SYS_EXECUTE_WAIT       = 4'h1,
            SYS_EXECUTE_DECODE     = 4'h2,
            SYS_EXECUTE_READ_ADDR  = 4'h3,
            SYS_EXECUTE_STACK      = 4'h4,
            SYS_EXECUTE_STACK_WAIT = 4'h5,
            SYS_EXECUTE_ERROR      = 4'hF;

  // Operation States
  parameter SYS_OPER_INIT          = 4'h0,
            SYS_OPER_READ_TEL      = 4'h1,
            SYS_OPER_READ_TELTEL   = 4'h2;

  always@(posedge clk or negedge rst) begin
    if(!rst) begin
      sys_func <= SYS_FUNC_READ;
      state <= SYS_READ_INIT;
      mem_addr <= start_addr;
      trav_B <= `NIL;
      trav_P <= start_addr;
      mem_execute <= 0;
      gc_ready <= 0;
      is_finished_reg <= 0;
      debug_sig <= 0;
      mux_controller <= `MUX_TRAVERSAL;
      mem_ready_prev <= 0;
      stack_ptr <= 0;
      stack_exec_pending <= 0;
    end
    else if (execute) begin
      mem_ready_prev <= mem_ready;
      case (sys_func)
        SYS_FUNC_EXECUTE: begin
          case(state)
            SYS_EXECUTE_INIT: begin
              is_finished_reg <= 0;
              address1 <= mem_addr;
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1;
              debug_sig <= 3;
              state <= SYS_EXECUTE_READ_ADDR;
            end
           SYS_EXECUTE_READ_ADDR: begin
             if(mem_ready_edge) begin
               mem_data <= read_data1;
               mem_tag <= read_data1[`tag_start:`tag_end];
               hed <= read_data1[`hed_start:`hed_end];
               tel <= read_data1[`tel_start:`tel_end];
               exec_addr_reg <= mem_addr;
               if(trav_B != `NIL) mem_addr <= trav_B;
               debug_sig <= 10;
               if(read_data1[`stack_bit] == 1'b1) begin
                 state <= SYS_EXECUTE_STACK;
               end else begin
                 module_address <= mem_addr;
                 module_data <= read_data1;
                 mux_controller <= `MUX_EXECUTE;
                 state <= SYS_EXECUTE_WAIT;
               end
             end else begin
               mem_func <= 0;
               mem_execute <= 0;
             end
           end

            SYS_EXECUTE_WAIT: begin
              if(module_finished) begin
               mem_addr <= module_address;
               sys_func = execute_return_sys_func;
               state = execute_return_state;
               mux_controller <= `MUX_TRAVERSAL;
              end
            end

           SYS_EXECUTE_STACK_WAIT: begin
             if(module_finished) begin
               if (stack_exec_pending) begin
                 stack_ptr <= stack_ptr - 1'b1;
                 trav_B <= stack_return[stack_top_idx];
                 mem_addr <= stack_return[stack_top_idx];
                 stack_exec_pending <= 0;
                 sys_func <= SYS_FUNC_READ;
                 state <= SYS_READ_INIT;
               end else begin
                 mem_addr <= module_address;
                 sys_func = execute_return_sys_func;
                 state = execute_return_state;
               end
               mux_controller <= `MUX_TRAVERSAL;
             end
           end

           SYS_EXECUTE_STACK: begin
             is_finished_reg <= 0;
             case(mem_data[`hed_start:`hed_end]) 
               `cell: begin
                 module_address <= exec_addr_reg;
                 module_data <= mem_data;
                 mux_controller <= `MUX_CELL;
                 state <= SYS_EXECUTE_STACK_WAIT;
               end
               `increment: begin
                 module_address <= exec_addr_reg;
                 module_data <= mem_data;
                 mux_controller <= `MUX_INCR;
                 state <= SYS_EXECUTE_STACK_WAIT;
               end
               `equality: begin
                 module_address <= exec_addr_reg;
                 module_data <= mem_data;
                 mux_controller <= `MUX_EQUAL;
                 state <= SYS_EXECUTE_STACK_WAIT;
               end
               `replace: begin
                 module_address <= exec_addr_reg;
                 module_data <= mem_data;
                 mux_controller <= `MUX_EDIT;
                 state <= SYS_EXECUTE_STACK_WAIT;
               end
               default: begin
                 state <= SYS_EXECUTE_ERROR;
               end
             endcase
           end

           SYS_EXECUTE_ERROR: begin
             state <= SYS_EXECUTE_ERROR;
             is_finished_reg <= 1;
           end
          endcase
        end

        SYS_FUNC_READ: begin
          case(state)
            SYS_READ_INIT: begin
              debug_sig <= 1;
              if (stack_ptr != 0 && mem_addr == stack_addr[stack_top_idx]) begin
                is_finished_reg <= 0;
                stack_exec_pending <= 1;
                sys_func <= SYS_FUNC_EXECUTE;
                state <= SYS_EXECUTE_INIT;
              end
              // mem_addr is only max when you reach the end and use 
              // trav_b's inital value
              else if(mem_addr == 2047) begin 
                debug_sig <= 2;
                if (stack_ptr != 0) begin
                  is_finished_reg <= 0;
                  stack_exec_pending <= 1;
                  mem_addr <= stack_addr[stack_top_idx];
                  sys_func <= SYS_FUNC_EXECUTE;
                  state <= SYS_EXECUTE_INIT;
                end else if(gc) begin 
                  state <= SYS_READ_GC_WAIT;
                  gc_ready <= 1;
                end else begin
                  is_finished_reg <= 1;
                end
              end
              else begin
                is_finished_reg <= 0;
                address1 <= mem_addr;
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state <= SYS_READ_WAIT;
              end
            end

            SYS_READ_GC_WAIT: begin
              debug_sig <= 6;
              if(!gc && gc_ready) begin
                debug_sig <= 10;
                mem_addr <= read_data1;
                trav_P <= read_data1;
                gc_ready <= 0;
                is_finished_reg <= 0;
                address1 <= read_data1;
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1;
                state <= SYS_READ_WAIT;
                //state <= SYS_READ_INIT;
              end 
            end

            SYS_READ_WAIT: begin
              gc_ready <= 0;
              if(mem_ready_edge) begin
                debug_sig <= 6;
                mem_data <= read_data1;
                mem_tag <= read_data1[`tag_start:`tag_end];
                hed <= read_data1[`hed_start:`hed_end];
                tel <= read_data1[`tel_start:`tel_end];
                sys_func <= SYS_FUNC_TRAVERSE;
                state <= SYS_TRAVERSE_INIT;
              end
              else begin
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end

        SYS_FUNC_WRITE: begin
          case(state)
            SYS_WRITE_INIT: begin
              address1 <= mem_addr;
              write_data <= {mem_tag, hed, tel};
              mem_func <= `SET_CONTENTS;
              mem_execute <= 1;
              state <= SYS_WRITE_WAIT;
            end

            SYS_WRITE_WAIT: begin
              if(mem_ready_edge) begin
                  sys_func <= write_return_sys_func;
                  state <= write_return_state;
              end
              else begin
                address1 <= 0;
                write_data <= 0;
                mem_func <= 0;
                mem_execute <= 0;
              end
            end
          endcase
        end

        SYS_FUNC_TRAVERSE: begin
          case(state)
            SYS_TRAVERSE_INIT: begin
                if (mem_data[`stack_bit] == 1'b1) begin
                  if (stack_ptr == STACK_DEPTH) begin
                    state <= SYS_EXECUTE_ERROR;
                  end else begin
                    stack_addr[stack_ptr] <= mem_addr;
                    stack_return[stack_ptr] <= trav_B;
                    stack_ptr <= stack_ptr + 1'b1;
                    trav_B <= mem_addr;
                    mem_addr <= tel;
                    sys_func <= SYS_FUNC_READ;
                    state <= SYS_READ_INIT;
                  end
                end else if (mem_data[`large_atom_bit]) begin
                  mem_addr <= trav_B;
                  sys_func <= SYS_FUNC_READ;
                  state <= SYS_READ_INIT;
                end else begin
                case(mem_tag[1:0])
                  `CELL_CELL: begin
                     // if the hed cell hasn't been visited we push into it
                     if(mem_tag[3:2] == 2'b00) begin 
                       // Verified
                       // Set the command after write to traverse the hed
                       write_return_sys_func <= SYS_FUNC_TRAVERSE;
                       write_return_state <= SYS_TRAVERSE_PUSH;
                       //set tag to visited hed
                       mem_tag[3] <= 1;
                       //Store pointer to previous value in B
                       trav_P <= hed;
                       hed <= trav_B;
                       trav_B <= mem_addr;
                       //Write Data
                       sys_func <= SYS_FUNC_WRITE;
                       state <= SYS_WRITE_INIT;
                     end
                     else if(mem_tag[3:2] == 2'b10) begin // if hed was visited and tel wasnt
                       // Verified
                       // Set the command after write to traverse the tel
                       write_return_sys_func <= SYS_FUNC_TRAVERSE;
                       write_return_state <= SYS_TRAVERSE_PUSH;
                       //pop the hed
                       trav_B <= hed;
                       trav_P <= trav_B;
                       debug_sig <= 11;
                       hed <= trav_P;
                       //Wait for a clock cycle to push the tel
                       state <= SYS_TRAVERSE_TEL;
                     end
                     else if(mem_tag[3:2] == 2'b11) begin // if both were visited
                       // Set the command after write to pop
                       if(mem_tag[7] == 1 && gc == 0) begin // If we still need to execute
                         debug_sig <= 4;
                         write_return_sys_func <= SYS_FUNC_EXECUTE;
                         write_return_state <= SYS_EXECUTE_INIT;
                       end else begin
                         write_return_sys_func <= SYS_FUNC_TRAVERSE;
                         write_return_state <= SYS_TRAVERSE_POP;
                       end
                       mem_tag[3:2] <= 2'b00;
                       trav_B <= tel;
                       trav_P <= trav_B;
                       tel <= trav_P;
                       //Write Data
                       sys_func <= SYS_FUNC_WRITE;
                       state <= SYS_WRITE_INIT;
                    end
                  end

                  `ATOM_ATOM: begin
                    // Pop
                    mem_addr <= trav_B;
                    sys_func <= SYS_FUNC_READ;
                    state <= SYS_READ_INIT;
                  end
                  
                  `ATOM_CELL: begin
                    if(mem_tag[2] == 1'b0) begin // if both were visited
                      // Set the command after write to traverse the tel
                      write_return_sys_func <= SYS_FUNC_TRAVERSE;
                      write_return_state <= SYS_TRAVERSE_PUSH;
                      //set tag to visited tel
                      mem_tag[2] <= 1;
                      //Store pointer to previous value in B
                      trav_P <= tel;
                      tel <= trav_B;
                      trav_B <= mem_addr;
                      //Write Data
                      sys_func <= SYS_FUNC_WRITE;
                      state <= SYS_WRITE_INIT;
                    end
                    else begin
                      // Set the command after write to pop
                      if(mem_tag[7] == 1'b1 && gc == 0) begin // If we still need to execute
                        write_return_sys_func <= SYS_FUNC_EXECUTE;
                        write_return_state <= SYS_EXECUTE_INIT;
                      end else begin
                        write_return_sys_func <= SYS_FUNC_TRAVERSE;
                        write_return_state <= SYS_TRAVERSE_POP;
                      end
                      mem_tag[3:2] <= 2'b00;
                      trav_B <= tel;
                      trav_P <= trav_B;
                      tel <= trav_P;
                      //Write Data
                      sys_func <= SYS_FUNC_WRITE;
                      state <= SYS_WRITE_INIT;
                    end
                  end
                  `CELL_ATOM: begin
                    // if the hed cell hasn't been visited we push into it
                    if(mem_tag[3] == 0) begin 
                      // Set the command after write to traverse the hed
                      write_return_sys_func <= SYS_FUNC_TRAVERSE;
                      write_return_state <= SYS_TRAVERSE_PUSH;
                      //set tag to visited hed
                      mem_tag[3] <= 1;
                      //Store pointer to previous value in B
                      trav_P <= hed;
                      hed <= trav_B;
                      trav_B <= mem_addr;
                      //Write Data
                      sys_func <= SYS_FUNC_WRITE;
                      state <= SYS_WRITE_INIT;
                    end
                    else begin
                      // Set the command after write to pop
                      if(mem_tag[7] == 1 && gc == 0) begin // If we still need to execute
                        write_return_sys_func <= SYS_FUNC_EXECUTE;
                        write_return_state <= SYS_EXECUTE_INIT;
                      end else begin
                        write_return_sys_func <= SYS_FUNC_TRAVERSE;
                        write_return_state <= SYS_TRAVERSE_POP;
                      end
                      mem_tag[3:2] <= 2'b00;
                      trav_B <= hed;
                      trav_P <= trav_B;
                      hed <= trav_P;
                      //Write Data
                      sys_func <= SYS_FUNC_WRITE;
                      state <= SYS_WRITE_INIT;
                    end
                  end
                endcase
                end
            end
            SYS_TRAVERSE_PUSH: begin
              mem_addr <= trav_P;
              sys_func <= SYS_FUNC_READ;
              state <= SYS_READ_INIT;
            end

            SYS_TRAVERSE_POP: begin
              mem_addr <= trav_B;
              sys_func <= SYS_FUNC_READ;
              state <= SYS_READ_INIT;
            end

            SYS_TRAVERSE_TEL: begin
              //set tag to visited tel
              mem_tag[2] <= 1;
              //Store pointer to previous value in B
              trav_P <= tel;
              tel <= trav_B;
              trav_B <= mem_addr;
              //Write Data
              sys_func <= SYS_FUNC_WRITE;
              state <= SYS_WRITE_INIT;
            end
          endcase
        end

      endcase
    end
  end

endmodule
