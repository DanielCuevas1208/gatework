# Changelog

All notable changes to Gatework appear in this file.

The format follows the Keep a Changelog convention.
This project uses semantic versioning.

## [0.6.0.0] - 2026-08-03

### Added

- Add two new logic values: unknown (x) and floating (z).
- Add the TRIBUF tri-state buffer gate with a data and an enable input.
- A disabled tri-state buffer floats its output to z.
- A gate reads a floating input as unknown.
- Undefined values propagate through combinational gates.
- Accept x and z in input assignments, flip-flop init lists, and assertions.
- VCD output uses x and z value characters.
- Bundle golden waveforms for a tri-state demo and an undefined-state demo.
- Add QuickCheck properties for the four-state model and the buffer truth table.

## [0.5.0.0] - 2026-08-03

### Added

- Add NAND, NOR, and XNOR gates.
- Add reusable modules with the module declaration.
- Add module instances with the instance declaration.
- Modules flatten into the top-level netlist before simulation.
- Use dotted names for the internal signals of an instance.
- Support flip-flops whose clock is a module input port.
- Support assertions and nested instances inside modules.
- Reject unknown modules, port-count mismatches, and circular instances.
- Bundle golden waveforms for a gate demo, a hierarchical adder, and a hierarchical counter.
- Add QuickCheck properties for the new gates and for hierarchy behavior.

## [0.4.0.0] - 2026-08-03

### Added

- Check netlist waveform assertions with the assert declaration.
- Assert syntax: assert SIGNAL = VALUE at TIME.
- Report each failed assertion with the expected and actual value.
- Write assertion text into the VCD header as a comment block.
- Bundle a golden waveform for an assertion demo.
- Add QuickCheck properties for assertion soundness.

## [0.3.0.0] - 2026-08-03

### Added

- Add an optional active-high reset pin to D flip-flops with the rst= field.
- Reset acts asynchronously and forces every bit to its initial value.
- Add width parameterization to D flip-flops with comma-separated d= and q= lists.
- Support an optional width= field and per-bit init lists.
- Bundle golden waveforms for a reset demo and a two-bit register demo.
- Add QuickCheck properties for reset sampling and register width.

### Changed

- Rename the flip-flop data and output fields to hold signal lists.

## [0.2.0.0] - 2026-08-03

### Added

- Change input signals at scheduled times with the --at option.
- Simulate a D flip-flop register with a scheduled data stream.
- Bundle a golden waveform for the register demo.
- Derive the VCD version header from the package version.
- Add QuickCheck properties for scheduled inputs and entry points.

### Fixed

- Add source-repository metadata so cabal check passes.

## [0.1.0.0] - 2026-08-03

- First coherent release of the simulation core.
