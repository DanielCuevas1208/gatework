# Gatework

Gatework is an event-driven digital logic simulator in Haskell.
It parses a plain-text netlist, runs the circuit, and writes a VCD waveform file.
GTKWave and other waveform viewers can open the output.
The simulator uses four logic values: low, high, unknown, and floating.

## Value

Gatework makes digital state changes easy to inspect.

You can do these tasks:

- Simulate a ripple-carry adder from a netlist file.
- Simulate a four-bit counter from a netlist file.
- Simulate a register with a scheduled data stream.
- Reset a flip-flop with an asynchronous reset pin.
- Build a multi-bit register from one flip-flop declaration.
- Use NAND, NOR, and XNOR gates alongside the basic gates.
- Define reusable modules and instantiate them many times.
- Build a hierarchical adder from half-adder and full-adder modules.
- Open the VCD output in GTKWave and inspect the waveforms.
- Verify gate behavior with QuickCheck property tests.
- Compare the counter waveform with a repository golden file.
- Check netlist behavior with waveform assertions.
- Inspect assertion metadata inside the VCD file.
- Use unknown (x) and floating (z) logic values.
- Drive a tri-state buffer from data and enable inputs.
- See an uninitialized flip-flop read as unknown.
- Watch a gate read a floating input as unknown.

## Architecture

The project has four library modules.

| Module | Responsibility |
| --- | --- |
| `Gatework.Logic` | Defines logic values and gate functions |
| `Gatework.Netlist` | Parses, validates, and flattens circuit files |
| `Gatework.Simulator` | Schedules signal changes |
| `Gatework.VCD` | Renders the waveform text |

The data flow is:

```text
netlist text -> parser -> module table -> flattened netlist -> event queue -> waveform recorder -> assertion check -> VCD
```

The parser validates names, gate arity, drivers, clocks, and references.
The parser expands each instance into the module gates.
The flattened netlist uses dotted names for instance signals.
The scheduler processes only changed signals.
A rising clock edge samples attached flip-flops together.
An asserted reset forces flip-flop outputs to their initial values.
The recorder keeps the initial value and every later transition.
The assertion checker compares declared expectations with the waveform.
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

## Register demo

Run a D flip-flop with a scheduled data stream.

```powershell
cabal run gatework -- --netlist fixtures/register.net --duration 8 --output register.vcd --set d=1 --at 2 d=0 --at 4 d=1 --at 6 d=0
```

The `--set` option sets the initial value at time zero.
The `--at` option changes an input at a fixed time.
The flip-flop samples the data input on each rising clock edge.

| Time | d | q |
| --- | --- | --- |
| 0 | 1 | 0 |
| 1 | 1 | 1 |
| 2 | 0 | 1 |
| 3 | 0 | 0 |
| 4 | 1 | 0 |
| 5 | 1 | 1 |
| 6 | 0 | 1 |
| 7 | 0 | 0 |

## Reset demo

Run a D flip-flop with an asynchronous reset.

```powershell
cabal run gatework -- --netlist fixtures/reset.net --duration 8 --output reset.vcd --set d=1 --at 2 rst=1 --at 4 rst=0 --at 6 d=0
```

The reset input `rst` is active high.
It forces the flip-flop back to its initial value without waiting for a clock edge.
The clock does not sample data while reset is high.

| Time | d | rst | q |
| --- | --- | --- | --- |
| 0 | 1 | 0 | 0 |
| 1 | 1 | 0 | 1 |
| 2 | 1 | 1 | 0 |
| 3 | 1 | 1 | 0 |
| 4 | 1 | 0 | 0 |
| 5 | 1 | 0 | 1 |
| 6 | 0 | 0 | 1 |
| 7 | 0 | 0 | 0 |

## Two-bit register demo

Run a two-bit register from one flip-flop declaration.

```powershell
cabal run gatework -- --netlist fixtures/reg2.net --duration 10 --output reg2.vcd --set d0=1,d1=0 --at 4 d0=0,d1=1 --at 6 rst=1 --at 8 rst=0,d0=1,d1=1
```

The `d=` and `q=` fields take comma-separated signal lists.
The register samples every bit on each rising clock edge.

| Time | d0 | d1 | rst | q0 | q1 |
| --- | --- | --- | --- | --- | --- |
| 0 | 1 | 0 | 0 | 0 | 0 |
| 1 | 1 | 0 | 0 | 1 | 0 |
| 4 | 0 | 1 | 0 | 1 | 0 |
| 5 | 0 | 1 | 0 | 0 | 1 |
| 6 | 0 | 1 | 1 | 0 | 0 |
| 8 | 1 | 1 | 0 | 0 | 0 |
| 9 | 1 | 1 | 0 | 1 | 1 |

## Gate demo

Run the universal gate truth demo.

```powershell
cabal run gatework -- --netlist fixtures/gates.net --duration 7 --output gates.vcd --set a=0,b=1 --at 2 a=1,b=1 --at 4 a=1,b=0 --at 6 a=0,b=0
```

The command writes this output:

```text
Wrote gates.vcd
Signals: 5
Duration: 7 time units
Assertions: 12 passed
```

The run walks the complete truth table of NAND, NOR, and XNOR.
Each assertion checks one row of one table.
The run reports a pass only when every assertion holds.

| Time | a | b | nand_out | nor_out | xnor_out |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | 1 | 1 | 0 | 0 |
| 2 | 1 | 1 | 0 | 0 | 1 |
| 4 | 1 | 0 | 1 | 0 | 0 |
| 6 | 0 | 0 | 1 | 1 | 1 |

## Hierarchical adder demo

Run the hierarchical ripple-carry adder.

```powershell
cabal run gatework -- --netlist fixtures/haddader.net --duration 0 --output haddader.vcd --set a0=1,a1=1,a2=0,a3=0,b0=1,b1=0,b2=1,b3=0,cin=0
```

The netlist defines a half-adder module and a full-adder module.
The full-adder module contains two half-adder instances.
The top level joins four full-adder instances in a carry chain.
The adder produces binary 1000 for three plus five.

## Hierarchical counter demo

Run the hierarchical four-bit counter.

```powershell
cabal run gatework -- --netlist fixtures/hcounter.net --duration 8 --output hcounter.vcd
```

The netlist defines a one-bit flop module.
The `counter4` module contains four flop instances.
The counter advances on rising clock edges.
Its value sequence is 0, 1, 2, 3, and 4.

## Assertion demo

Run a netlist that checks its own waveform.

```powershell
cabal run gatework -- --netlist fixtures/assert.net --duration 6 --output assert.vcd --set a=0,b=1 --at 3 a=1 --at 5 a=0
```

The command writes this output:

```text
Wrote assert.vcd
Signals: 4
Duration: 6 time units
Assertions: 3 passed
```

The fixture declares three expectations.
Each one checks the output `y` at a fixed time.
The run reports a pass only when every assertion holds.

| Time | a | b | y | Assertion |
| --- | --- | --- | --- | --- |
| 0 | 0 | 1 | 1 | `y = 1` holds |
| 3 | 1 | 1 | 0 | `y = 0` holds |
| 5 | 0 | 1 | 1 | `y = 1` holds |

A wrong expectation makes the run fail.
The error names the signal, the time, and both values.

```text
assertion failed: out must be 1 at time 2, but was 0
```

The run still writes the VCD file.
Use the file to inspect the waveform after the failure.

## Tri-state buffer demo

Run a tri-state buffer with a scheduled enable.

```powershell
cabal run gatework -- --netlist fixtures/tristate.net --duration 8 --output tristate.vcd --set d=0,en=0 --at 2 en=1 --at 4 d=1 --at 6 en=0
```

The command writes this output:

```text
Wrote tristate.vcd
Signals: 4
Duration: 8 time units
Assertions: 8 passed
```

The gate `TRIBUF` drives `y` only while `en` is high.
When `en` is low, `y` floats to `z`.
The gate `NOT` reads a floating input as unknown.

| Time | d | en | y | nz |
| --- | --- | --- | --- | --- |
| 0 | 0 | 0 | z | x |
| 3 | 0 | 1 | 0 | 1 |
| 5 | 1 | 1 | 1 | 0 |
| 7 | 1 | 0 | z | x |

## Undefined state demo

Run a flip-flop with an unknown initial value.

```powershell
cabal run gatework -- --netlist fixtures/unknown.net --duration 8 --output unknown.vcd --set d=1 --at 4 d=0
```

The command writes this output:

```text
Wrote unknown.vcd
Signals: 4
Duration: 8 time units
Assertions: 6 passed
```

The `init=x` field keeps the output unknown until the first clock edge.
The `NOT` gate shows the unknown until the flip-flop samples data.

| Time | d | q | nq |
| --- | --- | --- | --- |
| 0 | 1 | x | x |
| 3 | 1 | 1 | 0 |
| 5 | 0 | 0 | 1 |

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

The file `fixtures/register.golden.vcd` holds the complete register waveform.
This excerpt shows the first two timestamps:

```text
#0
1!
0"
0#
#1
1"
1#
#2
0!
0#
```

Here `!` is the data input `d`, `"` is the output `q`, and `#` is the clock `clk`.

The files `fixtures/reset.golden.vcd` and `fixtures/reg2.golden.vcd` hold
the reset and two-bit register waveforms.

The file `fixtures/gates.golden.vcd` holds the gate demo waveform.

The file `fixtures/haddader.golden.vcd` holds the hierarchical adder waveform.
Its identifiers include dotted instance names such as `f0.p`.

The file `fixtures/hcounter.golden.vcd` holds the hierarchical counter waveform.
Its identifiers include dotted instance names such as `counter.d0`.

The file `fixtures/adder.golden.vcd` holds the flat adder waveform.
It shows the settled sum for three plus five.

The file `fixtures/assert.golden.vcd` holds the assertion demo waveform.
Its header carries the assertion text as a comment block:

```text
$comment
  assert y = 1 at 0
  assert y = 0 at 3
  assert y = 1 at 5
$end
```

The file `fixtures/tristate.golden.vcd` holds the tri-state demo waveform.
Its timeline uses `z` for a floating wire and `x` for a floating value read by a gate:

```text
#0
0!
0"
0#
z#
0$
1$
x$
#2
1"
0#
1$
```

The file `fixtures/unknown.golden.vcd` holds the undefined-state demo waveform.
Its timeline shows `x` on the register output before the first clock edge:

```text
#0
1!
x"
0#
x#
0$
#1
1"
0#
1$
```

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

Supported gates are AND, OR, XOR, NAND, NOR, XNOR, NOT, and TRIBUF.
NAND, NOR, and XNOR use two inputs.
A gate output must have a `wire` declaration.
A flip-flop uses `clock=`, `d=`, and `q=` fields.
It accepts optional `init=`, `rst=`, and `width=` fields.
Flip-flop clocks must be declared `clock` signals.
Clock periods use even integers of at least two.

The `TRIBUF` gate is a tri-state buffer.
Its first input is the data signal.
Its second input is the enable signal.
A low enable makes the output float to `z`.
A high enable drives the output from the data input.
A gate reads a `z` input as unknown.

```text
gate TRIBUF driver (d,en) -> y
```

Logic values use the VCD characters `0`, `1`, `x`, and `z`.
The value `x` means unknown.
The value `z` means floating.
Input assignments, init lists, and assertions accept all four values.

```text
dff reg clock=clk d=d q=q init=x
assert y = z at 0
```

Use comma-separated lists to build a wider flip-flop.
The lists for `d=` and `q=` must have equal length.
The `init=` list must match that length or use one value for all bits.
The `width=` field is optional and must match the list length.

```text
dff state clock=clk d=a q=state_q init=0
dff pair clock=clk d=d0,d1 q=q0,q1 init=0,0 rst=reset
```

The `rst=` field names an active-high reset signal.
Reset acts asynchronously. It does not wait for a clock edge.
An asserted reset forces every bit to its initial value.

Use `assert` to check a signal value at a fixed time.
The time must be a non-negative integer.
The value must be 0, 1, x, or z.
The signal must exist in the netlist.

```text
assert y = 1 at 5
assert q0 = 0 at 3
```

The assertion compares the settled waveform value with the expectation.
A mismatch makes the run report an error and fail.
An assertion time beyond the run duration is an error.

### Modules and instances

A module is a reusable subcircuit.
Define it once, then use it many times.

```text
module halfadd (a,b) -> (sum,carry)
  gate XOR xsum (a,b) -> sum
  gate AND xcarry (a,b) -> carry
end

input a
input b
wire s
wire c
instance halfadd u1 (a,b) -> (s,c)
```

The module signature lists input and output ports.
The body declares wires, gates, flip-flops, assertions, and other instances.
Do not use `input` or `output` inside a module.
Do not put a module inside another module.
Use `end` to close the module.

An instance connects module ports to top-level signals.
The port counts must match the module signature.
The internal signals of an instance use dotted names.
For example, the wire `p` of instance `f0` becomes `f0.p`.

A flip-flop clock can be a module input port.
Connect that port to a top-level clock signal.
Modules may contain instances of other modules.
A circular chain of instances is an error.
An instance that names a missing module is an error.

## Verification

The test suite has two parts.
Deterministic tests cover parsing, validation, counter progression, adder carry propagation, scheduled inputs, reset behavior, register width, assertions, and golden VCD output.
Deterministic tests also cover NAND, NOR, and XNOR truth tables, module flattening, nested instances, port validation, and circular instantiation.
Deterministic tests also cover undefined and floating values, tri-state buffers, and their golden output.
QuickCheck properties cover gate algebra, full adder correctness, scheduled input sampling, reset sampling, register width, and assertion soundness.
QuickCheck properties also compare the hierarchical adder and counter with their flat versions.
QuickCheck properties also cover the four-state model and the tri-state buffer truth table.

QuickCheck runs one hundred random cases for each property.
The gate properties cover the complete truth table.
The adder property compares the simulation with integer addition over random four-bit values.
The scheduled-input property compares each sampled flip-flop value with a reference model.
The reset property compares the waveform with a reference model of reset and clock events.
The width property compares each register bit with a per-bit reference model.
The entry-point property shows that both simulation entry points produce identical output.
The assertion property shows that real values pass and inverted values fail.
The hierarchy property shows that the hierarchical circuits match the flat circuits.
The four-state property shows that the gates keep their two-state behavior for known inputs.
The buffer properties show that an enabled buffer passes data and a disabled buffer floats.

## Test status

All tests pass on GHC 9.6.7 with Cabal 3.14 in the bundled container.
The CI workflow runs the same checks on Ubuntu with GHC 9.6.6.
Golden tests compare the complete counter, register, reset, two-bit register, assertion, gate, hierarchical adder, hierarchical counter, adder, tri-state, and undefined-state VCD text.
CI runs every demo and compares its output with the golden file.

## Limitations

The simulator uses four logic values: low, high, unknown, and floating.
A floating value reads as unknown inside a gate.
One gate drives one wire.
The simulator does not resolve two drivers on the same wire.
Combinational loops stop with an event-limit error.
All gates use zero delay.
Zero-delay gates can show combinational settling transients at clock edges and at time zero.
Input changes apply only at scheduled times.
They do not react to circuit state.
VCD output uses one module scope and one-bit signals.
An asynchronous reset that releases on a clock edge is a race.
The event order decides the result.
A wide flip-flop uses one shared reset signal.
Assertions use the settled value at each time.
An assertion time beyond the run duration is an error.
A file defines its modules and its top level in one place.
Modules flatten before simulation, so the VCD stays flat.
One module declaration cannot live inside another.
An instance output must connect to a declared signal.
The dotted instance names are part of the VCD signal names.

## Roadmap

Release 0.6.0.0 completed undefined and floating logic values and tri-state buffers.
Release 0.5.0.0 completed universal gates and hierarchical netlists.
Release 0.4.0.0 completed waveform assertions and VCD comment metadata.
Release 0.3.0.0 completed reset pins and parameterized flip-flops.
Release 0.2.0.0 completed scheduled input transitions.

Remaining work:

1. Add multi-bit vectors and bus syntax.
2. Add multi-driver bus resolution.
3. Add module definitions in separate files.
4. Add a waveform report command.

## License

Gatework uses the BSD 3-Clause License.
