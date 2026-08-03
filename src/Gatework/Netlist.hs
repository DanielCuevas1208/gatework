module Gatework.Netlist
  ( Assertion (..)
  , Clock (..)
  , DFlipFlop (..)
  , Gate (..)
  , Instance (..)
  , Module (..)
  , Netlist (..)
  , Time
  , netlistSignals
  , parseNetlist
  , parseNetlistFile
  ) where

import Control.Monad (unless)
import Data.Char (isAlphaNum, isSpace, toUpper)
import Data.List (foldl', nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
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

data Module = Module
  { moduleName :: String
  , moduleInputs :: [String]
  , moduleOutputs :: [String]
  , moduleBody :: [Declaration]
  }
  deriving (Eq, Show)

data Instance = Instance
  { instanceName :: String
  , instanceModule :: String
  , instanceInputs :: [String]
  , instanceOutputs :: [String]
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
  | InstanceDeclaration Instance
  deriving (Eq, Show)

data ParsedNetlist = ParsedNetlist
  { parsedModules :: Map String Module
  , parsedDeclarations :: [Declaration]
  }

emptyNetlist :: Netlist
emptyNetlist = Netlist [] [] [] [] [] [] []

parseNetlistFile :: FilePath -> IO (Either String Netlist)
parseNetlistFile path = parseNetlist <$> readFile path

parseNetlist :: String -> Either String Netlist
parseNetlist source = do
  parsed <- parseStatements (usefulLines source)
  validateModules (parsedModules parsed)
  netlist <- flattenParsed parsed
  _ <- validateNetlist netlist
  pure netlist

usefulLines :: String -> [(Int, String)]
usefulLines source =
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
  InstanceDeclaration _ -> netlist

parseStatements :: [(Int, String)] -> Either String ParsedNetlist
parseStatements statementLines = go statementLines Map.empty []
  where
    go remaining modules declarations = case remaining of
      [] -> Right (ParsedNetlist modules (reverse declarations))
      (lineNumber, line) : rest -> case words line of
        "module" : _ -> do
          (moduleDef, remainder) <- parseModuleBlock lineNumber line rest
          if Map.member (moduleName moduleDef) modules
            then Left ("duplicate module: " ++ moduleName moduleDef)
            else go remainder (Map.insert (moduleName moduleDef) moduleDef modules) declarations
        _ -> do
          declaration <- parseLine (lineNumber, line)
          go rest modules (declaration : declarations)

parseModuleBlock :: Int -> String -> [(Int, String)] -> Either String (Module, [(Int, String)])
parseModuleBlock lineNumber line rest = do
  (name, inputs, outputs) <- case words line of
    ["module", moduleName', ports, "->", outputPorts] ->
      parseModuleSignature lineNumber moduleName' ports outputPorts
    _ -> Left (lineError lineNumber "expected module NAME (inputs) -> (outputs)")
  let (bodyLines, remainder) = break isModuleEnd rest
  case remainder of
    [] -> Left (lineError lineNumber ("unterminated module: " ++ name))
    (_ : afterEnd) -> do
      unless (not (null bodyLines)) $
        Left (lineError lineNumber ("module has an empty body: " ++ name))
      declarations <- mapM parseModuleLine bodyLines
      pure (Module name inputs outputs declarations, afterEnd)
  where
    isModuleEnd (_, lineContent) = words lineContent == ["end"]

parseModuleLine :: (Int, String) -> Either String Declaration
parseModuleLine (lineNumber, line) = case words line of
  ("input" : _) -> Left (lineError lineNumber "input declarations are not allowed inside a module")
  ("output" : _) -> Left (lineError lineNumber "output declarations are not allowed inside a module")
  ("module" : _) -> Left (lineError lineNumber "nested modules are not allowed")
  ("end" : _) -> Left (lineError lineNumber "unexpected end outside a module block")
  _ -> parseLine (lineNumber, line)

parseModuleSignature :: Int -> String -> String -> String -> Either String (String, [String], [String])
parseModuleSignature lineNumber name inputPorts outputPorts = do
  moduleName' <- parseIdentifier lineNumber name
  inputNames <- parsePorts lineNumber inputPorts
  outputNames <- parsePorts lineNumber outputPorts
  unless (not (null inputNames)) $
    Left (lineError lineNumber "module requires at least one input port")
  unless (not (null outputNames)) $
    Left (lineError lineNumber "module requires at least one output port")
  unless (null (duplicates inputNames)) $
    Left (lineError lineNumber "module input ports cannot repeat")
  unless (null (duplicates outputNames)) $
    Left (lineError lineNumber "module output ports cannot repeat")
  let overlap = [port | port <- inputNames, port `elem` outputNames]
  unless (null overlap) $
    Left (lineError lineNumber "module ports cannot be both input and output")
  pure (moduleName', inputNames, outputNames)

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
  ["instance", moduleText, name, ports, "->", outputs] -> do
    moduleName' <- parseIdentifier lineNumber moduleText
    instanceName' <- parseIdentifier lineNumber name
    inputNames <- parsePorts lineNumber ports
    outputNames <- parsePorts lineNumber outputs
    unless (not (null inputNames)) $
      Left (lineError lineNumber "instance requires at least one input")
    unless (not (null outputNames)) $
      Left (lineError lineNumber "instance requires at least one output")
    pure (InstanceDeclaration (Instance instanceName' moduleName' inputNames outputNames))
  _ -> Left (lineError lineNumber "expected input, output, wire, clock, gate, dff, assert, or instance declaration")

parsePorts :: Int -> String -> Either String [String]
parsePorts lineNumber token
  | length token < 2 || head token /= '(' || last token /= ')' =
      Left (lineError lineNumber "port lists must use parentheses")
  | otherwise = do
      let body = init (tail token)
          names = splitOn ',' body
      unless (not (null body) && all (not . null) names) $
        Left (lineError lineNumber "port lists cannot be empty")
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
  mapM_ (checkGate declared (netlistWires netlist) (netlistOutputs netlist)) (netlistGates netlist)
  mapM_ (checkFlipFlop declared clockNames) (netlistFlipFlops netlist)
  mapM_ (checkAssertion (netlistSignals netlist)) (netlistAssertions netlist)
  pure netlist

checkGate :: [String] -> [String] -> [String] -> Gate -> Either String ()
checkGate declared wires outputs gate = do
  unless (gateOutput gate `elem` wires || gateOutput gate `elem` outputs) $
    Left ("gate output must be declared as a wire or output: " ++ gateOutput gate)
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

validateModules :: Map String Module -> Either String ()
validateModules modules = mapM_ validateModule (Map.elems modules)

validateModule :: Module -> Either String ()
validateModule moduleDef = do
  let ports = moduleInputs moduleDef ++ moduleOutputs moduleDef
      wires = [signal | WireDeclaration signal <- moduleBody moduleDef]
      clocks = [clock | ClockDeclaration clock <- moduleBody moduleDef]
      clockSignals = map clockSignal clocks
      dffOutputs = concat [dffOutput flipFlop | FlipFlopDeclaration flipFlop <- moduleBody moduleDef]
      declared = nub (ports ++ wires ++ clockSignals ++ dffOutputs)
      driven = [gateOutput gate | GateDeclaration gate <- moduleBody moduleDef] ++ dffOutputs
      componentNames =
        [gateName gate | GateDeclaration gate <- moduleBody moduleDef]
          ++ [dffName flipFlop | FlipFlopDeclaration flipFlop <- moduleBody moduleDef]
          ++ [instanceName instanceDef | InstanceDeclaration instanceDef <- moduleBody moduleDef]
  checkDuplicates "signal" declared
  checkDuplicates "component" componentNames
  checkDuplicates "driven signal" driven
  mapM_ (checkModuleGate moduleDef declared) (moduleGates moduleDef)
  mapM_ (checkModuleFlipFlop moduleDef declared clockSignals) (moduleFlipFlops moduleDef)
  mapM_ (checkAssertion declared) (moduleAssertions moduleDef)

moduleGates :: Module -> [Gate]
moduleGates moduleDef = [gate | GateDeclaration gate <- moduleBody moduleDef]

moduleFlipFlops :: Module -> [DFlipFlop]
moduleFlipFlops moduleDef = [flipFlop | FlipFlopDeclaration flipFlop <- moduleBody moduleDef]

moduleAssertions :: Module -> [Assertion]
moduleAssertions moduleDef = [assertion | AssertionDeclaration assertion <- moduleBody moduleDef]

checkModuleGate :: Module -> [String] -> Gate -> Either String ()
checkModuleGate moduleDef declared gate = do
  unless (gateOutput gate `elem` moduleWires moduleDef || gateOutput gate `elem` moduleOutputs moduleDef) $
    Left ("gate output must be declared as a wire or module output: " ++ gateOutput gate)
  mapM_ (checkKnown declared "gate input") (gateInputs gate)
  where
    moduleWires current = [signal | WireDeclaration signal <- moduleBody current]

checkModuleFlipFlop :: Module -> [String] -> [String] -> DFlipFlop -> Either String ()
checkModuleFlipFlop moduleDef declared clockSignals flipFlop = do
  unless (dffClock flipFlop `elem` clockSignals || dffClock flipFlop `elem` moduleInputs moduleDef) $
    Left ("dff clock must be a module clock or input port: " ++ dffClock flipFlop)
  mapM_ (checkKnown declared "dff data input") (dffData flipFlop)
  mapM_ (checkKnown declared "dff reset") (maybe [] pure (dffReset flipFlop))

flattenParsed :: ParsedNetlist -> Either String Netlist
flattenParsed parsed = do
  expanded <- concat <$> mapM (expandTop parsed) (parsedDeclarations parsed)
  pure (foldl' addDeclaration emptyNetlist expanded)

expandTop :: ParsedNetlist -> Declaration -> Either String [Declaration]
expandTop parsed declaration = case declaration of
  InstanceDeclaration instanceDef ->
    expandInstance parsed id (instanceName instanceDef) [] instanceDef
  other -> pure [other]

expandInstance :: ParsedNetlist -> (String -> String) -> String -> [String] -> Instance
  -> Either String [Declaration]
expandInstance parsed callerRename instancePath stack instanceDef = do
  moduleDef <- maybe
    (Left ("instance references an unknown module: " ++ instanceModule instanceDef))
    Right
    (Map.lookup (instanceModule instanceDef) (parsedModules parsed))
  let moduleRef = moduleName moduleDef
  if moduleRef `elem` stack
    then Left ("circular module instantiation: " ++ moduleRef)
    else do
      let connectionInputs = instanceInputs instanceDef
          connectionOutputs = instanceOutputs instanceDef
      unless (length connectionInputs == length (moduleInputs moduleDef)) $
        Left ( "instance " ++ instancePath ++ " expects "
            ++ show (length (moduleInputs moduleDef))
            ++ " inputs, but got "
            ++ show (length connectionInputs)
            )
      unless (length connectionOutputs == length (moduleOutputs moduleDef)) $
        Left ( "instance " ++ instancePath ++ " expects "
            ++ show (length (moduleOutputs moduleDef))
            ++ " outputs, but got "
            ++ show (length connectionOutputs)
            )
      let portMap = Map.fromList
            ( zip (moduleInputs moduleDef) connectionInputs
                ++ zip (moduleOutputs moduleDef) connectionOutputs
            )
          rename signal = case Map.lookup signal portMap of
            Just external -> callerRename external
            Nothing -> callerRename (instancePath ++ "." ++ signal)
          instancePrefix = instancePath ++ "."
      concat <$> mapM (expandDeclaration parsed rename instancePrefix (moduleRef : stack)) (moduleBody moduleDef)

expandDeclaration :: ParsedNetlist -> (String -> String) -> String -> [String] -> Declaration
  -> Either String [Declaration]
expandDeclaration parsed rename instancePrefix stack declaration = case declaration of
  WireDeclaration signal -> pure [WireDeclaration (rename signal)]
  ClockDeclaration clock -> pure [ClockDeclaration clock {clockSignal = rename (clockSignal clock)}]
  GateDeclaration gate -> pure
    [ GateDeclaration gate
      { gateName = instancePrefix ++ gateName gate
      , gateInputs = map rename (gateInputs gate)
      , gateOutput = rename (gateOutput gate)
      }
    ]
  FlipFlopDeclaration flipFlop -> pure
    [ FlipFlopDeclaration flipFlop
      { dffName = instancePrefix ++ dffName flipFlop
      , dffClock = rename (dffClock flipFlop)
      , dffData = map rename (dffData flipFlop)
      , dffOutput = map rename (dffOutput flipFlop)
      , dffReset = fmap rename (dffReset flipFlop)
      }
    ]
  AssertionDeclaration assertion -> pure
    [ AssertionDeclaration assertion {assertionSignal = rename (assertionSignal assertion)}
    ]
  InstanceDeclaration nested ->
    expandInstance parsed rename (instancePrefix ++ instanceName nested) stack nested
  _ -> Left "unexpected declaration in a module body"

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

