# NanoTrader FPGA Project Roadmap

## Status Key

- [x] Completed
- [ ] Not completed

## Priority Key

- **[M] Must:** Core project requirement
- **[S] Should:** Valuable, but can wait until the core works
- **[L] Later:** Complete only if time, hardware, and progress allow
- **[O] Ongoing:** Repeat throughout the project

---

## Phase 0: Build a Mini Pipeline Skeleton 

- [X] **Phase 0.1:** Establish the first RTL simulation latency baseline for:
  `parser → book → strategy → risk` **[M]**
- [X] **Phase 0.2:** Synthesize the mini pipeline and examine resource usage, timing, and inferred hardware **[M]** 

## Phase 1: Scale the Datapath From 1 Symbol/16-Bit to 8 Symbols/32-Bit 

- [X] **Phase 1.1:** ~~Implement and verify a fixed 8-symbol, 32-bit datapath **[M]**~~ implemented 4 symbols version
- [X] **Phase 1.2:** Refactor the design so the number of symbols is configurable using `NUM_SYMBOLS` **[M]**
- [X] **Phase 1.3:** _Test multiple configurations, such as 1, 4, 8, and 16 symbols_ **[S]**
- [ ] **Phase 1.5:** _Consider multiple parallel parser lanes and simultaneous book updates_ **[L]**
- [ ] **Phase 1.6:** ~~Deploy this version using an internal test generator, UART, LEDs, or ILA **[S, depends on board access]**~~(POSTPONE)
- [X] **Phase 1.7:** Compare latency, timing, and resource usage against Phase 0 **[M]** (note: ETA latency and sim latency secured)

## Phase 2: Add Valid/Ready Flow Control, FIFOs, and One Real Clock-Domain Crossing

- [ ] **Phase 2.1:** Add valid/ready flow control between pipeline modules **[M]**
- [ ] **Phase 2.2:** Add a synchronous FIFO and verify its behavior under backpressure **[M]**
- [ ] **Phase 2.3:** Implement and simulate an asynchronous FIFO between two clock domains **[M]**
- [ ] **Phase 2.4:** Deploy the FIFO/CDC test on hardware using two clocks **[S]**
- [ ] **Phase 2.5:** Measure how many cycles and nanoseconds the FIFO and CDC logic add **[M]**

## Phase 3: Learn Vendor Ethernet IP and AXI4-Stream; Write an RTL Ethernet/IPv4/UDP Parser

- [ ] **Phase 3.1:** Learn the AXI4-Stream handshake and packet-boundary signals **[M]**
- [ ] **Phase 3.2:** Learn how the selected board’s Ethernet MAC or vendor Ethernet IP connects to user RTL **[M]**
- [ ] **Phase 3.3:** Write an RTL parser for Ethernet, IPv4, and UDP headers **[M]**
- [ ] **Phase 3.4:** Test the parser using simulated Ethernet packets **[M]**
- [ ] **Phase 3.5:** Deploy using a board-supported Ethernet interface before attempting SFP+/10G **[S]**
- [ ] **Phase 3.6:** Measure packet-input-to-quote-output latency **[M]**

## Phase 4: Parse an Exchange-Style Market-Data Protocol

- [ ] **Phase 4.1:** Define a simplified exchange-style market-data message format **[M]**
- [ ] **Phase 4.2:** Parse message types, security IDs, prices, quantities, and sequence numbers **[M]**
- [ ] **Phase 4.3:** Filter messages using supported security IDs **[M]**
- [ ] **Phase 4.4:** Detect missing, duplicated, or out-of-order sequence numbers **[M]**
- [ ] **Phase 4.5:** Connect parsed market-data messages to the multi-symbol order book **[M]**
- [ ] **Phase 4.6:** Add order acknowledgements, rejects, fills, and cancels using an order-lifecycle FSM **[S, simplify to one outstanding order]**
- [ ] **Phase 4.7:** Measure the latency added by protocol parsing and order-state tracking **[M]**

## Phase 5: Full Hardware Deployment Using Ethernet

- [ ] **Phase 5.1:** Select a deployment board based on available Ethernet connectivity and FPGA resources **[S]**
- [ ] **Phase 5.2:** Deploy the complete market-data-to-order pipeline on a KC705, Zynq, PYNQ, or similar board **[S]**
- [ ] **Phase 5.3:** Send test packets from a host computer and verify hardware responses **[S]**
- [ ] **Phase 5.4:** Capture internal pipeline activity using ILA or hardware timestamps **[S]**
- [ ] **Phase 5.5:** Add SFP+/10G deployment after the lower-speed Ethernet version works **[L]**

## Phase 6: Ongoing Latency, Timing, and Resource Analysis

- [ ] **Phase 6.1:** Record RTL simulation latency in clock cycles at every major milestone **[M, O]**
- [ ] **Phase 6.2:** Record synthesis timing and resource reports at every major milestone **[M, O]**
- [ ] **Phase 6.3:** Record post-route timing reports after stable milestones **[S, O]**
- [ ] **Phase 6.4:** Convert cycle latency into nanoseconds using the achieved clock frequency **[M, O]**
- [ ] **Phase 6.5:** Perform hardware timestamp measurements and ILA verification **[S, O]**
- [ ] **Phase 6.6:** Identify the critical path and largest latency contributors **[M, O]**
- [ ] **Phase 6.7:** Optimize only when latency, timing, or resource usage becomes meaningfully worse **[S, O]**

> Phase 6 is ongoing. Check each item after performing it for the current milestone, then repeat the analysis after later milestones.

## Phase 7: Benchmark Against an Equivalent C++ Trading Pipeline

Implement an equivalent software pipeline containing:

- Packet parsing
- Book updates
- Strategy decisions
- Risk checks

Tasks:

- [ ] **Phase 7.1:** Write an equivalent C++ parser and trading pipeline **[L]**
- [ ] **Phase 7.2:** Verify that the FPGA and C++ implementations produce equivalent outputs **[L]**
- [ ] **Phase 7.3:** Measure software latency and throughput under controlled conditions **[L]**
- [ ] **Phase 7.4:** Compare FPGA and software latency, throughput, and determinism **[L]**
- [ ] **Phase 7.5:** Document the limitations of the comparison and avoid misleading benchmark claims **[L]**

## Phase 8: Automated Testing and Engineering Log

- [ ] **Phase 8.1:** Create automated regression tests for each completed module **[M, O]**
- [ ] **Phase 8.2:** Add tests for normal behavior, edge cases, resets, stalls, and malformed inputs **[M, O]**
- [ ] **Phase 8.3:** Maintain bug-and-fix records **[M, O]**
- [ ] **Phase 8.4:** Record design experiments and their results **[M, O]**
- [ ] **Phase 8.5:** Track timing, latency, and resource changes between versions **[M, O]**
- [ ] **Phase 8.6:** Record genuine reverted changes and explain why they were reverted **[M, O]**
- [ ] **Phase 8.7:** Maintain a lessons-learned section for each major milestone **[M, O]**



