module MB.Gen.Post
    ( generatePosts
    , postTemplateAttrs
    )
where

import Control.Applicative
import Control.Monad
import Data.Maybe
import qualified Data.Map as M
import Data.Time.LocalTime
import Data.Time.Clock
import System.IO
import System.Exit
import Text.StringTemplate
    ( setManyAttrib )

import qualified Text.Pandoc as Pandoc
import MB.Processing
import MB.Types
import MB.Templates
import qualified MB.Files as Files

import MB.Gen.Base

writePost :: Blog -> Handle -> Post -> IO ()
writePost blog h post = do
  let writerOpts = getWriterOptions blog Pandoc.defaultWriterOptions
  hPutStr h $ Pandoc.writeHtmlString writerOpts (postAst post)

buildPost :: Handle -> Blog -> Post -> (Maybe Post, Maybe Post) -> IO ()
buildPost h blog post prevNext = do
  eTmpl <- loadTemplate $ Files.postTemplatePath blog

  case eTmpl of
    Left msg -> putStrLn msg >> exitFailure
    Right tmpl ->
        do
          pAttrs <- postTemplateAttrs blog post
          let tmplWithPostAttrs =
                  setManyAttrib [("post_authors", postAuthors post)] $
                  setManyAttrib [("post", pAttrs)] $
                  setManyAttrib [ ("next_post_url", Files.postUrl <$> (fst prevNext))
                                , ("prev_post_url", Files.postUrl <$> (snd prevNext))
                                ]
                  tmpl

          html <- readFile $ Files.postIntermediateHtml blog post
          let attrs = [ ("post_html", html)
                      ]

          let out = (fillTemplate blog tmplWithPostAttrs attrs)
          buildPage h blog out $ Just $ getRawPostTitle blog post

postTemplateAttrs :: Blog -> Post -> IO (M.Map String String)
postTemplateAttrs blog post = do
  created <- postModificationString post
  let datestr = postDate post <|> Just created
  return $ M.fromList [ ("title", getPostTitle blog post BlogPost)
                      , ("date", fromJust datestr)
                      , ("url", Files.postUrl post)
                      , ("basename", Files.postBaseName post)
                      , ("tex_macros", postTeXMacros post)
                      ]

generatePost :: Blog -> Post -> ChangeSummary -> IO ()
generatePost blog post summary = do
  let finalHtml = Files.postIntermediateHtml blog post
      generate = (postFilename post `elem` (postsChanged summary))
                 || configChanged summary

  when generate $ do
    newPost <- applyPreProcessors blog post

    h <- openFile finalHtml WriteMode
    writePost blog h newPost
    hClose h
    applyPostProcessors blog finalHtml BlogPost

generatePosts :: Blog -> ChangeSummary -> IO ()
generatePosts blog summary = do
  let numRegenerated = if configChanged summary
                       then length $ blogPosts blog
                       else length $ postsChanged summary

  when (numRegenerated > 0) $ putStrLn $ "Rendering " ++ (show numRegenerated) ++ " post" ++
       (if numRegenerated == 1 then "" else "s") ++ ":"

  let n = length posts
      posts = [p | p <- blogPosts blog, postFilename p `elem` postsChanged summary]

  forM_ (zip posts [0..]) $ \(p, i) ->
      do
        putStrLn $ "Rendering post " ++ (show $ i + 1) ++ "/" ++
                     (show numRegenerated) ++ ": " ++ (getPostTitle blog p Index) ++
                     " (" ++ (postFilename p) ++ ")"

        let prevPost = if i == 0 then Nothing else Just (posts !! (i - 1))
            nextPost = if i == n - 1 then Nothing else Just (posts !! (i + 1))

        generatePost blog p summary
        h <- openFile (Files.postFinalHtml blog p) WriteMode
        buildPost h blog p (prevPost, nextPost)
        hClose h

postModificationString :: Post -> IO String
postModificationString p = do
  tz <- getCurrentTimeZone
  localTime <- toLocalTime $ postModificationTime p
  return $ show localTime ++ "  " ++ timeZoneName tz

toLocalTime :: UTCTime -> IO LocalTime
toLocalTime u = do
  tz <- getCurrentTimeZone
  return $ utcToLocalTime tz u