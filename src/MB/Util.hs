module MB.Util
    ( copyTree
    , toUtcTime
    , toLocalTime
    , pandocTitle
    )
where
import Control.Applicative
    ( (<$>)
    )
import System.Directory
    ( doesDirectoryExist
    , doesFileExist
    , createDirectory
    , getDirectoryContents
    , copyFile
    )
import System.FilePath
    ( (</>)
    , takeFileName
    )
import Control.Monad
    ( when
    , forM_
    , filterM
    )
import System.Exit
    ( exitFailure
    )
import System.Posix.Types
    ( EpochTime
    )
import Data.Time.Clock
    ( UTCTime
    )
import Data.Time.Format
    ( parseTime
    )
import Data.Time.LocalTime
    ( LocalTime
    , getCurrentTimeZone
    , utcToLocalTime
    )
import System.Locale
    ( defaultTimeLocale
    )
import Data.Maybe
    ( fromJust
    )
import qualified Text.Pandoc.Definition as Pandoc

copyTree :: FilePath -> FilePath -> IO ()
copyTree srcPath dstPath = do
  dstFExists <- doesFileExist dstPath
  dstDExists <- doesDirectoryExist dstPath

  when (dstFExists || dstDExists) $ do
    putStrLn $ "Cannot copy " ++ (show srcPath) ++ " to existing destination path " ++
                 (show dstPath) ++ "; remove to continue."
    exitFailure

  createDirectory dstPath
  copyTree' srcPath dstPath

  where
    copyTree' src dst = do
      -- For each file in src, copy it to dest.
      entries <- filter (not . flip elem [".", ".."]) <$> getDirectoryContents src

      dirs <- filterM doesDirectoryExist $ map (src </>) entries
      files <- filterM doesFileExist $ map (src </>) entries

      -- For each directory in src, create it in dest, then descend
      -- into that directory in both src and dest.
      forM_ files $ \f -> copyFile f $ dst </> takeFileName f
      forM_ dirs $ \dir ->
          do
            let dstDir = dst </> dirName
                dirName = takeFileName dir

            createDirectory dstDir
            copyTree' (src </> dirName) dstDir

toUtcTime :: EpochTime -> UTCTime
toUtcTime t = fromJust $ parseTime defaultTimeLocale "%s" $ show t

toLocalTime :: UTCTime -> IO LocalTime
toLocalTime u = do
  tz <- getCurrentTimeZone
  return $ utcToLocalTime tz u

pandocTitle :: Pandoc.Pandoc -> Int -> String
pandocTitle (Pandoc.Pandoc m _) dpi = concat $ map getStr $ Pandoc.docTitle m
    where
      getStr (Pandoc.Str s) = s
      getStr (Pandoc.Math _ s) = "<EQ DPI=\"" ++ show dpi ++ "\">" ++ s ++ "</EQ>"
      getStr Pandoc.Space = " "
      getStr i = error $ "Unexpected inline in document title, got " ++ (show i)