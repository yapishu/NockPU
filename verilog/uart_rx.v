module uart_rx #(
  parameter integer CLK_HZ = 50000000,
  parameter integer BAUD = 115200
)(
  input clk,
  input rst_n,
  input rx,
  output reg [7:0] data,
  output reg valid
);
  localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
  localparam integer HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;

  localparam RX_IDLE  = 2'd0;
  localparam RX_START = 2'd1;
  localparam RX_DATA  = 2'd2;
  localparam RX_STOP  = 2'd3;

  reg [1:0] state;
  reg [$clog2(CLKS_PER_BIT + 1) - 1:0] clk_count;
  reg [2:0] bit_index;
  reg rx_sync1;
  reg rx_sync2;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_sync1 <= 1'b1;
      rx_sync2 <= 1'b1;
    end else begin
      rx_sync1 <= rx;
      rx_sync2 <= rx_sync1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= RX_IDLE;
      clk_count <= 0;
      bit_index <= 0;
      data <= 8'b0;
      valid <= 1'b0;
    end else begin
      valid <= 1'b0;
      case (state)
        RX_IDLE: begin
          clk_count <= 0;
          bit_index <= 0;
          if (rx_sync2 == 1'b0) begin
            state <= RX_START;
          end
        end

        RX_START: begin
          if (clk_count == HALF_CLKS_PER_BIT) begin
            if (rx_sync2 == 1'b0) begin
              clk_count <= 0;
              bit_index <= 0;
              state <= RX_DATA;
            end else begin
              state <= RX_IDLE;
            end
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        RX_DATA: begin
          if (clk_count == CLKS_PER_BIT - 1) begin
            data[bit_index] <= rx_sync2;
            clk_count <= 0;
            if (bit_index == 3'd7) begin
              state <= RX_STOP;
            end else begin
              bit_index <= bit_index + 1'b1;
            end
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        RX_STOP: begin
          if (clk_count == CLKS_PER_BIT - 1) begin
            valid <= 1'b1;
            state <= RX_IDLE;
            clk_count <= 0;
          end else begin
            clk_count <= clk_count + 1'b1;
          end
        end

        default: begin
          state <= RX_IDLE;
        end
      endcase
    end
  end
endmodule
