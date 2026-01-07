`include "memory_unit.vh"

module nockpu_axi_lite #(
  parameter integer AXI_ADDR_WIDTH = 12,
`ifdef NPU_STACK_DEPTH_TRAV
  parameter integer STACK_DEPTH_TRAV = `NPU_STACK_DEPTH_TRAV,
`else
  parameter integer STACK_DEPTH_TRAV = 2048,
`endif
`ifdef NPU_STACK_DEPTH_EQUAL
  parameter integer STACK_DEPTH_EQUAL = `NPU_STACK_DEPTH_EQUAL
`else
  parameter integer STACK_DEPTH_EQUAL = 2048
`endif
)(
  input clk,
  input rst,
  // AXI4-Lite slave interface (32-bit data).
  input [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  input s_axi_awvalid,
  output wire s_axi_awready,
  input [31:0] s_axi_wdata,
  input [3:0] s_axi_wstrb,
  input s_axi_wvalid,
  output wire s_axi_wready,
  output reg [1:0] s_axi_bresp,
  output reg s_axi_bvalid,
  input s_axi_bready,
  input [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  input s_axi_arvalid,
  output wire s_axi_arready,
  output reg [31:0] s_axi_rdata,
  output reg [1:0] s_axi_rresp,
  output reg s_axi_rvalid,
  input s_axi_rready,
  // AXI4-Stream input for bulk memory writes.
  input [63:0] s_axis_tdata,
  input s_axis_tvalid,
  input s_axis_tlast,
  output wire s_axis_tready,
  output wire core_done
);
  // Register map (byte offsets).
  localparam REG_CONTROL      = 6'h00;
  localparam REG_STATUS       = 6'h04;
  localparam REG_START_ADDR   = 6'h08;
  localparam REG_MEM_ADDR     = 6'h0C;
  localparam REG_MEM_WDATA_LO = 6'h10;
  localparam REG_MEM_WDATA_HI = 6'h14;
  localparam REG_MEM_CMD      = 6'h18;
  localparam REG_MEM_STATUS   = 6'h1C;
  localparam REG_MEM_RDATA_LO = 6'h20;
  localparam REG_MEM_RDATA_HI = 6'h24;
  localparam REG_HINT         = 6'h28;
  localparam REG_STREAM_CTRL  = 6'h2C;
  localparam REG_STREAM_STATUS = 6'h30;
  localparam REG_FREE_PTR     = 6'h34;
  localparam REG_ROOT_PTR     = 6'h38;

  localparam REG_CONTROL_W      = REG_CONTROL >> 2;
  localparam REG_STATUS_W       = REG_STATUS >> 2;
  localparam REG_START_ADDR_W   = REG_START_ADDR >> 2;
  localparam REG_MEM_ADDR_W     = REG_MEM_ADDR >> 2;
  localparam REG_MEM_WDATA_LO_W = REG_MEM_WDATA_LO >> 2;
  localparam REG_MEM_WDATA_HI_W = REG_MEM_WDATA_HI >> 2;
  localparam REG_MEM_CMD_W      = REG_MEM_CMD >> 2;
  localparam REG_MEM_STATUS_W   = REG_MEM_STATUS >> 2;
  localparam REG_MEM_RDATA_LO_W = REG_MEM_RDATA_LO >> 2;
  localparam REG_MEM_RDATA_HI_W = REG_MEM_RDATA_HI >> 2;
  localparam REG_HINT_W         = REG_HINT >> 2;
  localparam REG_STREAM_CTRL_W  = REG_STREAM_CTRL >> 2;
  localparam REG_STREAM_STATUS_W = REG_STREAM_STATUS >> 2;
  localparam REG_FREE_PTR_W     = REG_FREE_PTR >> 2;
  localparam REG_ROOT_PTR_W     = REG_ROOT_PTR >> 2;

  // AXI-lite write holding.
  reg aw_valid;
  reg [AXI_ADDR_WIDTH-1:0] aw_addr;
  reg w_valid;
  reg [31:0] w_data;
  reg [3:0] w_strb;

  assign s_axi_awready = !aw_valid && !s_axi_bvalid;
  assign s_axi_wready = !w_valid && !s_axi_bvalid;

  // AXI-lite read holding.
  reg ar_valid;
  reg [AXI_ADDR_WIDTH-1:0] ar_addr;
  assign s_axi_arready = !ar_valid && !s_axi_rvalid;

  function [31:0] apply_wstrb;
    input [31:0] old;
    input [31:0] data;
    input [3:0] strb;
    reg [31:0] result;
    begin
      result = old;
      if (strb[0]) result[7:0]   = data[7:0];
      if (strb[1]) result[15:8]  = data[15:8];
      if (strb[2]) result[23:16] = data[23:16];
      if (strb[3]) result[31:24] = data[31:24];
      apply_wstrb = result;
    end
  endfunction

  // Control registers.
  reg [`memory_addr_width - 1:0] start_addr_reg;
  reg [`memory_addr_width - 1:0] mem_addr_reg;
  reg [31:0] mem_wdata_lo;
  reg [31:0] mem_wdata_hi;
  reg [31:0] mem_rdata_lo;
  reg [31:0] mem_rdata_hi;
  reg [`memory_addr_width - 1:0] host_addr_reg;
  reg [`memory_data_width - 1:0] host_wdata_reg;
  reg start_pulse;
  reg mem_cmd_pulse;
  reg mem_cmd_we;
  reg stream_start_pulse;
  reg stream_abort_pulse;
  reg stream_status_clear;

  // Memory command state.
  reg mem_busy;
  reg mem_done;
  reg mem_error;
  reg host_req;
  reg host_we;
  reg mem_issued;
  reg mem_status_clear;
  reg mem_cmd_invalid;
  reg stream_active;
  reg stream_pending;
  reg stream_done;
  reg stream_error;
  reg stream_last_buf;
  reg stream_last_inflight;
  reg [`memory_addr_width - 1:0] stream_addr;
  reg [`memory_data_width - 1:0] stream_data_buf;

  // Core wires.
  wire host_ready;
  wire host_rvalid;
  wire [`memory_data_width - 1:0] host_rdata;
  wire busy;
  wire done;
  wire [7:0] error;
  wire [7:0] edit_error;
  wire [`noun_width-1:0] hint;
  wire hint_tag;
  wire [`memory_addr_width - 1:0] free_ptr;
  wire [`memory_addr_width - 1:0] root_ptr;

  wire stream_fire;
  assign s_axis_tready = stream_active && !stream_pending && !stream_last_inflight && !busy && !mem_busy;
  assign stream_fire = s_axis_tvalid && s_axis_tready;

  // Instantiate core.
  nockpu_top #(
    .STACK_DEPTH_TRAV (STACK_DEPTH_TRAV),
    .STACK_DEPTH_EQUAL (STACK_DEPTH_EQUAL)
  ) core(
    .clk (clk),
    .rst (rst),
    .start (start_pulse && !stream_active && !stream_pending),
    .start_addr (start_addr_reg),
    .host_req (host_req),
    .host_we (host_we),
    .host_addr (host_addr_reg),
    .host_wdata (host_wdata_reg),
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
  assign core_done = done;

  // AXI write handling.
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      aw_valid <= 1'b0;
      aw_addr <= {AXI_ADDR_WIDTH{1'b0}};
      w_valid <= 1'b0;
      w_data <= 32'b0;
      w_strb <= 4'b0;
      s_axi_bresp <= 2'b00;
      s_axi_bvalid <= 1'b0;

      start_addr_reg <= {`memory_addr_width{1'b0}};
      mem_addr_reg <= {`memory_addr_width{1'b0}};
      mem_wdata_lo <= 32'b0;
      mem_wdata_hi <= 32'b0;
      start_pulse <= 1'b0;
      mem_cmd_pulse <= 1'b0;
      mem_cmd_we <= 1'b0;
      stream_start_pulse <= 1'b0;
      stream_abort_pulse <= 1'b0;
      stream_status_clear <= 1'b0;
      mem_status_clear <= 1'b0;
      mem_cmd_invalid <= 1'b0;
    end else begin
      start_pulse <= 1'b0;
      mem_cmd_pulse <= 1'b0;
      stream_start_pulse <= 1'b0;
      stream_abort_pulse <= 1'b0;
      stream_status_clear <= 1'b0;
      mem_status_clear <= 1'b0;
      mem_cmd_invalid <= 1'b0;

      if (s_axi_awready && s_axi_awvalid) begin
        aw_addr <= s_axi_awaddr;
        aw_valid <= 1'b1;
      end
      if (s_axi_wready && s_axi_wvalid) begin
        w_data <= s_axi_wdata;
        w_strb <= s_axi_wstrb;
        w_valid <= 1'b1;
      end

      if (aw_valid && w_valid && !s_axi_bvalid) begin
        case (aw_addr[AXI_ADDR_WIDTH-1:2])
          REG_CONTROL_W: begin
            if (w_data[0]) start_pulse <= 1'b1;
          end
          REG_START_ADDR_W: begin
            start_addr_reg <= apply_wstrb({{(32-`memory_addr_width){1'b0}}, start_addr_reg}, w_data, w_strb);
          end
          REG_MEM_ADDR_W: begin
            mem_addr_reg <= apply_wstrb({{(32-`memory_addr_width){1'b0}}, mem_addr_reg}, w_data, w_strb);
          end
          REG_MEM_WDATA_LO_W: begin
            mem_wdata_lo <= apply_wstrb(mem_wdata_lo, w_data, w_strb);
          end
          REG_MEM_WDATA_HI_W: begin
            mem_wdata_hi <= apply_wstrb(mem_wdata_hi, w_data, w_strb);
          end
          REG_MEM_CMD_W: begin
            mem_cmd_we <= w_data[1];
            if (w_data[0] ^ w_data[1]) begin
              mem_cmd_pulse <= 1'b1;
            end else if (w_data[0] && w_data[1]) begin
              mem_cmd_invalid <= 1'b1;
            end
          end
          REG_MEM_STATUS_W: begin
            mem_status_clear <= 1'b1;
          end
          REG_STREAM_CTRL_W: begin
            if (w_data[0]) stream_start_pulse <= 1'b1;
            if (w_data[1]) stream_abort_pulse <= 1'b1;
          end
          REG_STREAM_STATUS_W: begin
            stream_status_clear <= 1'b1;
          end
          default: begin
          end
        endcase

        s_axi_bvalid <= 1'b1;
        s_axi_bresp <= 2'b00;
        aw_valid <= 1'b0;
        w_valid <= 1'b0;
      end

      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end
    end
  end

  // AXI read handling.
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      ar_valid <= 1'b0;
      ar_addr <= {AXI_ADDR_WIDTH{1'b0}};
      s_axi_rdata <= 32'b0;
      s_axi_rresp <= 2'b00;
      s_axi_rvalid <= 1'b0;
      mem_rdata_lo <= 32'b0;
      mem_rdata_hi <= 32'b0;
    end else begin
      if (s_axi_arready && s_axi_arvalid) begin
        ar_addr <= s_axi_araddr;
        ar_valid <= 1'b1;
      end

      if (ar_valid && !s_axi_rvalid) begin
        case (ar_addr[AXI_ADDR_WIDTH-1:2])
          REG_STATUS_W: begin
            s_axi_rdata <= {
              hint_tag,
              6'b0,
              edit_error,
              error,
              mem_error,
              mem_done,
              mem_busy,
              host_ready,
              done,
              busy
            };
          end
          REG_START_ADDR_W: begin
            s_axi_rdata <= {{(32-`memory_addr_width){1'b0}}, start_addr_reg};
          end
          REG_MEM_ADDR_W: begin
            s_axi_rdata <= {{(32-`memory_addr_width){1'b0}}, mem_addr_reg};
          end
          REG_MEM_WDATA_LO_W: begin
            s_axi_rdata <= mem_wdata_lo;
          end
          REG_MEM_WDATA_HI_W: begin
            s_axi_rdata <= mem_wdata_hi;
          end
          REG_MEM_STATUS_W: begin
            s_axi_rdata <= {29'b0, mem_error, mem_done, mem_busy};
          end
          REG_MEM_RDATA_LO_W: begin
            s_axi_rdata <= mem_rdata_lo;
          end
          REG_MEM_RDATA_HI_W: begin
            s_axi_rdata <= mem_rdata_hi;
          end
          REG_HINT_W: begin
            s_axi_rdata <= {4'b0, hint};
          end
          REG_FREE_PTR_W: begin
            s_axi_rdata <= {{(32-`memory_addr_width){1'b0}}, free_ptr};
          end
          REG_ROOT_PTR_W: begin
            s_axi_rdata <= {{(32-`memory_addr_width){1'b0}}, root_ptr};
          end
          REG_STREAM_STATUS_W: begin
            s_axi_rdata <= {28'b0, stream_error, stream_done, stream_pending, stream_active};
          end
          default: begin
            s_axi_rdata <= 32'b0;
          end
        endcase
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b1;
        ar_valid <= 1'b0;
      end

      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      if (host_rvalid) begin
        mem_rdata_lo <= host_rdata[31:0];
        mem_rdata_hi <= host_rdata[63:32];
      end
    end
  end

  // Memory command FSM (idle core only).
  localparam MEM_IDLE        = 3'b000;
  localparam MEM_ISSUE       = 3'b001;
  localparam MEM_WAIT_READ   = 3'b010;
  localparam MEM_WAIT_WRITE  = 3'b011;
  localparam MEM_STREAM_ISSUE = 3'b100;
  localparam MEM_STREAM_WAIT  = 3'b101;
  reg [2:0] mem_state;

  // Stream loader state.
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      stream_active <= 1'b0;
      stream_pending <= 1'b0;
      stream_done <= 1'b0;
      stream_error <= 1'b0;
      stream_last_buf <= 1'b0;
      stream_last_inflight <= 1'b0;
      stream_addr <= {`memory_addr_width{1'b0}};
      stream_data_buf <= {`memory_data_width{1'b0}};
    end else begin
      if (stream_status_clear) begin
        stream_done <= 1'b0;
        stream_error <= 1'b0;
      end

      if (stream_fire) begin
        stream_data_buf <= s_axis_tdata;
        stream_last_buf <= s_axis_tlast;
        stream_pending <= 1'b1;
      end

      if (mem_state == MEM_STREAM_ISSUE && host_ready) begin
        stream_last_inflight <= stream_last_buf;
        stream_addr <= stream_addr + 1'b1;
      end

      if (mem_state == MEM_STREAM_WAIT && host_ready) begin
        stream_pending <= 1'b0;
        if (stream_last_inflight) begin
          stream_active <= 1'b0;
          stream_done <= 1'b1;
          stream_last_inflight <= 1'b0;
        end
      end

      if (stream_abort_pulse) begin
        stream_active <= 1'b0;
        stream_pending <= 1'b0;
        stream_done <= 1'b0;
        stream_last_inflight <= 1'b0;
        stream_error <= 1'b1;
      end else if (stream_start_pulse) begin
        if (stream_active || mem_state != MEM_IDLE || mem_cmd_pulse || busy) begin
          stream_error <= 1'b1;
        end else begin
          stream_active <= 1'b1;
          stream_done <= 1'b0;
          stream_pending <= 1'b0;
          stream_last_inflight <= 1'b0;
          stream_addr <= mem_addr_reg;
        end
      end
    end
  end

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      mem_state <= MEM_IDLE;
      mem_busy <= 1'b0;
      mem_done <= 1'b0;
      mem_error <= 1'b0;
      host_req <= 1'b0;
      host_we <= 1'b0;
      mem_issued <= 1'b0;
      host_addr_reg <= {`memory_addr_width{1'b0}};
      host_wdata_reg <= {`memory_data_width{1'b0}};
    end else begin
      host_req <= 1'b0;
      if (mem_status_clear) begin
        mem_done <= 1'b0;
        mem_error <= 1'b0;
      end
      if (mem_cmd_invalid) begin
        mem_error <= 1'b1;
      end
      if (mem_cmd_pulse && (mem_state != MEM_IDLE || stream_active)) begin
        mem_error <= 1'b1;
      end
      case (mem_state)
        MEM_IDLE: begin
          mem_issued <= 1'b0;
          mem_busy <= 1'b0;
          if (mem_cmd_pulse) begin
            if (busy || stream_active) begin
              mem_error <= 1'b1;
            end else begin
              mem_busy <= 1'b1;
              host_we <= mem_cmd_we;
              host_addr_reg <= mem_addr_reg;
              host_wdata_reg <= {mem_wdata_hi, mem_wdata_lo};
              mem_state <= MEM_ISSUE;
            end
          end else if (stream_active && stream_pending) begin
            if (busy) begin
              mem_error <= 1'b1;
            end else begin
              mem_busy <= 1'b1;
              host_we <= 1'b1;
              host_addr_reg <= stream_addr;
              host_wdata_reg <= stream_data_buf;
              mem_state <= MEM_STREAM_ISSUE;
            end
          end
        end
        MEM_ISSUE: begin
          mem_busy <= 1'b1;
          host_req <= 1'b1;
          if (host_ready) begin
            mem_issued <= 1'b1;
            mem_state <= host_we ? MEM_WAIT_WRITE : MEM_WAIT_READ;
          end
        end
        MEM_WAIT_READ: begin
          mem_busy <= 1'b1;
          if (host_rvalid) begin
            mem_done <= 1'b1;
            mem_busy <= 1'b0;
            mem_state <= MEM_IDLE;
          end
        end
        MEM_WAIT_WRITE: begin
          mem_busy <= 1'b1;
          if (host_ready) begin
            mem_done <= 1'b1;
            mem_busy <= 1'b0;
            mem_state <= MEM_IDLE;
          end
        end
        MEM_STREAM_ISSUE: begin
          mem_busy <= 1'b1;
          host_req <= 1'b1;
          if (host_ready) begin
            mem_state <= MEM_STREAM_WAIT;
          end
        end
        MEM_STREAM_WAIT: begin
          mem_busy <= 1'b1;
          if (host_ready) begin
            mem_busy <= 1'b0;
            mem_state <= MEM_IDLE;
          end
        end
        default: begin
          mem_state <= MEM_IDLE;
        end
      endcase
    end
  end

endmodule
