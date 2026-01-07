module uart_tx #(
  parameter integer CLK_HZ = 50000000,
  parameter integer BAUD = 115200
)(
  input clk,
  input rst_n,
  input [7:0] data,
  input start,
  output reg tx,
  output wire busy
);
  localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

  localparam TX_IDLE  = 2'd0;
  localparam TX_START = 2'd1;
  localparam TX_DATA  = 2'd2;
  localparam TX_STOP  = 2'd3;

  reg [1:0] state;
  reg [$clog2(CLKS_PER_BIT + 1) - 1:0] clk_count;
  reg [2:0] bit_index;
  reg [7:0] shift_reg;

  assign busy = (state != TX_IDLE);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= TX_IDLE;
      clk_count <= 0;
      bit_index <= 0;
      shift_reg <= 8'b0;
      tx <= 1'b1;
    end else begin
      case (state)
        TX_IDLE: begin
          tx <= 1'b1;
          clk_count <= 0;
          bit_index <= 0;
          if (start) begin
            shift_reg <= data;
            state <= TX_START;
            tx <= 1'b0;
          end
        end

        TX_START: begin
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= 0;
            tx <= shift_reg[0];
            state <= TX_DATA;
            bit_index <= 0;
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        TX_DATA: begin
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= 0;
            if (bit_index == 3'd7) begin
              tx <= 1'b1;
              state <= TX_STOP;
            end else begin
              shift_reg <= {1'b0, shift_reg[7:1]};
              bit_index <= bit_index + 1'b1;
              tx <= shift_reg[1];
            end
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        TX_STOP: begin
          if (clk_count == CLKS_PER_BIT - 1) begin
            clk_count <= 0;
            state <= TX_IDLE;
            tx <= 1'b1;
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        default: begin
          state <= TX_IDLE;
          tx <= 1'b1;
        end
      endcase
    end
  end
endmodule
