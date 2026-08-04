# Changelog

All notable changes to Gatework appear in this file.

The format follows the Keep a Changelog convention.
This project uses semantic versioning.

## [0.16.0.0] - 2026-08-04

### Added

- Add the `BUF` gate for non-inverting signal transfer.
- Pass low, high, and unknown values through `BUF`.
- Convert floating `z` input to unknown `x` inside `BUF`.
- Support `BUF` on buses, modules, and delayed gate paths.
- Add a buffer waveform fixture, golden VCD, deterministic tests, and a QuickCheck property.

### Changed

- Bump the package version to 0.16.0.0.

## [0.15.0.0] - 2026-08-04

### Added

- Declare a flip-flop clock-to-output delay with the `tco=N` field.
- The output commits N time units after each rising clock edge.
- The delay applies to an asserted reset too.
- The edge captures the data value at the clock edge.
- A later data change does not affect the captured value.
- A wide register commits every bit together after its delay.
- Reject a negative, non-integer, or repeated tco field.
- Add a clock-to-output delay demo fixture and a golden waveform.
- Add deterministic tests and a QuickCheck property for the delay.

### Changed

- The scheduler commits flip-flop samples after their declared delay.
- Bump the package version to 0.15.0.0.
- Update the golden VCD files to the new version string.

## [0.14.0.0] - 2026-08-04

### Added

- Declare separate rise and fall delays with the `rise=N` and `fall=N` fields.
- A rising output transition fires after the rise delay.
- Any other transition fires after the fall delay.
- The `delay=N` field sets both delays to the same value.
- The `delay=N` field cannot combine with `rise=` or `fall=`.
- Reject negative, non-integer, repeated, and unknown delay fields.
- Add an asymmetric delay demo fixture and a golden waveform.
- Add deterministic tests and a QuickCheck property for asymmetric delays.

### Changed

- The scheduler picks the delay from the new output value.
- Bump the package version to 0.14.0.0.
- Update the golden VCD files to the new version string.

## [0.13.0.0] - 2026-08-03

### Added

- Declare a gate output delay with the `delay=N` field.
- A gate transition fires at the input time plus the delay.
- The delay applies to both rising and falling transitions.
- Delays accumulate through a chain of gates.
- The initial state settles at time zero without delay.
- Zero delay keeps the immediate gate behavior.
- Each driver of a shared wire commits with its own delay.
- Reject negative, non-integer, repeated, and unknown gate fields.
- Add a delay demo fixture and a golden waveform.
- Add deterministic tests and a QuickCheck property for gate delays.

### Changed

- The scheduler tracks one committed contribution per gate driver.
- A gate output changes only when the resolved wire value changes.
- A combinational loop with a consistent state settles.
- Only an oscillating loop stops with an event-limit error.
- Bump the package version to 0.13.0.0.
- Update the golden VCD files to the new version string.
- Update the clocked and adder goldens to the settled values.

## [0.12.0.0] - 2026-08-03

### Added

- Render each bus as one multi-bit vector in the VCD header.
- Group bus values into one line in the VCD timeline.
- Use the standard VCD vector syntax for the values.
- Include unknown and floating values inside vector strings.
- Detect module-internal buses after flattening.
- Add a four-state vector demo fixture and a golden waveform.
- Add deterministic tests and a QuickCheck property for vector output.
- Extend the CI workflow to run the vector demo.

### Changed

- Group all bus bits under one VCD variable and identifier.
- Bump the package version to 0.12.0.0.
- Update the golden VCD files to the new version string.
- Update the bus golden file to the vector format.

## [0.11.0.0] - 2026-08-03

### Added

- Set a whole input bus on the command line with one bit string.
- Accept whole-bus bit strings in the --set and --at options.
- The bit string lists the most-significant bit first.
- The value may use 0, 1, x, and z.
- Reject a value that does not match the bus width.
- Add deterministic tests and a QuickCheck property for whole-bus values.
- Run the bus demo with whole-bus values in the CI workflow.

### Changed

- Bump the package version to 0.11.0.0.

## [0.10.0.0] - 2026-08-03

### Added

- Add the report command to print the signal values as a text table.
- Each row shows one change time and every signal value.
- Print the report to standard output without the --output option.
- Write the report to a file with the --output option.
- Add a counter report golden file.
- Add deterministic tests and a QuickCheck property for the report.
- Extend the CI workflow to run the report demo.

### Changed

- Bump the package version to 0.10.0.0.
- Update the golden VCD files to the new version string.

## [0.9.0.0] - 2026-08-03

### Added

- Define reusable modules in separate library files.
- Load module libraries with the --library command-line option.
- Repeat --library to load more than one module library.
- A library file may contain only module definitions.
- A library module can use modules from another library.
- Reject a module name that appears more than once across files.
- Reject a main netlist that shadows a library module.
- Reject top-level declarations inside a library file.
- Prefix library parse errors with the file path.
- Add a library adder demo fixture and a golden waveform.
- Add deterministic tests and a QuickCheck property for library loading.

### Fixed

- Load library files with an explicit read error check.

## [0.8.0.0] - 2026-08-03

### Added

- Allow several gates to drive one wire.
- Resolve many driver values into one wire value.
- A floating (z) contribution is neutral during resolution.
- Known driver values dominate floating contributions.
- A low and a high together resolve to unknown (x).
- Any unknown contribution resolves to unknown.
- Two disabled tri-state buffers float the shared wire.
- Add a shared-bus demo fixture and a golden waveform.
- Add deterministic tests and a QuickCheck property for wire resolution.

### Changed

- The scheduler emits one resolved event per driven wire.
- A flip-flop output stays exclusive to its flip-flop.
- A gate cannot drive a flip-flop output.

## [0.7.0.0] - 2026-08-03

### Added

- Add multi-bit buses to input, output, and wire declarations with `NAME[WIDTH]`.
- Add bit references `NAME[i]` and slice references `NAME[hi:lo]`.
- A gate applies its function bitwise over equal-width references.
- A D flip-flop accepts bus data and bus output lists.
- Module input and output ports accept bus widths.
- Instance connections must match module port widths.
- Assertions address a single bus bit.
- Reject out-of-range indexes, invalid slices, and mixed gate widths.
- Reject dff data and output width mismatches.
- Reject conflicting widths for the same signal name.
- Add a bus demo fixture and a golden waveform.
- Add deterministic tests and QuickCheck properties for bus behavior.

### Changed

- Expand each bus into single-bit signals before simulation.
- Module input and output ports carry an explicit width.
- A flip-flop bus output requires a `wire` or `output` declaration.

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
