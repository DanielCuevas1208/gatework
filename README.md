# Gatework

Gatework is an event-driven digital logic simulator in Haskell.
It parses a plain-text netlist, runs the circuit, and writes a VCD waveform file.
GTKWave and other waveform viewers can open the output.

## Value

Gatework makes digital state changes easy to inspect.

You can do these tasks:

- Simulate a ripple-carry adder from a netlist file.
- Simulate a four-bit counter from a netlist file.
- Open the VCD output in GTKWave and inspect the waveforms.
- Verify gate behavior with QuickCheck property tests.
- Compare the counter waveform with a repository golden file.

## Architecture

The project has four library modules.

| Module | Responsibility |
| --- | --- |
| `Gatework.Logic` | Defines logic values and gate functions |
| `Gatework.Netlist` | Parses and validates circuit files |
| `Gatework.Simulator` | Schedules signal changes |
| `Gatework.VCD` | Renders the waveform text |

The data flow is:

```text
netlist text -> parser -> typed model -> event queue -> waveform recorder -> VCD
```

The parser validates names, gate arity, drivers, clocks, and references.
The scheduler processes only changed signals.
A rising clock edge samples attached flip-flops together.
The recorder keeps the initial value and every later transition.
The VCD writer uses stable signal order and stable identifiers.

The repository layout is:

```text
src/                   library modules
app/                   command-line tool
test/                  test suite
fixtures/              circuit files and golden output
.github/workflows/     continuous integration
```

## Setup

Install GHC 9.6 and Cabal 3.10 or newer.

Build the package.

```powershell
cabal build
```

Run the test suite.

```powershell
cabal test --enable-tests
```

The frozen Cabal file pins the package versions.

### Run with Docker

You can also run the project in a container.
The container avoids a local Haskell install.

Build the image.

```powershell
docker build -t gatework-dev .
```

Run the test suite.

```powershell
docker run --rm -v "${PWD}:/work" -w /work gatework-dev sh -c "cabal update && cabal test --enable-tests"
```

The first run downloads the package index.
On Windows PowerShell, use the absolute repository path in the volume.

## Counter demo

Run the bundled counter.

```powershell
cabal run gatework -- --netlist fixtures/counter.net --duration 8 --output counter.vcd
```

The command writes this output:

```text
Wrote counter.vcd
Signals: 11
Duration: 8 time units
```

Open the waveform in GTKWave.

```powershell
gtkwave counter.vcd
```

The counter advances on rising clock edges.
Its value sequence is 0, 1, 2, 3, and 4.

| Time | q3 | q2 | q1 | q0 | Value |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 0 | 0 | 0 |
| 1 | 0 | 0 | 0 | 1 | 1 |
| 3 | 0 | 0 | 1 | 0 | 2 |
| 5 | 0 | 0 | 1 | 1 | 3 |
| 7 | 0 | 1 | 0 | 0 | 4 |

## Ripple-carry adder

Run three plus five with explicit input values.

```powershell
cabal run gatework -- --netlist fixtures/adder.net --duration 0 --output adder.vcd --set a0=1,a1=1,a2=0,a3=0,b0=1,b1=0,b2=1,b3=0,cin=0
```

The low-order bit uses index zero.
The adder produces binary 1000 for this example.

## Sample output

The file `fixtures/counter.golden.vcd` holds the complete counter waveform.
This excerpt shows the first timestamp:

```text
#0
0!
0"
0#
0$
0%
0&
1&
0'
0(
0)
0*
0+
#1
1!
1%
0&
1'
```

Each identifier is one signal.
The header maps identifiers to signal names.

## Netlist format

Use one declaration per line.
Use `#` for comments.
Gate inputs use commas without spaces.

```text
input a
input b
output y
wire n
wire y
clock clk period=2
gate NOT invert (a) -> n
gate AND combine (n,b) -> y
dff state clock=clk d=a q=state_q init=0
```

Supported gates are AND, OR, XOR, and NOT.
A gate output must have a `wire` declaration.
A flip-flop uses `clock=`, `d=`, `q=`, and optional `init=` fields.
Flip-flop clocks must be declared `clock` signals.
Clock periods use even integers of at least two.

## Verification

The test suite has two parts.
Deterministic tests cover parsing, validation, counter progression, adder carry propagation, and golden VCD output.
QuickCheck properties cover gate algebra and full adder correctness.

QuickCheck runs one hundred random cases for each property.
The gate properties cover the complete truth table.
The adder property compares the simulation with integer addition over random four-bit values.

## Test status

All tests pass on GHC 9.6.7 with Cabal 3.14 in the bundled container.
The CI workflow runs the same checks on Ubuntu with GHC 9.6.6.
The golden test compares the complete counter VCD text.
CI also runs both demos and compares the counter output with the golden file.

## Limitations

The simulator uses two-state logic: low and high.
Combinational loops stop with an event-limit error.
All gates use zero delay.
Zero-delay gates can show combinational settling transients at clock edges.
Input values cannot change during a run.
VCD output uses one module scope and one-bit signals.

## Roadmap

Later releases can remain independent:

1. Add scheduled input transitions.
2. Add reset pins and parameterized flip-flops.
3. Add richer VCD metadata and waveform assertions.
4. Add more gates and hierarchical netlists.

## License

Gatework uses the BSD 3-Clause License.
