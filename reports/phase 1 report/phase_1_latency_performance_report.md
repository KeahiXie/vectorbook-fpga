# Phase 1 Performance and Verification Report

## Design Overview

Phase 1 expands the original single-symbol trading pipeline into a parameterized multi-symbol design.

The current configuration supports:

- `NUM_SYMBOLS = 4`
- `PRICE_WIDTH = 32` bits
- `QUANTITY_WIDTH = 16` bits
- `125 MHz` clock
- One incoming market-data byte per clock cycle

## 1. Architecture

- Pipeline structure  
  `byte_stream -> parser_p1 -> order_book_array_p1 -> strategy_risk_array -> per-symbol order outputs`

- Packet format  

  | Byte | 0 | 1-4 | 5-6 | 7-10 | 11-12 |
  |---|---|---|---|---|---|
  | Field | Symbol ID | Bid price | Bid quantity | Ask price | Ask quantity |

- Expected latency  
  - Data transmission: 12 cycles from the first accepted byte to the final accepted byte
  - Parser publication: 1 cycle
  - Book update: 1 cycle
  - Strategy decision: 1 cycle
  - Risk decision: 1 cycle
  - Total latency: 16 cycles
  - Total latency at `125 MHz`: `128 ns`

## 2. RTL Simulation

The Phase 1 design was tested using:

- Vivado Simulator 2019.2
- Testbench: `vectorbook-fpga/tb/phase_1_top_tb.sv`
- Timescale: `1ns/1ps`
- Clock frequency: `125 MHz`
- Clock period: `8 ns`
- Input bytes change on the falling edge and are sampled on the rising edge

### 2.1 Test Configuration

#### 2.1.1 Strategy Configuration

- `min_spread = 5`
- `threshold = 2/1`
- `order_quantity = 50`

#### 2.1.2 Risk Configuration

- `max_quantity = 100`
- `trading_enable = 1`
- `kill_switch = 0`

#### 2.1.3 Test Case

Symbol 3, bid `1000/120`, ask `1020/40`  
Expected result: buy order at price `1020`, quantity `50`

### 2.2 Waveform

See `vectorbook-fpga/reports/waveforms`

### 2.3 Measured Latency

- First byte to final byte: 12 cycles = `96 ns`
- Final byte to `order_valid`: 4 cycles = `32 ns`
- Total latency: 16 cycles = `128 ns`

### 2.4 Functional Result

- `order_valid[3] = 1`
- `order_side[3] = 0` (`buy`)
- `order_price[3] = 1020`
- `order_quantity_out[3] = 50`
- Result: **PASS**

## 3. Synthesis and Implementation
- FPGA target
- LUT/FF/BRAM/DSP usage
- Timing summary
- Maximum frequency

## 4. Hardware Validation
- Board and clock
- Input method
- ILA measurements
- Comparison with simulation

## 5. Results Summary
- Total latency
- Processing latency
- Throughput
- Resource utilization
- Maximum verified frequency