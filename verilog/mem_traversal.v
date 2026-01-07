`include "memory_unit.vh"
`include "memory_mux.vh"
`include "mem_traversal.vh"
`include "execute.vh"


module mem_traversal #(
  parameter integer STACK_DEPTH = 2048
)(
  input power, clk, rst,
  input [`memory_addr_width - 1:0] start_addr,
  output reg [`memory_addr_width - 1:0] root_addr,
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
  output reg [7:0] traversal_error,
  output reg [`memory_addr_width - 1:0] module_address,
  output reg [`memory_data_width - 1:0] module_data,
  output reg [2:0] mux_controller,
  input module_finished,
  input [3:0] return_sys_func,
  input [3:0] return_state
);
  // finish signal
  reg is_finished_reg;
  assign finished = is_finished_reg;

  reg [`memory_addr_width - 1:0] trav_stack_addr [0:STACK_DEPTH - 1];
  reg [1:0] trav_stack_state [0:STACK_DEPTH - 1];
  localparam integer STACK_PTR_WIDTH = $clog2(STACK_DEPTH + 1);
  reg [STACK_PTR_WIDTH - 1:0] trav_stack_ptr;
  wire [STACK_PTR_WIDTH - 1:0] trav_stack_top_idx;
  assign trav_stack_top_idx = trav_stack_ptr - 1'b1;

  localparam TRAV_ENTER     = 2'b00,
             TRAV_AFTER_HED = 2'b01,
             TRAV_AFTER_TEL = 2'b10;

  reg [`memory_addr_width - 1:0] mem_addr;
  reg [`memory_data_width - 1:0] mem_data;
  reg [`tag_width - 1:0] mem_tag;
  reg [`noun_width - 1:0] hed, tel;

  reg mem_ready_prev;
  wire mem_ready_edge;
  assign mem_ready_edge = mem_ready && !mem_ready_prev;

  reg exec_pop_pending;
  reg module_done_pending;
  reg [2:0] active_module;

  reg [3:0] state;
  localparam STATE_IDLE      = 4'h0,
             STATE_READ      = 4'h1,
             STATE_WAIT      = 4'h2,
             STATE_PROCESS   = 4'h3,
             STATE_EXEC_WAIT = 4'h4,
             STATE_GC_WAIT   = 4'h5,
             STATE_FINISH_WAIT = 4'h6;

  localparam integer MEM_DEPTH = 1 << `memory_addr_width;
  reg [MEM_DEPTH - 1:0] in_stack;
  wire hed_is_cell;
  wire tel_is_cell;
  wire [`memory_addr_width - 1:0] hed_addr;
  wire [`memory_addr_width - 1:0] tel_addr;
  wire hed_is_cell_trav;
  wire tel_is_cell_trav;
  wire is_stack_node;
  wire is_exec_node;
  wire is_large_atom;
  assign hed_is_cell = (mem_tag[1] == `CELL);
  assign tel_is_cell = (mem_tag[0] == `CELL);
  assign hed_addr = hed[`memory_addr_width - 1:0];
  assign tel_addr = tel[`memory_addr_width - 1:0];
  assign hed_is_cell_trav = hed_is_cell && !in_stack[hed_addr];
  assign tel_is_cell_trav = tel_is_cell && !in_stack[tel_addr];
  assign is_stack_node = mem_data[`stack_bit];
  assign is_exec_node = mem_data[`execute_bit];
  assign is_large_atom = mem_data[`large_atom_bit];

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      is_finished_reg <= 1'b0;
      gc_ready <= 1'b0;
      mem_execute <= 1'b0;
      mem_func <= 0;
      address1 <= 0;
      address2 <= 0;
      write_data <= 0;
      module_address <= 0;
      module_data <= 0;
      mux_controller <= `MUX_TRAVERSAL;
      mem_addr <= 0;
      root_addr <= 0;
      mem_data <= 0;
      mem_tag <= 0;
      hed <= 0;
      tel <= 0;
      traversal_error <= 0;
      mem_ready_prev <= 1'b0;
      trav_stack_ptr <= 0;
      in_stack <= {MEM_DEPTH{1'b0}};
      exec_pop_pending <= 1'b0;
      module_done_pending <= 1'b0;
      active_module <= `MUX_TRAVERSAL;
      state <= STATE_IDLE;
    end else if (execute) begin
      mem_ready_prev <= mem_ready;
      case (state)
        STATE_IDLE: begin
          is_finished_reg <= 1'b0;
          mux_controller <= `MUX_TRAVERSAL;
          gc_ready <= 1'b0;
          exec_pop_pending <= 1'b0;
          module_done_pending <= 1'b0;
          active_module <= `MUX_TRAVERSAL;
          mem_execute <= 1'b0;
          mem_func <= 0;
          if (gc) begin
            trav_stack_ptr <= 0;
            gc_ready <= 1'b1;
            state <= STATE_GC_WAIT;
          end else if (trav_stack_ptr == 0) begin
            if (mem_ready) begin
              traversal_error <= 0;
              root_addr <= start_addr;
              trav_stack_addr[0] <= start_addr;
              trav_stack_state[0] <= TRAV_ENTER;
              trav_stack_ptr <= 1;
              in_stack <= {MEM_DEPTH{1'b0}};
              in_stack[start_addr] <= 1'b1;
              mem_addr <= start_addr;
              address1 <= start_addr;
              address2 <= 0;
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1'b1;
              state <= STATE_WAIT;
            end else begin
              mem_execute <= 1'b0;
              mem_func <= 0;
            end
          end
        end

        STATE_READ: begin
          if (trav_stack_ptr == 0) begin
            is_finished_reg <= 1'b0;
            address1 <= root_addr;
            address2 <= 0;
            if (mem_ready) begin
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1'b1;
              state <= STATE_FINISH_WAIT;
            end else begin
              mem_execute <= 1'b0;
              mem_func <= 0;
            end
          end else begin
            mem_addr <= trav_stack_addr[trav_stack_top_idx];
            address1 <= trav_stack_addr[trav_stack_top_idx];
            address2 <= 0;
            if (mem_ready) begin
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1'b1;
              state <= STATE_WAIT;
            end else begin
              mem_execute <= 1'b0;
              mem_func <= 0;
            end
          end
        end

        STATE_WAIT: begin
          gc_ready <= 1'b0;
          if (mem_ready_edge) begin
            mem_data <= read_data1;
            mem_tag <= read_data1[`tag_start:`tag_end];
            hed <= read_data1[`hed_start:`hed_end];
            tel <= read_data1[`tel_start:`tel_end];
            mem_execute <= 1'b0;
            mem_func <= 0;
            state <= STATE_PROCESS;
          end else begin
            mem_execute <= 1'b0;
            mem_func <= 0;
          end
        end

        STATE_PROCESS: begin
          if (gc) begin
            trav_stack_ptr <= 0;
            in_stack <= {MEM_DEPTH{1'b0}};
            exec_pop_pending <= 1'b0;
            gc_ready <= 1'b1;
            mem_execute <= 1'b0;
            mem_func <= 0;
            state <= STATE_GC_WAIT;
          end else if (trav_stack_ptr == 0) begin
            is_finished_reg <= 1'b0;
            address1 <= root_addr;
            address2 <= 0;
            if (mem_ready) begin
              mem_func <= `GET_CONTENTS;
              mem_execute <= 1'b1;
              state <= STATE_FINISH_WAIT;
            end else begin
              mem_execute <= 1'b0;
              mem_func <= 0;
            end
          end else if (is_large_atom) begin
            if (trav_stack_ptr == 1) begin
              is_finished_reg <= 1'b0;
              address1 <= root_addr;
              address2 <= 0;
              if (mem_ready) begin
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1'b1;
                state <= STATE_FINISH_WAIT;
              end else begin
                mem_execute <= 1'b0;
                mem_func <= 0;
              end
            end else begin
              trav_stack_ptr <= trav_stack_ptr - 1'b1;
              in_stack[trav_stack_addr[trav_stack_top_idx]] <= 1'b0;
              mem_addr <= trav_stack_addr[trav_stack_top_idx - 1'b1];
              state <= STATE_READ;
            end
          end else begin
            case (trav_stack_state[trav_stack_top_idx])
              TRAV_ENTER: begin
                if (is_stack_node) begin
                  if (tel_is_cell_trav) begin
                    trav_stack_state[trav_stack_top_idx] <= TRAV_AFTER_TEL;
                    if (trav_stack_ptr == STACK_DEPTH) begin
`ifdef TRACE_TRAV
                      $display("trav stack overflow at addr %0d data %h",
                               mem_addr,
                               mem_data);
`endif
                      traversal_error <= `ERROR_TRAV_STACK_OVERFLOW;
                      is_finished_reg <= 1'b1;
                      state <= STATE_IDLE;
                    end else begin
                      trav_stack_addr[trav_stack_ptr] <= tel;
                      trav_stack_state[trav_stack_ptr] <= TRAV_ENTER;
                      trav_stack_ptr <= trav_stack_ptr + 1'b1;
                      in_stack[tel_addr] <= 1'b1;
                      mem_addr <= tel;
                      state <= STATE_READ;
                    end
                  end else begin
                    if (!gc) begin
                      exec_pop_pending <= 1'b1;
                      module_address <= mem_addr;
                      module_data <= mem_data;
                      case (mem_data[`hed_start:`hed_end])
                        `cell: begin
                          mux_controller <= `MUX_CELL;
                          active_module <= `MUX_CELL;
                        end
                        `increment: begin
                          mux_controller <= `MUX_INCR;
                          active_module <= `MUX_INCR;
                        end
                        `equality: begin
                          mux_controller <= `MUX_EQUAL;
                          active_module <= `MUX_EQUAL;
                        end
                        `replace: begin
                          mux_controller <= `MUX_EDIT;
                          active_module <= `MUX_EDIT;
                        end
                        default: begin
`ifdef TRACE_TRAV
                          $display("trav unknown stack opcode addr %0d data %h",
                                   mem_addr,
                                   mem_data);
`endif
                          traversal_error <= `ERROR_TRAV_UNKNOWN_OPCODE;
                          is_finished_reg <= 1'b1;
                          state <= STATE_IDLE;
                          mux_controller <= `MUX_TRAVERSAL;
                          active_module <= `MUX_TRAVERSAL;
                        end
                      endcase
                      if (!is_finished_reg) begin
                        state <= STATE_EXEC_WAIT;
                      end
                    end else begin
                      trav_stack_ptr <= trav_stack_ptr - 1'b1;
                      in_stack[trav_stack_addr[trav_stack_top_idx]] <= 1'b0;
                      state <= STATE_READ;
                    end
                  end
                end else if (hed_is_cell_trav) begin
                  trav_stack_state[trav_stack_top_idx] <= TRAV_AFTER_HED;
                  if (trav_stack_ptr == STACK_DEPTH) begin
`ifdef TRACE_TRAV
                    $display("trav stack overflow at addr %0d data %h",
                             mem_addr,
                             mem_data);
`endif
                    traversal_error <= `ERROR_TRAV_STACK_OVERFLOW;
                    is_finished_reg <= 1'b1;
                    state <= STATE_IDLE;
                  end else begin
                    trav_stack_addr[trav_stack_ptr] <= hed;
                    trav_stack_state[trav_stack_ptr] <= TRAV_ENTER;
                    trav_stack_ptr <= trav_stack_ptr + 1'b1;
                    in_stack[hed_addr] <= 1'b1;
                    mem_addr <= hed;
                    state <= STATE_READ;
                  end
                end else if (tel_is_cell_trav) begin
                  trav_stack_state[trav_stack_top_idx] <= TRAV_AFTER_TEL;
                  if (trav_stack_ptr == STACK_DEPTH) begin
`ifdef TRACE_TRAV
                    $display("trav stack overflow at addr %0d data %h",
                             mem_addr,
                             mem_data);
`endif
                    traversal_error <= `ERROR_TRAV_STACK_OVERFLOW;
                    is_finished_reg <= 1'b1;
                    state <= STATE_IDLE;
                  end else begin
                    trav_stack_addr[trav_stack_ptr] <= tel;
                    trav_stack_state[trav_stack_ptr] <= TRAV_ENTER;
                    trav_stack_ptr <= trav_stack_ptr + 1'b1;
                    in_stack[tel_addr] <= 1'b1;
                    mem_addr <= tel;
                    state <= STATE_READ;
                  end
                end else begin
                  if (is_exec_node && !gc) begin
                    exec_pop_pending <= 1'b1;
                    active_module <= `MUX_EXECUTE;
                    module_address <= mem_addr;
                    module_data <= mem_data;
                    mux_controller <= `MUX_EXECUTE;
                    state <= STATE_EXEC_WAIT;
                  end else if (trav_stack_ptr == 1) begin
                    is_finished_reg <= 1'b0;
                    address1 <= root_addr;
                    address2 <= 0;
                    if (mem_ready) begin
                      mem_func <= `GET_CONTENTS;
                      mem_execute <= 1'b1;
                      state <= STATE_FINISH_WAIT;
                    end else begin
                      mem_execute <= 1'b0;
                      mem_func <= 0;
                    end
                  end else begin
                    trav_stack_ptr <= trav_stack_ptr - 1'b1;
                    in_stack[trav_stack_addr[trav_stack_top_idx]] <= 1'b0;
                    mem_addr <= trav_stack_addr[trav_stack_top_idx - 1'b1];
                    state <= STATE_READ;
                  end
                end
              end

              TRAV_AFTER_HED: begin
                if (tel_is_cell_trav) begin
                  trav_stack_state[trav_stack_top_idx] <= TRAV_AFTER_TEL;
                  if (trav_stack_ptr == STACK_DEPTH) begin
`ifdef TRACE_TRAV
                    $display("trav stack overflow at addr %0d data %h",
                             mem_addr,
                             mem_data);
`endif
                    traversal_error <= `ERROR_TRAV_STACK_OVERFLOW;
                    is_finished_reg <= 1'b1;
                    state <= STATE_IDLE;
                  end else begin
                    trav_stack_addr[trav_stack_ptr] <= tel;
                    trav_stack_state[trav_stack_ptr] <= TRAV_ENTER;
                    trav_stack_ptr <= trav_stack_ptr + 1'b1;
                    in_stack[tel_addr] <= 1'b1;
                    mem_addr <= tel;
                    state <= STATE_READ;
                  end
                end else if (is_exec_node && !gc) begin
                  exec_pop_pending <= 1'b1;
                  active_module <= `MUX_EXECUTE;
                  module_address <= mem_addr;
                  module_data <= mem_data;
                  mux_controller <= `MUX_EXECUTE;
                  state <= STATE_EXEC_WAIT;
                end else begin
                  if (trav_stack_ptr == 1) begin
                    is_finished_reg <= 1'b0;
                    address1 <= root_addr;
                    address2 <= 0;
                    if (mem_ready) begin
                      mem_func <= `GET_CONTENTS;
                      mem_execute <= 1'b1;
                      state <= STATE_FINISH_WAIT;
                    end else begin
                      mem_execute <= 1'b0;
                      mem_func <= 0;
                    end
                  end else begin
                    trav_stack_ptr <= trav_stack_ptr - 1'b1;
                    in_stack[trav_stack_addr[trav_stack_top_idx]] <= 1'b0;
                    mem_addr <= trav_stack_addr[trav_stack_top_idx - 1'b1];
                    state <= STATE_READ;
                  end
                end
              end

              TRAV_AFTER_TEL: begin
                if ((is_exec_node || is_stack_node) && !gc) begin
                  exec_pop_pending <= 1'b1;
                  module_address <= mem_addr;
                  module_data <= mem_data;
                  if (is_stack_node) begin
                    case (mem_data[`hed_start:`hed_end])
                      `cell: begin
                        mux_controller <= `MUX_CELL;
                        active_module <= `MUX_CELL;
                      end
                      `increment: begin
                        mux_controller <= `MUX_INCR;
                        active_module <= `MUX_INCR;
                      end
                      `equality: begin
                        mux_controller <= `MUX_EQUAL;
                        active_module <= `MUX_EQUAL;
                      end
                      `replace: begin
                        mux_controller <= `MUX_EDIT;
                        active_module <= `MUX_EDIT;
                      end
                      default: begin
`ifdef TRACE_TRAV
                        $display("trav unknown stack opcode addr %0d data %h",
                                 mem_addr,
                                 mem_data);
`endif
                        traversal_error <= `ERROR_TRAV_UNKNOWN_OPCODE;
                        is_finished_reg <= 1'b1;
                        state <= STATE_IDLE;
                        mux_controller <= `MUX_TRAVERSAL;
                        active_module <= `MUX_TRAVERSAL;
                      end
                    endcase
                    if (!is_finished_reg) begin
                      state <= STATE_EXEC_WAIT;
                    end
                  end else begin
                    active_module <= `MUX_EXECUTE;
                    mux_controller <= `MUX_EXECUTE;
                    state <= STATE_EXEC_WAIT;
                  end
                end else begin
                  if (trav_stack_ptr == 1) begin
                    is_finished_reg <= 1'b0;
                    address1 <= root_addr;
                    address2 <= 0;
                    if (mem_ready) begin
                      mem_func <= `GET_CONTENTS;
                      mem_execute <= 1'b1;
                      state <= STATE_FINISH_WAIT;
                    end else begin
                      mem_execute <= 1'b0;
                      mem_func <= 0;
                    end
                  end else begin
                    trav_stack_ptr <= trav_stack_ptr - 1'b1;
                    in_stack[trav_stack_addr[trav_stack_top_idx]] <= 1'b0;
                    mem_addr <= trav_stack_addr[trav_stack_top_idx - 1'b1];
                    state <= STATE_READ;
                  end
                end
              end

              default: begin
                state <= STATE_IDLE;
              end
            endcase
          end
        end

        STATE_EXEC_WAIT: begin
          if (gc) begin
            trav_stack_ptr <= 0;
            in_stack <= {MEM_DEPTH{1'b0}};
            exec_pop_pending <= 1'b0;
            module_done_pending <= 1'b0;
            gc_ready <= 1'b1;
            mem_execute <= 1'b0;
            mem_func <= 0;
            mux_controller <= `MUX_TRAVERSAL;
            active_module <= `MUX_TRAVERSAL;
            state <= STATE_GC_WAIT;
          end else begin
            if (module_finished) begin
              module_done_pending <= 1'b1;
            end
            if (module_finished || module_done_pending) begin
              if (return_sys_func == `SYS_FUNC_EXECUTE
              && return_state == `SYS_EXECUTE_ERROR) begin
                is_finished_reg <= 1'b1;
                state <= STATE_IDLE;
                mux_controller <= `MUX_TRAVERSAL;
                exec_pop_pending <= 1'b0;
                module_done_pending <= 1'b0;
                active_module <= `MUX_TRAVERSAL;
              end else if (trav_stack_ptr == 0) begin
                mux_controller <= `MUX_TRAVERSAL;
                exec_pop_pending <= 1'b0;
                active_module <= `MUX_TRAVERSAL;
                is_finished_reg <= 1'b0;
                address1 <= root_addr;
                address2 <= 0;
                if (mem_ready) begin
                  mem_func <= `GET_CONTENTS;
                  mem_execute <= 1'b1;
                  state <= STATE_FINISH_WAIT;
                  module_done_pending <= 1'b0;
                end else begin
                  mem_execute <= 1'b0;
                  mem_func <= 0;
                end
              end else begin
                mux_controller <= `MUX_TRAVERSAL;
                exec_pop_pending <= 1'b0;
                active_module <= `MUX_TRAVERSAL;
                trav_stack_state[trav_stack_top_idx] <= TRAV_ENTER;
                mem_addr <= trav_stack_addr[trav_stack_top_idx];
                state <= STATE_READ;
                module_done_pending <= 1'b0;
              end
            end
          end
        end

        STATE_GC_WAIT: begin
          if (!gc && gc_ready) begin
            if (mem_ready) begin
              gc_ready <= 1'b0;
              trav_stack_ptr <= 0;
              module_done_pending <= 1'b0;
              if (read_data1[`memory_addr_width - 1:0] != `NIL_ADDR) begin
                root_addr <= read_data1[`memory_addr_width - 1:0];
                trav_stack_addr[0] <= read_data1[`memory_addr_width - 1:0];
                trav_stack_state[0] <= TRAV_ENTER;
                trav_stack_ptr <= 1;
                in_stack <= {MEM_DEPTH{1'b0}};
                in_stack[read_data1[`memory_addr_width - 1:0]] <= 1'b1;
                mem_addr <= read_data1[`memory_addr_width - 1:0];
                address1 <= read_data1[`memory_addr_width - 1:0];
                address2 <= 0;
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1'b1;
                state <= STATE_WAIT;
              end else begin
                is_finished_reg <= 1'b0;
                address1 <= root_addr;
                address2 <= 0;
                mem_func <= `GET_CONTENTS;
                mem_execute <= 1'b1;
                state <= STATE_FINISH_WAIT;
              end
            end else begin
              mem_execute <= 1'b0;
              mem_func <= 0;
            end
          end
        end

        STATE_FINISH_WAIT: begin
          if (mem_ready_edge) begin
            mem_execute <= 1'b0;
            mem_func <= 0;
`ifdef TRACE_FINISH
            $display("finish check addr %0d data %h exec %0d stack %0d",
                     root_addr,
                     read_data1,
                     read_data1[`execute_bit],
                     read_data1[`stack_bit]);
`endif
            if (read_data1[`execute_bit] || read_data1[`stack_bit]) begin
              is_finished_reg <= 1'b0;
              trav_stack_ptr <= 1;
              in_stack <= {MEM_DEPTH{1'b0}};
              in_stack[root_addr] <= 1'b1;
              trav_stack_addr[0] <= root_addr;
              trav_stack_state[0] <= TRAV_ENTER;
              mem_addr <= root_addr;
              mem_data <= read_data1;
              mem_tag <= read_data1[`tag_start:`tag_end];
              hed <= read_data1[`hed_start:`hed_end];
              tel <= read_data1[`tel_start:`tel_end];
              state <= STATE_PROCESS;
            end else begin
              is_finished_reg <= 1'b1;
              state <= STATE_IDLE;
            end
          end else begin
            mem_execute <= 1'b0;
            mem_func <= 0;
          end
        end

        default: begin
          state <= STATE_IDLE;
        end
      endcase
    end else begin
      state <= STATE_IDLE;
      is_finished_reg <= 1'b0;
      gc_ready <= 1'b0;
      mem_execute <= 1'b0;
      mem_func <= 0;
      mux_controller <= `MUX_TRAVERSAL;
      trav_stack_ptr <= 0;
      in_stack <= {MEM_DEPTH{1'b0}};
      exec_pop_pending <= 1'b0;
      module_done_pending <= 1'b0;
      active_module <= `MUX_TRAVERSAL;
    end
  end
endmodule
