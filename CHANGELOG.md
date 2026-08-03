# Changelog

All notable changes to Gatework appear in this file.

The format follows the Keep a Changelog convention.
This project uses semantic versioning.

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
