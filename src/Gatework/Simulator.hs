module Gatework.Simulator
  ( Assertion (..)
  , AssertionFailure (..)
  , Simulation (..)
  , Time
  , resolveValue
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
  , simulationBuses :: [(String, Int)]
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
  | GateCommit Gate

type EventQueue = Map Time [Pending]
type WireState = Map String Logic
type Changes = Map String [(Time, Logic)]

data SimState = SimState
  { simWireValues :: WireState
  , simDrivers :: Map String [(Gate, Logic)]
  }

type DriverIndexes = (Map String [Gate], Map String [Gate])

resolveValue :: [Logic] -> Logic
resolveValue values = case [value | value <- values, value /= TriState] of
  [] -> TriState
  known
    | all (== Low) known -> Low
    | all (== High) known -> High
    | otherwise -> Undefined

buildDriverIndexes :: Netlist -> DriverIndexes
buildDriverIndexes netlist =
  ( byOutput
  , byInput
  )
  where
    byOutput =
      Map.fromListWith (flip (++)) [(gateOutput gate, [gate]) | gate <- netlistGates netlist]
    byInput =
      Map.fromListWith (flip (++))
        [(signal, [gate]) | gate <- netlistGates netlist, signal <- gateInputs gate]

resolvedOutput :: Map String [Gate] -> WireState -> String -> Logic
resolvedOutput byOutput state output =
  resolveValue
    [evaluateGate state gate | gate <- Map.findWithDefault [] output byOutput]

currentContribution :: Map String [(Gate, Logic)] -> Gate -> Logic
currentContribution drivers gate =
  case
    [ value
    | (driving, value) <- Map.findWithDefault [] (gateOutput gate) drivers
    , gateName driving == gateName gate
    ] of
      value : _ -> value
      [] -> Low

commitsForChanged :: Map String [Gate] -> Map String [(Gate, Logic)] -> WireState -> [String] -> [Gate]
commitsForChanged byInput drivers state changedSignals =
  [ gate
  | signal <- changedSignals
  , gate <- Map.findWithDefault [] signal byInput
  , evaluateGate state gate /= currentContribution drivers gate
  ]

scheduleCommits :: Time -> EventQueue -> [Gate] -> ([Pending], EventQueue)
scheduleCommits time queue commits = foldl' step ([], queue) commits
  where
    step (immediate, currentQueue) gate
      | gateDelay gate == 0 || time == 0 = (immediate ++ [GateCommit gate], currentQueue)
      | otherwise =
          ( immediate
          , Map.insertWith (++) (time + fromIntegral (gateDelay gate)) [GateCommit gate] currentQueue
          )

commitContribution :: Map String [(Gate, Logic)] -> Gate -> Logic -> Map String [(Gate, Logic)]
commitContribution drivers gate value =
  Map.adjust (replace (gateName gate) value) (gateOutput gate) drivers
  where
    replace name replacement entries =
      [(g, if gateName g == name then replacement else current) | (g, current) <- entries]

resolveDrivenWire :: Map String [(Gate, Logic)] -> String -> Logic
resolveDrivenWire drivers output =
  resolveValue [value | (_, value) <- Map.findWithDefault [] output drivers]

initialDrivers :: Map String [Gate] -> WireState -> Map String [(Gate, Logic)]
initialDrivers byOutput state =
  Map.map
    (\gates -> [(gate, evaluateGate state gate) | gate <- gates])
    byOutput

initialDrivenEvents :: Map String [Gate] -> WireState -> [Pending]
initialDrivenEvents byOutput state =
  [ SignalEvent output (resolvedOutput byOutput state output)
  | output <- Map.keys byOutput
  ]

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
      let (byOutput, byInput) = buildDriverIndexes netlist
          baseState = initialState netlist inputOverrides
          simState = SimState baseState (initialDrivers byOutput baseState)
          initialEvents = initialDrivenEvents byOutput baseState
          scheduledQueue = foldl' addScheduledEvent (clockQueue netlist duration) scheduledInputs
          queue = addInitialEvents scheduledQueue initialEvents
          initialChanges = initialWaveform netlist baseState
      result <- runQueue netlist byInput duration queue simState initialChanges
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

initialState :: Netlist -> [(String, Logic)] -> WireState
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

initialWaveform :: Netlist -> WireState -> Changes
initialWaveform netlist state =
  Map.fromList
    [ (signal, [(0, Map.findWithDefault Low signal state)])
    | signal <- netlistSignals netlist
    ]

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

runQueue :: Netlist -> Map String [Gate] -> Time -> EventQueue -> SimState -> Changes
  -> Either String Simulation
runQueue netlist byInput duration queue state changes = case Map.minViewWithKey queue of
  Nothing -> Right (Simulation duration (netlistSignals netlist) (netlistBusWidths netlist) changes [] [])
  Just ((time, pending), remaining)
    | time > duration ->
        Right (Simulation duration (netlistSignals netlist) (netlistBusWidths netlist) changes [] [])
    | otherwise -> do
        (nextQueue, nextState, nextChanges) <-
          settleAtTime netlist byInput duration time pending remaining state changes 0
        runQueue netlist byInput duration nextQueue nextState nextChanges

settleAtTime :: Netlist -> Map String [Gate] -> Time -> Time -> [Pending]
  -> EventQueue -> SimState -> Changes -> Int -> Either String (EventQueue, SimState, Changes)
settleAtTime netlist byInput duration time pending queue state changes steps
  | steps > 100000 = Left ("event limit exceeded at time " ++ show time)
  | null pending = Right (queue, state, changes)
  | otherwise = case head pending of
      SignalEvent signal value ->
        processSignalEvent netlist byInput duration time signal value (tail pending) queue state changes steps
      FlipFlopBatch samples ->
        processFlipFlopBatch netlist byInput duration time samples (tail pending) queue state changes steps
      GateCommit gate ->
        processGateCommit netlist byInput duration time gate (tail pending) queue state changes steps

processSignalEvent :: Netlist -> Map String [Gate] -> Time -> Time
  -> String -> Logic -> [Pending] -> EventQueue -> SimState -> Changes -> Int
  -> Either String (EventQueue, SimState, Changes)
processSignalEvent netlist byInput duration time signal value pending queue state changes steps =
  case Map.lookup signal (simWireValues state) of
    Nothing -> Left ("event references an unknown signal: " ++ signal)
    Just oldValue
      | oldValue == value -> settleAtTime netlist byInput duration time pending queue state changes (steps + 1)
      | otherwise ->
          let nextState = state {simWireValues = Map.insert signal value (simWireValues state)}
              nextChanges = recordChange time signal value changes
              commits = commitsForChanged byInput (simDrivers nextState) (simWireValues nextState) [signal]
              flipFlopEvents =
                if oldValue == Low && value == High
                  then [FlipFlopBatch (edgeSamples netlist signal (simWireValues nextState))]
                  else []
              (immediate, scheduledQueue) = scheduleCommits time queue commits
          in settleAtTime netlist byInput duration time (pending ++ flipFlopEvents ++ immediate)
               scheduledQueue nextState nextChanges (steps + 1)

processFlipFlopBatch :: Netlist -> Map String [Gate] -> Time -> Time
  -> [(DFlipFlop, Int, Logic)] -> [Pending] -> EventQueue -> SimState -> Changes -> Int
  -> Either String (EventQueue, SimState, Changes)
processFlipFlopBatch netlist byInput duration time samples pending queue state changes steps =
  let (nextState, nextChanges, changedOutputs) = foldl' applySample (state, changes, []) samples
      commits = commitsForChanged byInput (simDrivers nextState) (simWireValues nextState) changedOutputs
      (immediate, scheduledQueue) = scheduleCommits time queue commits
  in settleAtTime netlist byInput duration time (pending ++ immediate) scheduledQueue nextState nextChanges (steps + 1)
  where
    applySample (currentState, currentChanges, changed) (flipFlop, index, value) =
      let output = dffOutput flipFlop !! index
      in case Map.lookup output (simWireValues currentState) of
        Nothing -> (currentState, currentChanges, changed)
        Just oldValue
          | oldValue == value -> (currentState, currentChanges, changed)
          | otherwise ->
              ( currentState {simWireValues = Map.insert output value (simWireValues currentState)}
              , recordChange time output value currentChanges
              , changed ++ [output]
              )

processGateCommit :: Netlist -> Map String [Gate] -> Time -> Time
  -> Gate -> [Pending] -> EventQueue -> SimState -> Changes -> Int
  -> Either String (EventQueue, SimState, Changes)
processGateCommit netlist byInput duration time gate pending queue state changes steps
  | value == currentContribution (simDrivers state) gate =
      settleAtTime netlist byInput duration time pending queue state changes (steps + 1)
  | otherwise =
      let drivers' = commitContribution (simDrivers state) gate value
          output = gateOutput gate
          resolved = resolveDrivenWire drivers' output
          oldWire = Map.findWithDefault Low output (simWireValues state)
          nextState = state {simDrivers = drivers'}
      in if resolved == oldWire
           then settleAtTime netlist byInput duration time pending queue nextState changes (steps + 1)
           else processSignalEvent netlist byInput duration time output resolved pending queue nextState changes (steps + 1)
  where
    value = evaluateGate (simWireValues state) gate

sampleFlipFlops :: Netlist -> String -> WireState -> [(DFlipFlop, Int, Logic)]
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

edgeSamples :: Netlist -> String -> WireState -> [(DFlipFlop, Int, Logic)]
edgeSamples netlist signal state =
  sampleFlipFlops netlist signal state ++ forcedResetSamples netlist signal

dffSampleValue :: DFlipFlop -> Int -> WireState -> Logic
dffSampleValue flipFlop index state
  | resetAsserted = dffInitial flipFlop !! index
  | otherwise = Map.findWithDefault Low (dffData flipFlop !! index) state
  where
    resetAsserted = case dffReset flipFlop of
      Just reset -> Map.findWithDefault Low reset state == High
      Nothing -> False

dffWidth :: DFlipFlop -> Int
dffWidth flipFlop = length (dffData flipFlop)

evaluateGate :: WireState -> Gate -> Logic
evaluateGate state gate =
  evalGate (gateType gate)
    [Map.findWithDefault Low input state | input <- gateInputs gate]

recordChange :: Time -> String -> Logic -> Changes -> Changes
recordChange time signal value =
  Map.adjust (\entries -> entries ++ [(time, value)]) signal

signalChanges :: Simulation -> String -> [(Time, Logic)]
signalChanges simulation signal =
  Map.findWithDefault [] signal (simulationChanges simulation)
