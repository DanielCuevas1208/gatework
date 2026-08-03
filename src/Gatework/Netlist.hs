module Gatework.Netlist
  ( Assertion (..)
  , Clock (..)
  , DFlipFlop (..)
  , Gate (..)
  , Netlist (..)
  , Time
  , netlistSignals
  , parseNetlist
  , parseNetlistFile
  ) where

import Control.Monad (unless)
import Data.Char (isAlphaNum, isSpace, toUpper)
import Data.List (foldl', nub)
import Gatework.Logic

type Time = Integer

data Assertion = Assertion
  { assertionSignal :: String
  , assertionValue :: Logic
  , assertionTime :: Time
  }
  deriving (Eq, Show)

data Clock = Clock
  { clockSignal :: String
  , clockPeriod :: Int
  }
  deriving (Eq, Show)

data DFlipFlop = DFlipFlop
  { dffName :: String
  , dffClock :: String
  , dffData :: [String]
  , dffOutput :: [String]
  , dffInitial :: [Logic]
  , dffReset :: Maybe String
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
  , netlistAssertions :: [Assertion]
  }
  deriving (Eq, Show)

data Declaration
  = InputDeclaration String
  | OutputDeclaration String
  | WireDeclaration String
  | ClockDeclaration Clock
  | GateDeclaration Gate
  | FlipFlopDeclaration DFlipFlop
  | AssertionDeclaration Assertion

emptyNetlist :: Netlist
emptyNetlist = Netlist [] [] [] [] [] [] []

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
  AssertionDeclaration assertion ->
    netlist {netlistAssertions = netlistAssertions netlist ++ [assertion]}

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
    dataText <- requiredField lineNumber "d" parsedFields
    outputText <- requiredField lineNumber "q" parsedFields
    clockName <- parseIdentifier lineNumber clock
    dataNames <- parseSignalList lineNumber "d" dataText
    outputNames <- parseSignalList lineNumber "q" outputText
    unless (not (null dataNames)) $
      Left (lineError lineNumber "dff requires at least one data input")
    unless (length dataNames == length outputNames) $
      Left (lineError lineNumber "dff data and output lists must have equal width")
    width <- parseDffWidth lineNumber (length dataNames) parsedFields
    initial <- parseInitList lineNumber width parsedFields
    reset <- case lookup "rst" parsedFields of
      Nothing -> Right Nothing
      Just value -> Just <$> parseIdentifier lineNumber value
    pure (FlipFlopDeclaration (DFlipFlop dffName' clockName dataNames outputNames initial reset))
  ["assert", signal, "=", value, "at", timeText] -> do
    signalName <- parseIdentifier lineNumber signal
    logic <- maybe
      (Left (lineError lineNumber "assert value must be 0 or 1"))
      Right
      (parseLogic value)
    time <- parseAssertTime lineNumber timeText
    pure (AssertionDeclaration (Assertion signalName logic time))
  _ -> Left (lineError lineNumber "expected input, output, wire, clock, gate, dff, or assert declaration")

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
    | key `elem` ["clock", "d", "q", "init", "rst", "width"] && not (null value) -> Right (key, value)
  _ -> Left (lineError lineNumber ("invalid dff field: " ++ field))

parseSignalList :: Int -> String -> String -> Either String [String]
parseSignalList lineNumber key value = do
  let names = splitOn ',' value
  unless (all (not . null) names) $
    Left (lineError lineNumber ("dff " ++ key ++ " list cannot contain empty entries"))
  mapM (parseIdentifier lineNumber) names

parseDffWidth :: Int -> Int -> [(String, String)] -> Either String Int
parseDffWidth lineNumber impliedWidth fields = case lookup "width" fields of
  Nothing -> Right impliedWidth
  Just value -> do
    width <- parseDecimal lineNumber "width" value
    unless (width >= 1) $
      Left (lineError lineNumber "width must be a positive integer")
    unless (width == impliedWidth) $
      Left (lineError lineNumber "width must match the number of dff data signals")
    pure width

parseInitList :: Int -> Int -> [(String, String)] -> Either String [Logic]
parseInitList lineNumber width fields = case lookup "init" fields of
  Nothing -> Right (replicate width Low)
  Just value -> case splitOn ',' value of
    [single] -> maybe
      (Left (lineError lineNumber "init must be 0 or 1"))
      (Right . replicate width)
      (parseLogic single)
    values -> do
      unless (length values == width) $
        Left (lineError lineNumber "init list width must match dff width")
      mapM parseInitValue values
  where
    parseInitValue token = maybe
      (Left (lineError lineNumber "init must be 0 or 1"))
      Right
      (parseLogic token)

parseDecimal :: Int -> String -> String -> Either String Int
parseDecimal lineNumber key token = case reads token of
  [(number, "")] -> Right number
  _ -> Left (lineError lineNumber (key ++ " must be an integer"))

parseAssertTime :: Int -> String -> Either String Time
parseAssertTime lineNumber token = do
  time <- parseDecimal lineNumber "assert time" token
  unless (time >= 0) $
    Left (lineError lineNumber "assert time cannot be negative")
  pure (fromIntegral time)

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
      dffOutputs = concatMap dffOutput (netlistFlipFlops netlist)
      declared = netlistInputs netlist ++ netlistWires netlist ++ clockNames ++ dffOutputs
      componentNames = map gateName (netlistGates netlist) ++ map dffName (netlistFlipFlops netlist)
      driven = map gateOutput (netlistGates netlist) ++ dffOutputs
  checkDuplicates "signal" (netlistInputs netlist ++ netlistWires netlist ++ clockNames ++ dffOutputs)
  checkDuplicates "component" componentNames
  checkDuplicates "driven signal" driven
  mapM_ (checkKnown declared "output") (netlistOutputs netlist)
  mapM_ (checkGate declared (netlistWires netlist)) (netlistGates netlist)
  mapM_ (checkFlipFlop declared clockNames) (netlistFlipFlops netlist)
  mapM_ (checkAssertion (netlistSignals netlist)) (netlistAssertions netlist)
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
  mapM_ (checkKnown declared "dff data input") (dffData flipFlop)
  mapM_ (checkKnown declared "dff reset") (maybe [] pure (dffReset flipFlop))

checkKnown :: [String] -> String -> String -> Either String ()
checkKnown declared label name =
  unless (name `elem` declared) (Left (label ++ " is not declared: " ++ name))

checkAssertion :: [String] -> Assertion -> Either String ()
checkAssertion known assertion =
  checkKnown known "assert signal" (assertionSignal assertion)

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
      ++ concatMap dffOutput (netlistFlipFlops netlist)
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

