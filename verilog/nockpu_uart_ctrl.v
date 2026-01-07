`include "memory_unit.vh"

module nockpu_uart_ctrl(
  input clk,
  input rst_n,
  input [7:0] rx_data,
  input rx_valid,
  output reg [7:0] tx_data,
  output reg tx_start,
  input tx_busy,
  output reg start,
  output reg [`memory_addr_width - 1:0] start_addr,
  output reg host_req,
  output reg host_we,
  output reg [`memory_addr_width - 1:0] host_addr,
  output reg [`memory_data_width - 1:0] host_wdata,
  input host_ready,
  input host_rvalid,
  input [`memory_data_width - 1:0] host_rdata,
  input busy,
  input done,
  input [7:0] error,
  input [7:0] edit_error,
  input [`noun_width - 1:0] hint,
  input hint_tag,
  input [`memory_addr_width - 1:0] free_ptr,
  input [`memory_addr_width - 1:0] root_ptr,
  output reg reset_req
);
  localparam ST_IDLE       = 5'd0;
  localparam ST_W_ADDR0    = 5'd1;
  localparam ST_W_ADDR1    = 5'd2;
  localparam ST_W_COUNT0   = 5'd3;
  localparam ST_W_COUNT1   = 5'd4;
  localparam ST_W_DATA     = 5'd5;
  localparam ST_W_ISSUE    = 5'd6;
  localparam ST_W_WAIT     = 5'd7;
  localparam ST_W_DONE     = 5'd8;
  localparam ST_R_ADDR0    = 5'd9;
  localparam ST_R_ADDR1    = 5'd10;
  localparam ST_R_COUNT0   = 5'd11;
  localparam ST_R_COUNT1   = 5'd12;
  localparam ST_R_HEADER   = 5'd13;
  localparam ST_R_ISSUE    = 5'd14;
  localparam ST_R_WAIT     = 5'd15;
  localparam ST_R_SEND     = 5'd16;
  localparam ST_S_ADDR0    = 5'd17;
  localparam ST_S_ADDR1    = 5'd18;
  localparam ST_S_ISSUE    = 5'd19;
  localparam ST_S_ACK      = 5'd20;
  localparam ST_P_HEADER   = 5'd21;
  localparam ST_P_PAYLOAD  = 5'd22;
  localparam ST_P_SEND     = 5'd23;
  localparam ST_X_ACK      = 5'd24;

  localparam CMD_WRITE  = 8'h57; // 'W'
  localparam CMD_READ   = 8'h52; // 'R'
  localparam CMD_START  = 8'h53; // 'S'
  localparam CMD_STATUS = 8'h50; // 'P'
  localparam CMD_RESET  = 8'h58; // 'X'

  reg [4:0] state;
  reg [15:0] addr_reg;
  reg [15:0] count_reg;
  reg [2:0] byte_idx;
  reg [`memory_data_width - 1:0] word_reg;

  reg [7:0] rx_buf;
  reg rx_buf_valid;

  reg [127:0] tx_shift;
  reg [4:0] tx_count;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_start <= 1'b0;
      tx_data <= 8'b0;
      tx_shift <= 128'b0;
      tx_count <= 0;
    end else begin
      tx_start <= 1'b0;
      if (tx_count != 0 && !tx_busy) begin
        tx_data <= tx_shift[7:0];
        tx_shift <= {8'h00, tx_shift[127:8]};
        tx_count <= tx_count - 1'b1;
        tx_start <= 1'b1;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      addr_reg <= 16'b0;
      count_reg <= 16'b0;
      byte_idx <= 3'b0;
      word_reg <= {`memory_data_width{1'b0}};
      start <= 1'b0;
      start_addr <= {`memory_addr_width{1'b0}};
      host_req <= 1'b0;
      host_we <= 1'b0;
      host_addr <= {`memory_addr_width{1'b0}};
      host_wdata <= {`memory_data_width{1'b0}};
      reset_req <= 1'b0;
      rx_buf <= 8'b0;
      rx_buf_valid <= 1'b0;
    end else begin
      start <= 1'b0;
      host_req <= 1'b0;
      host_we <= 1'b0;
      reset_req <= 1'b0;
      if (rx_valid && !rx_buf_valid) begin
        rx_buf <= rx_data;
        rx_buf_valid <= 1'b1;
      end

      case (state)
        ST_IDLE: begin
          if (rx_buf_valid) begin
            case (rx_buf)
              CMD_WRITE:  state <= ST_W_ADDR0;
              CMD_READ:   state <= ST_R_ADDR0;
              CMD_START:  state <= ST_S_ADDR0;
              CMD_STATUS: state <= ST_P_HEADER;
              CMD_RESET:  state <= ST_X_ACK;
              default:    state <= ST_IDLE;
            endcase
            rx_buf_valid <= 1'b0;
          end
        end

        ST_W_ADDR0: begin
          if (rx_buf_valid) begin
            addr_reg[7:0] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_W_ADDR1;
          end
        end
        ST_W_ADDR1: begin
          if (rx_buf_valid) begin
            addr_reg[15:8] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_W_COUNT0;
          end
        end
        ST_W_COUNT0: begin
          if (rx_buf_valid) begin
            count_reg[7:0] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_W_COUNT1;
          end
        end
        ST_W_COUNT1: begin
          if (rx_buf_valid) begin
            count_reg[15:8] <= rx_buf;
            rx_buf_valid <= 1'b0;
            if ({rx_buf, count_reg[7:0]} == 16'b0) begin
              state <= ST_W_DONE;
            end else begin
              byte_idx <= 3'b0;
              word_reg <= {`memory_data_width{1'b0}};
              state <= ST_W_DATA;
            end
          end
        end
        ST_W_DATA: begin
          if (rx_buf_valid) begin
            word_reg[byte_idx * 8 +: 8] <= rx_buf;
            rx_buf_valid <= 1'b0;
            if (byte_idx == 3'd7) begin
              state <= ST_W_ISSUE;
            end else begin
              byte_idx <= byte_idx + 1'b1;
            end
          end
        end
        ST_W_ISSUE: begin
          if (host_ready) begin
            host_req <= 1'b1;
            host_we <= 1'b1;
            host_addr <= addr_reg[`memory_addr_width - 1:0];
            host_wdata <= word_reg;
            state <= ST_W_WAIT;
          end
        end
        ST_W_WAIT: begin
          if (host_ready) begin
            addr_reg <= addr_reg + 1'b1;
            if (count_reg == 16'd1) begin
              count_reg <= 16'd0;
              state <= ST_W_DONE;
            end else begin
              count_reg <= count_reg - 1'b1;
              byte_idx <= 3'b0;
              word_reg <= {`memory_data_width{1'b0}};
              state <= ST_W_DATA;
            end
          end
        end
        ST_W_DONE: begin
          if (tx_count == 0) begin
            tx_shift <= {120'b0, 8'h77}; // 'w'
            tx_count <= 5'd1;
            state <= ST_IDLE;
          end
        end

        ST_R_ADDR0: begin
          if (rx_buf_valid) begin
            addr_reg[7:0] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_R_ADDR1;
          end
        end
        ST_R_ADDR1: begin
          if (rx_buf_valid) begin
            addr_reg[15:8] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_R_COUNT0;
          end
        end
        ST_R_COUNT0: begin
          if (rx_buf_valid) begin
            count_reg[7:0] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_R_COUNT1;
          end
        end
        ST_R_COUNT1: begin
          if (rx_buf_valid) begin
            count_reg[15:8] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_R_HEADER;
          end
        end
        ST_R_HEADER: begin
          if (tx_count == 0) begin
            tx_shift <= {120'b0, 8'h72}; // 'r'
            tx_count <= 5'd1;
            if ({count_reg[15:8], count_reg[7:0]} == 16'b0) begin
              state <= ST_IDLE;
            end else begin
              state <= ST_R_ISSUE;
            end
          end
        end
        ST_R_ISSUE: begin
          if (tx_count == 0 && host_ready) begin
            host_req <= 1'b1;
            host_we <= 1'b0;
            host_addr <= addr_reg[`memory_addr_width - 1:0];
            state <= ST_R_WAIT;
          end
        end
        ST_R_WAIT: begin
          if (host_rvalid) begin
            if (tx_count == 0) begin
              tx_shift <= {64'b0, host_rdata};
              tx_count <= 5'd8;
              state <= ST_R_SEND;
            end
          end
        end
        ST_R_SEND: begin
          if (tx_count == 0) begin
            addr_reg <= addr_reg + 1'b1;
            if (count_reg == 16'd1) begin
              count_reg <= 16'd0;
              state <= ST_IDLE;
            end else begin
              count_reg <= count_reg - 1'b1;
              state <= ST_R_ISSUE;
            end
          end
        end

        ST_S_ADDR0: begin
          if (rx_buf_valid) begin
            addr_reg[7:0] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_S_ADDR1;
          end
        end
        ST_S_ADDR1: begin
          if (rx_buf_valid) begin
            addr_reg[15:8] <= rx_buf;
            rx_buf_valid <= 1'b0;
            state <= ST_S_ISSUE;
          end
        end
        ST_S_ISSUE: begin
          if (!busy && host_ready) begin
            start_addr <= addr_reg[`memory_addr_width - 1:0];
            start <= 1'b1;
            state <= ST_S_ACK;
          end
        end
        ST_S_ACK: begin
          if (tx_count == 0) begin
            tx_shift <= {120'b0, 8'h73}; // 's'
            tx_count <= 5'd1;
            state <= ST_IDLE;
          end
        end

        ST_P_HEADER: begin
          if (tx_count == 0) begin
            tx_shift <= {120'b0, 8'h70}; // 'p'
            tx_count <= 5'd1;
            state <= ST_P_PAYLOAD;
          end
        end
        ST_P_PAYLOAD: begin
          if (tx_count == 0) begin
            tx_shift[7:0] <= {6'b0, done, busy};
            tx_shift[15:8] <= error;
            tx_shift[23:16] <= edit_error;
            tx_shift[31:24] <= {7'b0, hint_tag};
            tx_shift[63:32] <= {4'b0, hint};
            tx_shift[95:64] <= {{(32-`memory_addr_width){1'b0}}, root_ptr};
            tx_shift[127:96] <= {{(32-`memory_addr_width){1'b0}}, free_ptr};
            tx_count <= 5'd16;
            state <= ST_P_SEND;
          end
        end
        ST_P_SEND: begin
          if (tx_count == 0) begin
            state <= ST_IDLE;
          end
        end

        ST_X_ACK: begin
          if (tx_count == 0) begin
            reset_req <= 1'b1;
            tx_shift <= {120'b0, 8'h78}; // 'x'
            tx_count <= 5'd1;
            state <= ST_IDLE;
          end
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
