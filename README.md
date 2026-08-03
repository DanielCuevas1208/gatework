# Gatework

Gatework is an event-driven digital logic simulator in Haskell.
It parses a plain-text netlist, runs the circuit, and writes a VCD waveform file.
GTKWave and other waveform viewers can open the output.
The simulator uses four logic values: low, high, unknown, and floating.
Multi-bit buses use bracketed widths and slices.
Reusable modules can live in separate library files.

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
- Store reusable modules in separate library files.
- Load a module library with the `--library` option.
- Build a hierarchical adder from a module library file.
- Open the VCD output in GTKWave and inspect the waveforms.
- Verify gate behavior with QuickCheck property tests.
- Compare the counter waveform with a repository golden file.
- Check netlist behavior with waveform assertions.
- Inspect assertion metadata inside the VCD file.
- Use unknown (x) and floating (z) logic values.
- Drive a tri-state buffer from data and enable inputs.
- Share one wire between two tri-state buffers.
- Resolve a low and a high driver into unknown.
- See an uninitialized flip-flop read as unknown.
- Watch a gate read a floating input as unknown.
- Declare multi-bit buses with `input a[4]` and `wire x[4]`.
- Read one bit of a bus with `a[2]`.
- Read a bus slice with `a[3:0]`.
- Apply a gate bitwise across two buses.
- Pass a bus through a module port.
- Sample a whole bus into a register on one clock edge.
- Check a single bus bit with an assertion.

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
library text -> parser -> library module table
netlist text -> parser -> module table -> flattened netlist -> event queue -> waveform recorder -> assertion check -> VCD
```

The parser validates names, gate arity, drivers, clocks, and references.
The parser loads module definitions from library files.
A library file holds only module definitions.
The parser merges the main and library modules into one table.
The parser rejects a module name that appears in more than one file.
The parser expands each instance into the module gates.
The parser expands each bus into single-bit signals before simulation.
The flattened netlist uses dotted names for instance signals.
The scheduler processes only changed signals.
The scheduler resolves several gate drivers into one wire value.
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

## Module library adder demo

Run the same adder with its modules in a separate file.

```powershell
cabal run gatework -- --netlist fixtures/libadder.net --library fixtures/adderlib.net --duration 0 --output libadder.vcd --set a0=1,a1=1,a2=0,a3=0,b0=1,b1=0,b2=1,b3=0,cin=0
```

The file `fixtures/libadder.net` holds only the top level.
The file `fixtures/adderlib.net` defines the half-adder and full-adder modules.
The `--library` option loads the module definitions.
The library adder produces the same waveform as the hierarchical adder.

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

## Shared bus demo

Run two tri-state buffers that share one wire.

```powershell
cabal run gatework -- --netlist fixtures/shared.net --duration 8 --output shared.vcd --set d0=0,e0=0,d1=1,e1=0 --at 2 e0=1 --at 4 e1=1 --at 6 e0=0
```

The command writes this output:

```text
Wrote shared.vcd
Signals: 6
Duration: 8 time units
Assertions: 8 passed
```

Both buffers drive the wire `y`.
The simulator resolves the two driver values into one value.
A disabled buffer floats to `z`.
A `z` contribution is neutral during resolution.
An enabled buffer drives its data value.
Two enabled buffers with different values give `x`.

| Time | d0 | e0 | d1 | e1 | y | ny |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 1 | 0 | z | x |
| 3 | 0 | 1 | 1 | 0 | 0 | 1 |
| 5 | 0 | 1 | 1 | 1 | x | x |
| 7 | 0 | 0 | 1 | 1 | 1 | 0 |

The gate `NOT observer` reads the resolved wire `y`.
Its output `ny` is the inverse of the resolved value.

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

## Bus demo

Run four-bit bus operations with gates and a register.

```powershell
cabal run gatework -- --netlist fixtures/bus.net --duration 3 --output bus.vcd --set 'a[0]=1,a[2]=1,b[1]=1,b[3]=1'
```

The command writes this output:

```text
Wrote bus.vcd
Signals: 24
Duration: 3 time units
Assertions: 7 passed
```

The inputs `a` and `b` are four-bit buses.
The gate `XOR combine` applies bitwise across both buses.
The module `invert_bus` passes the bus `x` through a four-bit port.
The gate `AND mask` reads the slice `a[3:2]`.
The gate `OR first` reads one bit of each bus.
The register samples the whole bus on the first rising clock edge.
Each assertion checks one bit of one bus.

| Time | a[3:0] | b[3:0] | x[3:0] | n[3:0] | q[3:0] |
| --- | --- | --- | --- | --- | --- |
| 0 | 0101 | 1010 | 1111 | 0000 | 0000 |
| 1 | 0101 | 1010 | 1111 | 0000 | 1111 |

The value 0101 means `a[0]=1`, `a[1]=0`, `a[2]=1`, and `a[3]=0`.
Bit 0 is the least-significant bit.
The value 1010 means `b[0]=0`, `b[1]=1`, `b[2]=0`, and `b[3]=1`.

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

The file `fixtures/libadder.golden.vcd` holds the module library adder waveform.
Its content matches the hierarchical adder golden file.

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

The file `fixtures/bus.golden.vcd` holds the bus demo waveform.
Its header maps each bus bit to one identifier:

```text
$var wire 1 ! a[0] $end
$var wire 1 " a[1] $end
$var wire 1 # a[2] $end
$var wire 1 $ a[3] $end
```

Its timeline shows the settled values after the zero-delay transients:

```text
#0
1)
1*
1+
1,
0-
0.
0/
00
18
#1
11
12
13
14
15
```

Here `)` is `x[0]`, `-` is `n[0]`, and `0` is `n[3]`.
The value `18` means `c0` is high.
The value `00` means `n[3]` is low.
The identifier `1` is `q[0]`.
The register outputs change together on the clock edge.

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
A gate output must have a `wire` or `output` declaration.
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

### Multiple drivers

One wire can have many gate drivers.
The simulator resolves the driver values into one wire value.
The value `z` is neutral during resolution.
A known value dominates the `z` contributions.
Two known values that differ give `x`.
Any unknown contribution gives `x`.

```text
wire y
gate TRIBUF a (d0,e0) -> y
gate TRIBUF b (d1,e1) -> y
```

A flip-flop output stays exclusive to its flip-flop.
A gate cannot drive a flip-flop output.
One wire cannot have two flip-flop drivers.

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

### Buses

A bus is a set of one-bit signals with one name.
Declare a bus with a width in brackets.

```text
input a[4]
output s[4]
wire t[4]
```

The bus `a[4]` creates the signals `a[0]`, `a[1]`, `a[2]`, and `a[3]`.
Bit 0 is the least-significant bit.
A signal without a width has one bit.

A reference selects the whole bus, one bit, or a slice.

```text
a          whole bus
a[2]       one bit
a[3:0]     a slice
```

The slice covers the indexes from the lower bound to the upper bound.
A reference lists its bits from the lowest index upward.
A slice bound outside the declared width is an error.
A slice upper bound below the lower bound is an error.

All references in one gate must have the same width.
The gate applies its function to each bit position.

```text
gate XOR combine (a,b) -> s
gate AND first (a[0],b[0]) -> c0
gate AND mask (a[3:2],b[3:2]) -> t[1:0]
```

The first gate combines `a[0]` with `b[0]`.
It also combines `a[1]` with `b[1]`, and so on.
The second gate combines two single bits.
The third gate combines two two-bit slices.

A flip-flop reads and writes buses.
The data and output widths must match.
The `init=` list matches the width or uses one value for all bits.
A flip-flop bus output must have a `wire` or `output` declaration.

```text
dff reg clock=clk d=a q=q init=0,0,0,0
```

An assertion addresses one bit.

```text
assert s[0] = 1 at 0
assert s[2] = 0 at 4
```

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

A module port may carry a width.
The instance connection must match the port width.
A four-bit port connects to a four-bit bus.

```text
module invert_bus (a[4]) -> (n[4])
  gate NOT invert (a) -> n
end

wire x[4]
wire n[4]
gate XOR combine (a,b) -> x
instance invert_bus inv (x) -> (n)
```

A flip-flop clock can be a module input port.
Connect that port to a top-level clock signal.
Modules may contain instances of other modules.
A circular chain of instances is an error.
An instance that names a missing module is an error.

### Module libraries

Store reusable module definitions in a separate file.
A library file holds only module definitions.
It cannot hold inputs, outputs, wires, gates, or instances.

```text
# halfadd.net
module halfadd (a,b) -> (sum,carry)
  gate XOR xsum (a,b) -> sum
  gate AND carry (a,b) -> carry
end
```

Load the library when you run the tool.

```powershell
cabal run gatework -- --netlist top.net --library halfadd.net
```

Repeat `--library` for more libraries.
A library module can use modules from another library.
A module name cannot appear in more than one file.
The main netlist cannot reuse a module name from a library.
An error names the library file that caused it.

## Verification

The test suite has two parts.
Deterministic tests cover parsing, validation, counter progression, adder carry propagation, scheduled inputs, reset behavior, register width, assertions, and golden VCD output.
Deterministic tests also cover NAND, NOR, and XNOR truth tables, module flattening, nested instances, port validation, and circular instantiation.
Deterministic tests also cover undefined and floating values, tri-state buffers, and their golden output.
Deterministic tests also cover bus declarations, bitwise gates, bit references, slices, bus registers, bus assertions, bus module ports, and error cases.
Deterministic tests also cover multi-driver resolution, scheduled driver changes, flip-flop output exclusivity, the shared-bus fixture, and its golden output.
Deterministic tests also cover module library loading, cross-library module references, duplicate module names, and library file validation.
QuickCheck properties cover gate algebra, full adder correctness, scheduled input sampling, reset sampling, register width, and assertion soundness.
QuickCheck properties also compare the hierarchical adder and counter with their flat versions.
QuickCheck properties also cover the four-state model and the tri-state buffer truth table.
QuickCheck properties also compare a bus circuit with a bitwise reference model.
QuickCheck properties also compare the shared bus with a per-time resolution model.
QuickCheck properties also compare a library adder with its flat version.

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
The bus XOR property compares a bus gate with per-bit evaluation.
The bus register property compares each register bit with a reference value.
The bus hierarchy property shows that a bus module matches its flat circuit.
The shared-bus property compares each resolved wire value with a per-time model.
The library adder property compares a library netlist with the flat adder.

## Test status

All tests pass on GHC 9.6.7 with Cabal 3.14 in the bundled container.
The CI workflow runs the same checks on Ubuntu with GHC 9.6.6.
Golden tests compare the counter, register, reset, two-bit register, assertion, gate, hierarchical adder, library adder, hierarchical counter, adder, tri-state, undefined-state, bus, and shared-bus VCD text.
CI runs every demo and compares its output with the golden file.
CI confirms that a missing library file stops the run.

## Limitations

The simulator uses four logic values: low, high, unknown, and floating.
A floating value reads as unknown inside a gate.
Several gates can drive one wire.
The simulator resolves the driver values into one wire value.
Resolution treats z as neutral and known values as dominant.
A low and a high together give x.
A flip-flop output stays exclusive to its flip-flop.
A gate cannot drive a flip-flop output.
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
A netlist file can define modules inline or load them from library files.
A library file holds only module definitions.
A library file cannot hold top-level declarations.
The main netlist cannot shadow a library module.
Two library files cannot define the same module.
Modules flatten before simulation, so the VCD stays flat.
A bus expands into single-bit signals, so the VCD stays flat.
A flip-flop bus output must have a `wire` or `output` declaration.
A reference to a whole bus uses the declared width.
An assertion addresses one bit, not a whole bus.
Input assignments on the command line address one bit.
The CLI does not accept whole-bus values.
One module declaration cannot live inside another.
An instance output must connect to a declared signal.
The dotted instance names are part of the VCD signal names.

## Roadmap

Release 0.9.0.0 completed module libraries.
Release 0.8.0.0 completed multi-driver wire resolution.
Release 0.7.0.0 completed multi-bit buses, bit references, slices, and bus module ports.
Release 0.6.0.0 completed undefined and floating logic values and tri-state buffers.
Release 0.5.0.0 completed universal gates and hierarchical netlists.
Release 0.4.0.0 completed waveform assertions and VCD comment metadata.
Release 0.3.0.0 completed reset pins and parameterized flip-flops.
Release 0.2.0.0 completed scheduled input transitions.

Remaining work:

1. Add a waveform report command.
2. Add whole-bus input values on the command line.
3. Add multi-bit values in the VCD timeline.

## License

Gatework uses the BSD 3-Clause License.
