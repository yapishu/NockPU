# DE10-Lite External Memory Plan

Goal: support larger heaps using the DE10-Lite onboard SDRAM while preserving
correctness and keeping resource usage modest.

## Assumptions

- DE10-Lite provides 64MB SDRAM (16-bit data bus). It does not include SRAM.
- We keep the current `memory_unit` API for the rest of the core.
- Speed is secondary to correctness and feature completeness.

## Approach

1. Pick a controller:
   - Short-term: Intel SDRAM Controller IP (Platform Designer/Qsys) for stable timing.
   - Long-term: a small open HDL SDRAM controller if we want portability.
2. Build a `ram_sdram.v` wrapper that matches the `ram.v` ports but adds latency
   handling and serialize dual-port access into a single SDRAM port.
3. Update `memory_unit` to tolerate variable read latency, potentially by:
   - Latching requests, then waiting for `ram_sdram_ready`.
   - Returning `is_ready` only after the SDRAM read data is valid.
4. Optionally add a tiny on-chip cache or write buffer to reduce SDRAM stalls.
5. Wire SDRAM pins in `verilog/nockpu_de10_uart.v` (or a new top-level) and add
   pin assignments in `synthesis/NPU_UI.qsf`.
6. Extend simulation with a simple SDRAM model or a behavioral stub that adds
   fixed latency, to keep unit tests working.
7. Update host tools to support larger `memory_addr_width` and bigger loads.

## Risks / Notes

- SDRAM is effectively single-port; the core's dual-port memory model will need
  arbitration and may lower throughput.
- Stackless traversal mutates memory; ensure the SDRAM controller supports
  back-to-back writes without losing ordering.
- Initialization/refresh must complete before the core starts.

## Next Actions

- Confirm SDRAM pin map and timing (DE10-Lite schematic + datasheet).
- Decide controller implementation and integrate a `ram_sdram.v` wrapper.
- Add a latency-aware path in `memory_unit` and update testbenches accordingly.
