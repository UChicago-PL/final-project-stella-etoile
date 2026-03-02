module Main where

import Menace.Types
import Menace.Engine
import Menace.Persist
import Options.Applicative
import qualified Data.IntMap.Strict as IM

data Mode = TrainMode | PlayMode | DuelMode deriving (Eq, Show)

data Args = Args {
    mode :: Mode,
    useSym :: Bool,
    initW :: Int,
    winR :: Int,
    drawR :: Int,
    lossP :: Int,
    minW :: Int,
    gamesN :: Int,
    reportN :: Int,
    seedN :: Int,
    humanAs :: String,
    showW :: Bool,
    colorM :: Bool,
    loadF :: Maybe FilePath,
    saveF :: Maybe FilePath,
    xLoadF :: Maybe FilePath,
    oLoadF :: Maybe FilePath
} deriving (Eq, Show)

parseMode :: Parser Mode
parseMode =
    hsubparser (
        command "train" (info (pure TrainMode) (progDesc "Self-play training"))
        <> command "play" (info (pure PlayMode) (progDesc "Human vs MENACE"))
        <> command "duel" (info (pure DuelMode) (progDesc "MENACE vs MENACE (no learning)"))
    )

argsParser :: Parser Args
argsParser =
    Args <$> parseMode
        <*> switch (long "symmetry" <> help "Enable symmetry reduction")
        <*> option auto (long "initial-weight" <> value 3 <> help "Initial beads per legal move")
        <*> option auto (long "win-reward" <> value 3 <> help "Beads added on win")
        <*> option auto (long "draw-reward" <> value 1 <> help "Beads added on draw")
        <*> option auto (long "loss-penalty" <> value 1 <> help "Beads removed on loss")
        <*> option auto (long "min-weight" <> value 1 <> help "Minimum beads per move")
        <*> option auto (long "games" <> value 5000 <> help "Training games (train) / number of games (duel)")
        <*> option auto (long "report-every" <> value 1000 <> help "Print stats every N games (train only; currently summary at end)")
        <*> option auto (long "seed" <> value 1 <> help "Random seed")
        <*> strOption (long "human" <> value "X" <> help "Human plays X or O (play mode)")
        <*> switch (long "show-weights" <> help "Show bead weights during play")
        <*> switch (long "color" <> help "Colorize X and O (colourblind-friendly)")
        <*> optional (strOption (long "load" <> metavar "FILE" <> help "Load MENACE JSON (train/play)"))
        <*> optional (strOption (long "save" <> metavar "FILE" <> help "Save MENACE JSON (train/play)"))
        <*> optional (strOption (long "x-load" <> metavar "FILE" <> help "Load MENACE JSON for X (duel)"))
        <*> optional (strOption (long "o-load" <> metavar "FILE" <> help "Load MENACE JSON for O (duel)"))

toPlayer :: String -> Player
toPlayer s = case s of
        "X" -> PX
        "x" -> PX
        "O" -> PO
        "o" -> PO
        _   -> PX

toConfig :: Args -> Config
toConfig a =
    Config {
        useSymmetry   = useSym a,
        initialWeight = initW a,
        winReward     = winR a,
        drawReward    = drawR a,
        lossPenalty   = lossP a,
        minWeight     = minW a,
        games         = gamesN a,
        reportEvery   = reportN a,
        seed          = seedN a,
        humanPlays    = toPlayer (humanAs a),
        showWeights   = showW a,
        loadPath      = loadF a,
        savePath      = saveF a,
        colorMode     = colorM a
    }

loadOrEmpty :: Maybe FilePath -> IO MENACE
loadOrEmpty Nothing = pure IM.empty
loadOrEmpty (Just fp) = do
    e <- loadMENACE fp
    case e of
        Left err -> do
            putStrLn ("Failed to load, starting empty: " <> err)
            pure IM.empty
        Right men -> do
            putStrLn ("Loaded MENACE from " <> fp)
            pure men

loadOrFail :: String -> Maybe FilePath -> IO MENACE
loadOrFail label mfp =
    case mfp of
        Nothing -> do
            putStrLn ("Missing required file: " <> label)
            pure IM.empty
        Just fp -> do
            e <- loadMENACE fp
            case e of
                Left err -> do
                    putStrLn ("Failed to load " <> label <> ": " <> err)
                    pure IM.empty
                Right men -> do
                    putStrLn ("Loaded " <> label <> " from " <> fp)
                    pure men

maybeSave :: Maybe FilePath -> MENACE -> IO ()
maybeSave Nothing _ = pure ()
maybeSave (Just fp) men = do
    saveMENACE fp men
    putStrLn ("Saved MENACE to " <> fp)

main :: IO ()
main = do
    a <- execParser (info (argsParser <**> helper) fullDesc)
    let cfg = toConfig a
    case mode a of
        TrainMode -> do
            men0 <- loadOrEmpty (loadPath cfg)
            let (menF, (wx, wo, dr)) = train cfg men0
            putStrLn ("Training complete. X wins=" <> show wx <> " O wins=" <> show wo <> " draws=" <> show dr)
            maybeSave (savePath cfg) menF

        PlayMode -> do
            men0 <- loadOrEmpty (loadPath cfg)
            menF <- playHuman cfg men0
            maybeSave (savePath cfg) menF

        DuelMode -> do
            menX <- loadOrFail "X model (--x-load)" (xLoadF a)
            menO <- loadOrFail "O model (--o-load)" (oLoadF a)
            let (wx, wo, dr) = duelMany cfg menX menO
            putStrLn ("Duel complete. X wins=" <> show wx <> " O wins=" <> show wo <> " draws=" <> show dr)