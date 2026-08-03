module Gatework.Report
  ( renderReport
  ) where

import Data.List (intercalate, nub, sort)
import qualified Data.Map.Strict as Map
import Gatework.Logic (Logic (..), logicChar)
import Gatework.Simulator (Simulation (..), Time, signalChanges)

renderReport :: Simulation -> String
renderReport simulation = unlines (header : divider : rows)
  where
    signals = simulationSignals simulation
    times = changeTimes simulation
    headers = "time" : signals
    valueWidths = timeWidth : replicate (length signals) 1
    widths = zipWith max (map length headers) valueWidths
    timeWidth = maximum (length "time" : map (length . show) times)
    renderCell width value = replicate (width - length value) ' ' ++ value
    row cells = intercalate " | " (zipWith renderCell widths cells)
    header = row headers
    divider = intercalate " | " [replicate width '-' | width <- widths]
    rows = [row (show time : map (renderSignal time) signals) | time <- times]
    renderSignal time signal = [logicChar (signalValueAt simulation signal time)]

changeTimes :: Simulation -> [Time]
changeTimes simulation = sort . nub $
  [ time
  | entries <- Map.elems (simulationChanges simulation)
  , (time, _) <- entries
  ]

signalValueAt :: Simulation -> String -> Time -> Logic
signalValueAt simulation signal time =
  case reverse [(changeTime, value) | (changeTime, value) <- signalChanges simulation signal, changeTime <= time] of
    (_, value) : _ -> value
    [] -> Low
