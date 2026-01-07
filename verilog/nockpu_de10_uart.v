`include "memory_unit.vh"

module nockpu_de10_uart(
  input CLOCK_50,
  input [1:0] KEY,
  input UART_RX,
  output UART_TX,
  output [9:0] LEDR
);
  wire clk = CLOCK_50;
  wire sys_rst_n = KEY[0];

  reg [3:0] reset_count;
  reg core_reset_active;
  wire core_rst_n = sys_rst_n && !core_reset_active;
  wire uart_reset_req;

  always @(posedge clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      core_reset_active <= 1'b0;
      reset_count <= 4'b0;
    end else begin
      if (uart_reset_req) begin
        core_reset_active <= 1'b1;
        reset_count <= 4'd8;
      end else if (core_reset_active) begin
        if (reset_count == 0) begin
          core_reset_active <= 1'b0;
        end else begin
          reset_count <= reset_count - 1'b1;
        end
      end
    end
  end

  wire rx_valid;
  wire [7:0] rx_data;
  wire tx_busy;
  wire [7:0] tx_data;
  wire tx_start;

  uart_rx #(
    .CLK_HZ (50000000),
    .BAUD (115200)
  ) uart_rx_inst (
    .clk (clk),
    .rst_n (sys_rst_n),
    .rx (UART_RX),
    .data (rx_data),
    .valid (rx_valid)
  );

  uart_tx #(
    .CLK_HZ (50000000),
    .BAUD (115200)
  ) uart_tx_inst (
    .clk (clk),
    .rst_n (sys_rst_n),
    .data (tx_data),
    .start (tx_start),
    .tx (UART_TX),
    .busy (tx_busy)
  );

  wire start;
  wire [`memory_addr_width - 1:0] start_addr;
  wire host_req;
  wire host_we;
  wire [`memory_addr_width - 1:0] host_addr;
  wire [`memory_data_width - 1:0] host_wdata;
  wire host_ready;
  wire [`memory_data_width - 1:0] host_rdata;
  wire host_rvalid;
  wire busy;
  wire done;
  wire [7:0] error;
  wire [7:0] edit_error;
  wire [`noun_width-1:0] hint;
  wire hint_tag;
  wire [`memory_addr_width - 1:0] free_ptr;
  wire [`memory_addr_width - 1:0] root_ptr;

  nockpu_uart_ctrl uart_ctrl(
    .clk (clk),
    .rst_n (sys_rst_n),
    .rx_data (rx_data),
    .rx_valid (rx_valid),
    .tx_data (tx_data),
    .tx_start (tx_start),
    .tx_busy (tx_busy),
    .start (start),
    .start_addr (start_addr),
    .host_req (host_req),
    .host_we (host_we),
    .host_addr (host_addr),
    .host_wdata (host_wdata),
    .host_ready (host_ready),
    .host_rvalid (host_rvalid),
    .host_rdata (host_rdata),
    .busy (busy),
    .done (done),
    .error (error),
    .edit_error (edit_error),
    .hint (hint),
    .hint_tag (hint_tag),
    .free_ptr (free_ptr),
    .root_ptr (root_ptr),
    .reset_req (uart_reset_req)
  );

  nockpu_top #(
    .USE_STACKLESS_TRAV (1)
  ) core(
    .clk (clk),
    .rst (core_rst_n),
    .start (start),
    .start_addr (start_addr),
    .host_req (host_req),
    .host_we (host_we),
    .host_addr (host_addr),
    .host_wdata (host_wdata),
    .host_ready (host_ready),
    .host_rdata (host_rdata),
    .host_rvalid (host_rvalid),
    .busy (busy),
    .done (done),
    .error (error),
    .edit_error (edit_error),
    .hint (hint),
    .hint_tag (hint_tag),
    .free_ptr (free_ptr),
    .root_ptr (root_ptr)
  );

  assign LEDR[0] = busy;
  assign LEDR[1] = done;
  assign LEDR[2] = (error != 0);
  assign LEDR[3] = (edit_error != 0);
  assign LEDR[4] = hint_tag;
  assign LEDR[9:5] = 5'b0;
endmodule
