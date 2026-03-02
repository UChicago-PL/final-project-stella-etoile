module Menace.Engine (
    menaceMove,
    playSelf,
    train,
    playHuman,
    summarizeWeights,
    duelMany
    ) where

import Menace.Types
import Menace.Board
import Menace.Symmetry
import System.Random (StdGen, mkStdGen, randomR)
import qualified Data.IntMap.Strict as IM

type History = [(BoardKey, Move, Player)]

keyFor :: Config -> BoardKey -> (BoardKey, Move -> Move, Move -> Move)
keyFor cfg k =
    if useSymmetry cfg
        then
            let (kc, f, finv) = canonicalize k
                toCanon m = f m
                fromCanon m = finv m
            in (kc, toCanon, fromCanon)
        else (k, id, id)

ensureMatchbox :: Config -> BoardKey -> Matchbox
ensureMatchbox cfg k =
    let ms = legalMoves k
    in IM.fromList [(m, initialWeight cfg) | m <- ms]

getMatchbox :: Config -> MENACE -> BoardKey -> Matchbox
getMatchbox cfg men k =
    case IM.lookup k men of
        Just mb -> mb
        Nothing -> ensureMatchbox cfg k

weightedChoice :: StdGen -> [(Move, Weight)] -> (Move, StdGen)
weightedChoice g xs =
    let total = sum (map snd xs)
    in if total <= 0
        then
            let (i, g') = randomR (0, length xs - 1) g
            in (fst (xs !! i), g')
        else
            let (r, g') = randomR (1, total) g
            in (pick r xs, g')
    where
        pick _ [] = error "weightedChoice: empty"
        pick n ((m, w) : rest)
            | n <= w = m
            | otherwise = pick (n - w) rest

normalizeBox :: Config -> BoardKey -> Matchbox -> Matchbox
normalizeBox cfg k mb =
    let mb' = IM.filter (>= minWeight cfg) mb
    in if IM.null mb' then ensureMatchbox cfg k else mb'

menaceMove :: Config -> MENACE -> StdGen -> BoardKey -> (Move, MENACE, StdGen, Maybe String)
menaceMove cfg men g k =
    let (kc, toCanon, fromCanon) = keyFor cfg k
        mb0 = getMatchbox cfg men kc
        ms = legalMoves k
        weightsCanon =
            [ (toCanon m, IM.findWithDefault (initialWeight cfg) (toCanon m) mb0)
            | m <- ms
            ]
        (mCanon, g') = weightedChoice g weightsCanon
        mReal = fromCanon mCanon
        mb1 = IM.union mb0 (IM.fromList [(toCanon m, initialWeight cfg) | m <- ms])
        men' = IM.insert kc (normalizeBox cfg kc mb1) men
        dbg =
            if showWeights cfg
                then Just ("Weights: " <> show weightsCanon <> "  picked=" <> show (mReal + 1))
                else Nothing
    in (mReal, men', g', dbg)

applyMove :: BoardKey -> Player -> Move -> BoardKey
applyMove k p m =
    let c = case p of
                PX -> X
                PO -> O
    in setCell k m c

updateOne :: Config -> Int -> (BoardKey, Move, Player) -> MENACE -> MENACE
updateOne cfg delta (k, m, _) men =
    let (kc, toCanon, _) = keyFor cfg k
        mb0 = getMatchbox cfg men kc
        m' = toCanon m
        w0 = IM.findWithDefault (initialWeight cfg) m' mb0
        w1 = max (minWeight cfg) (w0 + delta)
        mb1 = IM.insert m' w1 mb0
        mb2 = normalizeBox cfg kc mb1
    in IM.insert kc mb2 men

updateHistory :: Config -> Outcome -> History -> MENACE -> MENACE
updateHistory cfg out hist men =
    let deltaFor p =
            case out of
                Draw  -> drawReward cfg
                WinPX -> if p == PX then winReward cfg else negate (lossPenalty cfg)
                WinPO -> if p == PO then winReward cfg else negate (lossPenalty cfg)
        step men' h@(_, _, p) = updateOne cfg (deltaFor p) h men'
    in foldl step men hist

playSelf :: Config -> MENACE -> StdGen -> (Outcome, MENACE, StdGen)
playSelf cfg men g0 = go emptyBoardKey men g0 []
    where
        go k men g hist =
            case outcome k of
                Just out -> (out, updateHistory cfg out hist men, g)
                Nothing ->
                    let p = currentPlayer k
                        (m, men1, g1, _) = menaceMove cfg men g k
                        k1 = applyMove k p m
                        hist1 = hist <> [(k, m, p)]
                    in go k1 men1 g1 hist1

train :: Config -> MENACE -> (MENACE, (Int, Int, Int))
train cfg men0 =
    let g0 = mkStdGen (seed cfg)
        step (men, g, wx, wo, dr) _ =
            let (out, men1, g1) = playSelf cfg men g
                (wx', wo', dr') =
                    case out of
                        WinPX -> (wx + 1, wo, dr)
                        WinPO -> (wx, wo + 1, dr)
                        Draw  -> (wx, wo, dr + 1)
            in (men1, g1, wx', wo', dr')
        (menF, _, wx, wo, dr) = foldl step (men0, g0, 0, 0, 0) [1 .. games cfg]
    in (menF, (wx, wo, dr))

parseMove :: String -> Maybe Int
parseMove s =
    case reads s of
        [(n, "")] | n >= 1 && n <= 9 -> Just (n - 1)
        _ -> Nothing

playHuman :: Config -> MENACE -> IO MENACE
playHuman cfg men0 = loop emptyBoardKey men0 (mkStdGen (seed cfg)) []
    where
        humanP = humanPlays cfg

        loop k men g hist =
            case outcome k of
                Just out -> do
                    putStrLn ""
                    printBoard cfg k
                    putStrLn ""
                    putStrLn ("Result: " <> show out)
                    let men1 = updateHistory cfg out hist men
                    pure men1

                Nothing -> do
                    putStrLn ""
                    printBoard cfg k
                    putStrLn ""
                    let p = currentPlayer k
                    if p == humanP
                        then do
                            putStrLn "Your move (1-9):"
                            s <- getLine
                            case parseMove s of
                                Nothing -> do
                                    putStrLn "Invalid input."
                                    loop k men g hist
                                Just m ->
                                    if getCell k m /= Empty
                                        then do
                                            putStrLn "That square is taken."
                                            loop k men g hist
                                        else do
                                            let k1 = applyMove k p m
                                            loop k1 men g (hist <> [(k, m, p)])
                        else do
                            let (m, men1, g1, dbg) = menaceMove cfg men g k
                            putStrLn ("MENACE plays: " <> show (m + 1))
                            case dbg of
                                Nothing -> pure ()
                                Just t  -> putStrLn t
                            let k1 = applyMove k p m
                            loop k1 men1 g1 (hist <> [(k, m, p)])

summarizeWeights :: Config -> MENACE -> BoardKey -> [(Move, Weight)]
summarizeWeights cfg men k =
    let (kc, toCanon, _) = keyFor cfg k
        mb = getMatchbox cfg men kc
        ms = legalMoves k
    in [(m, IM.findWithDefault (initialWeight cfg) (toCanon m) mb) | m <- ms]

playDuel :: Config -> MENACE -> MENACE -> StdGen -> (Outcome, StdGen)
playDuel cfg menX menO g0 = go emptyBoardKey g0
    where
        go k g =
            case outcome k of
                Just out ->
                    (out, g)
                Nothing ->
                    let p = currentPlayer k
                    in if p == PX
                        then
                            let (m, _, g1, _) = menaceMove cfg menX g k
                                k1 = applyMove k p m
                            in go k1 g1
                        else
                            let (m, _, g1, _) = menaceMove cfg menO g k
                                k1 = applyMove k p m
                            in go k1 g1

duelMany :: Config -> MENACE -> MENACE -> (Int, Int, Int)
duelMany cfg menX menO =
    let g0 = mkStdGen (seed cfg)
        step (g, wx, wo, dr) _ =
            let (out, g1) = playDuel cfg menX menO g
            in case out of
                WinPX -> (g1, wx + 1, wo, dr)
                WinPO -> (g1, wx, wo + 1, dr)
                Draw  -> (g1, wx, wo, dr + 1)
        (_, wx, wo, dr) = foldl step (g0, 0, 0, 0) [1 .. games cfg]
    in (wx, wo, dr)