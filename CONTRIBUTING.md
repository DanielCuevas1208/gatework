# Contributing to Gatework

Thank you for your interest in Gatework.
This guide explains how to build, test, and change the project.

## Build the project

Install GHC 9.6 and Cabal 3.10 or newer.

Build the package.

```powershell
cabal build
```

Run the test suite.

```powershell
cabal test --enable-tests
```

## Run the checks

The CI workflow runs these checks.

- `cabal check` checks the package metadata.
- `cabal build all --enable-tests` builds everything.
- `cabal test --enable-tests` runs the test suite.
- Every demo writes a VCD file.
- Each demo output must match its golden file.
- The report demo writes a text table.
- The report output must match its golden file.

Run the checks before you open a pull request.

## Add a test

Put deterministic tests and QuickCheck properties in `test/Spec.hs`.

Add a netlist fixture in `fixtures/`.
The file name ends with `.net`.
A demo may load module definitions with the `--library` option.
Add the library file to `fixtures/` too.

Add a golden file when you add a demo.
The file name ends with `.golden.vcd`.
Run the demo to generate the golden file.
Then compare the output with the golden file in the CI workflow.

## Code style

The project uses a two-space indent.
Haskell code must compile with no warnings under `-Wall`.
Keep public functions small and pure.
Give each module one responsibility.
Write a changelog entry for every release.

## Documentation style

Write public documentation in ASD-STE100 style.
Use active voice and short sentences.
Do not use emojis.
Keep instructions under 20 words.
Keep descriptive sentences under 25 words.

## License

By contributing, you agree that your work uses the BSD 3-Clause License.
