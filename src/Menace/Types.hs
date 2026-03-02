module Menace.Types (
    Player(..),
    Cell(..),
    BoardKey,
    Move,
    Weight,
    Matchbox,
    MENACE,
    Outcome(..),
    Config(..)
    ) where

import Data.IntMap.Strict (IntMap)

data Player = PX | PO deriving (Eq, Ord, Show)

data Cell = Empty | X | O deriving (Eq, Ord, Show, Enum, Bounded)

type BoardKey = Int
type Move = Int
type Weight = Int

type Matchbox = IntMap Weight
type MENACE = IntMap Matchbox

data Outcome = WinPX | WinPO | Draw deriving (Eq, Show)

data Config = Config {
    useSymmetry :: Bool,
    initialWeight :: Int,
    winReward :: Int,
    drawReward :: Int,
    lossPenalty :: Int,
    minWeight :: Int,
    games :: Int,
    reportEvery :: Int,
    seed :: Int,
    humanPlays :: Player,
    showWeights :: Bool,
    loadPath :: Maybe FilePath,
    savePath :: Maybe FilePath,
    colorMode :: Bool
    } deriving (Eq, Show)