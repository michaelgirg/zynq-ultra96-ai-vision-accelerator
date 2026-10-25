# Job interrupts, timing and AXI watchdog

The mailbox now reports **whole firmware-job completion**, separate from the
accelerator's frame interrupt. Its level-high IRQ connects to PS interrupt concat
input 3 in the RV32 SoC build; DMA remains on inputs 0/1 and the accelerator on 2.
Use the generated BSP's interrupt identifiers, not a hard-coded GIC number.
The application remains polling-based; no interrupt-driven ARM driver is claimed.

## Register extension

Existing mailbox offsets `0x00`-`0x2C` are unchanged. All accesses are aligned
32-bit words. Writes require all four byte strobes; zero strobes are a no-op.
Unknown, read-only, partial or illegal writes return `SLVERR`.

| Offset | Register | Meaning |
| ---: | --- | --- |
| `0x030` | `VERSION` | Read-only `0x00010000`; required by the complete application |
| `0x034` | `IRQ_STATUS` | Sticky W1C: bit 0 complete, bit 1 fail, bit 2 AXI timeout |
| `0x038` | `IRQ_ENABLE` | Same three mask bits; reset to zero |
| `0x03C` | `DIAG_CONTROL` | Write 1 to clear captures/counters only while idle, acknowledged and not quarantined |
| `0x040` | `SUBMIT_LO` | Accepted-submit control-clock timestamp, low word |
| `0x044` | `SUBMIT_HI` | High word |
| `0x048` | `CLAIM_LO` | Accepted-claim timestamp, low word |
| `0x04C` | `CLAIM_HI` | High word |
| `0x050` | `END_LO` | Accepted complete/fail timestamp, low word |
| `0x054` | `END_HI` | High word |
| `0x058` | `JOB_CYCLES_LO` | End minus submit, low word |
| `0x05C` | `JOB_CYCLES_HI` | High word |
| `0x060` | `COMPLETED_COUNT` | Saturating successful-job count |
| `0x064` | `FAILED_COUNT` | Saturating failed-job count |
| `0x068` | `FW_TIMEOUT_COUNT` | Saturating count of fails published with firmware error 6 |
| `0x06C` | `AXI_TIMEOUT_COUNT` | Count of independent bridge timeout events; at most one per system reset |
| `0x070` | `FIRST_FAULT_KIND` | 0 none, 1 firmware failure, 2 AXI timeout |
| `0x074` | `FIRST_FAULT_JOB` | Job ID, or zero if no job is owned |
| `0x078` | `FIRST_FAULT_CODE` | Firmware error code; zero for AXI timeout |
| `0x07C` | `FIRST_FAULT_ADDR` | AXI address for an AXI first fault |
| `0x080` | `FIRST_FAULT_INFO` | AXI first-fault channel/direction mask |
| `0x084` | `FIRST_FAULT_WAIT` | AXI first-fault stalled-cycle threshold |
| `0x088` | `FIRST_FAULT_LO` | First-fault timestamp, low word |
| `0x08C` | `FIRST_FAULT_HI` | High word |
| `0x090` | `AXI_STATUS` | Live bit 0 timeout, bit 1 quarantined |
| `0x094` | `AXI_FAULT_ADDR` | Sticky bridge address, independent of an earlier firmware first fault |
| `0x098` | `AXI_FAULT_INFO` | Sticky bridge channel/direction mask |
| `0x09C` | `AXI_FAULT_WAIT` | Sticky bridge stalled-cycle threshold |

IRQ is `|(IRQ_STATUS & IRQ_ENABLE)`. Events latch even while masked. W1C only
acknowledges the interrupt, not the job. Job ACK clears complete/fail IRQ causes
and terminal ownership, but preserves timing/counters/first fault and the AXI
timeout cause. A new timeout event wins over simultaneous W1C/ACK. A held timeout
counts once; clearing its IRQ does not cause repeated interrupts for that event.

The 64-bit counter runs at the control clock. Submit clears the previous job's
claim/end/duration; complete/fail freezes the finished job's duration, including
claim latency and firmware orchestration, but not ARM cache maintenance or the
classifier. Read timestamp pairs while terminal and before another submit.
Event counters saturate rather than wrap; timestamp arithmetic is modulo 64 bits.
First-fault capture is retained until explicit diagnostic clear/system reset.

## Watchdog safety contract

`AXI_WATCHDOG_CYCLES` defaults to 1,000,000 control clocks (10 ms at 100 MHz).
It counts **consecutive clocks without an AXI handshake** while a transfer is
waiting. Any AW/W/B/AR/R handshake restarts the interval, including independent
AW and W progress. Progress on the threshold clock wins. CPU response
backpressure and a CPU held reset with no outstanding traffic are not slave timeouts.

Channel bits are AW=0, W=1, B=2, AR=3, R=4; bit 8 indicates a write. Multiple
bits can be set while both write channels wait. This is a progress watchdog,
not a bound on whole-transaction latency or a complete AXI protocol checker.

On timeout, the bridge latches the first address/mask/threshold and quarantines
new requests. **It does not drop VALID, synthesize a slave response, reset DMA,
ACK the mailbox, or declare the job cancelled.** It continues the outstanding
AXI transaction. If the slave eventually responds, the response drains and the
CPU receives a fault even for a late OKAY. Quarantine remains until coordinated
fabric/system reset. If the slave never responds, AXI remains pending.

Software CPU reset is separate from fabric reset. Reset during an in-flight
request preserves/drains the AXI transaction, discards its processor response,
and quarantines subsequent traffic. It does not by itself set the timeout IRQ;
`AXI_STATUS` still exposes quarantine. Reset while the bridge is idle is safe.
Do not hot-reload a polling controller with CPU reset alone: it may have an
outstanding MMIO read even when the mailbox appears idle. Use coordinated reset.

The complete application detects quarantine through the mailbox, snapshots its
diagnostics, and avoids DMA/accelerator reads, classification, buffer reuse and
job ACK. The standalone boot helper also checks mailbox version/quarantine before
loading firmware, submitting or acknowledging a job. Neither helper can repair
a fabric fault with CPU-only reset. The ARM mailbox path must remain reachable
independently of the stalled target. SmartConnect/PS fault-isolation behavior is not proven by the behavioral
fabric. This watchdog does not protect an ARM core already stalled in its own
MMIO access, nor make CPU-only or peripheral-only reset a safe recovery action.

## Local verification and deployment boundary

The [source-bound simulation record](evidence/job_diagnostics.json) reports
15,885 mailbox checks (320 randomized jobs / 20 seeds) and 184 watchdog checks, including six stalled
channel scenarios, late-response drain, exact timeout boundaries, processor
backpressure, CPU-reset abandonment and real bridge-to-mailbox fault IRQs. The
full SoC gate checks job IRQ/cause, timestamp ordering/duration and cumulative
success/failure counts for every job at all three stream clocks. These are
directed checks, not licensed covergroup/code-coverage closure claims.

The [32-step formal check](bounded_formal.md) uses a reduced four-clock threshold
to exercise expiration, sticky diagnostics, reset/drain and quarantine. It also
detects intentional payload and quarantine defects. It is not an unbounded or
liveness proof. The [native application](ultra96_application.md) checks the host
quarantine path with a functional model, not execution of RV32 firmware.

Run `scripts/run_riscv_regression.ps1`, `scripts/run_soc_end_to_end.ps1`,
`scripts/run_bounded_formal.py` and `scripts/validate_vision_app.py` using their
documented tool overrides. Source/header/register-document consistency is in CI.
The RTL and block-design wiring are now implemented in the
[October 24 Vivado checkpoint](implementation_signoff.md). That implementation
record is distinct from the simulation receipts above (their `vivado_rebuilt`
field describes the simulation-only gate). Licensed UVM evidence remains the
older baseline. Physical-board execution is not claimed.
