# Changes vs master (main baseline)

This repository has no `master` branch. This document compares the current `reid`
worktree to `main` at merge-base commit `105ebf94c5aa7f303c1aa1a670de1735cd944480`
and includes uncommitted changes present when this file was written.

## Intent and priorities

- Feature completeness for Nock execution, including large atoms and large axes.
- Resource management correctness (allocator/GC/root tracking).
- Practical integration on real hardware (host access, AXI-lite, DE10-Lite UART, U55c).
- Test-driven confidence via regression and targeted unit tests.

## Summary of major deltas

- Added top-level wrappers (`nockpu_top`, `nockpu_axi_lite`, `nockpu_u55c`) to make
  the core practical to drive from a host and to target the U55c.
- Added a DE10-Lite UART loader path and a stackless traversal option for lower
  on-chip resource use.
- Reworked traversal + memory handling for GC safety, root tracking, and proper
  error propagation across all modules.
- Implemented large-atom and large-axis support across `slot`, `edit`, `+`, and `=`.
- Added a regression harness and new testbenches for GC, wrappers, and large-atom
  behavior.

## Detailed file list and rationale

### Top-level integration / wrappers

- `verilog/nockpu_top.v`: new core wrapper with host read/write interface, `busy/done`,
  `hint/hint_tag`, and `free_ptr/root_ptr`. Why: practical integration and host
  visibility into memory/results without re-synthesis.
- `verilog/nockpu_axi_lite.v`: new AXI4-Lite + AXI-stream wrapper with register map
  and bulk loader. Why: expose the core to a host bus and enable efficient noun loading.
- `verilog/nockpu_u55c.v`: new U55c-friendly wrapper with Vitis-style ports and
  `interrupt` wired to `done`. Why: direct deployment on the target board.
- `verilog/nockpu_de10_uart.v`: DE10-Lite top-level with UART loader and LED status.
  Why: bringup on a small MAX10 board without AXI.
- `verilog/nockpu_de10_uart.v`: added `USE_STACKLESS_TRAV` parameter (default 1)
  to control stackless traversal selection. Why: keep stackless optional while
  favoring the low-resource path on DE10-Lite.
- `verilog/nockpu_de10_uart.v`: added `USE_SDRAM`/`SDRAM_LATENCY` parameters to
  route memory through the SDRAM stub when desired. Why: hook up external-memory
  plumbing without committing to a full controller yet.
- `verilog/nockpu_uart_ctrl.v`, `verilog/uart_rx.v`, `verilog/uart_tx.v`: UART
  protocol and transport. Why: load memory, start execution, and fetch results
  over a simple serial link.
- `verilog/NPU_UI.v`: updated to instantiate `nockpu_top` instead of hand wiring
  traversal/execute/memory. Why: remove duplicate wiring and align board demo with
  the new top-level.

### Memory system and GC

- `verilog/memory_unit.vh`: `memory_addr_width` is now overrideable and `NIL_ADDR`
  / `ADDR_PAD` derive from it. Why: correct packing and scalable memory depth.
- `verilog/ram.v`: RAM depth derived from `memory_addr_width` and now uses a
  `req/ready` handshake to gate accesses (optional `TRACE_RAM` debug). Why:
  correct sizing plus a clean hook for variable-latency memory.
- `verilog/ram_sdram.v`: new SDRAM wrapper stub with fixed latency and serialized
  read phases. Why: stand-in for an external SDRAM controller while keeping the
  core interface stable.
- `verilog/memory_unit.v`: allocator/GC fixes (free pointer updates, `free_addr`
  set after GC, corrected max-memory mask, reset defaults, optional TRACE logging,
  and removed hard `$stop`). Added `free_ptr` output and a RAM `req/ready` handshake
  so reads/writes/GC wait on `ram_ready`. Why: robust resource management and a
  latency-tolerant memory interface for SDRAM.
- `verilog/memory_unit.v`: added `USE_SDRAM`/`SDRAM_LATENCY` to select the SDRAM
  stub and route memory outputs accordingly. Why: enable variable-latency external
  memory without breaking the existing tests.
- `verilog/mem_traversal.v`: explicit traversal stack with `STACK_DEPTH` parameter,
  `in_stack` guard, mem-ready edge handling, GC restart path, and `root_addr` output.
  Error propagation covers all modules. Why: deterministic traversal and GC safety.
- `verilog/mem_traversal_stackless.v`: restored pointer-reversal traversal as a
  low-resource option, updated for GC/root tracking and large atoms. Why: keep a
  stackless path for tight MAX10 resources.
- `verilog/mem_traversal_stackless.v`: fixed start-address capture on execute
  edge and gated reads/writes on `mem_ready` to avoid missed commands. Why:
  stackless traversal must not lose the first read after reset/start.
- `verilog/control_mux.v`: defaulted combinational outputs to avoid latches and
  stale signals. Why: safer muxing and correct return-state propagation.
- `verilog/execute.vh`: added traversal error codes for stackless/stackful faults.

### Execute and opcode helpers

- `verilog/execute.v`: removed `execute_tag` input (uses tags from `execute_data`);
  added large-axis handling for `slot` and `replace`, atom-formula init handling,
  tag-cleanup for const copy, and fixed op11 hint paths (static, dynamic, and
  large-atom static hints). Why: opcode completeness and correctness with large atoms/axes.
- `verilog/execute.v`: reset `hint`/`hint_tag` on reset (not per-exec) so hints
  persist for host polling while avoiding X-valued outputs after reset.
- `verilog/cell_block.v`: large-atom cells are treated as atoms for `cell`. Why:
  correct noun classification when large-atom headers appear.
- `verilog/incr_block.v`: supports large-atom increment with multi-limb carry, small
  overflow handling, and GC interaction; emits errors for invalid operands. Why:
  feature completeness for `+` on large atoms.
- `verilog/equal_block.v`: rewritten to iterative stack compare with `STACK_DEPTH`
  and large-atom support. Why: avoid deep recursion and handle large atoms.
- `verilog/edit_block.v`: added large-axis decoding (limb scan), `msb_index` helper,
  and extra error paths. Why: `slot`/`edit` correctness with large-axis values.

### Tooling, regression, and tests

- `scripts/regress_nock.py`: regression harness that runs `execute_tb`, decodes
  memory, evaluates reference Nock, compares results, supports forced GC, and checks
  op11 hint output. Why: repeatable correctness checks.
- `scripts/nockpu_uart.py`: UART host tool for load/start/poll/read/decode. Why:
  practical end-to-end use on DE10-Lite.
- `scripts/regress_nock.py`: added `--stackless` to compile tests with stackless
  traversal enabled. Why: validate the low-resource path in regression.
- `testbenches/execute_tb.v`: plusargs (`mem`, `dump`, `max_cycles`, `print_cycles`),
  cycle counting, GC tracing, hint output, root tracking, and combined error output.
  Why: regression driver and better debug visibility.
- `testbenches/execute_tb.v`: optional stackless traversal instantiation when
  `NPU_STACKLESS_TRAV=1` is defined. Why: allow regression to cover stackless mode.
- `testbenches/mem_traversal_tb.v`: updated for dual-port memory interface and
  timeout-based completion. Why: keep traversal tests aligned with the new core.
- `testbenches/mem_traversal_stackless_tb.v`: new stackless traversal smoke test.
- `testbenches/memory_unit_tb.v`: updated for dual-port memory, `free_ptr`, `gc_ready`,
  and read/write verification; `mem_request` timing avoids execute sampling races
  and optional debug prints were added. Why: validate allocator and memory API behavior.
- `testbenches/nockpu_top_tb.v`: new host-interface smoke test. Why: verify core
  integration and host memory access.
- `testbenches/nockpu_de10_uart_tb.v`: UART loader smoke test that writes memory,
  starts execution, polls status, and reads back the root. Why: validate DE10 UART
  control path end-to-end.
- `testbenches/nockpu_axi_lite_tb.v`: new AXI-lite/AXI-stream smoke test. Why:
  verify register map, loader, and control plane.
- `testbenches/gc_pressure_tb.v`: new GC stress test that forces low free space and
  checks root relocation. Why: validate GC under pressure.
- `testbenches/incr_block_gc_tb.v`: new unit test ensuring `incr_block` behaves
  correctly across GC events. Why: guard large-atom increment with GC interaction.
- `memory/traversal_only.hex`: minimal fixture for stackless traversal testing.

### Memory tooling and fixtures

- `memory/noun_converter.py`: emits large-atom chains in memory images. Why: build
  valid large-atom fixtures.
- `memory/decode_mem.py`: new memory decoder (supports large atoms). Why: inspect
  and debug memory outputs.
- `memory/gen_large_tests.py`: new generator for large-axis and large-atom tests.
  Why: systematic coverage for large-atom ops.
- `memory/large_atom_incr.hex`, `memory/large_atom_equal.hex`,
  `memory/large_axis_slot.hex`, `memory/large_axis_replace.hex`: new fixtures for
  large-atom and large-axis behavior. Why: regression and unit test inputs.

### Documentation and build

- `README.md`: added regression instructions, top-level/AXI/U55c wrapper docs,
  DE10 UART reference, and configuration knobs. Why: make new interfaces discoverable.
- `documents/de10_uart.md`: UART protocol and wiring guide. Why: bringup aid.
- `documents/de10_memory_plan.md`: external SDRAM integration plan for DE10-Lite.
  Why: roadmap for larger heaps beyond on-chip RAM.
- `synthesis/NPU_UI.qsf`: updated to DE10 UART top-level and RAM inference; notes
  for UART pin assignment. Why: working Quartus project for the DE10-Lite.

## Notes

- The baseline is `main` at `105ebf94c5aa7f303c1aa1a670de1735cd944480` because
  there is no `master` branch in this repo.
