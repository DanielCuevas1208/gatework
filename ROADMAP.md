# Gatework roadmap

This roadmap lists the next bounded simulator releases.
Each milestone names a user outcome, a deliverable, acceptance criteria, and local verification.

## Status

### `setup-hold-checks` — in progress

Users can declare setup and hold windows on each flip-flop.
Gatework reports timestamped findings and stores them beside the VCD waveform.

Implementation is complete, including deterministic waveform-preservation coverage.
Executable verification is blocked because this workspace lacks Cabal, GHC, and a running Docker daemon.
CI must confirm the acceptance criteria before this milestone becomes complete.

Acceptance criteria:

- Parse optional non-negative `setup=N` and `hold=N` fields.
- Treat a zero window as disabled.
- Report transitions at the setup-start and hold-end boundaries.
- Report simultaneous data and rising-clock transitions as setup findings.
- Export flip-flop, data, clock, data time, and clock time in CLI and VCD output.
- Preserve simulation state behavior and clean runs without timing windows.

Verification:

```text
cabal test --enable-tests
cabal run gatework -- --netlist fixtures/setuphold.net --duration 4 --output setuphold.vcd --set d=0 --at 0 d=1 --at 4 d=0
```

CI also checks the CLI findings and golden VCD output.
The deterministic suite checks that findings do not change simulated state.

### `counterexample-waveform` — planned

Users can stop an assertion run at its first failure and inspect a short trace.

Bounded deliverable:

- Add a command option that writes the shortest failing prefix beside the VCD.

Acceptance criteria:

- Stop at the first failed assertion.
- Include input transitions and affected signal changes through the failure time.
- Replay the prefix and produce the same verdict.
- Keep the trace deterministic across repeated runs.

Verification:

```text
cabal test --enable-tests
```

### `circuit-comparison` — planned

Users can compare two netlists against one finite input schedule.

Bounded deliverable:

- Add a comparison command with paired netlists and selected output signals.

Acceptance criteria:

- Apply one shared schedule to both circuits.
- Report output disagreements with timestamps.
- Pass equivalent circuits and identify an intentionally broken circuit.
- State the finite-schedule and selected-output scope in the report.

Verification:

```text
cabal test --enable-tests
```
