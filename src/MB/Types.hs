module MB.Types
    ( Config(..)
    , Post(..)
    )
where
import Data.Time.Clock
    ( UTCTime
    )
import qualified Text.Pandoc.Definition as Pandoc

data Config = Config { baseDir :: FilePath
                     , postSourceDir :: FilePath
                     , htmlDir :: FilePath
                     , stylesheetDir :: FilePath
                     , postHtmlDir :: FilePath
                     , postIntermediateDir :: FilePath
                     , imageDir :: FilePath
                     , templateDir :: FilePath
                     , htmlTempDir :: FilePath
                     , baseUrl :: String
                     }

data Post = Post { postTitle :: Int -> String
                 , postTitleRaw :: String
                 , postFilename :: String
                 , postModificationTime :: UTCTime
                 , postAst :: Pandoc.Pandoc
                 }