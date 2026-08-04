module Gatework.VCD
  ( renderVCD
  , writeVCD
  ) where

import Data.Char (isDigit)
import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import qualified Paths_gatework (version)
import Data.Version (showVersion)
import Gatework.Logic
import Gatework.Simulator

data VcdVariable
  = VcdScalar String
  | VcdVector String Int
  deriving (Eq, Show)

renderVCD :: Simulation -> String
renderVCD simulation = header ++ timeline
  where
    variables = vcdVariables simulation
    identifiers = zip variables (map identifierFor [0 ..])
    header = unlines
      ( [ "$date"
        , "  generated deterministically by gatework"
        , "$end"
        , "$version"
        , "  gatework " ++ showVersion Paths_gatework.version
        , "$end"
        ]
          ++ commentLines
          ++ [ "$timescale 1ns $end"
             , "$scope module gatework $end"
             ]
          ++ [renderDeclaration variable identifier | (variable, identifier) <- identifiers]
          ++ [ "$upscope $end"
             , "$enddefinitions $end"
             ]
      )
    commentLines
      | null assertions = []
      | otherwise = "$comment" : map renderAssertion assertions ++ ["$end"]
    assertions = simulationAssertions simulation
    renderAssertion assertion = concat
      [ "  assert "
      , assertionSignal assertion
      , " = "
      , [logicChar (assertionValue assertion)]
      , " at "
      , show (assertionTime assertion)
      ]
    timeline = concatMap (renderTime simulation identifiers) (changeTimes simulation)

writeVCD :: FilePath -> Simulation -> IO ()
writeVCD path = writeFile path . renderVCD

renderDeclaration :: VcdVariable -> String -> String
renderDeclaration (VcdScalar signal) identifier =
  "$var wire 1 " ++ identifier ++ " " ++ signal ++ " $end"
renderDeclaration (VcdVector base width) identifier =
  "$var wire " ++ show width ++ " " ++ identifier ++ " "
    ++ base ++ "[" ++ show (width - 1) ++ ":0] $end"

changeTimes :: Simulation -> [Time]
changeTimes simulation = sort . nub $
  [ time
  | entries <- Map.elems (simulationChanges simulation)
  , (time, _) <- entries
  ]

renderTime :: Simulation -> [(VcdVariable, String)] -> Time -> String
renderTime simulation identifiers time =
  "#" ++ show time ++ "\n"
    ++ concatMap (renderVariableChange simulation time) identifiers

renderVariableChange :: Simulation -> Time -> (VcdVariable, String) -> String
renderVariableChange simulation time (variable, identifier) = case variable of
  VcdScalar signal ->
    concat
      [ [logicChar value] ++ identifier ++ "\n"
      | (changeTime, value) <- signalChanges simulation signal
      , changeTime == time
      ]
  VcdVector base width
    | not (vectorChangedAt simulation base width time) -> ""
    | otherwise ->
        "b" ++ vectorValue simulation base width time ++ identifier ++ "\n"

vectorChangedAt :: Simulation -> String -> Int -> Time -> Bool
vectorChangedAt simulation base width time =
  any bitChangedAt [0 .. width - 1]
  where
    bitChangedAt index =
      any ((== time) . fst) (signalChanges simulation (bitName base width index))

vectorValue :: Simulation -> String -> Int -> Time -> String
vectorValue simulation base width time =
  [logicChar (bitValueAt simulation (bitName base width index) time)
  | index <- [width - 1, width - 2 .. 0]]

bitValueAt :: Simulation -> String -> Time -> Logic
bitValueAt simulation signal time =
  case reverse [(changeTime, value) | (changeTime, value) <- signalChanges simulation signal, changeTime <= time] of
    (_, value) : _ -> value
    [] -> Low

bitName :: String -> Int -> Int -> String
bitName base width index
  | width <= 1 = base
  | otherwise = base ++ "[" ++ show index ++ "]"

vcdVariables :: Simulation -> [VcdVariable]
vcdVariables simulation = go (Map.fromList (simulationBuses simulation)) (simulationSignals simulation)
  where
    go _ [] = []
    go buses (signal : rest) = case parseBusBit signal of
      Just (base, 0)
        | Just width <- Map.lookup base buses
        , take (width - 1) rest == [bitName base width index | index <- [1 .. width - 1]] ->
            VcdVector base width : go (Map.delete base buses) (drop (width - 1) rest)
      _ -> VcdScalar signal : go buses rest

parseBusBit :: String -> Maybe (String, Int)
parseBusBit signal = case break (== '[') signal of
  (base, '[' : rest)
    | not (null rest)
    , last rest == ']'
    , all isDigit (init rest) ->
        Just (base, read (init rest))
  _ -> Nothing

identifierFor :: Int -> String
identifierFor value = go value
  where
    alphabet = ['!' .. '~']
    base = length alphabet
    go index =
      let (quotient, remainder) = index `divMod` base
          prefix = if quotient == 0 then "" else go (quotient - 1)
      in prefix ++ [alphabet !! remainder]
