# DE10-Lite UART Loader

This design adds a UART bridge for loading memory images, starting execution,
and reading results back over a simple binary protocol. It targets the DE10-Lite
MAX10 board and uses on-chip RAM inference (no external SRAM controller IP).

## Wiring

The DE10-Lite does not include a built-in USB-UART. Use an external USB-UART
adapter (3.3V TTL) wired to a GPIO header pin of your choice.

- `UART_RX` is FPGA input (connect USB-UART TX).
- `UART_TX` is FPGA output (connect USB-UART RX).

Assign the pins in `synthesis/NPU_UI.qsf` (search for the UART comment block).

## Protocol (little-endian, binary)

All commands are a single ASCII byte followed by payloads. Responses are a
single ASCII header byte followed by optional data.

- `W` (0x57) Write memory:
  - Payload: `addr` (u16), `count` (u16), then `count` 64-bit words.
  - Response: `w` (0x77) after all words are written.
- `R` (0x52) Read memory:
  - Payload: `addr` (u16), `count` (u16).
  - Response: `r` (0x72) then `count` 64-bit words.
- `S` (0x53) Start execution:
  - Payload: `start_addr` (u16).
  - Response: `s` (0x73) once start is accepted.
- `P` (0x50) Poll status:
  - Response: `p` (0x70) + 16-byte payload:
    - byte0: flags (bit0 busy, bit1 done)
    - byte1: error
    - byte2: edit_error
    - byte3: hint_tag
    - bytes4-7: hint (u32, low 28 bits used)
    - bytes8-11: root_ptr (u32)
    - bytes12-15: free_ptr (u32)
- `X` (0x58) Reset core:
  - Response: `x` (0x78); core reset is pulsed for a few cycles.

## Host script

Use `scripts/nockpu_uart.py` (requires `pyserial`):

```
python3 scripts/nockpu_uart.py \
  --port /dev/ttyUSB0 \
  --mem memory/constant_tb.hex \
  --reset \
  --run \
  --poll \
  --decode
```

Notes:
- Load a memory hex file first; then pulse reset so the allocator reloads the
  free pointer from word 0.
- `--decode` reads back memory and prints the resulting noun using `root_ptr`.
  Adjust `--mem-depth` if you change `memory_addr_width`.
