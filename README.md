# BPSK Modem (RTL)

SystemVerilog implementation of a BPSK modem. The current version (v1) is a digital loopback (tx→rx) with a built-in self-test (BIST), without a real DSP pipeline. The goal of v1 is to verify the framer/deframer, framing, and control logic on real hardware before adding the DSP chain and other operational modes.

## Status

- ✅ Framing/deframing, PRBS payload, CRC.
- ✅ BIST self-test with error counting and sync loss tracking.
- ✅ Single point of control (`modem_control`) with aggregated status.
- ⏳ Register map integration with APB interface implementation.
- ⏳ DSP chain (CIC/FIR/DDC/DUC) — not implemented, only fixed-point parameters are reserved in packages.

## Architecture

```
                         ┌────────────────┐
        adc_in_if ─────▶ │                │
        dac_out_if ◀──── │   modem_core   │
        tx_data_in  ───▶ │                │ ───▶ rx_data_out
        modem_ctrl  ───▶ │                │ ───▶ modem_status
                         └────────────────┘
                          │      │      │
                    ┌─────┘      │      └─────┐
                    ▼            ▼             ▼
               modem_tx   modem_control   modem_rx
                    │            │             │
         ┌──────────┼──────┐     │      ┌──────┼──────────┐
         ▼          ▼      ▼     │      ▼      ▼          ▼
    prbs_gen   tx_control  mapper│  deframer  rx_control  (framer — общий с tx)
                                 │
                         (agregation of control/status,
                          FSM: IDLE → ACTIVE → BIST)
```

In v1 `tx_signal` (the output of `modem_tx`) connects directly to `rx_signal` (the input of `modem_rx`) inside `modem_core` via a controlled multiplexer (`digital_loopback`),  bypassing the real DSP pipeline and the `adc_in_if`/`dac_out_if` ports.

### Repository Structure

```
rtl/
├── modem_core.sv          # top level: tx + rx + modem_control, digital-loopback multiplexer
├── modem_tx.sv
├── modem_rx.sv
├── submodules/
│   ├── modem_control.sv   # supervisory FSM: on/off, BIST trigger, status aggregation
│   ├── tx_control.sv      # FSM for transmitting BIST traffic
│   ├── rx_control.sv      # FSM for receiving/measuring BIST, sync loss watchdog
│   ├── framer.sv
│   ├── deframer.sv
│   ├── mapper.sv
│   └── prbs_gen.sv
└── common/
    ├── packages/          # bpsk_modem_pkg, bpsk_tx_pkg, bpsk_rx_pkg
    ├── interfaces/        # axis_if — AXI-Stream-like interface (modports master/slave/monitor)
    ├── macros/            # axis_checks.svh — axis_if consistency checks during elaboration
    └── rtl/               # reusable primitives (posedge_gen, etc.)

sim/
└── targets/               # testbenches, one per module/level (modem_core_tb, framer_tb, ...)
```

### Architectural Principles

- **Leaf modules** (`framer`, `deframer`, `mapper`, `prbs_gen`, `tx_control`, `rx_control`) do not import packages — all configuration is passed via `parameter`. This makes them reusable and testable in isolation.
- **Integration modules** (`modem_tx`, `modem_rx`, `modem_core`, `modem_control`) import packages and bind specific configurations.
- **Control/status are grouped into packed structures** by domain instead of long lists of scalar ports: `tx_ctrl_t`/`tx_status_t`, `rx_ctrl_t`/`rx_status_t`, `modem_ctrl_t`/`modem_status_t` (in the corresponding packages).
- **Streaming connections** between DSP-oriented blocks use `axis_if`, with elaboration-time consistency checks for interface parameters (`axis_checks.svh`).

## Top Level: `modem_core`

| Port | Direction | Purpose |
|---|---|---|
| `clk`, `rst` | in | synchronous reset, single clock domain |
| `adc_in_if` | slave (in) | ADC input — reserved for v2, unused in v1 |
| `dac_out_if` | master (out) | DAC output — reserved for v2, unused in v1 |
| `tx_data_in` | slave (in) | transmitter payload input |
| `rx_data_out` | master (out) | receiver decoded payload output |
| `modem_ctrl` | in (`modem_ctrl_t`) | mode/commands: `modem_on`, `bist_start`, `bist_clear` |
| `modem_status` | out (`modem_status_t`) | aggregated status:  `bist_done`, `bist_active`, `bist_sync_lost`, `bist_pkt_match`, `crc_err_cnt`, `bist_bit_err_accum` |

## How to Build / Run Simulation

The simulation environment is automated via a unified QuestaSim script. You do not need to compile source files manually; the automation script handles dependency parsing and compilation automatically based on the selected target.
Testbenches are located in `sim/targets/<module>/` — one for each module plus the integration-level `modem_core_tb`. Example run for the top level in ModelSim/Questa:

```
cd sim
questasim -do "do common/run_target.do modem_core"
```

## Known Limitations of v1

- DSP pipeline is not implemented — only the fixed-point bit widths for future stages (CIC/FIR/DDC/DUC) are reserved in `bpsk_tx_pkg`/`bpsk_rx_pkg`.
- `adc_in_if`/`dac_out_if` are present in the `modem_core`, interface but do not participate in the v1 datapath.
- The only available mode is the digital loopback for the duration of the BIST run.
- Demodulation is hard-decision only.

## Roadmap
- **v1.1** — Complete all outstanding code technical debt marked as `TODO`. Expand testbench verification by implementing comprehensive code and functional coverage metrics to ensure maximum RTL stability.
- **v2** — real DSP chain (CIC/FIR/DDC/DUC) between `modem_tx`/`modem_rx` and `adc_in_if`/`dac_out_if`; analog loopback as an intermediate mode to verify DSP without a second device.
- **v3** — additional operational modes  (`MODE_RF`, `MODE_SERVICE`, `MODE_RX_ONLY`), expansion of `modem_control` (graceful shutdown, error handling), soft-decision demodulation.