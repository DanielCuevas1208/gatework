module Gatework.Logic
  ( GateType (..)
  , Logic (..)
  , evalGate
  , gateArity
  , logicChar
  , parseGateType
  , parseLogic
  ) where

import Data.Char (toLower)
import Data.List (foldl')

data Logic = Low | High | Undefined | TriState
  deriving (Eq, Ord, Read, Show)

data GateType = And | Or | Xor | Not | Nand | Nor | Xnor | Tribuf
  deriving (Eq, Ord, Read, Show)

gateArity :: GateType -> Int
gateArity And = 2
gateArity Or = 2
gateArity Xor = 2
gateArity Not = 1
gateArity Nand = 2
gateArity Nor = 2
gateArity Xnor = 2
gateArity Tribuf = 2

parseGateType :: String -> Maybe GateType
parseGateType value = case map toLower value of
  "and" -> Just And
  "or" -> Just Or
  "xor" -> Just Xor
  "not" -> Just Not
  "nand" -> Just Nand
  "nor" -> Just Nor
  "xnor" -> Just Xnor
  "tribuf" -> Just Tribuf
  _ -> Nothing

parseLogic :: String -> Maybe Logic
parseLogic value = case map toLower value of
  "0" -> Just Low
  "1" -> Just High
  "x" -> Just Undefined
  "z" -> Just TriState
  _ -> Nothing

logicChar :: Logic -> Char
logicChar Low = '0'
logicChar High = '1'
logicChar Undefined = 'x'
logicChar TriState = 'z'

evalGate :: GateType -> [Logic] -> Logic
evalGate And inputs
  | any (== Low) inputs = Low
  | any isUnknown inputs = Undefined
  | otherwise = High
evalGate Or inputs
  | any (== High) inputs = High
  | any isUnknown inputs = Undefined
  | otherwise = Low
evalGate Xor inputs
  | any isUnknown inputs = Undefined
  | otherwise = foldl' xorKnown Low inputs
evalGate Nand inputs
  | any (== Low) inputs = High
  | any isUnknown inputs = Undefined
  | otherwise = Low
evalGate Nor inputs
  | any (== High) inputs = Low
  | any isUnknown inputs = Undefined
  | otherwise = High
evalGate Xnor inputs
  | any isUnknown inputs = Undefined
  | otherwise = invert (foldl' xorKnown Low inputs)
evalGate Not inputs = case inputs of
  input : _ -> invert input
  [] -> Undefined
evalGate Tribuf inputs = case inputs of
  [dataValue, enable] -> tribufValue dataValue enable
  _ -> Undefined

isUnknown :: Logic -> Bool
isUnknown value = value == Undefined || value == TriState

invert :: Logic -> Logic
invert Low = High
invert High = Low
invert Undefined = Undefined
invert TriState = Undefined

tribufValue :: Logic -> Logic -> Logic
tribufValue dataValue enable = case enable of
  Low -> TriState
  High -> case dataValue of
    TriState -> Undefined
    _ -> dataValue
  Undefined -> Undefined
  TriState -> Undefined

xorKnown :: Logic -> Logic -> Logic
xorKnown left right = case (left, right) of
  (Low, Low) -> Low
  (Low, High) -> High
  (High, Low) -> High
  (High, High) -> Low
  _ -> Undefined
