`timescale 1ns/1ns
`include "../verilog/memory_unit.vh"

module nockpu_de10_uart_tb();
  localparam integer CLK_HZ = 50000000;
  localparam integer BAUD = 115200;
  localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

  parameter MEM_INIT_FILE = "./memory/constant_tb.hex";
  parameter integer MEM_WORDS = 5;
  parameter integer MAX_POLLS = 50;
  parameter integer SIM_TIMEOUT_CYCLES = 5000000;
  parameter [`memory_data_width - 1:0] EXPECTED_WORD1 = 64'h0300000a400000ae;

  reg clk;
  reg [1:0] KEY;
  reg UART_RX;
  wire UART_TX;
  wire [9:0] LEDR;

  nockpu_de10_uart dut(
    .CLOCK_50 (clk),
    .KEY (KEY),
    .UART_RX (UART_RX),
    .UART_TX (UART_TX),
    .LEDR (LEDR)
  );

  // Capture UART controller bytes directly to avoid UART decode drift in sim.
  wire [7:0] uart_tx_data = dut.tx_data;
  wire uart_tx_valid = dut.tx_start;

  reg [7:0] rx_fifo [0:255];
  integer rx_wr;
  integer rx_rd;

  always @(posedge clk or negedge KEY[0]) begin
    if (!KEY[0]) begin
      rx_wr <= 0;
      rx_rd <= 0;
    end else if (uart_tx_valid) begin
      rx_fifo[rx_wr] <= uart_tx_data;
      rx_wr <= rx_wr + 1;
    end
  end

  always @(posedge clk or negedge KEY[0]) begin
    if (!KEY[0]) begin
      max_tx_count <= 5'b0;
    end else if (dut.uart_ctrl.tx_count > max_tx_count) begin
      max_tx_count <= dut.uart_ctrl.tx_count;
    end
  end

  always @(posedge clk or negedge KEY[0]) begin
    if (!KEY[0]) begin
      tx_start_count <= 0;
    end else if (dut.uart_ctrl.tx_start) begin
      tx_start_count <= tx_start_count + 1;
    end
  end

  task wait_clks;
    input integer cycles;
    integer i;
    begin
      for (i = 0; i < cycles; i = i + 1) begin
        @(posedge clk);
      end
    end
  endtask

  task uart_send_byte;
    input [7:0] data;
    integer bit_idx;
    begin
      UART_RX <= 1'b0;
      wait_clks(CLKS_PER_BIT);
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        UART_RX <= data[bit_idx];
        wait_clks(CLKS_PER_BIT);
      end
      UART_RX <= 1'b1;
      wait_clks(CLKS_PER_BIT);
    end
  endtask

  task uart_send_u16;
    input [15:0] data;
    begin
      uart_send_byte(data[7:0]);
      uart_send_byte(data[15:8]);
    end
  endtask

  task uart_send_u64;
    input [63:0] data;
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1) begin
        uart_send_byte(data[i*8 +: 8]);
      end
    end
  endtask

  task uart_read_byte;
    output [7:0] data;
    begin
      while (rx_rd == rx_wr) begin
        @(posedge clk);
      end
      data = rx_fifo[rx_rd];
      rx_rd = rx_rd + 1;
      rx_log[rx_count] = data;
      rx_last3 = rx_last2;
      rx_last2 = rx_last1;
      rx_last1 = rx_last0;
      rx_last0 = data;
      rx_count = rx_count + 1;
    end
  endtask

  task uart_expect_byte;
    input [7:0] expected;
    reg [7:0] got;
    begin
      uart_read_byte(got);
      if (got !== expected) begin
        $display("FAIL uart expect %h got %h", expected, got);
        $finish;
      end
    end
  endtask

  reg [`memory_data_width - 1:0] mem_image [0:MEM_WORDS - 1];

  task load_mem_image;
    integer idx;
    begin
      for (idx = 0; idx < MEM_WORDS; idx = idx + 1) begin
        mem_image[idx] = {`memory_data_width{1'b0}};
      end
      if (MEM_INIT_FILE != "") begin
        $readmemh(MEM_INIT_FILE, mem_image);
      end
    end
  endtask

  task uart_write_mem;
    integer idx;
    begin
      uart_send_byte("W");
      uart_send_u16(16'd0);
      uart_send_u16(MEM_WORDS[15:0]);
      for (idx = 0; idx < MEM_WORDS; idx = idx + 1) begin
        uart_send_u64(mem_image[idx]);
      end
      uart_expect_byte("w");
    end
  endtask

  task uart_reset;
    begin
      uart_send_byte("X");
      uart_expect_byte("x");
      wait_clks(CLKS_PER_BIT * 4);
    end
  endtask

  task uart_start;
    input [15:0] addr;
    begin
      uart_send_byte("S");
      uart_send_u16(addr);
      uart_expect_byte("s");
    end
  endtask

  task uart_poll;
    output [7:0] flags;
    output [7:0] err;
    output [7:0] edit_err;
    output [7:0] hint_tag;
    output [31:0] hint;
    output [31:0] root_ptr;
    output [31:0] free_ptr;
    reg [7:0] rx_byte;
    integer i;
    begin
      uart_send_byte("P");
      uart_expect_byte("p");
      uart_read_byte(flags);
      uart_read_byte(err);
      uart_read_byte(edit_err);
      uart_read_byte(hint_tag);
      hint = 0;
      for (i = 0; i < 4; i = i + 1) begin
        uart_read_byte(rx_byte);
        hint = hint | ({24'b0, rx_byte} << (8*i));
      end
      root_ptr = 0;
      for (i = 0; i < 4; i = i + 1) begin
        uart_read_byte(rx_byte);
        root_ptr = root_ptr | ({24'b0, rx_byte} << (8*i));
      end
      free_ptr = 0;
      for (i = 0; i < 4; i = i + 1) begin
        uart_read_byte(rx_byte);
        free_ptr = free_ptr | ({24'b0, rx_byte} << (8*i));
      end
    end
  endtask

  task uart_read_mem;
    input [15:0] addr;
    input [15:0] count;
    output [`memory_data_width - 1:0] word0;
    reg [7:0] rx_byte;
    integer i;
    begin
      uart_send_byte("R");
      uart_send_u16(addr);
      uart_send_u16(count);
      uart_expect_byte("r");
      word0 = 0;
      for (i = 0; i < 8; i = i + 1) begin
        uart_read_byte(rx_byte);
        word0 = word0 | ({56'b0, rx_byte} << (8*i));
      end
    end
  endtask

  integer poll_idx;
  reg [7:0] flags;
  reg [7:0] err;
  reg [7:0] edit_err;
  reg [7:0] hint_tag;
  reg [31:0] hint;
  reg [31:0] root_ptr;
  reg [31:0] free_ptr;
  reg [`memory_data_width - 1:0] read_word;
  reg poll_done;
  integer timeout_idx;
  integer rx_count;
  reg [7:0] rx_last0;
  reg [7:0] rx_last1;
  reg [7:0] rx_last2;
  reg [7:0] rx_last3;
  reg [4:0] max_tx_count;
  integer tx_start_count;
  integer rx_log_idx;
  reg [7:0] rx_log [0:255];

  initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;
  end

  initial begin
    for (timeout_idx = 0; timeout_idx < SIM_TIMEOUT_CYCLES; timeout_idx = timeout_idx + 1) begin
      @(posedge clk);
    end
    $display("FAIL timeout state=%0d host_ready=%b busy=%b done=%b tx_count=%0d max_tx_count=%0d tx_start_count=%0d rx_wr=%0d rx_rd=%0d",
             dut.uart_ctrl.state,
             dut.host_ready,
             dut.busy,
             dut.done,
             dut.uart_ctrl.tx_count,
             max_tx_count,
             tx_start_count,
             rx_wr,
             rx_rd);
    $display("FAIL timeout rx_count=%0d last=%h %h %h %h",
             rx_count, rx_last3, rx_last2, rx_last1, rx_last0);
    if (rx_count > 0) begin
      $write("FAIL timeout rx_log:");
      for (rx_log_idx = 0; rx_log_idx < rx_count; rx_log_idx = rx_log_idx + 1) begin
        $write(" %02x", rx_log[rx_log_idx]);
      end
      $write("\n");
    end
    $finish;
  end

  initial begin
    UART_RX = 1'b1;
    KEY = 2'b00;
    rx_count = 0;
    rx_last0 = 8'h00;
    rx_last1 = 8'h00;
    rx_last2 = 8'h00;
    rx_last3 = 8'h00;
    max_tx_count = 5'b0;
    tx_start_count = 0;
    load_mem_image();

    wait_clks(10);
    KEY = 2'b11;

    uart_write_mem();
    uart_reset();
    uart_start(16'd1);

    poll_done = 1'b0;
    poll_idx = 0;
    while (poll_idx < MAX_POLLS && !poll_done) begin
      uart_poll(flags, err, edit_err, hint_tag, hint, root_ptr, free_ptr);
      if (flags[1]) begin
        poll_done = 1'b1;
      end else begin
        poll_idx = poll_idx + 1;
        wait_clks(CLKS_PER_BIT * 4);
      end
    end

    if (!poll_done) begin
      $display("FAIL poll timeout");
      $finish;
    end
    if (err != 8'h00 || edit_err != 8'h00) begin
      $display("FAIL error %h edit_error %h", err, edit_err);
      $finish;
    end

    if (root_ptr == 0) begin
      root_ptr = 32'd1;
    end
    uart_read_mem(root_ptr[15:0], 16'd1, read_word);
    if (EXPECTED_WORD1 !== 0 && read_word !== EXPECTED_WORD1) begin
      $display("FAIL expected word %h got %h", EXPECTED_WORD1, read_word);
      $finish;
    end

    $display("PASS");
    $finish;
  end

endmodule
