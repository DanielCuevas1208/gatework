module Gatework.VCD
  ( renderVCD
  , writeVCD
  ) where

import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import qualified Paths_gatework (version)
import Data.Version (showVersion)
import Gatework.Logic
import Gatework.Simulator

renderVCD :: Simulation -> String
renderVCD simulation = header ++ timeline
  where
    signals = simulationSignals simulation
    identifiers = zip signals (map identifierFor [0 ..])
    header = unlines
      ( [ "$date"
        , "  generated deterministically by gatework"
        , "$end"
        , "$version"
        , "  gatework " ++ showVersion Paths_gatework.version
        , "$end"
        , "$timescale 1ns $end"
        , "$scope module gatework $end"
        ]
          ++ ["$var wire 1 " ++ identifier ++ " " ++ signal ++ " $end" | (signal, identifier) <- identifiers]
          ++ [ "$upscope $end"
             , "$enddefinitions $end"
             ]
      )
    timeline = concatMap (renderTime simulation identifiers) (changeTimes simulation)

writeVCD :: FilePath -> Simulation -> IO ()
writeVCD path = writeFile path . renderVCD

changeTimes :: Simulation -> [Time]
changeTimes simulation = sort . nub $
  [ time
  | entries <- Map.elems (simulationChanges simulation)
  , (time, _) <- entries
  ]

renderTime :: Simulation -> [(String, String)] -> Time -> String
renderTime simulation identifiers time =
  "#" ++ show time ++ "\n"
    ++ concatMap (renderSignalChange simulation time) identifiers

renderSignalChange :: Simulation -> Time -> (String, String) -> String
renderSignalChange simulation time (signal, identifier) = concat
  [ [logicChar value] ++ identifier ++ "\n"
  | (changeTime, value) <- signalChanges simulation signal
  , changeTime == time
  ]

identifierFor :: Int -> String
identifierFor value = go value
  where
    alphabet = ['!' .. '~']
    base = length alphabet
    go index =
      let (quotient, remainder) = index `divMod` base
          prefix = if quotient == 0 then "" else go (quotient - 1)
      in prefix ++ [alphabet !! remainder]
