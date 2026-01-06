# NockPU

This repository contains Verilog code used to produce hardware that can execute Nock code directly. 

Design and Reference documentation along with a general chat can be found by joining the urbit group:

`~mopfel-winrux/NockPU`

## How to run

This project can be simulated with `iverilog` and the waveform can be viewed with `gtkwave`. Please make sure those are installed on your system.

To compile the project run

`iverilog -o npu.vvp -c command_file`

This will create a file called `npu.vvp`. This can be simulated with `vvp` using the following command

`vvp npu.vvp`

When the simulation stops you can type `finish` to stop the simulation. This will create a file called `waveform.vcd` which will contain the waveform of the model.

This can be viewed using `gtkwave`:

`gtkwave waveform.vcd`

## Regression Tests

You can run the Nock opcode regression suite (simulation + reference evaluator) with:

`python3 scripts/regress_nock.py`

This uses the `execute_tb` testbench with `+mem=...` and `+dump=...` plusargs, and checks output nouns against a software Nock evaluator.

## Core Top-Level (nockpu_top)

`verilog/nockpu_top.v` wires the full core (memory unit, traversal, execute, and helper blocks) and exposes a simple host memory interface for loading nouns and reading results while the core is idle.

- `start` begins evaluation; `start_addr` selects the root (typically `1`).
- `busy` is high while running; `done` latches high when traversal finishes until the next `start`.
- `host_req/host_we/host_addr/host_wdata` issue a single read or write when `host_ready` is high.
- `host_rvalid/host_rdata` return read data after a host read completes.
- `hint/hint_tag` mirror op11 hints from the execute module (no valid strobe; last hint is retained).
- When loading a fresh memory image, toggle `rst` after writes so the memory unit reloads `free_mem` from address 0 before `start`.

To run the host-interface smoke test:

```
iverilog -g2012 -s nockpu_top_tb -o nockpu_top_tb.vvp -c command_file verilog/nockpu_top.v testbenches/nockpu_top_tb.v
vvp nockpu_top_tb.vvp +mem=memory/constant_tb.hex
```

## AXI4-Lite Wrapper (nockpu_axi_lite)

`verilog/nockpu_axi_lite.v` wraps `nockpu_top` with a 32-bit AXI4-Lite slave. It exposes control/status plus a host memory command interface and an AXI4-Stream bulk loader for writing nouns while the core is idle.

Register map (byte offsets):

- `0x00` CONTROL: bit0 `start` (write 1 to launch)
- `0x04` STATUS: bit0 `busy`, bit1 `done`, bit2 `host_ready`, bit3 `mem_busy`, bit4 `mem_done`, bit5 `mem_error`, bits[15:8] `error`, bits[23:16] `edit_error`, bit24 `hint_tag`
- `0x08` START_ADDR: start address (use `1` for root)
- `0x0C` MEM_ADDR: memory address for host read/write
- `0x10` MEM_WDATA_LO: write data [31:0]
- `0x14` MEM_WDATA_HI: write data [63:32]
- `0x18` MEM_CMD: bit0 `read`, bit1 `write` (write 1 to start)
- `0x1C` MEM_STATUS: bit0 `mem_busy`, bit1 `mem_done`, bit2 `mem_error` (write any value to clear done/error)
- `0x20` MEM_RDATA_LO: read data [31:0]
- `0x24` MEM_RDATA_HI: read data [63:32]
- `0x28` HINT: hint noun [27:0]
- `0x2C` STREAM_CTRL: bit0 `start` (use MEM_ADDR as base), bit1 `abort`
- `0x30` STREAM_STATUS: bit0 `active`, bit1 `pending`, bit2 `done`, bit3 `error` (write any value to clear done/error)
- `0x34` FREE_PTR: free memory pointer (read-only)

Streaming writes sequential 64-bit words starting at `MEM_ADDR`. Assert `STREAM_CTRL.start`, then drive `s_axis_tdata` with `s_axis_tvalid` until `s_axis_tlast` marks the final word. The core start is gated while a stream is active; `s_axis_tready` deasserts while a write is in flight.
`AXI_ADDR_WIDTH` defaults to 12 to cover the full register map.
`FREE_PTR` mirrors the allocator head and is most useful while the core is idle.

To run the AXI-lite smoke test:

```
iverilog -g2012 -s nockpu_axi_lite_tb -o nockpu_axi_lite_tb.vvp -c command_file verilog/nockpu_top.v verilog/nockpu_axi_lite.v testbenches/nockpu_axi_lite_tb.v
vvp nockpu_axi_lite_tb.vvp +mem=memory/constant_tb.hex
```

## U55c Wrapper (nockpu_u55c)

`verilog/nockpu_u55c.v` exposes the AXI-lite and AXI-stream ports with Vitis-style naming (`ap_clk`, `ap_rst_n`, `s_axi_control_*`, `s_axis_mem_*`). The `interrupt` output mirrors the core `done` signal.

## Configuration Knobs

- `memory_addr_width` can be overridden at compile time with `-Dmemory_addr_width=<N>`; memory images must match the new depth.
- `mem_traversal` and `equal_block` accept a `STACK_DEPTH` parameter. The top-level wrappers expose `STACK_DEPTH_TRAV` and `STACK_DEPTH_EQUAL` parameters (defaults 2048).
- You can also override the wrapper defaults with `-DNPU_STACK_DEPTH_TRAV=<N>` and `-DNPU_STACK_DEPTH_EQUAL=<N>` at compile time.

# Project Layout

In the `verilog` folder there is the verilog code that can be synthesized into hardware. 

The `simulation` folder contains the ModelSim project files that are used to run simulations of the hardware.

The `synthesis` folder contains the Quartus project file that is used to synthesize the verilog code into hardware.

The `memory` folder contains memory files that can be loaded onto the synthesized SRAM.

The `testbenches` folder contains wrapper classes for different verilog modules to perform unit tests. 

It contains Quartus and ModelSim project files . The synthesis and simulation folders respectively


## Acknowledgement
This work has been made possible by a Grant from [Tacen](https://www.tacen.com).
