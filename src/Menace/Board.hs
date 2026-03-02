module Menace.Board (
    emptyBoardKey,
    getCell,
    setCell,
    legalMoves,
    currentPlayer,
    winner,
    outcome,
    renderBoard,
    renderBoardWith,
    printBoard
    ) where

import Menace.Types
import Data.List (intercalate)
import System.Console.ANSI (
    SGR(SetRGBColor, Reset),
    ConsoleLayer(Foreground),
    setSGRCode
    )
import Data.Colour.SRGB (sRGB24)

emptyBoardKey :: BoardKey
emptyBoardKey = 0

pow3 :: Int -> Int
pow3 n = 3 ^ n

digitAt :: BoardKey -> Int -> Int
digitAt k i = (k `div` pow3 i) `mod` 3

cellFromDigit :: Int -> Cell
cellFromDigit d = case d of
    0 -> Empty
    1 -> X
    _ -> O

digitFromCell :: Cell -> Int
digitFromCell c = case c of
    Empty -> 0
    X     -> 1
    O     -> 2

getCell :: BoardKey -> Int -> Cell
getCell k i = cellFromDigit (digitAt k i)

setCell :: BoardKey -> Int -> Cell -> BoardKey
setCell k i c =
    let old = digitAt k i
        delta = (digitFromCell c - old) * pow3 i
    in k + delta

countCells :: BoardKey -> (Int, Int)
countCells k = go 0 0 0
    where
        go i cx co
            | i >= 9 = (cx, co)
            | otherwise =
                case getCell k i of
                    X     -> go (i + 1) (cx + 1) co
                    O     -> go (i + 1) cx (co + 1)
                    Empty -> go (i + 1) cx co

currentPlayer :: BoardKey -> Player
currentPlayer k =
    let (cx, co) = countCells k
    in if cx <= co then PX else PO

legalMoves :: BoardKey -> [Move]
legalMoves k = [i | i <- [0..8], getCell k i == Empty]

lines3 :: [[Int]]
lines3 = [
    [0,1,2],[3,4,5],[6,7,8],
    [0,3,6],[1,4,7],[2,5,8],
    [0,4,8],[2,4,6]
    ]

winner :: BoardKey -> Maybe Player
winner k = go lines3
    where
        toP c = case c of
            X -> Just PX
            O -> Just PO
            _ -> Nothing

        same3 a b c = a == b && b == c && a /= Empty

        go [] = Nothing
        go (ln:rest) =
            let [i,j,l] = ln
                a = getCell k i
                b = getCell k j
                c = getCell k l
            in if same3 a b c then toP a else go rest

outcome :: BoardKey -> Maybe Outcome
outcome k =
    case winner k of
        Just PX -> Just WinPX
        Just PO -> Just WinPO
        Nothing ->
            if null (legalMoves k) then Just Draw else Nothing

renderBoard :: BoardKey -> String
renderBoard k =
    let showC i = case getCell k i of
                Empty -> show (i + 1)
                X     -> "X"
                O     -> "O"
        row a b c = " " <> showC a <> " | " <> showC b <> " | " <> showC c <> " "
        sep = "\n---+---+---\n"
    in intercalate sep [row 0 1 2, row 3 4 5, row 6 7 8]

renderBoardWith :: Config -> BoardKey -> String
renderBoardWith cfg k =
    let blueX   = setSGRCode [SetRGBColor Foreground (sRGB24 0 114 178)]
        orangeO = setSGRCode [SetRGBColor Foreground (sRGB24 230 159 0)]
        resetC  = setSGRCode [Reset]

        showC i = case getCell k i of
                Empty -> show (i + 1)
                X     -> if colorMode cfg then blueX <> "X" <> resetC else "X"
                O     -> if colorMode cfg then orangeO <> "O" <> resetC else "O"

        row a b c = " " <> showC a <> " | " <> showC b <> " | " <> showC c <> " "
        sep = "\n---+---+---\n"
    in intercalate sep [row 0 1 2, row 3 4 5, row 6 7 8]

printBoard :: Config -> BoardKey -> IO ()
printBoard cfg k = putStrLn (renderBoardWith cfg k)