# JTAG to APB Bridge (`jtag_apb_bridge`) Documentation

This document describes the RTL in `rtl/jtag_apb_bridge.sv`.

## 1) Overview

`jtag_apb_bridge` is a synthesizable bridge that exposes an **APB master** over a **JTAG TAP** interface.

- JTAG clock/reset domain: `tck`, `trst_n`
- APB clock/reset domain: `pclk`, `preset_n`
- CDC method: toggle-based request/response handshakes

The bridge supports three JTAG instructions:

1. **BYPASS**: single-bit bypass register
2. **IDCODE**: 32-bit fixed IDCODE register
3. **APBACC**: APB access data register used to issue APB reads/writes and return read data

---

## 2) Module Interface

```systemverilog
module jtag_apb_bridge #(
  parameter int IR_LEN = 4,
  parameter logic [31:0] IDCODE = 32'h1495_11C3
) (
  input  logic        tck,
  input  logic        tms,
  input  logic        tdi,
  input  logic        trst_n,
  output logic        tdo,

  input  logic        pclk,
  input  logic        preset_n,

  output logic        psel,
  output logic        penable,
  output logic        pwrite,
  output logic [31:0] paddr,
  output logic [31:0] pwdata,
  input  logic [31:0] prdata,
  input  logic        pready,
  input  logic        pslverr
);
```

### Parameters

- `IR_LEN` (default `4`): instruction register width.
- `IDCODE` (default `32'h1495_11C3`): value shifted out in IDCODE instruction.

---

## 3) TAP Controller

The RTL implements the IEEE 1149.1 standard TAP controller state machine with all 16 states:

- `TEST_LOGIC_RESET`, `RUN_TEST_IDLE`
- `SELECT_DR_SCAN`, `CAPTURE_DR`, `SHIFT_DR`, `EXIT1_DR`, `PAUSE_DR`, `EXIT2_DR`, `UPDATE_DR`
- `SELECT_IR_SCAN`, `CAPTURE_IR`, `SHIFT_IR`, `EXIT1_IR`, `PAUSE_IR`, `EXIT2_IR`, `UPDATE_IR`

### JTAG timing behavior

- State transitions occur on **`posedge tck`**.
- `tdo` is driven on **`negedge tck`**.
- On reset (`trst_n=0`), TAP goes to `TEST_LOGIC_RESET`.

---

## 4) Supported Instructions and Registers

Assuming `IR_LEN=4`:

| Instruction | Opcode | Register | Width | Description |
|---|---:|---|---:|---|
| `BYPASS` | `4'b1111` | bypass register | 1 | Standard JTAG bypass path |
| `IDCODE` | `4'b0010` | IDCODE register | 32 | Shifts out `IDCODE` parameter |
| `APBACC` | `4'b1000` | APB access DR | 65 | Issues APB access and returns read data |

### IR behavior

- During `CAPTURE_IR`, shift register captures `...01` in LSBs (IEEE 1149.1 behavior).
- During `SHIFT_IR`, `tdi` is shifted into MSB and LSB is shifted out on `tdo`.
- During `UPDATE_IR`, current instruction is updated.

### APBACC DR bit map

`APBACC_DR_LEN = 65`, shifted LSB-first:

- `bit[0]`      : `write_not_read` (`1`=write, `0`=read)
- `bit[32:1]`   : APB address (`paddr`)
- `bit[64:33]`  : APB write data (`pwdata`)

When `APBACC` is captured (`CAPTURE_DR`), DR is loaded with:

- `bit[0] = 0`
- `bit[32:1] = 0`
- `bit[64:33] = last_apb_read_data`

> Note: APB error status (`pslverr`) is captured internally but not currently serialized into APBACC DR.

---

## 5) APB Transaction Flow

A transaction is launched when:

1. TAP is in `UPDATE_DR`
2. Active instruction is `APBACC`

At that point, `write_not_read`, address, and write data are latched in TCK domain and a request toggle flips.

### APB FSM (PCLK domain)

- `APB_IDLE`   : waits for request pulse
- `APB_SETUP`  : drives setup phase (`psel=1`, `penable=0`)
- `APB_ACCESS` : drives access phase (`psel=1`, `penable=1`) until `pready=1`

On completion:

- `prdata` and `pslverr` are latched
- response toggle flips and is synchronized back into TCK domain

---

## 6) Clock Domain Crossing (CDC)

The bridge uses **toggle synchronizers** for both directions:

- **Request path**: `tck -> pclk`
  - `apb_req_toggle_tck` synchronized to PCLK with 2FF chain
  - XOR edge detect creates single-cycle `req_pulse_pclk`

- **Response path**: `pclk -> tck`
  - `apb_rsp_toggle_pclk` synchronized to TCK with 2FF chain
  - XOR edge detect creates single-cycle `rsp_pulse_tck`

This avoids direct pulse transfer across asynchronous domains.

---

## 7) Typical JTAG Read/Write Sequences

## APB Read

1. `SHIFT_IR/UPDATE_IR`: load `APBACC`
2. `SHIFT_DR`: shift in DR payload with
   - `write_not_read=0`
   - desired address in `[32:1]`
3. `UPDATE_DR`: launches APB read
4. wait enough TCK cycles for APB completion and CDC return
5. `CAPTURE_DR/SHIFT_DR` under `APBACC`: read data from `[64:33]`

## APB Write

1. `SHIFT_IR/UPDATE_IR`: load `APBACC`
2. `SHIFT_DR`: shift in DR payload with
   - `write_not_read=1`
   - desired address in `[32:1]`
   - write data in `[64:33]`
3. `UPDATE_DR`: launches APB write
4. optional subsequent `CAPTURE_DR/SHIFT_DR` can read back last read-data field

---

## 8) Reset Behavior Summary

- `trst_n=0` (JTAG reset domain)
  - TAP state -> `TEST_LOGIC_RESET`
  - instruction register -> `IDCODE`
  - shift/data path registers cleared to defaults

- `preset_n=0` (APB reset domain)
  - APB FSM -> `APB_IDLE`
  - APB outputs deasserted
  - response handshake cleared

---

## 9) Integration Notes

- This block is an APB **master** endpoint; connect outputs to APB interconnect/slaves accordingly.
- For asynchronous `tck` and `pclk`, keep CDC constraints and false-path/multicycle constraints consistent with your signoff methodology.
- If software/tools require explicit status bits in DR (busy/error/ack), extend APBACC format or add a dedicated status instruction.
