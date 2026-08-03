module Gatework.Logic
  ( GateType (..)
  , Logic (..)
  , evalGate
  , gateArity
  , logicChar
  , parseGateType
  , parseLogic
  ) where

import Data.List (foldl')

data Logic = Low | High
  deriving (Eq, Ord, Read, Show)

data GateType = And | Or | Xor | Not
  deriving (Eq, Ord, Read, Show)

gateArity :: GateType -> Int
gateArity And = 2
gateArity Or = 2
gateArity Xor = 2
gateArity Not = 1

parseGateType :: String -> Maybe GateType
parseGateType value = case value of
  "AND" -> Just And
  "OR" -> Just Or
  "XOR" -> Just Xor
  "NOT" -> Just Not
  _ -> Nothing

parseLogic :: String -> Maybe Logic
parseLogic value = case value of
  "0" -> Just Low
  "1" -> Just High
  _ -> Nothing

logicChar :: Logic -> Char
logicChar Low = '0'
logicChar High = '1'

evalGate :: GateType -> [Logic] -> Logic
evalGate And inputs = if all (== High) inputs then High else Low
evalGate Or inputs = if any (== High) inputs then High else Low
evalGate Xor inputs = foldl' xorLogic Low inputs
evalGate Not inputs = case inputs of
  input : _ -> invert input
  [] -> Low

invert :: Logic -> Logic
invert Low = High
invert High = Low

xorLogic :: Logic -> Logic -> Logic
xorLogic Low Low = Low
xorLogic Low High = High
xorLogic High Low = High
xorLogic High High = Low
