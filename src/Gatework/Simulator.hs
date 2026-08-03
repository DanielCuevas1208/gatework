module Gatework.Simulator
  ( Simulation (..)
  , Time
  , signalChanges
  , simulate
  , simulateWithInputs
  ) where

import Data.List (foldl', nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Gatework.Logic
import Gatework.Netlist

type Time = Integer

data Simulation = Simulation
  { simulationDuration :: Time
  , simulationSignals :: [String]
  , simulationChanges :: Map String [(Time, Logic)]
  }
  deriving (Eq, Show)

data Pending
  = SignalEvent String Logic
  | FlipFlopBatch [(DFlipFlop, Logic)]

type EventQueue = Map Time [Pending]
type State = Map String Logic
type Changes = Map String [(Time, Logic)]

simulate :: Netlist -> Time -> Either String Simulation
simulate netlist duration = simulateWithInputs netlist [] duration

simulateWithInputs :: Netlist -> [(String, Logic)] -> Time -> Either String Simulation
simulateWithInputs netlist inputOverrides duration
  | duration < 0 = Left "simulation duration cannot be negative"
  | otherwise = do
      validateInputOverrides netlist inputOverrides
      let baseState = initialState netlist inputOverrides
          initialEvents = map (initialGateEvent baseState) (netlistGates netlist)
          queue = addInitialEvents (clockQueue netlist duration) initialEvents
          initialChanges = initialWaveform netlist baseState
      runQueue netlist duration queue baseState initialChanges

validateInputOverrides :: Netlist -> [(String, Logic)] -> Either String ()
validateInputOverrides netlist overrides = do
  let names = map fst overrides
  if length (nub names) /= length names
    then Left "input overrides cannot repeat a signal"
    else mapM_ validateName names
  where
    validateName name =
      if name `elem` netlistInputs netlist
        then Right ()
        else Left ("input override is not an input: " ++ name)

initialState :: Netlist -> [(String, Logic)] -> State
initialState netlist overrides =
  Map.union (Map.fromList overrides) dffState
  where
    dffState = foldl'
      (\state flipFlop -> Map.insert (dffOutput flipFlop) (dffInitial flipFlop) state)
      (Map.fromList [(signal, Low) | signal <- netlistSignals netlist])
      (netlistFlipFlops netlist)

initialWaveform :: Netlist -> State -> Changes
initialWaveform netlist state =
  Map.fromList
    [ (signal, [(0, Map.findWithDefault Low signal state)])
    | signal <- netlistSignals netlist
    ]

initialGateEvent :: State -> Gate -> Pending
initialGateEvent state gate = SignalEvent (gateOutput gate) (evaluateGate state gate)

addInitialEvents :: EventQueue -> [Pending] -> EventQueue
addInitialEvents queue events = Map.insertWith (++) 0 events queue

clockQueue :: Netlist -> Time -> EventQueue
clockQueue netlist duration = foldl' addClock Map.empty (netlistClocks netlist)
  where
    addClock queue clock = foldl' (addTransition clock) queue (transitionTimes clock duration)
    addTransition clock queue time =
      Map.insertWith (++) time [SignalEvent (clockSignal clock) (clockValue clock time)] queue

transitionTimes :: Clock -> Time -> [Time]
transitionTimes clock duration =
  let halfPeriod = fromIntegral (clockPeriod clock `div` 2)
  in [halfPeriod, halfPeriod * 2 .. duration]

clockValue :: Clock -> Time -> Logic
clockValue clock time =
  let halfPeriod = fromIntegral (clockPeriod clock `div` 2)
  in if odd (time `div` halfPeriod) then High else Low

runQueue :: Netlist -> Time -> EventQueue -> State -> Changes -> Either String Simulation
runQueue netlist duration queue state changes = case Map.minViewWithKey queue of
  Nothing -> Right (Simulation duration (netlistSignals netlist) changes)
  Just ((time, pending), remaining)
    | time > duration -> Right (Simulation duration (netlistSignals netlist) changes)
    | otherwise -> do
        (nextQueue, nextState, nextChanges) <-
          settleAtTime netlist duration time pending remaining state changes 0
        runQueue netlist duration nextQueue nextState nextChanges

settleAtTime :: Netlist -> Time -> Time -> [Pending] -> EventQueue -> State -> Changes -> Int
  -> Either String (EventQueue, State, Changes)
settleAtTime netlist duration time pending queue state changes steps
  | steps > 100000 = Left ("event limit exceeded at time " ++ show time)
  | null pending = Right (queue, state, changes)
  | otherwise = case head pending of
      SignalEvent signal value ->
        processSignalEvent netlist duration time signal value (tail pending) queue state changes steps
      FlipFlopBatch samples ->
        processFlipFlopBatch netlist duration time samples (tail pending) queue state changes steps

processSignalEvent :: Netlist -> Time -> Time -> String -> Logic -> [Pending] -> EventQueue -> State -> Changes -> Int
  -> Either String (EventQueue, State, Changes)
processSignalEvent netlist duration time signal value pending queue state changes steps =
  case Map.lookup signal state of
    Nothing -> Left ("event references an unknown signal: " ++ signal)
    Just oldValue
      | oldValue == value -> settleAtTime netlist duration time pending queue state changes (steps + 1)
      | otherwise ->
          let nextState = Map.insert signal value state
              nextChanges = recordChange time signal value changes
              gateEvents = gatesForSignals netlist [signal] nextState
              flipFlopEvents =
                if oldValue == Low && value == High
                  then [FlipFlopBatch (sampleFlipFlops netlist signal nextState)]
                  else []
          in settleAtTime netlist duration time (pending ++ flipFlopEvents ++ gateEvents)
               queue nextState nextChanges (steps + 1)

processFlipFlopBatch :: Netlist -> Time -> Time -> [(DFlipFlop, Logic)] -> [Pending] -> EventQueue -> State -> Changes -> Int
  -> Either String (EventQueue, State, Changes)
processFlipFlopBatch netlist duration time samples pending queue state changes steps =
  let (nextState, nextChanges, changedOutputs) = foldl' applySample (state, changes, []) samples
      gateEvents = gatesForSignals netlist changedOutputs nextState
  in settleAtTime netlist duration time (pending ++ gateEvents)
       queue nextState nextChanges (steps + 1)
  where
    applySample (currentState, currentChanges, changed) (flipFlop, value) =
      let output = dffOutput flipFlop
      in case Map.lookup output currentState of
        Nothing -> (currentState, currentChanges, changed)
        Just oldValue
          | oldValue == value -> (currentState, currentChanges, changed)
          | otherwise ->
              ( Map.insert output value currentState
              , recordChange time output value currentChanges
              , changed ++ [output]
              )

sampleFlipFlops :: Netlist -> String -> State -> [(DFlipFlop, Logic)]
sampleFlipFlops netlist clock state =
  [ (flipFlop, Map.findWithDefault Low (dffData flipFlop) state)
  | flipFlop <- netlistFlipFlops netlist
  , dffClock flipFlop == clock
  ]

gatesForSignals :: Netlist -> [String] -> State -> [Pending]
gatesForSignals netlist changedSignals state =
  [ SignalEvent (gateOutput gate) (evaluateGate state gate)
  | gate <- netlistGates netlist
  , any (`elem` gateInputs gate) changedSignals
  ]

evaluateGate :: State -> Gate -> Logic
evaluateGate state gate =
  evalGate (gateType gate)
    [Map.findWithDefault Low input state | input <- gateInputs gate]

recordChange :: Time -> String -> Logic -> Changes -> Changes
recordChange time signal value =
  Map.adjust (\entries -> entries ++ [(time, value)]) signal

signalChanges :: Simulation -> String -> [(Time, Logic)]
signalChanges simulation signal =
  Map.findWithDefault [] signal (simulationChanges simulation)
