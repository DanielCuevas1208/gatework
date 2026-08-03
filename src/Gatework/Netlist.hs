module Gatework.Netlist
  ( Clock (..)
  , DFlipFlop (..)
  , Gate (..)
  , Netlist (..)
  , netlistSignals
  , parseNetlist
  , parseNetlistFile
  ) where

import Control.Monad (unless)
import Data.Char (isAlphaNum, isSpace, toUpper)
import Data.List (foldl', nub)
import Gatework.Logic

data Clock = Clock
  { clockSignal :: String
  , clockPeriod :: Int
  }
  deriving (Eq, Show)

data DFlipFlop = DFlipFlop
  { dffName :: String
  , dffClock :: String
  , dffData :: String
  , dffOutput :: String
  , dffInitial :: Logic
  }
  deriving (Eq, Show)

data Gate = Gate
  { gateType :: GateType
  , gateName :: String
  , gateInputs :: [String]
  , gateOutput :: String
  }
  deriving (Eq, Show)

data Netlist = Netlist
  { netlistInputs :: [String]
  , netlistOutputs :: [String]
  , netlistWires :: [String]
  , netlistClocks :: [Clock]
  , netlistGates :: [Gate]
  , netlistFlipFlops :: [DFlipFlop]
  }
  deriving (Eq, Show)

data Declaration
  = InputDeclaration String
  | OutputDeclaration String
  | WireDeclaration String
  | ClockDeclaration Clock
  | GateDeclaration Gate
  | FlipFlopDeclaration DFlipFlop

emptyNetlist :: Netlist
emptyNetlist = Netlist [] [] [] [] [] []

parseNetlistFile :: FilePath -> IO (Either String Netlist)
parseNetlistFile path = parseNetlist <$> readFile path

parseNetlist :: String -> Either String Netlist
parseNetlist source = do
  declarations <- mapM parseLine usefulLines
  validateNetlist (foldl' addDeclaration emptyNetlist declarations)
  where
    usefulLines =
      [ (lineNumber, cleaned)
      | (lineNumber, raw) <- zip [1 :: Int ..] (lines source)
      , let cleaned = trim (takeWhile (/= '#') raw)
      , not (null cleaned)
      ]

addDeclaration :: Netlist -> Declaration -> Netlist
addDeclaration netlist declaration = case declaration of
  InputDeclaration name -> netlist {netlistInputs = netlistInputs netlist ++ [name]}
  OutputDeclaration name -> netlist {netlistOutputs = netlistOutputs netlist ++ [name]}
  WireDeclaration name -> netlist {netlistWires = netlistWires netlist ++ [name]}
  ClockDeclaration clock -> netlist {netlistClocks = netlistClocks netlist ++ [clock]}
  GateDeclaration gate -> netlist {netlistGates = netlistGates netlist ++ [gate]}
  FlipFlopDeclaration flipFlop ->
    netlist {netlistFlipFlops = netlistFlipFlops netlist ++ [flipFlop]}

parseLine :: (Int, String) -> Either String Declaration
parseLine (lineNumber, line) = case words line of
  ["input", name] -> InputDeclaration <$> parseIdentifier lineNumber name
  ["output", name] -> OutputDeclaration <$> parseIdentifier lineNumber name
  ["wire", name] -> WireDeclaration <$> parseIdentifier lineNumber name
  ["clock", name, period] -> do
    signal <- parseIdentifier lineNumber name
    parsedPeriod <- parseKeyInt lineNumber "period" period
    unless (parsedPeriod >= 2 && even parsedPeriod) $
      Left (lineError lineNumber "clock period must be an even integer of at least two")
    pure (ClockDeclaration (Clock signal parsedPeriod))
  ["gate", gateText, name, ports, "->", output] -> do
    gate <- maybe (Left (lineError lineNumber ("unknown gate type: " ++ gateText))) Right
      (parseGateType (map toUpper gateText))
    gateName' <- parseIdentifier lineNumber name
    inputNames <- parsePorts lineNumber ports
    outputName <- parseIdentifier lineNumber output
    unless (length inputNames == gateArity gate) $
      Left (lineError lineNumber ("gate " ++ name ++ " expects " ++ show (gateArity gate) ++ " inputs"))
    pure (GateDeclaration (Gate gate gateName' inputNames outputName))
  ("dff" : name : fields) -> do
    dffName' <- parseIdentifier lineNumber name
    parsedFields <- mapM (parseField lineNumber) fields
    clock <- requiredField lineNumber "clock" parsedFields
    dataInput <- requiredField lineNumber "d" parsedFields
    output <- requiredField lineNumber "q" parsedFields
    initial <- case lookup "init" parsedFields of
      Nothing -> Right Low
      Just value -> maybe (Left (lineError lineNumber "init must be 0 or 1")) Right (parseLogic value)
    clockName <- parseIdentifier lineNumber clock
    dataName <- parseIdentifier lineNumber dataInput
    outputName <- parseIdentifier lineNumber output
    pure (FlipFlopDeclaration (DFlipFlop dffName' clockName dataName outputName initial))
  _ -> Left (lineError lineNumber "expected input, output, wire, clock, gate, or dff declaration")

parsePorts :: Int -> String -> Either String [String]
parsePorts lineNumber token
  | length token < 2 || head token /= '(' || last token /= ')' =
      Left (lineError lineNumber "gate inputs must use parentheses")
  | otherwise = do
      let body = init (tail token)
          names = splitOn ',' body
      unless (not (null body) && all (not . null) names) $
        Left (lineError lineNumber "gate inputs cannot be empty")
      mapM (parseIdentifier lineNumber) names

parseField :: Int -> String -> Either String (String, String)
parseField lineNumber field = case break (== '=') field of
  (key, '=' : value)
    | key `elem` ["clock", "d", "q", "init"] && not (null value) -> Right (key, value)
  _ -> Left (lineError lineNumber ("invalid dff field: " ++ field))

requiredField :: Int -> String -> [(String, String)] -> Either String String
requiredField lineNumber key fields = case lookup key fields of
  Just value -> Right value
  Nothing -> Left (lineError lineNumber ("dff requires " ++ key ++ "=<signal>"))

parseKeyInt :: Int -> String -> String -> Either String Int
parseKeyInt lineNumber key token = do
  value <- case break (== '=') token of
    (actualKey, '=' : actualValue) | actualKey == key -> Right actualValue
    _ -> Left (lineError lineNumber ("expected " ++ key ++ "=<integer>"))
  case reads value of
    [(number, "")] -> Right number
    _ -> Left (lineError lineNumber (key ++ " must be an integer"))

parseIdentifier :: Int -> String -> Either String String
parseIdentifier lineNumber name
  | validIdentifier name = Right name
  | otherwise = Left (lineError lineNumber ("invalid signal name: " ++ name))

validIdentifier :: String -> Bool
validIdentifier name =
  not (null name)
    && all (\character -> isAlphaNum character || character `elem` "_.$") name

validateNetlist :: Netlist -> Either String Netlist
validateNetlist netlist = do
  let clockNames = map clockSignal (netlistClocks netlist)
      dffOutputs = map dffOutput (netlistFlipFlops netlist)
      declared = netlistInputs netlist ++ netlistWires netlist ++ clockNames ++ dffOutputs
      componentNames = map gateName (netlistGates netlist) ++ map dffName (netlistFlipFlops netlist)
      driven = map gateOutput (netlistGates netlist) ++ dffOutputs
  checkDuplicates "signal" (netlistInputs netlist ++ netlistWires netlist ++ clockNames ++ dffOutputs)
  checkDuplicates "component" componentNames
  checkDuplicates "driven signal" driven
  mapM_ (checkKnown declared "output") (netlistOutputs netlist)
  mapM_ (checkGate declared (netlistWires netlist)) (netlistGates netlist)
  mapM_ (checkFlipFlop declared clockNames) (netlistFlipFlops netlist)
  pure netlist

checkGate :: [String] -> [String] -> Gate -> Either String ()
checkGate declared wires gate = do
  unless (gateOutput gate `elem` wires) $
    Left ("gate output must be declared as a wire: " ++ gateOutput gate)
  mapM_ (checkKnown declared "gate input") (gateInputs gate)

checkFlipFlop :: [String] -> [String] -> DFlipFlop -> Either String ()
checkFlipFlop declared clocks flipFlop = do
  unless (dffClock flipFlop `elem` clocks) $
    Left ("dff clock is not declared: " ++ dffClock flipFlop)
  checkKnown declared "dff data input" (dffData flipFlop)

checkKnown :: [String] -> String -> String -> Either String ()
checkKnown declared label name =
  unless (name `elem` declared) (Left (label ++ " is not declared: " ++ name))

checkDuplicates :: String -> [String] -> Either String ()
checkDuplicates label values = case duplicates values of
  [] -> Right ()
  repeated -> Left ("duplicate " ++ label ++ ": " ++ head repeated)

duplicates :: Eq a => [a] -> [a]
duplicates values = nub [value | value <- values, count value values > 1]
  where
    count value = length . filter (== value)

netlistSignals :: Netlist -> [String]
netlistSignals netlist = nub
  ( netlistInputs netlist
      ++ netlistOutputs netlist
      ++ map clockSignal (netlistClocks netlist)
      ++ map dffOutput (netlistFlipFlops netlist)
      ++ netlistWires netlist
      ++ map gateOutput (netlistGates netlist)
  )

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

splitOn :: Char -> String -> [String]
splitOn delimiter value = case break (== delimiter) value of
  (part, _ : rest) -> part : splitOn delimiter rest
  (part, []) -> [part]

lineError :: Int -> String -> String
lineError lineNumber message = "line " ++ show lineNumber ++ ": " ++ message

