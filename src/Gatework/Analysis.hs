module Gatework.Analysis
  ( renderAnalysis
  ) where

import qualified Data.Map.Strict as Map
import Gatework.Logic (GateType (..))
import Gatework.Netlist
  ( Clock (..)
  , DFlipFlop (..)
  , Gate (..)
  , Latch (..)
  , Netlist (..)
  , netlistSignals
  )

renderAnalysis :: Netlist -> String
renderAnalysis netlist = unlines
  ( [ "Netlist analysis"
    , "================"
    , "Signals: " ++ show (length (netlistSignals netlist))
    , "  inputs: " ++ show (length (netlistInputs netlist))
    , "  outputs: " ++ show (length (netlistOutputs netlist))
    , "  wires: " ++ show (length (netlistWires netlist))
    , "Clocks: " ++ show (length (netlistClocks netlist))
    ]
      ++ map renderClock (netlistClocks netlist)
      ++ [ "Combinational gates: " ++ show (length gates)
         ]
      ++ renderGateCounts gates
      ++ [ "State:"
         , "  flip-flops: " ++ show (length flipFlops)
             ++ " (" ++ show (sum (map dffWidth flipFlops)) ++ " bits)"
         , "  latches: " ++ show (length latches)
             ++ " (" ++ show (sum (map latchWidth latches)) ++ " bits)"
         , "Timing:"
         , "  delayed gates: " ++ show (length (filter hasDelay gates))
         , "  clock-to-output delays: " ++ show (length (filter hasClockToOutputDelay flipFlops))
         , "Assertions: " ++ show (length (netlistAssertions netlist))
         ]
      ++ renderBuses (netlistBusWidths netlist)
  )
  where
    gates = netlistGates netlist
    flipFlops = netlistFlipFlops netlist
    latches = netlistLatches netlist

renderClock :: Clock -> String
renderClock clock =
  "  " ++ clockSignal clock ++ ": period " ++ show (clockPeriod clock)

renderGateCounts :: [Gate] -> [String]
renderGateCounts gates =
  [ "  " ++ gateLabel gateType ++ ": " ++ show count
  | gateType <- [And, Or, Xor, Not, Nand, Nor, Xnor, Buf, Mux, Maj, Tribuf]
  , let count = Map.findWithDefault 0 gateType counts
  , count > 0
  ]
  where
    counts = Map.fromListWith (+) [(gateType gate, 1 :: Int) | gate <- gates]

renderBuses :: [(String, Int)] -> [String]
renderBuses [] = ["Buses: none"]
renderBuses buses =
  ("Buses: " ++ show (length buses) ++ " (" ++ show (sum (map snd buses)) ++ " bits)")
    : ["  " ++ name ++ ": " ++ show width ++ " bits" | (name, width) <- buses]

gateLabel :: GateType -> String
gateLabel And = "AND"
gateLabel Or = "OR"
gateLabel Xor = "XOR"
gateLabel Not = "NOT"
gateLabel Nand = "NAND"
gateLabel Nor = "NOR"
gateLabel Xnor = "XNOR"
gateLabel Buf = "BUF"
gateLabel Mux = "MUX"
gateLabel Maj = "MAJ"
gateLabel Tribuf = "TRIBUF"

hasDelay :: Gate -> Bool
hasDelay gate = gateRiseDelay gate > 0 || gateFallDelay gate > 0

hasClockToOutputDelay :: DFlipFlop -> Bool
hasClockToOutputDelay flipFlop = dffClockToOutput flipFlop > 0

dffWidth :: DFlipFlop -> Int
dffWidth flipFlop = length (dffOutput flipFlop)

latchWidth :: Latch -> Int
latchWidth latch = length (latchOutput latch)
