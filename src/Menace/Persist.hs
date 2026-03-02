module Menace.Persist (
    saveMENACE,
    loadMENACE
    ) where

import Menace.Types
import Data.Aeson
    ( ToJSON(..)
    , FromJSON(..)
    , (.=)
    , (.:)
    , object
    , withObject
    , encode
    , eitherDecodeStrict'
    )

import Data.Aeson.Key (fromString)
import qualified Data.ByteString as SBS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.IntMap.Strict as IM

newtype JMatchbox = JMatchbox { unJMatchbox :: [(Int, Int)] } deriving (Eq, Show)

newtype JMenace = JMenace { unJMenace :: [(Int, JMatchbox)] } deriving (Eq, Show)

instance ToJSON JMatchbox where
    toJSON (JMatchbox xs) =
        object [fromString "moves" .= xs]

instance FromJSON JMatchbox where
    parseJSON =
        withObject "JMatchbox" $ \o ->
            JMatchbox <$> (o .: fromString "moves")

instance ToJSON JMenace where
    toJSON (JMenace xs) =
        object
            [ fromString "boxes"
                .= [(k, unJMatchbox mb) | (k, mb) <- xs]
            ]

instance FromJSON JMenace where
    parseJSON =
        withObject "JMenace" $ \o -> do
            xs <- o .: fromString "boxes"
            pure (JMenace [(k, JMatchbox mb) | (k, mb) <- xs])

toJ :: MENACE -> JMenace
toJ men = JMenace [(k, JMatchbox (IM.toList mb)) | (k, mb) <- IM.toList men]

fromJ :: JMenace -> MENACE
fromJ (JMenace xs) = IM.fromList [(k, IM.fromList (unJMatchbox mb)) | (k, mb) <- xs]

saveMENACE :: FilePath -> MENACE -> IO ()
saveMENACE fp men = LBS.writeFile fp (encode (toJ men))

loadMENACE :: FilePath -> IO (Either String MENACE)
loadMENACE fp = do
    bs <- SBS.readFile fp
    case eitherDecodeStrict' bs of
        Left e ->
            pure (Left e)
        Right jm ->
            pure (Right (fromJ jm))