module Main (main) where

import Data.List (intercalate)
import Gatework.Logic (Logic, logicChar, parseLogic)
import Gatework.Netlist (netlistSignals, parseNetlistFile)
import Gatework.Simulator
  ( AssertionFailure (..)
  , Simulation
  , Time
  , simulationAssertions
  , simulationFailures
  , simulateWithScheduledInputs
  )
import Gatework.VCD (writeVCD)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

data Options = Options
  { optionNetlist :: Maybe FilePath
  , optionDuration :: Integer
  , optionOutput :: FilePath
  , optionInputs :: [(String, Logic)]
  , optionScheduled :: [(Time, String, Logic)]
  }

defaultOptions :: Options
defaultOptions = Options Nothing 16 "gatework.vcd" [] []

main :: IO ()
main = do
  arguments <- getArgs
  case parseOptions arguments of
    Left message -> failWith message
    Right Nothing -> putStrLn usage
    Right (Just options) -> run options

run :: Options -> IO ()
run options = case optionNetlist options of
  Nothing -> failWith "--netlist is required"
  Just path -> do
    parsed <- parseNetlistFile path
    case parsed of
      Left message -> failWith message
      Right netlist ->
        case simulateWithScheduledInputs netlist (optionInputs options) (optionScheduled options) (optionDuration options) of
          Left message -> failWith message
          Right simulation -> do
            writeVCD (optionOutput options) simulation
            putStrLn ("Wrote " ++ optionOutput options)
            putStrLn ("Signals: " ++ show (length (netlistSignals netlist)))
            putStrLn ("Duration: " ++ show (optionDuration options) ++ " time units")
            reportAssertions simulation

reportAssertions :: Simulation -> IO ()
reportAssertions simulation = case simulationFailures simulation of
  [] -> case simulationAssertions simulation of
    [] -> pure ()
    assertions ->
      putStrLn ("Assertions: " ++ show (length assertions) ++ " passed")
  failures -> do
    mapM_ (hPutStrLn stderr . renderFailure) failures
    exitFailure

renderFailure :: AssertionFailure -> String
renderFailure failure = concat
  [ "assertion failed: "
  , failureSignal failure
  , " must be "
  , [logicChar (failureExpected failure)]
  , " at time "
  , show (failureTime failure)
  , ", but was "
  , [logicChar (failureActual failure)]
  ]

parseOptions :: [String] -> Either String (Maybe Options)
parseOptions arguments = parseMore defaultOptions arguments
  where
    parseMore options remaining = case remaining of
      [] -> Right (Just options)
      "--help" : _ -> Right Nothing
      "--netlist" : path : rest -> parseMore options {optionNetlist = Just path} rest
      "--duration" : value : rest -> do
        duration <- maybe (Left "--duration requires an integer") Right (readMaybe value)
        parseMore options {optionDuration = duration} rest
      "--output" : path : rest -> parseMore options {optionOutput = path} rest
      "--set" : assignments : rest -> do
        values <- parseAssignments assignments
        parseMore options {optionInputs = optionInputs options ++ values} rest
      "--at" : timeText : assignments : rest -> do
        time <- maybe (Left "--at requires an integer time") Right (readMaybe timeText)
        values <- parseAssignments assignments
        parseMore options {optionScheduled = optionScheduled options ++ [(time, name, logic) | (name, logic) <- values]} rest
      option : _ -> Left ("unknown option: " ++ option)

parseAssignments :: String -> Either String [(String, Logic)]
parseAssignments value = mapM parseAssignment (splitOn ',' value)
  where
    parseAssignment assignment = case break (== '=') assignment of
      (name, '=' : rawLogic) | not (null name) -> case parseLogic rawLogic of
        Just logic -> Right (name, logic)
        Nothing -> Left ("input value must be 0 or 1: " ++ assignment)
      _ -> Left ("input assignment must use signal=0 or signal=1: " ++ assignment)

splitOn :: Char -> String -> [String]
splitOn delimiter value = case break (== delimiter) value of
  (part, _ : rest) -> part : splitOn delimiter rest
  (part, []) -> [part]

failWith :: String -> IO a
failWith message = do
  hPutStrLn stderr message
  hPutStrLn stderr usage
  exitFailure

usage :: String
usage = intercalate "\n"
  [ "gatework --netlist FILE [--duration N] [--output FILE] [--set signal=0,signal=1] [--at TIME signal=0,signal=1]"
  , ""
  , "Simulate a netlist and write a VCD waveform."
  , "Use --at to change input signals at a fixed time during the run."
  , "Check assert declarations in the netlist against the waveform."
  ]


