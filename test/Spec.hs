module Main (main) where

import Control.Monad (forM)
import Data.Bits (xor)
import Data.Either (isLeft)
import Data.List (foldl', sortOn)
import Gatework.Logic (GateType (..), Logic (..), evalGate, parseLogic)
import Gatework.Netlist (Assertion (..), Netlist (..), netlistAssertions, netlistSignals, parseNetlist)
import Gatework.Simulator
  ( AssertionFailure (..)
  , Simulation
  , Time
  , resolveValue
  , signalChanges
  , simulate
  , simulateWithInputs
  , simulateWithScheduledInputs
  , simulationAssertions
  , simulationFailures
  )
import Gatework.VCD (renderVCD)
import System.Exit (exitFailure)
import Test.QuickCheck
  ( Arbitrary (..)
  , Property
  , choose
  , elements
  , forAll
  , property
  , quickCheckResult
  , vector
  )
import Test.QuickCheck.Test (isSuccess)

newtype Logical = Logical Logic
  deriving (Eq, Show)

instance Arbitrary Logical where
  arbitrary = Logical <$> elements [Low, High]

newtype Known = Known Logic
  deriving (Eq, Show)

instance Arbitrary Known where
  arbitrary = Known <$> elements [Low, High]

newtype FourState = FourState Logic
  deriving (Eq, Show)

instance Arbitrary FourState where
  arbitrary = FourState <$> elements [Low, High, Undefined, TriState]

and2 :: Logic -> Logic -> Logic
and2 left right = evalGate And [left, right]

or2 :: Logic -> Logic -> Logic
or2 left right = evalGate Or [left, right]

xor2 :: Logic -> Logic -> Logic
xor2 left right = evalGate Xor [left, right]

not1 :: Logic -> Logic
not1 value = evalGate Not [value]

main :: IO ()
main = do
  adderSource <- readFile "fixtures/adder.net"
  adder <- case parseNetlist adderSource of
    Left message -> do
      putStrLn ("adder fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  counterSource <- readFile "fixtures/counter.net"
  counter <- case parseNetlist counterSource of
    Left message -> do
      putStrLn ("counter fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  registerSource <- readFile "fixtures/register.net"
  register <- case parseNetlist registerSource of
    Left message -> do
      putStrLn ("register fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  resetSource <- readFile "fixtures/reset.net"
  reset <- case parseNetlist resetSource of
    Left message -> do
      putStrLn ("reset fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  reg2Source <- readFile "fixtures/reg2.net"
  reg2 <- case parseNetlist reg2Source of
    Left message -> do
      putStrLn ("reg2 fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  gatesSource <- readFile "fixtures/gates.net"
  gates <- case parseNetlist gatesSource of
    Left message -> do
      putStrLn ("gates fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  haddaderSource <- readFile "fixtures/haddader.net"
  haddader <- case parseNetlist haddaderSource of
    Left message -> do
      putStrLn ("haddader fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  hcounterSource <- readFile "fixtures/hcounter.net"
  hcounter <- case parseNetlist hcounterSource of
    Left message -> do
      putStrLn ("hcounter fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  tristateSource <- readFile "fixtures/tristate.net"
  tristate <- case parseNetlist tristateSource of
    Left message -> do
      putStrLn ("tristate fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  unknownSource <- readFile "fixtures/unknown.net"
  unknown <- case parseNetlist unknownSource of
    Left message -> do
      putStrLn ("unknown fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  sharedSource <- readFile "fixtures/shared.net"
  shared <- case parseNetlist sharedSource of
    Left message -> do
      putStrLn ("shared fixture failed to parse: " ++ message)
      exitFailure
    Right netlist -> pure netlist
  deterministic <- sequence
    [ testParser
    , testParserAcceptsCommentsAndBlankLines
    , testParserRejectsUnknownGate
    , testParserRejectsWrongArity
    , testParserRejectsEmptyInputs
    , testParserRejectsUndeclaredInput
    , testParserRejectsGateOutputWithoutWire
    , testParserRejectsDuplicateSignal
    , testMultiDriverResolution
    , testMultiDriverSettlesOnSchedule
    , testParserRejectsDuplicateDffOutput
    , testParserRejectsGateOnDffOutput
    , testParserRejectsInvalidClockPeriod
    , testParserRejectsInvalidIdentifier
    , testParserRejectsInvalidFlipFlop
    , testParserRejectsWidthMismatch
    , testParserRejectsUndeclaredReset
    , testParserRejectsBadInitList
    , testClockToggles
    , testDffSamplesOnRisingEdge
    , testDffRequiresDeclaredClock
    , testDffInitRespected
    , testDffResetAssertForcesInit
    , testDffResetOverridesClock
    , testDffResetDeassertHolds
    , testDffInitListRespected
    , testRegisterWidthSamplesAllBits
    , testEventLimitOnCombinationalLoop
    , testNegativeDurationRejected
    , testInputOverrideValidation
    , testScheduledInputValidation
    , testScheduledTransitionNoOp
    , testRegisterSamplesScheduledData
    , testCounter
    , testCounterFullSequence
    , testAdder
    , testVCDHeader
    , testGoldenVCD
    , testGoldenRegisterVCD
    , testGoldenResetVCD
    , testGoldenRegister2VCD
    , testParserAcceptsAssertion
    , testParserRejectsInvalidAssertion
    , testAssertionPasses
    , testAssertionFails
    , testAssertionBeyondDuration
    , testVCDCommentMetadata
    , testGoldenAssertVCD
    , testNandNorXnorTruth
    , testGatesFixture
    , testModuleHalfAdd
    , testModuleNestedFullAdd
    , testModuleClockInputPort
    , testModuleAssertion
    , testHierarchicalAdder
    , testHierarchicalCounter
    , testInstanceUnknownModule
    , testInstancePortCountMismatch
    , testUnterminatedModule
    , testEmptyModule
    , testDuplicateModule
    , testModuleRejectsInputDeclaration
    , testModuleRejectsUndeclaredGateInput
    , testModuleGateOutputNotWire
    , testCircularModuleInstantiation
    , testGoldenGatesVCD
    , testGoldenHaddaderVCD
    , testGoldenHcounterVCD
    , testGoldenAdderVCD
    , testLogicParseFourState
    , testUndefinedPropagatesThroughGates
    , testTriStateReadsAsUnknown
    , testTribufTruth
    , testDffInitUndefined
    , testScheduledInputWithTriState
    , testParserAcceptsFourStateAssertion
    , testVCDRendersUndefinedAndTriState
    , testTribufFixture
    , testUndefinedFixture
    , testGoldenTribufVCD
    , testGoldenUnknownVCD
    , testBusDeclarations
    , testBusGateBitwise
    , testBusBitReference
    , testBusSliceReference
    , testBusRegisterSamples
    , testBusAssertions
    , testBusModulePorts
    , testBusFixture
    , testParserRejectsBusOutOfRange
    , testParserRejectsBusWidthMismatch
    , testParserRejectsBusInvalidSlice
    , testParserRejectsBusWholeAssertion
    , testParserRejectsBusDffWidthMismatch
    , testParserRejectsBusConflictingWidths
    , testParserRejectsBusInstancePortMismatch
    , testGoldenBusVCD
    , testSharedBusFixture
    , testGoldenSharedVCD
    ]
  properties <- forM
    [ ("AND is commutative", quickCheckResult propAndCommutative)
    , ("OR is commutative", quickCheckResult propOrCommutative)
    , ("XOR is commutative", quickCheckResult propXorCommutative)
    , ("AND is associative", quickCheckResult propAndAssociative)
    , ("OR is associative", quickCheckResult propOrAssociative)
    , ("XOR is associative", quickCheckResult propXorAssociative)
    , ("AND identity is High", quickCheckResult propAndIdentity)
    , ("OR identity is Low", quickCheckResult propOrIdentity)
    , ("XOR identity is Low", quickCheckResult propXorIdentity)
    , ("AND annihilates Low", quickCheckResult propAndAnnihilator)
    , ("OR dominates High", quickCheckResult propOrDominator)
    , ("NOT is an involution", quickCheckResult propNotInvolution)
    , ("XOR cancels equal inputs", quickCheckResult propXorSelf)
    , ("De Morgan for AND", quickCheckResult propDeMorganAnd)
    , ("De Morgan for OR", quickCheckResult propDeMorganOr)
    , ("AND absorbs OR", quickCheckResult propAbsorptionAnd)
    , ("OR absorbs AND", quickCheckResult propAbsorptionOr)
    , ("AND distributes over OR", quickCheckResult propDistribution)
    , ("XNOR cancels a shared input", quickCheckResult propXnorIdentity)
    , ("ripple-carry adder adds four-bit values", quickCheckResult (propRippleCarryAdder adder))
    , ("scheduled inputs match a reference model", quickCheckResult (propScheduledInputSampling register))
    , ("reset matches a reference model", quickCheckResult (propResetSampling reset))
    , ("register width matches a per-bit reference", quickCheckResult (propRegisterWidthSampling reg2))
    , ("scheduled entry point matches the direct entry point", quickCheckResult (propEquivalentEntryPoints counter))
    , ("assertions follow the simulated waveform", quickCheckResult (propAssertionSoundness counter))
    , ("NAND inverts AND", quickCheckResult propNandInvertsAnd)
    , ("NOR inverts OR", quickCheckResult propNorInvertsOr)
    , ("XNOR inverts XOR", quickCheckResult propXnorInvertsXor)
    , ("hierarchical adder matches the flat adder", quickCheckResult (propHierarchicalAdderMatchesFlat adder haddader))
    , ("hierarchical counter matches the flat counter", quickCheckResult (propHierarchicalCounterMatchesFlat counter hcounter))
    , ("gates fixture follows the gate truth tables", quickCheckResult (propGatesFixture gates))
    , ("four-state gates match the two-state reference", quickCheckResult propTwoStateMatchesReference)
    , ("undefined inputs commute in binary gates", quickCheckResult propUndefinedCommutative)
    , ("TRIBUF follows its truth table", quickCheckResult propTribufTruth)
    , ("an enabled buffer passes known data", quickCheckResult propTribufEnable)
    , ("tri-state fixture stays consistent", quickCheckResult (propTribufFixtureSound tristate))
    , ("unknown fixture starts unclocked", quickCheckResult (propUnknownFixtureSampling unknown))
    , ("bus XOR matches the bitwise reference", quickCheckResult propBusXorBitwise)
    , ("bus register samples every bit", quickCheckResult propBusRegisterSampling)
    , ("bus module matches the flat circuit", quickCheckResult propBusModuleMatchesFlat)
    , ("shared bus follows the resolution model", quickCheckResult (propSharedBusResolution shared))
    ]
    $ \(label, action) -> do
      result <- action
      putStrLn (label ++ ": " ++ if isSuccess result then "PASS" else "FAIL")
      pure (isSuccess result)
  if and (deterministic ++ properties) then pure () else exitFailure

testParser :: IO Bool
testParser = do
  parsed <- readFile "fixtures/counter.net"
  let result = parseNetlist parsed
  check "counter netlist parses" $ case result of
    Right netlist ->
      length (netlistGates netlist) == 6
        && length (netlistFlipFlops netlist) == 4
        && netlistOutputs netlist == ["q0", "q1", "q2", "q3"]
    Left _ -> False

testParserAcceptsCommentsAndBlankLines :: IO Bool
testParserAcceptsCommentsAndBlankLines =
  check "parser accepts comments and blank lines" $ case
    parseNetlist "# a comment\n\ninput a\nwire out\ngate NOT inv (a) -> out\n" of
      Right netlist ->
        netlistInputs netlist == ["a"]
          && length (netlistGates netlist) == 1
      Left _ -> False

testParserRejectsUnknownGate :: IO Bool
testParserRejectsUnknownGate =
  check "parser rejects unknown gates" $ isLeft $
    parseNetlist "wire out\ngate NAND only (a,b) -> out"

testParserRejectsWrongArity :: IO Bool
testParserRejectsWrongArity =
  check "parser rejects wrong gate arity" $ isLeft $
    parseNetlist "input a\nwire out\ngate AND one (a) -> out"

testParserRejectsEmptyInputs :: IO Bool
testParserRejectsEmptyInputs =
  check "parser rejects empty gate inputs" $ isLeft $
    parseNetlist "wire out\ngate NOT inv () -> out"

testParserRejectsUndeclaredInput :: IO Bool
testParserRejectsUndeclaredInput =
  check "parser rejects undeclared gate input" $ isLeft $
    parseNetlist "wire out\ngate AND one (a,b) -> out"

testParserRejectsGateOutputWithoutWire :: IO Bool
testParserRejectsGateOutputWithoutWire =
  check "parser requires gate outputs to be wires" $ isLeft $
    parseNetlist "input a\ninput b\ngate AND one (a,b) -> out"

testParserRejectsDuplicateSignal :: IO Bool
testParserRejectsDuplicateSignal =
  check "parser rejects duplicate signal names" $ isLeft $
    parseNetlist "input a\nwire a"

testMultiDriverResolution :: IO Bool
testMultiDriverResolution = case
  parseNetlist (unlines
    [ "input a"
    , "input b"
    , "input en"
    , "output y"
    , "wire y"
    , "gate AND first (a,en) -> y"
    , "gate OR second (b,en) -> y"
    ]) of
    Left _ -> check "many gate drivers resolve to one wire value" False
    Right netlist ->
      check "many gate drivers resolve to one wire value" $ case
        ( simulateWithInputs netlist [("a", High), ("b", Low), ("en", High)] 0
        , simulateWithInputs netlist [("a", Low), ("b", Low), ("en", Low)] 0
        , simulateWithInputs netlist [("a", High), ("b", High), ("en", Low)] 0
        ) of
          (Right bothHigh, Right bothLow, Right conflict) ->
            finalValue bothHigh "y" == Just High
              && finalValue bothLow "y" == Just Low
              && finalValue conflict "y" == Just Undefined
          _ -> False

testMultiDriverSettlesOnSchedule :: IO Bool
testMultiDriverSettlesOnSchedule = case
  parseNetlist (unlines
    [ "input d0"
    , "input d1"
    , "input e0"
    , "input e1"
    , "output y"
    , "wire y"
    , "gate TRIBUF a (d0,e0) -> y"
    , "gate TRIBUF b (d1,e1) -> y"
    ]) of
    Left _ -> check "scheduled driver changes re-resolve the wire" False
    Right netlist -> check "scheduled driver changes re-resolve the wire" $ case
      simulateWithScheduledInputs netlist [("d0", Low), ("d1", High)]
        [(2, "e0", High), (4, "e1", High), (6, "e0", Low)] 8 of
        Right simulation ->
          valueAt simulation "y" 0 == TriState
            && valueAt simulation "y" 3 == Low
            && valueAt simulation "y" 5 == Undefined
            && valueAt simulation "y" 7 == High
        Left _ -> False

testParserRejectsDuplicateDffOutput :: IO Bool
testParserRejectsDuplicateDffOutput =
  check "parser rejects two flip-flops on one output" $ isLeft $
    parseNetlist (unlines
      [ "input d0"
      , "input d1"
      , "output q"
      , "clock clk period=2"
      , "dff first clock=clk d=d0 q=q init=0"
      , "dff second clock=clk d=d1 q=q init=0"
      ])

testParserRejectsGateOnDffOutput :: IO Bool
testParserRejectsGateOnDffOutput =
  check "parser rejects a gate on a flip-flop output" $ isLeft $
    parseNetlist (unlines
      [ "input d"
      , "input en"
      , "output q"
      , "clock clk period=2"
      , "dff state clock=clk d=d q=q init=0"
      , "gate TRIBUF driver (d,en) -> q"
      ])

testParserRejectsInvalidClockPeriod :: IO Bool
testParserRejectsInvalidClockPeriod =
  check "parser rejects invalid clock periods" $
    isLeft (parseNetlist "clock clk period=3")
      && isLeft (parseNetlist "clock clk period=0")
      && isLeft (parseNetlist "clock clk period=-2")
      && isLeft (parseNetlist "clock clk")

testParserRejectsInvalidIdentifier :: IO Bool
testParserRejectsInvalidIdentifier =
  check "parser rejects invalid signal names" $
    isLeft (parseNetlist "input bad-name")
      && isLeft (parseNetlist "input a'b")
      && isLeft (parseNetlist "input")

testParserRejectsInvalidFlipFlop :: IO Bool
testParserRejectsInvalidFlipFlop =
  check "parser rejects invalid flip-flop declarations" $
    isLeft (parseNetlist "input d\nclock clk period=2\ndff f clock=clk q=q init=0")
      && isLeft (parseNetlist "input d\nclock clk period=2\ndff f clock=clk d=d q=q init=2")
      && isLeft (parseNetlist "input d\nclock clk period=2\ndff f clock=clk d=d q=q extra=0")

testParserRejectsWidthMismatch :: IO Bool
testParserRejectsWidthMismatch =
  check "parser rejects flip-flop width mismatches" $
    isLeft (parseNetlist "input d0\ninput d1\noutput q0\noutput q1\nclock clk period=2\ndff pair clock=clk d=d0 q=q0,q1 init=0,0")
      && isLeft (parseNetlist "input d0\ninput d1\noutput q0\noutput q1\nclock clk period=2\ndff pair clock=clk d=d0,d1 q=q0,q1 init=0,0 width=3")
      && isLeft (parseNetlist "input d0\ninput d1\noutput q0\noutput q1\nclock clk period=2\ndff pair clock=clk d=d0,d1 q=q0,q1 init=0,0 width=0")

testParserRejectsUndeclaredReset :: IO Bool
testParserRejectsUndeclaredReset =
  check "parser rejects an undeclared flip-flop reset" $ isLeft $
    parseNetlist "input d\noutput q\nclock clk period=2\ndff f clock=clk d=d q=q init=0 rst=missing"

testParserRejectsBadInitList :: IO Bool
testParserRejectsBadInitList =
  check "parser rejects invalid flip-flop init lists" $
    isLeft (parseNetlist "input d0\ninput d1\noutput q0\noutput q1\nclock clk period=2\ndff pair clock=clk d=d0,d1 q=q0,q1 init=0,0,0")
      && isLeft (parseNetlist "input d0\ninput d1\noutput q0\noutput q1\nclock clk period=2\ndff pair clock=clk d=d0,d1 q=q0,q1 init=2")

testClockToggles :: IO Bool
testClockToggles = case parseNetlist "clock clk period=4" of
  Left _ -> check "clock toggles at half-period intervals" False
  Right netlist -> check "clock toggles at half-period intervals" $ case simulate netlist 8 of
    Right simulation ->
      signalChanges simulation "clk"
        == [(0, Low), (2, High), (4, Low), (6, High), (8, Low)]
    Left _ -> False

testDffSamplesOnRisingEdge :: IO Bool
testDffSamplesOnRisingEdge =
  let netlist = parseNetlist "input d\noutput q\nclock clk period=4\ndff f clock=clk d=d q=q init=0"
  in case netlist of
    Left _ -> check "dff samples on the rising edge" False
    Right parsed -> check "dff samples on the rising edge" $ case
      simulateWithInputs parsed [("d", High)] 4 of
        Right simulation -> signalChanges simulation "q" == [(0, Low), (2, High)]
        Left _ -> False

testDffRequiresDeclaredClock :: IO Bool
testDffRequiresDeclaredClock =
  let netlist =
        parseNetlist
          "input d\noutput q\nwire nclk\nclock clk period=4\ngate NOT inv (clk) -> nclk\ndff f clock=nclk d=d q=q init=0"
  in check "dff clock must be a declared clock" (isLeft netlist)

testDffInitRespected :: IO Bool
testDffInitRespected =
  let netlist = parseNetlist "input d\noutput q\nclock clk period=8\ndff f clock=clk d=d q=q init=1"
  in case netlist of
    Left _ -> check "dff initial value is honored" False
    Right parsed -> check "dff initial value is honored" $ case
      simulateWithInputs parsed [("d", Low)] 3 of
        Right simulation -> signalChanges simulation "q" == [(0, High)]
        Left _ -> False

testDffResetAssertForcesInit :: IO Bool
testDffResetAssertForcesInit =
  let netlist = parseNetlist "input d\ninput rst\noutput q\nclock clk period=2\ndff f clock=clk d=d q=q init=0 rst=rst"
  in case netlist of
    Left _ -> check "reset forces the dff to its initial value" False
    Right parsed -> check "reset forces the dff to its initial value" $ case
      simulateWithScheduledInputs parsed [("d", High)] [(3, "rst", High)] 4 of
        Right simulation -> signalChanges simulation "q" == [(0, Low), (1, High), (3, Low)]
        Left _ -> False

testDffResetOverridesClock :: IO Bool
testDffResetOverridesClock =
  let netlist = parseNetlist "input d\ninput rst\noutput q\nclock clk period=2\ndff f clock=clk d=d q=q init=0 rst=rst"
  in case netlist of
    Left _ -> check "an asserted reset overrides clock sampling" False
    Right parsed -> check "an asserted reset overrides clock sampling" $ case
      simulateWithInputs parsed [("d", High), ("rst", High)] 5 of
        Right simulation -> signalChanges simulation "q" == [(0, Low)]
        Left _ -> False

testDffResetDeassertHolds :: IO Bool
testDffResetDeassertHolds =
  let netlist = parseNetlist "input d\ninput rst\noutput q\nclock clk period=2\ndff f clock=clk d=d q=q init=0 rst=rst"
  in case netlist of
    Left _ -> check "reset deassertion holds the dff output" False
    Right parsed -> check "reset deassertion holds the dff output" $ case
      simulateWithScheduledInputs parsed [("d", High)] [(2, "rst", High), (4, "rst", Low)] 5 of
        Right simulation ->
          signalChanges simulation "q" == [(0, Low), (1, High), (2, Low), (5, High)]
        Left _ -> False

testDffInitListRespected :: IO Bool
testDffInitListRespected =
  let netlist = parseNetlist "input d0\ninput d1\noutput q0\noutput q1\nclock clk period=2\ndff pair clock=clk d=d0,d1 q=q0,q1 init=1,0"
  in case netlist of
    Left _ -> check "dff init list sets each bit" False
    Right parsed -> check "dff init list sets each bit" $ case
      simulate parsed 3 of
        Right simulation ->
          signalChanges simulation "q0" == [(0, High), (1, Low)]
            && signalChanges simulation "q1" == [(0, Low)]
        Left _ -> False

testRegisterWidthSamplesAllBits :: IO Bool
testRegisterWidthSamplesAllBits =
  let netlist = parseNetlist "input d0\ninput d1\noutput q0\noutput q1\nclock clk period=2\ndff pair clock=clk d=d0,d1 q=q0,q1 init=0,0"
  in case netlist of
    Left _ -> check "a width register samples every bit" False
    Right parsed -> check "a width register samples every bit" $ case
      simulateWithInputs parsed [("d0", High), ("d1", High)] 3 of
        Right simulation ->
          signalChanges simulation "q0" == [(0, Low), (1, High)]
            && signalChanges simulation "q1" == [(0, Low), (1, High)]
        Left _ -> False

testEventLimitOnCombinationalLoop :: IO Bool
testEventLimitOnCombinationalLoop =
  let netlist = parseNetlist "wire y\nwire z\ngate NOT a (y) -> z\ngate NOT b (z) -> y"
  in case netlist of
    Left _ -> check "combinational loops stop with an error" False
    Right parsed -> check "combinational loops stop with an error" $
      isLeft (simulate parsed 5)

testNegativeDurationRejected :: IO Bool
testNegativeDurationRejected =
  let netlist = parseNetlist "input a\nwire out\ngate NOT inv (a) -> out"
  in case netlist of
    Left _ -> check "negative duration is rejected" False
    Right parsed -> check "negative duration is rejected" $
      isLeft (simulateWithInputs parsed [("a", High)] (-1))

testInputOverrideValidation :: IO Bool
testInputOverrideValidation =
  let netlist = parseNetlist "input a\nwire out\ngate NOT inv (a) -> out"
  in case netlist of
    Left _ -> check "input overrides are validated" False
    Right parsed ->
      check "input overrides are validated" $
        isLeft (simulateWithInputs parsed [("b", High)] 1)
          && isLeft (simulateWithInputs parsed [("a", High), ("a", Low)] 1)
          && case simulateWithInputs parsed [("a", High)] 1 of
            Right simulation -> finalValue simulation "out" == Just Low
            Left _ -> False

testScheduledInputValidation :: IO Bool
testScheduledInputValidation =
  let netlist = parseNetlist "input a\nwire out\ngate NOT inv (a) -> out"
  in case netlist of
    Left _ -> check "scheduled inputs are validated" False
    Right parsed ->
      check "scheduled inputs are validated" $
        isLeft (simulateWithScheduledInputs parsed [] [(-1, "a", High)] 1)
          && isLeft (simulateWithScheduledInputs parsed [] [(1, "b", High)] 1)
          && case simulateWithScheduledInputs parsed [] [(1, "a", High)] 2 of
            Right simulation ->
              signalChanges simulation "a" == [(0, Low), (1, High)]
                && finalValue simulation "out" == Just Low
            Left _ -> False

testScheduledTransitionNoOp :: IO Bool
testScheduledTransitionNoOp =
  let netlist = parseNetlist "input a\nwire out\ngate NOT inv (a) -> out"
  in case netlist of
    Left _ -> check "unchanged scheduled values add no events" False
    Right parsed -> check "unchanged scheduled values add no events" $ case
      simulateWithScheduledInputs parsed [("a", High)] [(1, "a", High)] 3 of
        Right simulation -> signalChanges simulation "a" == [(0, High)]
        Left _ -> False

testRegisterSamplesScheduledData :: IO Bool
testRegisterSamplesScheduledData = do
  source <- readFile "fixtures/register.net"
  let simulation = do
        netlist <- parseNetlist source
        simulateWithScheduledInputs netlist [("d", High)]
          [(2, "d", Low), (4, "d", High), (6, "d", Low)] 8
  check "register samples a scheduled data stream" $ case simulation of
    Right result ->
      and
        [ signalChanges result "d" == [(0, High), (2, Low), (4, High), (6, Low)]
        , signalChanges result "q" == [(0, Low), (1, High), (3, Low), (5, High), (7, Low)]
        ]
    Left _ -> False

testCounter :: IO Bool
testCounter = do
  source <- readFile "fixtures/counter.net"
  let simulation = do
        netlist <- parseNetlist source
        simulate netlist 8
  check "counter advances on rising clock edges" $ case simulation of
    Right result ->
      and
        [ signalChanges result "q0" == [(0, Low), (1, High), (3, Low), (5, High), (7, Low)]
        , signalChanges result "q1" == [(0, Low), (3, High), (7, Low)]
        , signalChanges result "q2" == [(0, Low), (7, High)]
        , signalChanges result "q3" == [(0, Low)]
        ]
    Left _ -> False

testCounterFullSequence :: IO Bool
testCounterFullSequence = do
  source <- readFile "fixtures/counter.net"
  let simulation = do
        netlist <- parseNetlist source
        simulate netlist 31
  check "counter counts zero through fifteen then wraps" $ case simulation of
    Right result ->
      all
        (\edge -> counterValueAt result (fromIntegral (2 * edge - 1)) == edge `mod` 16)
        [1 :: Int .. 16]
    Left _ -> False

testAdder :: IO Bool
testAdder = do
  source <- readFile "fixtures/adder.net"
  let simulation = do
        netlist <- parseNetlist source
        simulateWithInputs netlist
          [ ("a0", High), ("a1", High), ("a2", Low), ("a3", Low)
          , ("b0", High), ("b1", Low), ("b2", High), ("b3", Low)
          , ("cin", Low)
          ] 0
  check "ripple-carry adder computes three plus five" $ case simulation of
    Right result ->
      and
        [ finalValue result "sum0" == Just Low
        , finalValue result "sum1" == Just Low
        , finalValue result "sum2" == Just Low
        , finalValue result "sum3" == Just High
        , finalValue result "cout" == Just Low
        ]
    Left _ -> False

testVCDHeader :: IO Bool
testVCDHeader = do
  source <- readFile "fixtures/counter.net"
  let result = do
        netlist <- parseNetlist source
        simulation <- simulate netlist 8
        pure (renderVCD simulation)
  check "VCD header uses stable signal order" $ case result of
    Left _ -> False
    Right text ->
      all (`elem` lines text)
        [ "$timescale 1ns $end"
        , "$scope module gatework $end"
        , "$var wire 1 ! q0 $end"
        , "$var wire 1 % clk $end"
        , "$var wire 1 + d3 $end"
        ]

testGoldenVCD :: IO Bool
testGoldenVCD = do
  source <- readFile "fixtures/counter.net"
  golden <- readFile "fixtures/counter.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <- simulate netlist 8
        pure (renderVCD simulation)
  check "counter VCD matches golden file" (actual == Right golden)

testGoldenRegisterVCD :: IO Bool
testGoldenRegisterVCD = do
  source <- readFile "fixtures/register.net"
  golden <- readFile "fixtures/register.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("d", High)]
            [(2, "d", Low), (4, "d", High), (6, "d", Low)] 8
        pure (renderVCD simulation)
  check "register VCD matches golden file" (actual == Right golden)

testGoldenResetVCD :: IO Bool
testGoldenResetVCD = do
  source <- readFile "fixtures/reset.net"
  golden <- readFile "fixtures/reset.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("d", High)]
            [(2, "rst", High), (4, "rst", Low), (6, "d", Low)] 8
        pure (renderVCD simulation)
  check "reset VCD matches golden file" (actual == Right golden)

testGoldenRegister2VCD :: IO Bool
testGoldenRegister2VCD = do
  source <- readFile "fixtures/reg2.net"
  golden <- readFile "fixtures/reg2.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("d0", High), ("d1", Low)]
            [ (4, "d0", Low), (4, "d1", High)
            , (6, "rst", High)
            , (8, "rst", Low), (8, "d0", High), (8, "d1", High)
            ] 10
        pure (renderVCD simulation)
  check "register width VCD matches golden file" (actual == Right golden)

testParserAcceptsAssertion :: IO Bool
testParserAcceptsAssertion =
  check "parser accepts assertion declarations" $ case
    parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 1 at 4\n" of
      Right netlist -> netlistAssertions netlist == [Assertion "out" High 4]
      Left _ -> False

testParserRejectsInvalidAssertion :: IO Bool
testParserRejectsInvalidAssertion =
  check "parser rejects invalid assertions" $
    isLeft (parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 2 at 1")
      && isLeft (parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 1")
      && isLeft (parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert missing = 1 at 1")
      && isLeft (parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 1 at -2")
      && isLeft (parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 1 at x")

testAssertionPasses :: IO Bool
testAssertionPasses = case
  parseNetlist (unlines
    [ "input a"
    , "input b"
    , "wire n"
    , "wire y"
    , "output y"
    , "gate NOT inv (a) -> n"
    , "gate AND combine (n,b) -> y"
    , "assert y = 1 at 0"
    , "assert y = 0 at 3"
    , "assert y = 1 at 5"
    ]) of
    Left _ -> check "passing assertions produce no failures" False
    Right netlist -> check "passing assertions produce no failures" $ case
      simulateWithScheduledInputs netlist [("a", Low), ("b", High)]
        [(3, "a", High), (5, "a", Low)] 6 of
        Right simulation ->
          null (simulationFailures simulation)
            && length (simulationAssertions simulation) == 3
        Left _ -> False

testAssertionFails :: IO Bool
testAssertionFails = case
  parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 1 at 2\n" of
    Left _ -> check "a failing assertion is reported" False
    Right netlist -> check "a failing assertion is reported" $ case
      simulateWithInputs netlist [("a", High)] 3 of
        Right simulation -> case simulationFailures simulation of
          [failure] ->
            failureSignal failure == "out"
              && failureTime failure == 2
              && failureExpected failure == High
              && failureActual failure == Low
          _ -> False
        Left _ -> False

testAssertionBeyondDuration :: IO Bool
testAssertionBeyondDuration = case
  parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 0 at 5\n" of
    Left _ -> check "assertion times beyond duration are rejected" False
    Right netlist -> check "assertion times beyond duration are rejected" $
      isLeft (simulateWithInputs netlist [("a", High)] 3)

testVCDCommentMetadata :: IO Bool
testVCDCommentMetadata = case
  parseNetlist "input a\nwire out\ngate NOT inv (a) -> out\nassert out = 1 at 2\n" of
    Left _ -> check "VCD records assertions as comment metadata" False
    Right netlist -> check "VCD records assertions as comment metadata" $ case
      simulate netlist 3 of
        Left _ -> False
        Right simulation ->
          all (`elem` lines (renderVCD simulation))
            [ "$comment"
            , "  assert out = 1 at 2"
            , "$end"
            ]

testGoldenAssertVCD :: IO Bool
testGoldenAssertVCD = do
  source <- readFile "fixtures/assert.net"
  golden <- readFile "fixtures/assert.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("a", Low), ("b", High)]
            [(3, "a", High), (5, "a", Low)] 6
        pure (renderVCD simulation)
  check "assert VCD matches golden file" (actual == Right golden)

testNandNorXnorTruth :: IO Bool
testNandNorXnorTruth =
  check "NAND, NOR, and XNOR follow their truth tables" $
    and
      [ evalGate Nand [Low, Low] == High
      , evalGate Nand [Low, High] == High
      , evalGate Nand [High, Low] == High
      , evalGate Nand [High, High] == Low
      , evalGate Nor [Low, Low] == High
      , evalGate Nor [Low, High] == Low
      , evalGate Nor [High, Low] == Low
      , evalGate Nor [High, High] == Low
      , evalGate Xnor [Low, Low] == High
      , evalGate Xnor [Low, High] == Low
      , evalGate Xnor [High, Low] == Low
      , evalGate Xnor [High, High] == High
      ]

testGatesFixture :: IO Bool
testGatesFixture = do
  source <- readFile "fixtures/gates.net"
  let simulation = do
        netlist <- parseNetlist source
        simulateWithScheduledInputs netlist [("a", Low), ("b", High)]
          [ (2, "a", High), (2, "b", High)
          , (4, "a", High), (4, "b", Low)
          , (6, "a", Low), (6, "b", Low)
          ] 7
  check "gates fixture asserts the full truth table" $ case simulation of
    Right result ->
      null (simulationFailures result)
        && length (simulationAssertions result) == 12
        && valueAt result "nand_out" 0 == High
        && valueAt result "nand_out" 2 == Low
        && valueAt result "nand_out" 4 == High
        && valueAt result "nand_out" 6 == High
        && valueAt result "nor_out" 0 == Low
        && valueAt result "nor_out" 6 == High
        && valueAt result "xnor_out" 0 == Low
        && valueAt result "xnor_out" 2 == High
        && valueAt result "xnor_out" 4 == Low
        && valueAt result "xnor_out" 6 == High
    Left _ -> False

testModuleHalfAdd :: IO Bool
testModuleHalfAdd =
  let source = unlines
        [ "module halfadd (a,b) -> (sum,carry)"
        , "  gate XOR xsum (a,b) -> sum"
        , "  gate AND xcarry (a,b) -> carry"
        , "end"
        , "input a"
        , "input b"
        , "output sum"
        , "output carry"
        , "wire sum"
        , "wire carry"
        , "instance halfadd u1 (a,b) -> (sum,carry)"
        ]
  in case parseNetlist source of
    Left _ -> check "a half adder module flattens into gates" False
    Right netlist ->
      check "a half adder module flattens into gates" $ case
        simulateWithInputs netlist [("a", High), ("b", Low)] 0 of
          Right simulation ->
            finalValue simulation "sum" == Just High
              && finalValue simulation "carry" == Just Low
          Left _ -> False

testModuleNestedFullAdd :: IO Bool
testModuleNestedFullAdd =
  let source = unlines
        [ "module halfadd (a,b) -> (sum,carry)"
        , "  gate XOR xsum (a,b) -> sum"
        , "  gate AND xcarry (a,b) -> carry"
        , "end"
        , "module fulladd (a,b,cin) -> (sum,cout)"
        , "  wire p"
        , "  wire g"
        , "  wire h"
        , "  instance halfadd u1 (a,b) -> (p,g)"
        , "  instance halfadd u2 (p,cin) -> (sum,h)"
        , "  gate OR xcarry (g,h) -> cout"
        , "end"
        , "input a"
        , "input b"
        , "input cin"
        , "output sum"
        , "output cout"
        , "wire sum"
        , "wire cout"
        , "instance fulladd f (a,b,cin) -> (sum,cout)"
        ]
  in case parseNetlist source of
    Left _ -> check "a full adder nests two half adders" False
    Right netlist ->
      check "a full adder nests two half adders" $ case
        simulateWithInputs netlist [("a", High), ("b", High), ("cin", High)] 0 of
          Right simulation ->
            finalValue simulation "sum" == Just High
              && finalValue simulation "cout" == Just High
          Left _ -> False

testModuleClockInputPort :: IO Bool
testModuleClockInputPort =
  let source = unlines
        [ "module reg (clk,d) -> (q)"
        , "  dff state clock=clk d=d q=q init=0"
        , "end"
        , "input d"
        , "output q"
        , "clock clk period=2"
        , "instance reg r (clk,d) -> (q)"
        ]
  in case parseNetlist source of
    Left _ -> check "a module clock port drives its flip-flops" False
    Right netlist -> check "a module clock port drives its flip-flops" $ case
      simulateWithInputs netlist [("d", High)] 4 of
        Right simulation -> signalChanges simulation "q" == [(0, Low), (1, High)]
        Left _ -> False

testModuleAssertion :: IO Bool
testModuleAssertion =
  let source = unlines
        [ "module inv (a) -> (out)"
        , "  gate NOT g (a) -> out"
        , "  assert out = 0 at 1"
        , "end"
        , "input a"
        , "output out"
        , "wire out"
        , "instance inv u (a) -> (out)"
        ]
  in case parseNetlist source of
    Left _ -> check "assertions inside modules are checked" False
    Right netlist -> check "assertions inside modules are checked" $ case
      simulateWithInputs netlist [("a", High)] 2 of
        Right simulation -> null (simulationFailures simulation)
        Left _ -> False

testHierarchicalAdder :: IO Bool
testHierarchicalAdder = do
  source <- readFile "fixtures/haddader.net"
  let simulation = do
        netlist <- parseNetlist source
        simulateWithInputs netlist
          [ ("a0", High), ("a1", High), ("a2", Low), ("a3", Low)
          , ("b0", High), ("b1", Low), ("b2", High), ("b3", Low)
          , ("cin", Low)
          ] 0
  check "hierarchical adder computes three plus five" $ case simulation of
    Right result ->
      and
        [ finalValue result "sum0" == Just Low
        , finalValue result "sum1" == Just Low
        , finalValue result "sum2" == Just Low
        , finalValue result "sum3" == Just High
        , finalValue result "cout" == Just Low
        ]
    Left _ -> False

testHierarchicalCounter :: IO Bool
testHierarchicalCounter = do
  source <- readFile "fixtures/hcounter.net"
  let simulation = do
        netlist <- parseNetlist source
        simulate netlist 8
  check "hierarchical counter advances on clock edges" $ case simulation of
    Right result ->
      and
        [ signalChanges result "q0" == [(0, Low), (1, High), (3, Low), (5, High), (7, Low)]
        , signalChanges result "q1" == [(0, Low), (3, High), (7, Low)]
        , signalChanges result "q2" == [(0, Low), (7, High)]
        , signalChanges result "q3" == [(0, Low)]
        ]
    Left _ -> False

testInstanceUnknownModule :: IO Bool
testInstanceUnknownModule =
  check "instances require a known module" $ isLeft $
    parseNetlist "input a\nwire out\ninstance missing u (a) -> (out)"

testInstancePortCountMismatch :: IO Bool
testInstancePortCountMismatch =
  check "instances reject port count mismatches" $
    isLeft (parseNetlist (unlines
      [ "module half (a,b) -> (s,c)"
      , "  gate XOR g (a,b) -> s"
      , "  gate AND h (a,b) -> c"
      , "end"
      , "input a"
      , "wire s"
      , "wire c"
      , "instance half u (a) -> (s,c)"
      ]))
      && isLeft (parseNetlist (unlines
      [ "module half (a,b) -> (s,c)"
      , "  gate XOR g (a,b) -> s"
      , "  gate AND h (a,b) -> c"
      , "end"
      , "input a"
      , "input b"
      , "wire s"
      , "wire c"
      , "instance half u (a,b) -> (s)"
      ]))

testUnterminatedModule :: IO Bool
testUnterminatedModule =
  check "parser rejects unterminated modules" $ isLeft $
    parseNetlist "module m (a) -> (out)\n  gate NOT g (a) -> out\ninput a\nwire out"

testEmptyModule :: IO Bool
testEmptyModule =
  check "parser rejects empty module bodies" $ isLeft $
    parseNetlist "module m (a) -> (out)\nend\ninput a\nwire out"

testDuplicateModule :: IO Bool
testDuplicateModule =
  check "parser rejects duplicate modules" $ isLeft $
    parseNetlist (unlines
      [ "module m (a) -> (out)"
      , "  gate NOT g (a) -> out"
      , "end"
      , "module m (a) -> (out)"
      , "  gate NOT g (a) -> out"
      , "end"
      ])

testModuleRejectsInputDeclaration :: IO Bool
testModuleRejectsInputDeclaration =
  check "modules reject input declarations" $ isLeft $
    parseNetlist (unlines
      [ "module m (a) -> (out)"
      , "  input x"
      , "  gate NOT g (a) -> out"
      , "end"
      ])

testModuleRejectsUndeclaredGateInput :: IO Bool
testModuleRejectsUndeclaredGateInput =
  check "modules reject undeclared gate inputs" $ isLeft $
    parseNetlist (unlines
      [ "module m (a) -> (out)"
      , "  gate NOT g (missing) -> out"
      , "end"
      , "input a"
      , "wire out"
      , "instance m u (a) -> (out)"
      ])

testModuleGateOutputNotWire :: IO Bool
testModuleGateOutputNotWire =
  check "modules require gate outputs to be declared" $ isLeft $
    parseNetlist (unlines
      [ "module m (a) -> (out)"
      , "  gate NOT g (a) -> missing"
      , "end"
      , "input a"
      , "wire out"
      , "instance m u (a) -> (out)"
      ])

testCircularModuleInstantiation :: IO Bool
testCircularModuleInstantiation =
  check "parser rejects circular module instantiation" $ isLeft $
    parseNetlist (unlines
      [ "module loop (a) -> (out)"
      , "  instance loop inner (a) -> (out)"
      , "end"
      , "input a"
      , "wire out"
      , "instance loop top (a) -> (out)"
      ])

testGoldenGatesVCD :: IO Bool
testGoldenGatesVCD = do
  source <- readFile "fixtures/gates.net"
  golden <- readFile "fixtures/gates.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("a", Low), ("b", High)]
            [ (2, "a", High), (2, "b", High)
            , (4, "a", High), (4, "b", Low)
            , (6, "a", Low), (6, "b", Low)
            ] 7
        pure (renderVCD simulation)
  check "gates VCD matches golden file" (actual == Right golden)

testGoldenHaddaderVCD :: IO Bool
testGoldenHaddaderVCD = do
  source <- readFile "fixtures/haddader.net"
  golden <- readFile "fixtures/haddader.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <- simulateWithInputs netlist
          [ ("a0", High), ("a1", High), ("a2", Low), ("a3", Low)
          , ("b0", High), ("b1", Low), ("b2", High), ("b3", Low)
          , ("cin", Low)
          ] 0
        pure (renderVCD simulation)
  check "hierarchical adder VCD matches golden file" (actual == Right golden)

testGoldenHcounterVCD :: IO Bool
testGoldenHcounterVCD = do
  source <- readFile "fixtures/hcounter.net"
  golden <- readFile "fixtures/hcounter.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <- simulate netlist 8
        pure (renderVCD simulation)
  check "hierarchical counter VCD matches golden file" (actual == Right golden)

testGoldenAdderVCD :: IO Bool
testGoldenAdderVCD = do
  source <- readFile "fixtures/adder.net"
  golden <- readFile "fixtures/adder.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <- simulateWithInputs netlist
          [ ("a0", High), ("a1", High), ("a2", Low), ("a3", Low)
          , ("b0", High), ("b1", Low), ("b2", High), ("b3", Low)
          , ("cin", Low)
          ] 0
        pure (renderVCD simulation)
  check "adder VCD matches golden file" (actual == Right golden)

testLogicParseFourState :: IO Bool
testLogicParseFourState =
  check "parser maps x and z to unknown and floating" $
    parseLogic "0" == Just Low
      && parseLogic "1" == Just High
      && parseLogic "x" == Just Undefined
      && parseLogic "z" == Just TriState
      && parseLogic "X" == Just Undefined
      && parseLogic "Z" == Just TriState
      && parseLogic "2" == Nothing

testUndefinedPropagatesThroughGates :: IO Bool
testUndefinedPropagatesThroughGates =
  check "undefined propagates through gates" $
    evalGate Not [Undefined] == Undefined
      && evalGate And [Undefined, High] == Undefined
      && evalGate And [Undefined, Low] == Low
      && evalGate Or [Undefined, High] == High
      && evalGate Or [Undefined, Low] == Undefined
      && evalGate Xor [Undefined, High] == Undefined
      && evalGate Nand [Undefined, Low] == High
      && evalGate Nor [Undefined, High] == Low
      && evalGate Xnor [Undefined, High] == Undefined

testTriStateReadsAsUnknown :: IO Bool
testTriStateReadsAsUnknown =
  check "gates read a floating input as unknown" $
    evalGate Not [TriState] == Undefined
      && evalGate And [TriState, High] == Undefined
      && evalGate Or [TriState, High] == High
      && evalGate And [TriState, Low] == Low
      && evalGate Xor [TriState, High] == Undefined

testTribufTruth :: IO Bool
testTribufTruth =
  check "TRIBUF follows its truth table" $
    evalGate Tribuf [Low, Low] == TriState
      && evalGate Tribuf [High, Low] == TriState
      && evalGate Tribuf [Low, High] == Low
      && evalGate Tribuf [High, High] == High
      && evalGate Tribuf [Low, Undefined] == Undefined
      && evalGate Tribuf [Low, TriState] == Undefined
      && evalGate Tribuf [TriState, High] == Undefined
      && evalGate Tribuf [High, High] == High

testDffInitUndefined :: IO Bool
testDffInitUndefined =
  let netlist = parseNetlist "input d\noutput q\nclock clk period=4\ndff f clock=clk d=d q=q init=x"
  in case netlist of
    Left _ -> check "dff init=x shows unknown until clocked" False
    Right parsed -> check "dff init=x shows unknown until clocked" $ case
      simulateWithInputs parsed [("d", High)] 4 of
        Right simulation -> signalChanges simulation "q" == [(0, Undefined), (2, High)]
        Left _ -> False

testScheduledInputWithTriState :: IO Bool
testScheduledInputWithTriState =
  let netlist = parseNetlist "input en\nwire y\noutput y\ngate NOT inv (en) -> y"
  in case netlist of
    Left _ -> check "scheduled tri-state input is recorded" False
    Right parsed -> check "scheduled tri-state input is recorded" $ case
      simulateWithScheduledInputs parsed [] [(2, "en", TriState)] 4 of
        Right simulation ->
          valueAt simulation "en" 2 == TriState
            && valueAt simulation "y" 2 == Undefined
        Left _ -> False

testParserAcceptsFourStateAssertion :: IO Bool
testParserAcceptsFourStateAssertion =
  check "parser accepts x and z assertion values" $ case
    parseNetlist
      "input en\nwire y\noutput y\ngate TRIBUF driver (en,en) -> y\nassert y = z at 0\nassert y = x at 2\n"
      of
      Right netlist ->
        netlistAssertions netlist
          == [Assertion "y" TriState 0, Assertion "y" Undefined 2]
      Left _ -> False

testVCDRendersUndefinedAndTriState :: IO Bool
testVCDRendersUndefinedAndTriState = case
  parseNetlist (unlines
    [ "input en"
    , "wire y"
    , "wire ny"
    , "output y"
    , "output ny"
    , "gate TRIBUF driver (en,en) -> y"
    , "gate NOT observer (y) -> ny"
    ]) of
    Left _ -> check "VCD renders x and z values" False
    Right netlist -> check "VCD renders x and z values" $ case
      simulateWithInputs netlist [("en", Low)] 3 of
        Right simulation ->
          let text = renderVCD simulation
          in any (startsWith 'z') (lines text)
               && any (startsWith 'x') (lines text)
        Left _ -> False
  where
    startsWith character line = not (null line) && head line == character

testTribufFixture :: IO Bool
testTribufFixture = do
  source <- readFile "fixtures/tristate.net"
  case parseNetlist source of
    Left _ -> check "tri-state fixture simulates the buffer" False
    Right netlist -> check "tri-state fixture simulates the buffer" $ case
      simulateWithScheduledInputs netlist [("d", Low), ("en", Low)]
        [(2, "en", High), (4, "d", High), (6, "en", Low)] 8 of
        Right simulation ->
          valueAt simulation "y" 0 == TriState
            && valueAt simulation "y" 3 == Low
            && valueAt simulation "y" 5 == High
            && valueAt simulation "y" 7 == TriState
            && valueAt simulation "nz" 0 == Undefined
            && valueAt simulation "nz" 3 == High
            && valueAt simulation "nz" 5 == Low
            && valueAt simulation "nz" 7 == Undefined
            && null (simulationFailures simulation)
        Left _ -> False

testUndefinedFixture :: IO Bool
testUndefinedFixture = do
  source <- readFile "fixtures/unknown.net"
  case parseNetlist source of
    Left _ -> check "undefined fixture simulates the register" False
    Right netlist -> check "undefined fixture simulates the register" $ case
      simulateWithScheduledInputs netlist [("d", High)] [(4, "d", Low)] 8 of
        Right simulation ->
          valueAt simulation "q" 0 == Undefined
            && valueAt simulation "nq" 0 == Undefined
            && valueAt simulation "q" 3 == High
            && valueAt simulation "nq" 3 == Low
            && valueAt simulation "q" 5 == Low
            && valueAt simulation "nq" 5 == High
            && null (simulationFailures simulation)
        Left _ -> False

testGoldenTribufVCD :: IO Bool
testGoldenTribufVCD = do
  source <- readFile "fixtures/tristate.net"
  golden <- readFile "fixtures/tristate.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("d", Low), ("en", Low)]
            [(2, "en", High), (4, "d", High), (6, "en", Low)] 8
        pure (renderVCD simulation)
  check "tri-state VCD matches golden file" (actual == Right golden)

testGoldenUnknownVCD :: IO Bool
testGoldenUnknownVCD = do
  source <- readFile "fixtures/unknown.net"
  golden <- readFile "fixtures/unknown.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("d", High)] [(4, "d", Low)] 8
        pure (renderVCD simulation)
  check "undefined VCD matches golden file" (actual == Right golden)

testBusDeclarations :: IO Bool
testBusDeclarations =
  check "bus declarations expand to single-bit signals" $ case
    parseNetlist (unlines
      [ "input a[4]"
      , "output x[2]"
      , "wire x[2]"
      , "wire w[3]"
      ]) of
      Right netlist ->
        netlistInputs netlist == ["a[0]", "a[1]", "a[2]", "a[3]"]
          && netlistOutputs netlist == ["x[0]", "x[1]"]
          && netlistWires netlist == ["x[0]", "x[1]", "w[0]", "w[1]", "w[2]"]
      Left _ -> False

testBusGateBitwise :: IO Bool
testBusGateBitwise = case
  parseNetlist (unlines
    [ "input a[4]"
    , "input b[4]"
    , "output x[4]"
    , "wire x[4]"
    , "gate XOR combine (a,b) -> x"
    ]) of
    Left _ -> check "a bus gate applies bitwise" False
    Right netlist -> check "a bus gate applies bitwise" $ case
      simulateWithInputs netlist (busInputs "a" 5 4 ++ busInputs "b" 10 4) 0 of
        Right simulation ->
          valueAt simulation "x[0]" 0 == High
            && valueAt simulation "x[1]" 0 == High
            && valueAt simulation "x[2]" 0 == High
            && valueAt simulation "x[3]" 0 == High
        Left _ -> False

testBusBitReference :: IO Bool
testBusBitReference = case
  parseNetlist (unlines
    [ "input a[4]"
    , "input b[4]"
    , "output c0"
    , "output c1"
    , "wire c0"
    , "wire c1"
    , "gate AND first (a[0],b[0]) -> c0"
    , "gate OR last (a[3],b[3]) -> c1"
    ]) of
    Left _ -> check "a bit reference reads one bus element" False
    Right netlist -> check "a bit reference reads one bus element" $ case
      simulateWithInputs netlist (busInputs "a" 5 4 ++ busInputs "b" 10 4) 0 of
        Right simulation ->
          valueAt simulation "c0" 0 == Low
            && valueAt simulation "c1" 0 == High
        Left _ -> False

testBusSliceReference :: IO Bool
testBusSliceReference = case
  parseNetlist (unlines
    [ "input a[4]"
    , "input b[4]"
    , "output hi[2]"
    , "wire hi[2]"
    , "gate AND mask (a[3:2],b[3:2]) -> hi"
    ]) of
    Left _ -> check "a slice reference pairs equal widths" False
    Right netlist -> check "a slice reference pairs equal widths" $ case
      simulateWithInputs netlist (busInputs "a" 5 4 ++ busInputs "b" 10 4) 0 of
        Right simulation ->
          valueAt simulation "hi[0]" 0 == Low
            && valueAt simulation "hi[1]" 0 == Low
        Left _ -> False

testBusRegisterSamples :: IO Bool
testBusRegisterSamples = case
  parseNetlist (unlines
    [ "input a[4]"
    , "output q[4]"
    , "clock clk period=2"
    , "dff reg clock=clk d=a q=q init=0,0,0,0"
    ]) of
    Left _ -> check "a bus register samples every bit" False
    Right netlist -> check "a bus register samples every bit" $ case
      simulateWithInputs netlist (busInputs "a" 9 4) 3 of
        Right simulation ->
          valueAt simulation "q[0]" 1 == High
            && valueAt simulation "q[1]" 1 == Low
            && valueAt simulation "q[2]" 1 == Low
            && valueAt simulation "q[3]" 1 == High
        Left _ -> False

testBusAssertions :: IO Bool
testBusAssertions = case
  parseNetlist (unlines
    [ "input a[4]"
    , "input b[4]"
    , "output x[4]"
    , "wire x[4]"
    , "gate XOR combine (a,b) -> x"
    , "assert x[0] = 1 at 0"
    , "assert x[3] = 1 at 0"
    ]) of
    Left _ -> check "assertions accept bus bits" False
    Right netlist -> check "assertions accept bus bits" $ case
      simulateWithInputs netlist (busInputs "a" 5 4 ++ busInputs "b" 10 4) 0 of
        Right simulation ->
          null (simulationFailures simulation)
            && length (simulationAssertions simulation) == 2
        Left _ -> False

testBusModulePorts :: IO Bool
testBusModulePorts = case
  parseNetlist (unlines
    [ "module invert_bus (a[4]) -> (n[4])"
    , "  gate NOT invert (a) -> n"
    , "end"
    , "input a[4]"
    , "output n[4]"
    , "wire n[4]"
    , "instance invert_bus inv (a) -> (n)"
    ]) of
    Left _ -> check "modules pass buses through ports" False
    Right netlist -> check "modules pass buses through ports" $ case
      simulateWithInputs netlist (busInputs "a" 10 4) 0 of
        Right simulation ->
          valueAt simulation "n[0]" 0 == High
            && valueAt simulation "n[1]" 0 == Low
            && valueAt simulation "n[2]" 0 == High
            && valueAt simulation "n[3]" 0 == Low
        Left _ -> False

testBusFixture :: IO Bool
testBusFixture = do
  source <- readFile "fixtures/bus.net"
  case parseNetlist source of
    Left _ -> check "bus fixture simulates bus operations" False
    Right netlist -> check "bus fixture simulates bus operations" $ case
      simulateWithInputs netlist (busInputs "a" 5 4 ++ busInputs "b" 10 4) 3 of
        Right simulation ->
          null (simulationFailures simulation)
            && valueAt simulation "x[0]" 0 == High
            && valueAt simulation "x[3]" 0 == High
            && valueAt simulation "n[0]" 0 == Low
            && valueAt simulation "hi[0]" 0 == Low
            && valueAt simulation "hi[1]" 0 == Low
            && valueAt simulation "c0" 0 == High
            && valueAt simulation "q[2]" 1 == High
        Left _ -> False

testParserRejectsBusOutOfRange :: IO Bool
testParserRejectsBusOutOfRange =
  check "parser rejects out-of-range bus indexes" $
    isLeft (parseNetlist (unlines
      [ "input a[4]"
      , "wire x"
      , "gate NOT inv (a[4]) -> x"
      ]))
      && isLeft (parseNetlist (unlines
      [ "input a[4]"
      , "wire x[2]"
      , "gate NOT inv (a[5:2]) -> x"
      ]))

testParserRejectsBusWidthMismatch :: IO Bool
testParserRejectsBusWidthMismatch =
  check "parser rejects mixed gate widths" $ isLeft $
    parseNetlist (unlines
      [ "input a[4]"
      , "input b"
      , "output x[4]"
      , "wire x[4]"
      , "gate XOR combine (a,b) -> x"
      ])

testParserRejectsBusInvalidSlice :: IO Bool
testParserRejectsBusInvalidSlice =
  check "parser rejects invalid slice syntax" $
    isLeft (parseNetlist (unlines
      [ "input a[4]"
      , "wire x"
      , "gate NOT inv (a[2:5]) -> x"
      ]))
      && isLeft (parseNetlist (unlines
      [ "input a[4]"
      , "wire x"
      , "gate NOT inv (a[x]) -> x"
      ]))

testParserRejectsBusWholeAssertion :: IO Bool
testParserRejectsBusWholeAssertion =
  check "parser rejects whole-bus assertions" $ isLeft $
    parseNetlist (unlines
      [ "input a[4]"
      , "output x[4]"
      , "wire x[4]"
      , "gate NOT inv (a) -> x"
      , "assert x = 0 at 0"
      ])

testParserRejectsBusDffWidthMismatch :: IO Bool
testParserRejectsBusDffWidthMismatch =
  check "parser rejects mismatched dff bus widths" $ isLeft $
    parseNetlist (unlines
      [ "input a[4]"
      , "output q[2]"
      , "clock clk period=2"
      , "dff reg clock=clk d=a q=q init=0,0"
      ])

testParserRejectsBusConflictingWidths :: IO Bool
testParserRejectsBusConflictingWidths =
  check "parser rejects conflicting bus widths" $ isLeft $
    parseNetlist (unlines
      [ "input a[4]"
      , "wire a[2]"
      ])

testParserRejectsBusInstancePortMismatch :: IO Bool
testParserRejectsBusInstancePortMismatch =
  check "parser rejects mismatched instance bus ports" $ isLeft $
    parseNetlist (unlines
      [ "module invert_bus (a[4]) -> (n[4])"
      , "  gate NOT invert (a) -> n"
      , "end"
      , "input a"
      , "output n[4]"
      , "wire n[4]"
      , "instance invert_bus inv (a) -> (n)"
      ])

testGoldenBusVCD :: IO Bool
testGoldenBusVCD = do
  source <- readFile "fixtures/bus.net"
  golden <- readFile "fixtures/bus.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <- simulateWithInputs netlist (busInputs "a" 5 4 ++ busInputs "b" 10 4) 3
        pure (renderVCD simulation)
  check "bus VCD matches golden file" (actual == Right golden)

testSharedBusFixture :: IO Bool
testSharedBusFixture = do
  source <- readFile "fixtures/shared.net"
  case parseNetlist source of
    Left _ -> check "shared bus fixture simulates the wire" False
    Right netlist -> check "shared bus fixture simulates the wire" $ case
      simulateWithScheduledInputs netlist [("d0", Low), ("d1", High)]
        [(2, "e0", High), (4, "e1", High), (6, "e0", Low)] 8 of
        Right simulation ->
          valueAt simulation "y" 0 == TriState
            && valueAt simulation "ny" 0 == Undefined
            && valueAt simulation "y" 3 == Low
            && valueAt simulation "ny" 3 == High
            && valueAt simulation "y" 5 == Undefined
            && valueAt simulation "ny" 5 == Undefined
            && valueAt simulation "y" 7 == High
            && valueAt simulation "ny" 7 == Low
            && null (simulationFailures simulation)
        Left _ -> False

testGoldenSharedVCD :: IO Bool
testGoldenSharedVCD = do
  source <- readFile "fixtures/shared.net"
  golden <- readFile "fixtures/shared.golden.vcd"
  let actual = do
        netlist <- parseNetlist source
        simulation <-
          simulateWithScheduledInputs netlist [("d0", Low), ("d1", High)]
            [(2, "e0", High), (4, "e1", High), (6, "e0", Low)] 8
        pure (renderVCD simulation)
  check "shared bus VCD matches golden file" (actual == Right golden)

evalTwoState :: GateType -> [Logic] -> Logic
evalTwoState And inputs = if all (== High) inputs then High else Low
evalTwoState Or inputs = if any (== High) inputs then High else Low
evalTwoState Xor inputs = foldl' xorTwo Low inputs
evalTwoState Nand inputs = if all (== High) inputs then Low else High
evalTwoState Nor inputs = if any (== High) inputs then Low else High
evalTwoState Xnor inputs = invertTwo (foldl' xorTwo Low inputs)
evalTwoState Not inputs = case inputs of
  input : _ -> invertTwo input
  [] -> Low
evalTwoState Tribuf _ = Low

xorTwo :: Logic -> Logic -> Logic
xorTwo Low High = High
xorTwo High Low = High
xorTwo _ _ = Low

invertTwo :: Logic -> Logic
invertTwo High = Low
invertTwo _ = High

propTwoStateMatchesReference :: Known -> Known -> Bool
propTwoStateMatchesReference (Known left) (Known right) =
  and
    [ evalGate And [left, right] == evalTwoState And [left, right]
    , evalGate Or [left, right] == evalTwoState Or [left, right]
    , evalGate Xor [left, right] == evalTwoState Xor [left, right]
    , evalGate Nand [left, right] == evalTwoState Nand [left, right]
    , evalGate Nor [left, right] == evalTwoState Nor [left, right]
    , evalGate Xnor [left, right] == evalTwoState Xnor [left, right]
    , evalGate Not [left] == evalTwoState Not [left]
    ]

propUndefinedCommutative :: Known -> Bool
propUndefinedCommutative (Known value) =
  and
    [ evalGate And [Undefined, value] == evalGate And [value, Undefined]
    , evalGate Or [Undefined, value] == evalGate Or [value, Undefined]
    , evalGate Xor [Undefined, value] == evalGate Xor [value, Undefined]
    , evalGate Nand [Undefined, value] == evalGate Nand [value, Undefined]
    , evalGate Nor [Undefined, value] == evalGate Nor [value, Undefined]
    , evalGate Xnor [Undefined, value] == evalGate Xnor [value, Undefined]
    ]

propTribufTruth :: FourState -> FourState -> Bool
propTribufTruth (FourState dataValue) (FourState enable) =
  evalGate Tribuf [dataValue, enable] == expected
  where
    expected = case enable of
      Low -> TriState
      High -> case dataValue of
        TriState -> Undefined
        _ -> dataValue
      _ -> Undefined

propTribufEnable :: Known -> Bool
propTribufEnable (Known dataValue) =
  evalGate Tribuf [dataValue, Low] == TriState
    && evalGate Tribuf [dataValue, High] == dataValue

propTribufFixtureSound :: Netlist -> Property
propTribufFixtureSound netlist =
  forAll (elements [Low, High]) $ \dataValue ->
    forAll (elements [Low, High]) $ \enable ->
      let expectedY = if enable == Low then TriState else dataValue
          expectedNz = if enable == Low then Undefined else invertTwo dataValue
      in case simulateWithInputs netlist [("d", dataValue), ("en", enable)] 8 of
        Right simulation ->
          property
            ( valueAt simulation "y" 0 == expectedY
                && valueAt simulation "nz" 0 == expectedNz
            )
        Left _ -> property False

propUnknownFixtureSampling :: Netlist -> Property
propUnknownFixtureSampling netlist =
  forAll (elements [Low, High]) $ \dataValue ->
    case simulateWithInputs netlist [("d", dataValue)] 8 of
      Right simulation ->
        property
          ( valueAt simulation "q" 0 == Undefined
              && valueAt simulation "q" 3 == dataValue
              && valueAt simulation "nq" 0 == Undefined
              && valueAt simulation "nq" 3 == invertTwo dataValue
          )
      Left _ -> property False

busXorNetlist :: Either String Netlist
busXorNetlist = parseNetlist (unlines
  [ "input a[4]"
  , "input b[4]"
  , "output x[4]"
  , "wire x[4]"
  , "gate XOR combine (a,b) -> x"
  ])

busRegisterNetlist :: Either String Netlist
busRegisterNetlist = parseNetlist (unlines
  [ "input a[4]"
  , "output q[4]"
  , "clock clk period=2"
  , "dff reg clock=clk d=a q=q init=0,0,0,0"
  ])

flatBusNetlist :: Either String Netlist
flatBusNetlist = parseNetlist (unlines
  [ "input a[4]"
  , "input b[4]"
  , "output x[4]"
  , "output n[4]"
  , "output q[4]"
  , "clock clk period=2"
  , "wire x[4]"
  , "wire n[4]"
  , "gate XOR combine (a,b) -> x"
  , "gate NOT invert (x) -> n"
  , "dff reg clock=clk d=x q=q init=0,0,0,0"
  ])

hierarchicalBusNetlist :: Either String Netlist
hierarchicalBusNetlist = parseNetlist (unlines
  [ "module bitnot (a[4]) -> (n[4])"
  , "  gate NOT invert (a) -> n"
  , "end"
  , "input a[4]"
  , "input b[4]"
  , "output x[4]"
  , "output n[4]"
  , "output q[4]"
  , "clock clk period=2"
  , "wire x[4]"
  , "wire n[4]"
  , "gate XOR combine (a,b) -> x"
  , "instance bitnot inv (x) -> (n)"
  , "dff reg clock=clk d=x q=q init=0,0,0,0"
  ])

propBusXorBitwise :: Property
propBusXorBitwise =
  forAll (choose (0, 15)) $ \aValue ->
    forAll (choose (0, 15)) $ \bValue ->
      case busXorNetlist of
        Left _ -> property False
        Right netlist ->
          case simulateWithInputs netlist (busInputs "a" aValue 4 ++ busInputs "b" bValue 4) 0 of
            Right simulation -> property (busValueAt simulation "x" 4 0 == aValue `xor` bValue)
            Left _ -> property False

propBusRegisterSampling :: Property
propBusRegisterSampling =
  forAll (choose (0, 15)) $ \aValue ->
    case busRegisterNetlist of
      Left _ -> property False
      Right netlist ->
        case simulateWithInputs netlist (busInputs "a" aValue 4) 3 of
          Right simulation ->
            property
              ( busValueAt simulation "q" 4 0 == 0
                  && busValueAt simulation "q" 4 1 == aValue
                  && busValueAt simulation "q" 4 3 == aValue
              )
          Left _ -> property False

propBusModuleMatchesFlat :: Property
propBusModuleMatchesFlat =
  forAll (choose (0, 15)) $ \aValue ->
    forAll (choose (0, 15)) $ \bValue ->
      forAll (choose (0, 8)) $ \duration ->
        case (flatBusNetlist, hierarchicalBusNetlist) of
          (Right flat, Right hierarchical) ->
            case ( simulateWithInputs flat (busInputs "a" aValue 4 ++ busInputs "b" bValue 4) duration
                 , simulateWithInputs hierarchical (busInputs "a" aValue 4 ++ busInputs "b" bValue 4) duration
                 ) of
              (Right flatResult, Right hierarchicalResult) ->
                property (busSignalsMatch flatResult hierarchicalResult [0 .. duration])
              _ -> property False
          _ -> property False
  where
    busSignalsMatch flatResult hierarchicalResult times =
      all (sameAt flatResult hierarchicalResult) times
    sameAt flatResult hierarchicalResult time =
      all
        (\signal -> valueAt flatResult signal time == valueAt hierarchicalResult signal time)
        [ "x[0]", "x[1]", "x[2]", "x[3]"
        , "n[0]", "n[1]", "n[2]", "n[3]"
        , "q[0]", "q[1]", "q[2]", "q[3]"
        ]

propSharedBusResolution :: Netlist -> Property
propSharedBusResolution netlist =
  forAll (choose (0, 6)) $ \count ->
    forAll (vector (4 * count)) $ \bits ->
      let d0s = take count bits
          d1s = take count (drop count bits)
          e0s = take count (drop (2 * count) bits)
          e1s = take count (drop (3 * count) bits)
          times = [1 :: Int .. count]
          transitions = concat
            [ [(2 * fromIntegral k, name, boolToLogic value) | (k, value) <- zip times values]
            | (name, values) <- [("d0", d0s), ("d1", d1s), ("e0", e0s), ("e1", e1s)]
            ]
          duration = 2 * fromIntegral count + 1
      in case simulateWithScheduledInputs netlist {netlistAssertions = []} [] transitions duration of
        Left _ -> property False
        Right simulation ->
          property (all (sampleMatches simulation) [0 .. duration])
  where
    sampleMatches simulation time =
      let contribution dataValue enable = if enable == High then dataValue else TriState
          expectedY = resolveValue
            [ contribution (valueAt simulation "d0" time) (valueAt simulation "e0" time)
            , contribution (valueAt simulation "d1" time) (valueAt simulation "e1" time)
            ]
          expectedNy = evalGate Not [expectedY]
      in valueAt simulation "y" time == expectedY
          && valueAt simulation "ny" time == expectedNy

propNandInvertsAnd :: Logical -> Logical -> Bool
propNandInvertsAnd (Logical left) (Logical right) =
  evalGate Nand [left, right] == not1 (and2 left right)

propNorInvertsOr :: Logical -> Logical -> Bool
propNorInvertsOr (Logical left) (Logical right) =
  evalGate Nor [left, right] == not1 (or2 left right)

propXnorInvertsXor :: Logical -> Logical -> Bool
propXnorInvertsXor (Logical left) (Logical right) =
  evalGate Xnor [left, right] == not1 (xor2 left right)

propHierarchicalAdderMatchesFlat :: Netlist -> Netlist -> Property
propHierarchicalAdderMatchesFlat flat hierarchical =
  forAll (choose (0, 15)) $ \a ->
    forAll (choose (0, 15)) $ \b ->
      forAll (elements [Low, High]) $ \carryIn ->
        let expected = a + b + (if carryIn == High then 1 else 0)
        in case ( simulateWithInputs flat (adderInputs a b carryIn) 0
                , simulateWithInputs hierarchical (adderInputs a b carryIn) 0
                ) of
          (Right flatResult, Right hierarchicalResult) ->
            property
              ( resultToInt flatResult == expected
                  && resultToInt hierarchicalResult == expected
              )
          _ -> property False

propHierarchicalCounterMatchesFlat :: Netlist -> Netlist -> Property
propHierarchicalCounterMatchesFlat flat hierarchical =
  forAll (choose (0, 30)) $ \duration ->
    case (simulate flat duration, simulate hierarchical duration) of
      (Right flatResult, Right hierarchicalResult) ->
        property (all (sameBits flatResult hierarchicalResult) [0 .. duration])
      _ -> property False
  where
    sameBits flatResult hierarchicalResult time =
      all
        (\name -> valueAt flatResult name time == valueAt hierarchicalResult name time)
        (map fst counterBits)

propGatesFixture :: Netlist -> Property
propGatesFixture netlist =
  forAll (elements [Low, High]) $ \a ->
    forAll (elements [Low, High]) $ \b ->
      case simulateWithInputs netlist [("a", a), ("b", b)] 7 of
        Right simulation ->
          property
            ( valueAt simulation "nand_out" 6 == evalGate Nand [a, b]
                && valueAt simulation "nor_out" 6 == evalGate Nor [a, b]
                && valueAt simulation "xnor_out" 6 == evalGate Xnor [a, b]
            )
        Left _ -> property False

propAndCommutative :: Logical -> Logical -> Bool
propAndCommutative (Logical left) (Logical right) =
  and2 left right == and2 right left
propOrCommutative :: Logical -> Logical -> Bool
propOrCommutative (Logical left) (Logical right) =
  or2 left right == or2 right left

propXorCommutative :: Logical -> Logical -> Bool
propXorCommutative (Logical left) (Logical right) =
  xor2 left right == xor2 right left

propAndAssociative :: Logical -> Logical -> Logical -> Bool
propAndAssociative (Logical a) (Logical b) (Logical c) =
  and2 a (and2 b c) == and2 (and2 a b) c

propOrAssociative :: Logical -> Logical -> Logical -> Bool
propOrAssociative (Logical a) (Logical b) (Logical c) =
  or2 a (or2 b c) == or2 (or2 a b) c

propXorAssociative :: Logical -> Logical -> Logical -> Bool
propXorAssociative (Logical a) (Logical b) (Logical c) =
  xor2 a (xor2 b c) == xor2 (xor2 a b) c

propAndIdentity :: Logical -> Bool
propAndIdentity (Logical value) = and2 value High == value

propOrIdentity :: Logical -> Bool
propOrIdentity (Logical value) = or2 value Low == value

propXorIdentity :: Logical -> Bool
propXorIdentity (Logical value) = xor2 value Low == value

propAndAnnihilator :: Logical -> Bool
propAndAnnihilator (Logical value) = and2 value Low == Low

propOrDominator :: Logical -> Bool
propOrDominator (Logical value) = or2 value High == High

propNotInvolution :: Logical -> Bool
propNotInvolution (Logical value) = not1 (not1 value) == value

propXorSelf :: Logical -> Bool
propXorSelf (Logical value) = xor2 value value == Low

propDeMorganAnd :: Logical -> Logical -> Bool
propDeMorganAnd (Logical left) (Logical right) =
  not1 (and2 left right) == or2 (not1 left) (not1 right)

propDeMorganOr :: Logical -> Logical -> Bool
propDeMorganOr (Logical left) (Logical right) =
  not1 (or2 left right) == and2 (not1 left) (not1 right)

propAbsorptionAnd :: Logical -> Logical -> Bool
propAbsorptionAnd (Logical a) (Logical b) =
  and2 a (or2 a b) == a

propAbsorptionOr :: Logical -> Logical -> Bool
propAbsorptionOr (Logical a) (Logical b) =
  or2 a (and2 a b) == a

propDistribution :: Logical -> Logical -> Logical -> Bool
propDistribution (Logical a) (Logical b) (Logical c) =
  and2 a (or2 b c) == or2 (and2 a b) (and2 a c)

propXnorIdentity :: Logical -> Logical -> Bool
propXnorIdentity (Logical left) (Logical right) =
  xor2 left (not1 right) == not1 (xor2 left right)

propRippleCarryAdder :: Netlist -> Property
propRippleCarryAdder netlist =
  forAll (choose (0, 15)) $ \a ->
    forAll (choose (0, 15)) $ \b ->
      forAll (elements [Low, High]) $ \carryIn ->
        let expected = a + b + (if carryIn == High then 1 else 0)
        in case simulateWithInputs netlist (adderInputs a b carryIn) 0 of
          Right simulation -> resultToInt simulation == expected
          Left _ -> False

propScheduledInputSampling :: Netlist -> Property
propScheduledInputSampling netlist =
  forAll (choose (1, 6)) $ \count ->
    forAll (vector count) $ \dataValues ->
      let times = [2 * fromIntegral index | index <- [1 .. count]] :: [Time]
          transitions = zip3 times (repeat "d") (map boolToLogic dataValues)
          duration = 2 * fromIntegral count + 1
      in case simulateWithScheduledInputs netlist [("d", High)] transitions duration of
        Left _ -> property False
        Right simulation ->
          property (all (samplesMatch simulation dataValues) [1, 3 .. duration])
  where
    samplesMatch simulation dataValues edge =
      let preceding = (edge - 1) `div` 2
          reference = if preceding >= 1 then dataValues !! (fromIntegral preceding - 1) else True
          expected = boolToLogic reference
      in valueAt simulation "d" (edge - 1) == expected
          && valueAt simulation "q" edge == expected

data RefEvent
  = RefData Logic
  | RefReset Logic
  | RefEdge

referenceChanges :: [(Time, RefEvent)] -> [(Time, Logic)]
referenceChanges events = reverse changesRev
  where
    (changesRev, _, _, _) = foldl step ([(0, Low)], Low, Low, Low) events
    step (acc, d, r, q) (time, event) = case event of
      RefData value -> (acc, value, r, q)
      RefReset value ->
        let nextQ = if value == High then Low else q
        in (record time nextQ q acc, d, value, nextQ)
      RefEdge ->
        let nextQ = if r == High then Low else d
        in (record time nextQ q acc, d, r, nextQ)
    record time nextQ oldQ acc
      | nextQ == oldQ = acc
      | otherwise = (time, nextQ) : acc

propResetSampling :: Netlist -> Property
propResetSampling netlist =
  forAll (choose (1, 6)) $ \count ->
    forAll (vector count) $ \dataValues ->
      forAll (vector count) $ \resetValues ->
        let transitions =
              [ (2 * fromIntegral k, "d", boolToLogic value)
              | (k, value) <- zip [1 :: Int .. count] dataValues
              ]
              ++ [ (2 * fromIntegral k, "rst", boolToLogic value)
                 | (k, value) <- zip [1 :: Int .. count] resetValues
                 ]
            duration = 2 * fromIntegral count + 1
            events = sortOn fst $ concat
              [ [ (2 * fromIntegral k + 1, RefEdge) | k <- [0 :: Int .. count] ]
              , [ (2 * fromIntegral k, RefData (boolToLogic value))
                | (k, value) <- zip [1 :: Int .. count] dataValues
                ]
              , [ (2 * fromIntegral k, RefReset (boolToLogic value))
                | (k, value) <- zip [1 :: Int .. count] resetValues
                ]
              ]
        in case simulateWithScheduledInputs netlist [] transitions duration of
          Left _ -> property False
          Right simulation -> property (signalChanges simulation "q" == referenceChanges events)

propRegisterWidthSampling :: Netlist -> Property
propRegisterWidthSampling netlist =
  forAll (choose (1, 5)) $ \count ->
    forAll (vector (2 * count)) $ \bits ->
      let data0 = take count bits
          data1 = drop count bits
          transitions =
            [ (2 * fromIntegral k, "d0", boolToLogic value)
            | (k, value) <- zip [1 :: Int .. count] data0
            ]
            ++ [ (2 * fromIntegral k, "d1", boolToLogic value)
               | (k, value) <- zip [1 :: Int .. count] data1
               ]
          duration = 2 * fromIntegral count + 1
      in case simulateWithScheduledInputs netlist [] transitions duration of
        Left _ -> property False
        Right simulation ->
          property
            ( signalChanges simulation "q0" == bitReference data0
                && signalChanges simulation "q1" == bitReference data1
            )
  where
    bitReference values =
      reverse (snd (foldl step (Low, [(0, Low)]) (zip [1 :: Int ..] values)))
    step (oldQ, acc) (k, value) =
      let edgeTime = 2 * fromIntegral k + 1
          nextQ = boolToLogic value
      in (nextQ, if nextQ == oldQ then acc else (edgeTime, nextQ) : acc)

propEquivalentEntryPoints :: Netlist -> Property
propEquivalentEntryPoints netlist =
  forAll (choose (0, 30)) $ \duration ->
    case simulateWithScheduledInputs netlist [] [] duration of
      Left _ -> property False
      Right viaScheduled -> case simulate netlist duration of
        Left _ -> property False
        Right direct ->
          property (renderVCD viaScheduled == renderVCD direct)

propAssertionSoundness :: Netlist -> Property
propAssertionSoundness netlist =
  forAll (choose (0, 30)) $ \duration ->
    forAll (elements (netlistSignals netlist)) $ \signal ->
      forAll (choose (0, duration)) $ \time ->
        case simulate netlist duration of
          Left _ -> property False
          Right simulation ->
            let assertTime = fromIntegral time
                actual = valueAt simulation signal assertTime
            in property
                 ( assertionPasses netlist signal actual assertTime
                     && assertionFails netlist signal (not1 actual) assertTime
                 )
  where
    assertionPasses base signal value time = case
      simulateWithScheduledInputs base {netlistAssertions = [Assertion signal value time]} [] [] 30 of
        Right simulation -> null (simulationFailures simulation)
        Left _ -> False
    assertionFails base signal value time = case
      simulateWithScheduledInputs base {netlistAssertions = [Assertion signal value time]} [] [] 30 of
        Right simulation -> length (simulationFailures simulation) == 1
        Left _ -> False

boolToLogic :: Bool -> Logic
boolToLogic True = High
boolToLogic False = Low

adderInputs :: Int -> Int -> Logic -> [(String, Logic)]
adderInputs a b carryIn =
  concat
    [ [ (name ++ show position, logicForBit (bit position value))
      | position <- [0 .. 3]
      ]
    | (name, value) <- [("a", a), ("b", b)]
    ]
    ++ [("cin", carryIn)]

bit :: Int -> Int -> Int
bit position value = (value `div` 2 ^ position) `mod` 2

logicForBit :: Int -> Logic
logicForBit 0 = Low
logicForBit _ = High

busInputs :: String -> Int -> Int -> [(String, Logic)]
busInputs base value width =
  [ (base ++ "[" ++ show index ++ "]", logicForBit (bit index value))
  | index <- [0 .. width - 1]
  ]

busValueAt :: Simulation -> String -> Int -> Time -> Int
busValueAt simulation base width time =
  sum
    [ (if valueAt simulation (base ++ "[" ++ show index ++ "]") time == High then 1 else 0) * (2 :: Int) ^ index
    | index <- [0 .. width - 1]
    ]

resultToInt :: Simulation -> Int
resultToInt simulation =
  sum
    [ (if finalValue simulation name == Just High then 1 else 0) * (2 :: Int) ^ position
    | (name, position) <- sumBits
    ]
    + (if finalValue simulation "cout" == Just High then 16 else 0)

counterValueAt :: Simulation -> Time -> Int
counterValueAt simulation time =
  sum
    [ (if valueAt simulation name time == High then 1 else 0) * (2 :: Int) ^ position
    | (name, position) <- counterBits
    ]

sumBits :: [(String, Int)]
sumBits = [("sum0", 0), ("sum1", 1), ("sum2", 2), ("sum3", 3)]

counterBits :: [(String, Int)]
counterBits = [("q0", 0), ("q1", 1), ("q2", 2), ("q3", 3)]

valueAt :: Simulation -> String -> Time -> Logic
valueAt simulation signal time =
  snd (last [(changeTime, value) | (changeTime, value) <- signalChanges simulation signal, changeTime <= time])

finalValue :: Simulation -> String -> Maybe Logic
finalValue simulation signal = case reverse (signalChanges simulation signal) of
  (_, value) : _ -> Just value
  [] -> Nothing

check :: String -> Bool -> IO Bool
check label condition = do
  putStrLn (label ++ ": " ++ if condition then "PASS" else "FAIL")
  pure condition
