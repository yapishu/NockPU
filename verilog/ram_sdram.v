`include "memory_unit.vh"

// SDRAM wrapper stub: fixed-latency, single-port behavior with dual-read emulation.
module ram_sdram #(
  parameter integer LATENCY = 4
)(
  input wire clock,
  input wire [`memory_addr_width - 1:0] address1,
  input wire [`memory_addr_width - 1:0] address2,
  input wire [`memory_data_width - 1:0] data,
  input wire wren,
  input wire req,
  output reg [`memory_data_width - 1:0] q1,
  output reg [`memory_data_width - 1:0] q2,
  output reg ready
);

  localparam integer RAM_DEPTH = 1 << `memory_addr_width;
  reg [`memory_data_width - 1:0] ram [0:RAM_DEPTH - 1];

  reg busy;
  reg phase;
  reg [7:0] wait_ctr;
  reg [`memory_addr_width - 1:0] addr1_latched;
  reg [`memory_addr_width - 1:0] addr2_latched;

  initial begin
    busy = 1'b0;
    phase = 1'b0;
    wait_ctr = 8'b0;
    ready = 1'b0;
  end

  always @(posedge clock) begin
    ready <= 1'b0;
    if (!busy) begin
      if (req) begin
        addr1_latched <= address1;
        addr2_latched <= address2;
        phase <= 1'b0;
        wait_ctr <= LATENCY[7:0];
        busy <= 1'b1;
        if (wren) begin
          ram[address1] <= data;
        end
      end
    end else begin
      if (wait_ctr != 0) begin
        wait_ctr <= wait_ctr - 1'b1;
      end else if (!phase) begin
        q1 <= ram[addr1_latched];
        phase <= 1'b1;
        wait_ctr <= LATENCY[7:0];
      end else begin
        q2 <= ram[addr2_latched];
        busy <= 1'b0;
        ready <= 1'b1;
      end
    end
`ifdef TRACE_SDRAM
    if (req && !busy) begin
      $display("ram_sdram req wren=%b a1=%0d a2=%0d data=%h", wren, address1, address2, data);
    end
    if (ready) begin
      $display("ram_sdram ready q1=%h q2=%h", q1, q2);
    end
`endif
  end
endmodule
