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
  , parseNetlistFileWithLibraries
  , parseNetlistWithLibraries
  , resolveInputAssignments
  ) where

import Control.Exception (IOException, try)
import Control.Monad (foldM, unless)
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
  , gateDelay :: Int
  }
  deriving (Eq, Show)

data Module = Module
  { moduleName :: String
  , moduleInputPorts :: [(String, Int)]
  , moduleOutputPorts :: [(String, Int)]
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
  , netlistBusWidths :: [(String, Int)]
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

data RefBits
  = RefWhole
  | RefBit Int
  | RefSlice Int Int
  deriving (Eq, Show)

data Ref = Ref
  { refBase :: String
  , refBits :: RefBits
  }
  deriving (Eq, Show)

data RawDeclaration
  = RawInput String Int
  | RawOutput String Int
  | RawWire String Int
  | RawClock Clock
  | RawGate GateType String [Ref] Ref Int
  | RawDff String Ref [Ref] [Ref] (Maybe String) (Maybe String) (Maybe Ref)
  | RawAssert Ref Logic Time
  | RawInstance String String [Ref] [Ref]
  deriving (Eq, Show)

data RawModule = RawModule
  { rawModuleName :: String
  , rawModuleInputs :: [(String, Int)]
  , rawModuleOutputs :: [(String, Int)]
  , rawModuleBody :: [RawDeclaration]
  }
  deriving (Eq, Show)

data ParsedNetlist = ParsedNetlist
  { parsedModules :: Map String Module
  , parsedDeclarations :: [Declaration]
  }

emptyNetlist :: Netlist
emptyNetlist = Netlist [] [] [] [] [] [] [] []

parseNetlistFile :: FilePath -> IO (Either String Netlist)
parseNetlistFile = parseNetlistFileWithLibraries []

parseNetlistFileWithLibraries :: [FilePath] -> FilePath -> IO (Either String Netlist)
parseNetlistFileWithLibraries libraryPaths mainPath = do
  mainOutcome <- tryReadFile mainPath
  case mainOutcome of
    Left _ -> pure (Left ("cannot read netlist file: " ++ mainPath))
    Right mainSource -> do
      libraries <- readLibraries libraryPaths
      pure (do
        sources <- libraries
        parseNetlistWithLibraries sources mainSource)
  where
    readLibraries :: [FilePath] -> IO (Either String [(FilePath, String)])
    readLibraries [] = pure (Right [])
    readLibraries (path : rest) = do
      outcome <- tryReadFile path
      case outcome of
        Left _ -> pure (Left ("cannot read library file: " ++ path))
        Right content -> fmap (fmap ((path, content) :)) (readLibraries rest)

parseNetlist :: String -> Either String Netlist
parseNetlist = parseNetlistWithLibraries []

parseNetlistWithLibraries :: [(FilePath, String)] -> String -> Either String Netlist
parseNetlistWithLibraries libraries source = do
  (libraryModules, sources) <- loadLibraries libraries
  (rawModules, rawDeclarations) <- parseStatements (usefulLines source)
  combinedModules <- foldM addMainModule libraryModules (Map.elems rawModules)
  let signatureModules = signatureOnlyModules combinedModules
  modules <- mapM (resolveModule sources signatureModules) combinedModules
  validateModulesWithSources sources modules
  widths <- topLevelWidths rawDeclarations
  declarations <- resolveTopLevel signatureModules widths rawDeclarations
  netlist <- flattenParsed (ParsedNetlist modules declarations)
  _ <- validateNetlist netlist
  pure netlist

loadLibraries :: [(FilePath, String)] -> Either String (Map String RawModule, Map String FilePath)
loadLibraries = foldM addLibrary (Map.empty, Map.empty)

addLibrary :: (Map String RawModule, Map String FilePath) -> (FilePath, String)
  -> Either String (Map String RawModule, Map String FilePath)
addLibrary (modules, sources) (path, content) = do
  let libraryResult = parseStatements (usefulLines content)
  (libraryModules, libraryDeclarations) <- case libraryResult of
    Left message -> Left (path ++ ": " ++ message)
    Right parsed -> Right parsed
  unless (null libraryDeclarations) $
    Left (path ++ ": library files may contain only module definitions")
  foldM (insertLibraryModule path) (modules, sources) (Map.elems libraryModules)

insertLibraryModule :: FilePath -> (Map String RawModule, Map String FilePath) -> RawModule
  -> Either String (Map String RawModule, Map String FilePath)
insertLibraryModule path (modules, sources) moduleDef
  | Map.member name modules = Left (path ++ ": duplicate module: " ++ name)
  | otherwise = Right (Map.insert name moduleDef modules, Map.insert name path sources)
  where
    name = rawModuleName moduleDef

addMainModule :: Map String RawModule -> RawModule -> Either String (Map String RawModule)
addMainModule modules moduleDef
  | Map.member name modules = Left ("duplicate module: " ++ name)
  | otherwise = Right (Map.insert name moduleDef modules)
  where
    name = rawModuleName moduleDef

resolveModule :: Map String FilePath -> Map String Module -> RawModule -> Either String Module
resolveModule sources signatureModules moduleDef =
  case resolveRawModule signatureModules moduleDef of
    Left message -> Left (withSource (rawModuleName moduleDef) message)
    Right resolved -> Right resolved
  where
    withSource name message = case Map.lookup name sources of
      Just path -> path ++ ": " ++ message
      Nothing -> message

tryReadFile :: FilePath -> IO (Either IOException String)
tryReadFile path = try (readFile path)

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

parseStatements :: [(Int, String)] -> Either String (Map String RawModule, [RawDeclaration])
parseStatements statementLines = go statementLines Map.empty []
  where
    go remaining modules rawDeclarations = case remaining of
      [] -> Right (modules, reverse rawDeclarations)
      (lineNumber, line) : rest -> case words line of
        "module" : _ -> do
          (moduleDef, remainder) <- parseModuleBlock lineNumber line rest
          if Map.member (rawModuleName moduleDef) modules
            then Left ("duplicate module: " ++ rawModuleName moduleDef)
            else go remainder (Map.insert (rawModuleName moduleDef) moduleDef modules) rawDeclarations
        _ -> do
          declaration <- parseLine (lineNumber, line)
          go rest modules (declaration : rawDeclarations)

parseModuleBlock :: Int -> String -> [(Int, String)] -> Either String (RawModule, [(Int, String)])
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
      rawBody <- mapM parseModuleLine bodyLines
      pure (RawModule name inputs outputs rawBody, afterEnd)
  where
    isModuleEnd (_, lineContent) = words lineContent == ["end"]

parseModuleLine :: (Int, String) -> Either String RawDeclaration
parseModuleLine (lineNumber, line) = case words line of
  ("input" : _) -> Left (lineError lineNumber "input declarations are not allowed inside a module")
  ("output" : _) -> Left (lineError lineNumber "output declarations are not allowed inside a module")
  ("module" : _) -> Left (lineError lineNumber "nested modules are not allowed")
  ("end" : _) -> Left (lineError lineNumber "unexpected end outside a module block")
  _ -> parseLine (lineNumber, line)

parseModuleSignature :: Int -> String -> String -> String -> Either String (String, [(String, Int)], [(String, Int)])
parseModuleSignature lineNumber name inputPorts outputPorts = do
  moduleName' <- parseIdentifier lineNumber name
  inputNames <- parsePortsWithWidths lineNumber inputPorts
  outputNames <- parsePortsWithWidths lineNumber outputPorts
  unless (not (null inputNames)) $
    Left (lineError lineNumber "module requires at least one input port")
  unless (not (null outputNames)) $
    Left (lineError lineNumber "module requires at least one output port")
  unless (null (duplicates (map fst inputNames))) $
    Left (lineError lineNumber "module input ports cannot repeat")
  unless (null (duplicates (map fst outputNames))) $
    Left (lineError lineNumber "module output ports cannot repeat")
  let overlap = [port | (port, _) <- inputNames, port `elem` map fst outputNames]
  unless (null overlap) $
    Left (lineError lineNumber "module ports cannot be both input and output")
  pure (moduleName', inputNames, outputNames)

parseLine :: (Int, String) -> Either String RawDeclaration
parseLine (lineNumber, line) = case words line of
  ["input", name] -> uncurry RawInput <$> parsePort lineNumber name
  ["output", name] -> uncurry RawOutput <$> parsePort lineNumber name
  ["wire", name] -> uncurry RawWire <$> parsePort lineNumber name
  ["clock", name, period] -> do
    signal <- parseIdentifier lineNumber name
    parsedPeriod <- parseKeyInt lineNumber "period" period
    unless (parsedPeriod >= 2 && even parsedPeriod) $
      Left (lineError lineNumber "clock period must be an even integer of at least two")
    pure (RawClock (Clock signal parsedPeriod))
  ("gate" : gateText : name : ports : "->" : output : fields) -> do
    gate <- maybe (Left (lineError lineNumber ("unknown gate type: " ++ gateText))) Right
      (parseGateType (map toUpper gateText))
    gateName' <- parseIdentifier lineNumber name
    inputRefs <- parsePortList lineNumber ports
    outputRef <- parseRef lineNumber output
    unless (length inputRefs == gateArity gate) $
      Left (lineError lineNumber ("gate " ++ name ++ " expects " ++ show (gateArity gate) ++ " inputs"))
    delay <- parseGateFields lineNumber fields
    pure (RawGate gate gateName' inputRefs outputRef delay)
  ("dff" : name : fields) -> do
    dffName' <- parseIdentifier lineNumber name
    parsedFields <- mapM (parseField lineNumber) fields
    clockRef <- requiredField lineNumber "clock" parsedFields
    dataText <- requiredField lineNumber "d" parsedFields
    outputText <- requiredField lineNumber "q" parsedFields
    clock <- parseRef lineNumber clockRef
    dataRefs <- parseRefList lineNumber "d" dataText
    outputRefs <- parseRefList lineNumber "q" outputText
    unless (not (null dataRefs)) $
      Left (lineError lineNumber "dff requires at least one data input")
    let initText = lookup "init" parsedFields
        widthText = lookup "width" parsedFields
    reset <- case lookup "rst" parsedFields of
      Nothing -> Right Nothing
      Just value -> Just <$> parseRef lineNumber value
    pure (RawDff dffName' clock dataRefs outputRefs initText widthText reset)
  ["assert", signal, "=", value, "at", timeText] -> do
    signalRef <- parseRef lineNumber signal
    logic <- maybe
      (Left (lineError lineNumber "assert value must be 0, 1, x, or z"))
      Right
      (parseLogic value)
    time <- parseAssertTime lineNumber timeText
    pure (RawAssert signalRef logic time)
  ["instance", moduleText, name, ports, "->", outputs] -> do
    moduleName' <- parseIdentifier lineNumber moduleText
    instanceName' <- parseIdentifier lineNumber name
    inputRefs <- parsePortList lineNumber ports
    outputRefs <- parsePortList lineNumber outputs
    unless (not (null inputRefs)) $
      Left (lineError lineNumber "instance requires at least one input")
    unless (not (null outputRefs)) $
      Left (lineError lineNumber "instance requires at least one output")
    pure (RawInstance instanceName' moduleName' inputRefs outputRefs)
  _ -> Left (lineError lineNumber "expected input, output, wire, clock, gate, dff, assert, or instance declaration")

parsePortsWithWidths :: Int -> String -> Either String [(String, Int)]
parsePortsWithWidths lineNumber token
  | length token < 2 || head token /= '(' || last token /= ')' =
      Left (lineError lineNumber "port lists must use parentheses")
  | otherwise = do
      let body = init (tail token)
          names = splitOn ',' body
      unless (not (null body) && all (not . null) names) $
        Left (lineError lineNumber "port lists cannot be empty")
      mapM (parsePort lineNumber) names

parsePortList :: Int -> String -> Either String [Ref]
parsePortList lineNumber token
  | length token < 2 || head token /= '(' || last token /= ')' =
      Left (lineError lineNumber "port lists must use parentheses")
  | otherwise = do
      let body = init (tail token)
          names = splitOn ',' body
      unless (not (null body) && all (not . null) names) $
        Left (lineError lineNumber "port lists cannot be empty")
      mapM (parseRef lineNumber) names

parsePort :: Int -> String -> Either String (String, Int)
parsePort lineNumber token = case break (== '[') token of
  (base, '[' : rest)
    | not (null rest) && last rest == ']' -> do
        name <- parseIdentifier lineNumber base
        width <- parseNonNegative lineNumber "port width" (init rest)
        unless (width >= 1) $
          Left (lineError lineNumber "port width must be a positive integer")
        pure (name, width)
  (base, []) -> (,) <$> parseIdentifier lineNumber base <*> pure 1
  _ -> Left (lineError lineNumber ("invalid port: " ++ token))

parseRef :: Int -> String -> Either String Ref
parseRef lineNumber token = case break (== '[') token of
  (base, '[' : rest)
    | not (null rest) && last rest == ']' -> do
        name <- parseIdentifier lineNumber base
        bits <- parseRefBits lineNumber (init rest)
        pure (Ref name bits)
  (base, []) -> Ref <$> parseIdentifier lineNumber base <*> pure RefWhole
  _ -> Left (lineError lineNumber ("invalid signal reference: " ++ token))

parseRefBits :: Int -> String -> Either String RefBits
parseRefBits lineNumber body = case break (== ':') body of
  (indexText, []) -> RefBit <$> parseIndex lineNumber indexText
  (hiText, _ : loText) -> do
    hi <- parseIndex lineNumber hiText
    lo <- parseIndex lineNumber loText
    unless (hi >= lo) $
      Left (lineError lineNumber "slice upper bound must be at least the lower bound")
    pure (RefSlice hi lo)

parseIndex :: Int -> String -> Either String Int
parseIndex lineNumber token = case reads token of
  [(number, "")] | number >= 0 -> Right number
  _ -> Left (lineError lineNumber ("bit index must be a non-negative integer: " ++ token))

parseRefList :: Int -> String -> String -> Either String [Ref]
parseRefList lineNumber key value = do
  let tokens = splitOn ',' value
  unless (all (not . null) tokens) $
    Left (lineError lineNumber ("dff " ++ key ++ " list cannot contain empty entries"))
  mapM (parseRef lineNumber) tokens

parseField :: Int -> String -> Either String (String, String)
parseField lineNumber field = case break (== '=') field of
  (key, '=' : value)
    | key `elem` ["clock", "d", "q", "init", "rst", "width"] && not (null value) -> Right (key, value)
  _ -> Left (lineError lineNumber ("invalid dff field: " ++ field))

parseGateFields :: Int -> [String] -> Either String Int
parseGateFields lineNumber fields = do
  values <- mapM parseOne fields
  case [value | Just value <- values] of
    [] -> Right 0
    [value] -> Right value
    _ -> Left (lineError lineNumber "gate delay cannot repeat")
  where
    parseOne field = case break (== '=') field of
      ("delay", '=' : value)
        | not (null value) -> Just <$> parseDelayValue value
      _ -> Left (lineError lineNumber ("invalid gate field: " ++ field))
    parseDelayValue value = case reads value of
      [(number, "")] | number >= 0 -> Right number
      _ -> Left (lineError lineNumber ("gate delay must be a non-negative integer: " ++ value))

parseNonNegative :: Int -> String -> String -> Either String Int
parseNonNegative lineNumber key token = case reads token of
  [(number, "")] | number >= 0 -> Right number
  _ -> Left (lineError lineNumber (key ++ " must be a non-negative integer"))

parseAssertTime :: Int -> String -> Either String Time
parseAssertTime lineNumber token = do
  time <- parseNonNegative lineNumber "assert time" token
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

signatureOnlyModules :: Map String RawModule -> Map String Module
signatureOnlyModules rawModules =
  Map.map
    (\raw -> Module (rawModuleName raw) (rawModuleInputs raw) (rawModuleOutputs raw) [])
    rawModules

resolveRawModule :: Map String Module -> RawModule -> Either String Module
resolveRawModule signatureModules raw = do
  widths <- moduleWidths raw
  body <- concat <$> mapM (resolveDeclaration signatureModules widths) (rawModuleBody raw)
  pure (Module (rawModuleName raw) (rawModuleInputs raw) (rawModuleOutputs raw) body)

moduleWidths :: RawModule -> Either String (Map String Int)
moduleWidths raw =
  foldM addWidth (Map.fromList (rawModuleInputs raw ++ rawModuleOutputs raw)) (rawModuleBody raw)
  where
    addWidth widths (RawWire name width) = insertWidth widths name width
    addWidth widths (RawClock clock) = insertWidth widths (clockSignal clock) 1
    addWidth widths _ = Right widths

resolveTopLevel :: Map String Module -> Map String Int -> [RawDeclaration] -> Either String [Declaration]
resolveTopLevel signatureModules widths rawDeclarations =
  concat <$> mapM (resolveDeclaration signatureModules widths) rawDeclarations

topLevelWidths :: [RawDeclaration] -> Either String (Map String Int)
topLevelWidths = foldM addWidth Map.empty
  where
    addWidth widths (RawInput name width) = insertWidth widths name width
    addWidth widths (RawOutput name width) = insertWidth widths name width
    addWidth widths (RawWire name width) = insertWidth widths name width
    addWidth widths (RawClock clock) = insertWidth widths (clockSignal clock) 1
    addWidth widths _ = Right widths

insertWidth :: Map String Int -> String -> Int -> Either String (Map String Int)
insertWidth widths name width = case Map.lookup name widths of
  Nothing -> Right (Map.insert name width widths)
  Just existing
    | existing == width -> Right widths
    | otherwise ->
        Left ("conflicting widths for signal " ++ name ++ ": " ++ show existing ++ " and " ++ show width)

resolveDeclaration :: Map String Module -> Map String Int -> RawDeclaration -> Either String [Declaration]
resolveDeclaration signatureModules widths declaration = case declaration of
  RawInput name width -> Right (map InputDeclaration (bitNames name width))
  RawOutput name width -> Right (map OutputDeclaration (bitNames name width))
  RawWire name width -> Right (map WireDeclaration (bitNames name width))
  RawClock clock -> Right [ClockDeclaration clock]
  RawGate gateKind name inputRefs outputRef delay ->
    resolveGate widths gateKind name inputRefs outputRef delay
  RawDff name clockRef dataRefs outRefs initText widthText resetRef ->
    resolveDff widths name clockRef dataRefs outRefs initText widthText resetRef
  RawAssert signalRef value time -> resolveAssertion widths signalRef value time
  RawInstance name targetModule inputRefs outputRefs ->
    resolveInstance signatureModules widths name targetModule inputRefs outputRefs

resolveGate :: Map String Int -> GateType -> String -> [Ref] -> Ref -> Int -> Either String [Declaration]
resolveGate widths gateKind name inputRefs outputRef delay = do
  inputBits <- mapM (resolveRef widths) inputRefs
  outputBits <- resolveRef widths outputRef
  let width = length outputBits
  unless (all ((== width) . length) inputBits) $
    Left ("gate " ++ name ++ " mixes bus widths")
  pure
    [ GateDeclaration
        (Gate gateKind (componentName name width index) (map (!! index) inputBits) (outputBits !! index) delay)
    | index <- [0 .. width - 1]
    ]

resolveDff :: Map String Int -> String -> Ref -> [Ref] -> [Ref] -> Maybe String -> Maybe String -> Maybe Ref
  -> Either String [Declaration]
resolveDff widths name clockRef dataRefs outRefs initText widthText resetRef = do
  clockName <- case resolveRef widths clockRef of
    Left message -> Left message
    Right [signal] -> Right signal
    Right _ -> Left ("dff " ++ name ++ " clock must reference a single signal")
  dataBits <- concat <$> mapM (resolveRef widths) dataRefs
  outputBits <- concat <$> mapM (resolveRef widths) outRefs
  unless (not (null dataBits)) $
    Left ("dff " ++ name ++ " requires at least one data input")
  unless (length dataBits == length outputBits) $
    Left ("dff " ++ name ++ " data and output widths must match")
  let width = length outputBits
  case widthText of
    Nothing -> pure ()
    Just text -> do
      declaredWidth <- parseInt text
      unless (declaredWidth == width) $
        Left ("dff " ++ name ++ " width must match the data width")
  initList <- parseInitValues width initText
  resetSignal <- case resetRef of
    Nothing -> Right Nothing
    Just ref -> case resolveRef widths ref of
      Left message -> Left message
      Right [signal] -> Right (Just signal)
      Right _ -> Left ("dff " ++ name ++ " reset must reference a single signal")
  pure
    [ FlipFlopDeclaration
        (DFlipFlop
          (componentName name width index)
          clockName
          [dataBits !! index]
          [outputBits !! index]
          [initList !! index]
          resetSignal)
    | index <- [0 .. width - 1]
    ]

resolveAssertion :: Map String Int -> Ref -> Logic -> Time -> Either String [Declaration]
resolveAssertion widths signalRef value time = case resolveRef widths signalRef of
  Left message -> Left message
  Right [signal] -> Right [AssertionDeclaration (Assertion signal value time)]
  Right _ -> Left ("assert signal must reference a single bit: " ++ refBase signalRef)

resolveInstance :: Map String Module -> Map String Int -> String -> String -> [Ref] -> [Ref]
  -> Either String [Declaration]
resolveInstance signatureModules widths name targetModule inputRefs outputRefs = do
  moduleDef <- maybe
    (Left ("instance references an unknown module: " ++ targetModule))
    Right
    (Map.lookup targetModule signatureModules)
  let expectedInputs = map snd (moduleInputPorts moduleDef)
      expectedOutputs = map snd (moduleOutputPorts moduleDef)
  unless (length expectedInputs == length inputRefs) $
    Left ("instance " ++ name ++ " expects " ++ show (length expectedInputs)
      ++ " inputs, but got " ++ show (length inputRefs))
  unless (length expectedOutputs == length outputRefs) $
    Left ("instance " ++ name ++ " expects " ++ show (length expectedOutputs)
      ++ " outputs, but got " ++ show (length outputRefs))
  inputSignals <- mapM (checkConnection name) (zip expectedInputs inputRefs)
  outputSignals <- mapM (checkConnection name) (zip expectedOutputs outputRefs)
  pure [InstanceDeclaration (Instance name targetModule (concat inputSignals) (concat outputSignals))]
  where
    checkConnection connectionName (expected, ref) = do
      signals <- resolveRef widths ref
      unless (length signals == expected) $
        Left ("instance " ++ connectionName ++ " port has width " ++ show (length signals)
          ++ ", expected " ++ show expected)
      pure signals

resolveRef :: Map String Int -> Ref -> Either String [String]
resolveRef widths ref = case Map.lookup (refBase ref) widths of
  Nothing -> case refBits ref of
    RefWhole -> Right [refBase ref]
    RefBit 0 -> Right [refBase ref]
    RefBit index ->
      Left ("signal " ++ refBase ref ++ " has no declared width; index " ++ show index ++ " is out of range")
    RefSlice high low
      | high == 0 && low == 0 -> Right [refBase ref]
      | otherwise ->
          Left ("signal " ++ refBase ref ++ " has no declared width; slice ["
            ++ show high ++ ":" ++ show low ++ "] is out of range")
  Just width -> case refBits ref of
    RefWhole -> Right (bitNames (refBase ref) width)
    RefBit index -> do
      checkIndex (refBase ref) width index
      pure [bitAt (refBase ref) width index]
    RefSlice high low -> do
      unless (high >= 0 && low >= 0 && high < width && low < width) $
        Left ("signal " ++ refBase ref ++ " has width " ++ show width
          ++ "; slice [" ++ show high ++ ":" ++ show low ++ "] is out of range")
      pure [bitAt (refBase ref) width index | index <- [low .. high]]

checkIndex :: String -> Int -> Int -> Either String ()
checkIndex base width index
  | index >= 0 && index < width = Right ()
  | otherwise =
      Left ("signal " ++ base ++ " has width " ++ show width
        ++ "; index " ++ show index ++ " is out of range")

bitNames :: String -> Int -> [String]
bitNames base width
  | width <= 1 = [base]
  | otherwise = [base ++ "[" ++ show index ++ "]" | index <- [0 .. width - 1]]

bitAt :: String -> Int -> Int -> String
bitAt base width index
  | width <= 1 = base
  | otherwise = base ++ "[" ++ show index ++ "]"

componentName :: String -> Int -> Int -> String
componentName base width index
  | width <= 1 = base
  | otherwise = base ++ "[" ++ show index ++ "]"

parseInitValues :: Int -> Maybe String -> Either String [Logic]
parseInitValues width initText = case initText of
  Nothing -> Right (replicate width Low)
  Just value -> case splitOn ',' value of
    [single] -> maybe
      (Left "init must be 0, 1, x, or z")
      (Right . replicate width)
      (parseLogic single)
    values -> do
      unless (length values == width) $
        Left "init list width must match dff width"
      mapM parseInitValue values
  where
    parseInitValue token = maybe
      (Left "init must be 0, 1, x, or z")
      Right
      (parseLogic token)

parseInt :: String -> Either String Int
parseInt token = case reads token of
  [(number, "")] -> Right number
  _ -> Left "width must be an integer"

validateNetlist :: Netlist -> Either String Netlist
validateNetlist netlist = do
  let clockNames = map clockSignal (netlistClocks netlist)
      dffOutputs = concatMap dffOutput (netlistFlipFlops netlist)
      gateOutputs = map gateOutput (netlistGates netlist)
      declared = netlistInputs netlist ++ netlistWires netlist ++ clockNames ++ dffOutputs
      componentNames = map gateName (netlistGates netlist) ++ map dffName (netlistFlipFlops netlist)
  checkDuplicates "signal" (netlistInputs netlist ++ netlistWires netlist ++ clockNames ++ dffOutputs)
  checkDuplicates "component" componentNames
  checkDuplicates "flip-flop output" dffOutputs
  checkNoGateOnDffOutput dffOutputs gateOutputs
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

checkNoGateOnDffOutput :: [String] -> [String] -> Either String ()
checkNoGateOnDffOutput dffOutputs gateOutputs =
  case [name | name <- gateOutputs, name `elem` dffOutputs] of
    [] -> Right ()
    name : _ -> Left ("a gate cannot drive a flip-flop output: " ++ name)

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

validateModulesWithSources :: Map String FilePath -> Map String Module -> Either String ()
validateModulesWithSources sources modules =
  mapM_ validateOne modules
  where
    validateOne moduleDef = case validateModule moduleDef of
      Left message -> Left (withSource (moduleName moduleDef) message)
      Right () -> Right ()
    withSource name message = case Map.lookup name sources of
      Just path -> path ++ ": " ++ message
      Nothing -> message

validateModule :: Module -> Either String ()
validateModule moduleDef = do
  let portSignals = concatMap (uncurry bitNames) (moduleInputPorts moduleDef ++ moduleOutputPorts moduleDef)
      wires = [signal | WireDeclaration signal <- moduleBody moduleDef]
      clocks = [clock | ClockDeclaration clock <- moduleBody moduleDef]
      clockSignals = map clockSignal clocks
      dffOutputs = concat [dffOutput flipFlop | FlipFlopDeclaration flipFlop <- moduleBody moduleDef]
      gateOutputs = [gateOutput gate | GateDeclaration gate <- moduleBody moduleDef]
      declared = nub (portSignals ++ wires ++ clockSignals ++ dffOutputs)
      componentNames =
        [gateName gate | GateDeclaration gate <- moduleBody moduleDef]
          ++ [dffName flipFlop | FlipFlopDeclaration flipFlop <- moduleBody moduleDef]
          ++ [instanceName instanceDef | InstanceDeclaration instanceDef <- moduleBody moduleDef]
  checkDuplicates "signal" declared
  checkDuplicates "component" componentNames
  checkDuplicates "flip-flop output" dffOutputs
  checkNoGateOnDffOutput dffOutputs gateOutputs
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
  let moduleWires = [signal | WireDeclaration signal <- moduleBody moduleDef]
      moduleOutputs = concatMap (uncurry bitNames) (moduleOutputPorts moduleDef)
  unless (gateOutput gate `elem` moduleWires || gateOutput gate `elem` moduleOutputs) $
    Left ("gate output must be declared as a wire or module output: " ++ gateOutput gate)
  mapM_ (checkKnown declared "gate input") (gateInputs gate)

checkModuleFlipFlop :: Module -> [String] -> [String] -> DFlipFlop -> Either String ()
checkModuleFlipFlop moduleDef declared clockSignals flipFlop = do
  let moduleInputs = concatMap (uncurry bitNames) (moduleInputPorts moduleDef)
  unless (dffClock flipFlop `elem` clockSignals || dffClock flipFlop `elem` moduleInputs) $
    Left ("dff clock must be a module clock or input port: " ++ dffClock flipFlop)
  mapM_ (checkKnown declared "dff data input") (dffData flipFlop)
  mapM_ (checkKnown declared "dff reset") (maybe [] pure (dffReset flipFlop))

flattenParsed :: ParsedNetlist -> Either String Netlist
flattenParsed parsed = do
  expanded <- concat <$> mapM (expandTop parsed) (parsedDeclarations parsed)
  let netlist = foldl' addDeclaration emptyNetlist expanded
  pure netlist {netlistBusWidths = busWidthList (inferBusWidths expanded)}

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
      let moduleInputBits = concatMap (uncurry bitNames) (moduleInputPorts moduleDef)
          moduleOutputBits = concatMap (uncurry bitNames) (moduleOutputPorts moduleDef)
          connectionInputs = instanceInputs instanceDef
          connectionOutputs = instanceOutputs instanceDef
      unless (length connectionInputs == length moduleInputBits) $
        Left ( "instance " ++ instancePath ++ " expects "
            ++ show (length moduleInputBits)
            ++ " inputs, but got "
            ++ show (length connectionInputs)
            )
      unless (length connectionOutputs == length moduleOutputBits) $
        Left ( "instance " ++ instancePath ++ " expects "
            ++ show (length moduleOutputBits)
            ++ " outputs, but got "
            ++ show (length connectionOutputs)
            )
      let portMap = Map.fromList
            ( zip moduleInputBits connectionInputs
                ++ zip moduleOutputBits connectionOutputs
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

busWidthList :: Map String Int -> [(String, Int)]
busWidthList widths =
  [(name, width) | (name, width) <- Map.toAscList widths, width > 1]

inferBusWidths :: [Declaration] -> Map String Int
inferBusWidths = foldl' addName Map.empty . concatMap declarationNames
  where
    declarationNames declaration = case declaration of
      InputDeclaration name -> [name]
      OutputDeclaration name -> [name]
      WireDeclaration name -> [name]
      FlipFlopDeclaration flipFlop -> dffOutput flipFlop
      _ -> []
    addName widths name = case break (== '[') name of
      (base, '[' : rest)
        | not (null rest)
        , last rest == ']'
        , Just index <- readBracket (init rest) ->
            Map.insertWith max base (index + 1) widths
      _ -> widths
    readBracket text = case reads text of
      [(index, "")] -> Just index
      _ -> Nothing

resolveInputAssignments :: Netlist -> [(String, String)] -> Either String [(String, Logic)]
resolveInputAssignments netlist = fmap concat . mapM resolveOne
  where
    widths = Map.fromList (netlistBusWidths netlist)
    inputs = netlistInputs netlist
    resolveOne (name, value)
      | Just width <- Map.lookup name widths = do
          resolved <- expandBus name width value
          unless (all ((`elem` inputs) . fst) resolved) $
            Left ("input override is not an input: " ++ name)
          pure resolved
      | otherwise = do
          logic <- parseInputValue name value
          pure [(name, logic)]

expandBus :: String -> Int -> String -> Either String [(String, Logic)]
expandBus name width value
  | length value /= width =
      Left ( "bus " ++ name ++ " has width " ++ show width
          ++ ", but the value has " ++ show (length value) ++ " bits" )
  | otherwise = sequence
      [ case parseLogic [char] of
          Just logic -> Right (bitAt name width index, logic)
          Nothing ->
            Left ("input value must be 0, 1, x, or z: " ++ name ++ "=" ++ value)
      | (index, char) <- zip [width - 1, width - 2 .. 0] value
      ]

parseInputValue :: String -> String -> Either String Logic
parseInputValue name value = maybe
  (Left ("input value must be 0, 1, x, or z: " ++ name ++ "=" ++ value))
  Right
  (parseLogic value)

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

splitOn :: Char -> String -> [String]
splitOn delimiter value = case break (== delimiter) value of
  (part, _ : rest) -> part : splitOn delimiter rest
  (part, []) -> [part]

lineError :: Int -> String -> String
lineError lineNumber message = "line " ++ show lineNumber ++ ": " ++ message
