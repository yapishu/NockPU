`include "memory_unit.vh"
module ram(
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
  (* ramstyle = "M10K" *) reg [`memory_data_width - 1:0] ram [0:RAM_DEPTH - 1];
  reg req_d;

  always @(posedge clock) begin
    req_d <= req;
    ready <= req_d;
    if (req) begin
`ifdef TRACE_RAM
      $display("ram req wren=%b addr1=%0d addr2=%0d data=%h", wren, address1, address2, data);
`endif
      if (wren) begin
        // On a write cycle, store the input data at the specified address.
        ram[address1] <= data;
        q2 <= ram[address2];
      end else begin
        // On a read cycle, output the data at the specified address.
        q1 <= ram[address1];
        q2 <= ram[address2];
      end
    end
  end
endmodule
