module Main (main) where

import Control.Monad (forM)
import Data.Either (isLeft)
import Gatework.Logic (GateType (..), Logic (..), evalGate)
import Gatework.Netlist (Netlist (..), parseNetlist)
import Gatework.Simulator (Simulation, Time, signalChanges, simulate, simulateWithInputs)
import Gatework.VCD (renderVCD)
import System.Exit (exitFailure)
import Test.QuickCheck
  ( Arbitrary (..)
  , Property
  , choose
  , elements
  , forAll
  , quickCheckResult
  )
import Test.QuickCheck.Test (isSuccess)

newtype Logical = Logical Logic
  deriving (Eq, Show)

instance Arbitrary Logical where
  arbitrary = Logical <$> elements [Low, High]

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
  deterministic <- sequence
    [ testParser
    , testParserAcceptsCommentsAndBlankLines
    , testParserRejectsUnknownGate
    , testParserRejectsWrongArity
    , testParserRejectsEmptyInputs
    , testParserRejectsUndeclaredInput
    , testParserRejectsGateOutputWithoutWire
    , testParserRejectsDuplicateSignal
    , testParserRejectsDuplicateDrivenSignal
    , testParserRejectsInvalidClockPeriod
    , testParserRejectsInvalidIdentifier
    , testParserRejectsInvalidFlipFlop
    , testClockToggles
    , testDffSamplesOnRisingEdge
    , testDffRequiresDeclaredClock
    , testDffInitRespected
    , testEventLimitOnCombinationalLoop
    , testNegativeDurationRejected
    , testInputOverrideValidation
    , testCounter
    , testCounterFullSequence
    , testAdder
    , testVCDHeader
    , testGoldenVCD
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

testParserRejectsDuplicateDrivenSignal :: IO Bool
testParserRejectsDuplicateDrivenSignal =
  check "parser rejects duplicate driven signals" $ isLeft $
    parseNetlist "input x\nwire y\ngate NOT first (x) -> y\ngate NOT second (x) -> y"

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
