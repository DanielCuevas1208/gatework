module Gatework.Simulator
  ( Assertion (..)
  , AssertionFailure (..)
  , Simulation (..)
  , Time
  , signalChanges
  , simulate
  , simulateWithInputs
  , simulateWithScheduledInputs
  ) where

import Data.List (foldl', nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Gatework.Logic
import Gatework.Netlist

data Simulation = Simulation
  { simulationDuration :: Time
  , simulationSignals :: [String]
  , simulationChanges :: Map String [(Time, Logic)]
  , simulationAssertions :: [Assertion]
  , simulationFailures :: [AssertionFailure]
  }
  deriving (Eq, Show)

data AssertionFailure = AssertionFailure
  { failureSignal :: String
  , failureTime :: Time
  , failureExpected :: Logic
  , failureActual :: Logic
  }
  deriving (Eq, Show)

data Pending
  = SignalEvent String Logic
  | FlipFlopBatch [(DFlipFlop, Int, Logic)]

type EventQueue = Map Time [Pending]
type State = Map String Logic
type Changes = Map String [(Time, Logic)]

simulate :: Netlist -> Time -> Either String Simulation
simulate netlist duration = simulateWithInputs netlist [] duration

simulateWithInputs :: Netlist -> [(String, Logic)] -> Time -> Either String Simulation
simulateWithInputs netlist inputOverrides =
  simulateWithScheduledInputs netlist inputOverrides []

simulateWithScheduledInputs :: Netlist -> [(String, Logic)] -> [(Time, String, Logic)]
  -> Time -> Either String Simulation
simulateWithScheduledInputs netlist inputOverrides scheduledInputs duration
  | duration < 0 = Left "simulation duration cannot be negative"
  | otherwise = do
      validateInputOverrides netlist inputOverrides
      validateScheduledInputs netlist scheduledInputs
      validateAssertionTimes netlist duration
      let baseState = initialState netlist inputOverrides
          initialEvents = map (initialGateEvent baseState) (netlistGates netlist)
          scheduledQueue = foldl' addScheduledEvent (clockQueue netlist duration) scheduledInputs
          queue = addInitialEvents scheduledQueue initialEvents
          initialChanges = initialWaveform netlist baseState
      result <- runQueue netlist duration queue baseState initialChanges
      let assertions = netlistAssertions netlist
      pure result
        { simulationAssertions = assertions
        , simulationFailures = checkAssertions assertions result
        }

validateAssertionTimes :: Netlist -> Time -> Either String ()
validateAssertionTimes netlist duration =
  mapM_ checkTime (netlistAssertions netlist)
  where
    checkTime assertion
      | assertionTime assertion > duration =
          Left ( "assertion time exceeds duration: "
              ++ assertionSignal assertion
              ++ " at time "
              ++ show (assertionTime assertion)
              ++ " for duration "
              ++ show duration
              )
      | otherwise = Right ()

checkAssertions :: [Assertion] -> Simulation -> [AssertionFailure]
checkAssertions assertions simulation =
  [ AssertionFailure signal time expected actual
  | assertion <- assertions
  , let signal = assertionSignal assertion
        time = assertionTime assertion
        expected = assertionValue assertion
  , Just actual <- [valueAt time (signalChanges simulation signal)]
  , actual /= expected
  ]
  where
    valueAt time changes = case reverse [(t, value) | (t, value) <- changes, t <= time] of
      (_, value) : _ -> Just value
      [] -> Nothing

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

validateScheduledInputs :: Netlist -> [(Time, String, Logic)] -> Either String ()
validateScheduledInputs netlist transitions =
  mapM_ validateTransition transitions
  where
    validateTransition (time, signal, _)
      | time < 0 = Left ("input transition time cannot be negative: " ++ show time)
      | signal `notElem` netlistInputs netlist =
          Left ("input transition is not an input: " ++ signal)
      | otherwise = Right ()

addScheduledEvent :: EventQueue -> (Time, String, Logic) -> EventQueue
addScheduledEvent queue (time, signal, value) =
  Map.insertWith (flip (++)) time [SignalEvent signal value] queue

initialState :: Netlist -> [(String, Logic)] -> State
initialState netlist overrides =
  Map.union (Map.fromList overrides) dffState
  where
    dffState = foldl' addDffBits
      (Map.fromList [(signal, Low) | signal <- netlistSignals netlist])
      (netlistFlipFlops netlist)
    addDffBits state flipFlop =
      foldl'
        (\current (output, value) -> Map.insert output value current)
        state
        (zip (dffOutput flipFlop) (dffInitial flipFlop))

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
  Nothing -> Right (Simulation duration (netlistSignals netlist) changes [] [])
  Just ((time, pending), remaining)
    | time > duration -> Right (Simulation duration (netlistSignals netlist) changes [] [])
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
                  then [FlipFlopBatch (edgeSamples netlist signal nextState)]
                  else []
          in settleAtTime netlist duration time (pending ++ flipFlopEvents ++ gateEvents)
               queue nextState nextChanges (steps + 1)

processFlipFlopBatch :: Netlist -> Time -> Time -> [(DFlipFlop, Int, Logic)] -> [Pending] -> EventQueue -> State -> Changes -> Int
  -> Either String (EventQueue, State, Changes)
processFlipFlopBatch netlist duration time samples pending queue state changes steps =
  let (nextState, nextChanges, changedOutputs) = foldl' applySample (state, changes, []) samples
      gateEvents = gatesForSignals netlist changedOutputs nextState
  in settleAtTime netlist duration time (pending ++ gateEvents)
       queue nextState nextChanges (steps + 1)
  where
    applySample (currentState, currentChanges, changed) (flipFlop, index, value) =
      let output = dffOutput flipFlop !! index
      in case Map.lookup output currentState of
        Nothing -> (currentState, currentChanges, changed)
        Just oldValue
          | oldValue == value -> (currentState, currentChanges, changed)
          | otherwise ->
              ( Map.insert output value currentState
              , recordChange time output value currentChanges
              , changed ++ [output]
              )

sampleFlipFlops :: Netlist -> String -> State -> [(DFlipFlop, Int, Logic)]
sampleFlipFlops netlist clock state =
  [ (flipFlop, index, dffSampleValue flipFlop index state)
  | flipFlop <- netlistFlipFlops netlist
  , dffClock flipFlop == clock
  , index <- [0 .. dffWidth flipFlop - 1]
  ]

forcedResetSamples :: Netlist -> String -> [(DFlipFlop, Int, Logic)]
forcedResetSamples netlist reset =
  [ (flipFlop, index, dffInitial flipFlop !! index)
  | flipFlop <- netlistFlipFlops netlist
  , dffReset flipFlop == Just reset
  , index <- [0 .. dffWidth flipFlop - 1]
  ]

edgeSamples :: Netlist -> String -> State -> [(DFlipFlop, Int, Logic)]
edgeSamples netlist signal state =
  sampleFlipFlops netlist signal state ++ forcedResetSamples netlist signal

dffSampleValue :: DFlipFlop -> Int -> State -> Logic
dffSampleValue flipFlop index state
  | resetAsserted = dffInitial flipFlop !! index
  | otherwise = Map.findWithDefault Low (dffData flipFlop !! index) state
  where
    resetAsserted = case dffReset flipFlop of
      Just reset -> Map.findWithDefault Low reset state == High
      Nothing -> False

dffWidth :: DFlipFlop -> Int
dffWidth flipFlop = length (dffData flipFlop)

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
