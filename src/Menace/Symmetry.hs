module Menace.Symmetry
    ( canonicalize,
    applyTransform,
    bestTransform
    ) where

import Menace.Types
import Menace.Board (getCell, setCell, emptyBoardKey)

idx :: Int -> (Int, Int)
idx i = (i `div` 3, i `mod` 3)

unidx :: (Int, Int) -> Int
unidx (r, c) = r*3+c

rot90 :: (Int, Int) -> (Int, Int)
rot90 (r, c) = (c,2-r)

rot180 :: (Int, Int) -> (Int, Int)
rot180 = rot90 . rot90

rot270 :: (Int, Int) -> (Int, Int)
rot270 = rot90 . rot180

refV :: (Int, Int) -> (Int, Int)
refV (r, c) = (r,2-c)

transforms :: [Int -> Int]
transforms = [
    \i -> unidx (idx i),
    \i -> unidx (rot90  (idx i)),
    \i -> unidx (rot180 (idx i)),
    \i -> unidx (rot270 (idx i)),
    \i -> unidx (refV   (idx i)),
    \i -> unidx (rot90  (refV (idx i))),
    \i -> unidx (rot180 (refV (idx i))),
    \i -> unidx (rot270 (refV (idx i)))
    ]

applyTransform :: (Int -> Int) -> BoardKey -> BoardKey
applyTransform f k =
    foldl step emptyBoardKey [0 .. 8]
    where
        step acc i =
            let c = getCell k i
                j = f i
            in setCell acc j c

bestTransform :: BoardKey -> ((Int -> Int), BoardKey)
bestTransform k =
    foldl pick first rest
    where
        candidates = [(f, applyTransform f k) | f <- transforms]
        first = head candidates
        rest = tail candidates
        pick a@(_, ka) b@(_, kb) =
            if kb < ka then b else a

canonicalize :: BoardKey -> (BoardKey, (Int -> Int), (Int -> Int))
canonicalize k =
    let (f, kc) = bestTransform k
        finv = inverse f
    in (kc, f, finv)

inverse :: (Int -> Int) -> (Int -> Int)
inverse f = \j -> head [i | i <- [0 .. 8], f i == j]