module MB.Server
    ( withServing
    )
where

import Prelude hiding (catch)
import Control.Exception (SomeException, finally, catch)
import Control.Concurrent
import Data.List (isPrefixOf)
import System.Directory
import System.Exit
import System.FilePath ((</>))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Network.HTTP
import Network.HTTP.Server
import qualified Network.URL as URL
import Network.Socket (SockAddr)

import System.IO.Temp

import MB.Types

reloadJS :: String
reloadJS =
    "<script type=\"text/javascript\">\n\
    \</script>"

serverProcessor :: Processor
serverProcessor =
    nullProcessor { pageHead = Just reloadJS
                  }

withServing :: StartupConfig
            -> (StartupConfig -> (Blog -> Blog) -> IO ())
            -> IO ()
withServing conf act = do
  (hostname, portNum) <-
      case listenAddr conf of
        Nothing -> putStrLn "BUG: configuration did not provide a listen address!" >> exitFailure
        Just (h, p) -> return (h, p)

  tmpDir <- createTempDirectory "/tmp" "mbhtml.tmp"
  outputDir <- canonicalizePath tmpDir

  -- Set up the temp output directoryy and modify the config and blog.
  let serverConf = conf { htmlOutputDirectory = outputDir }
      url = "http://" ++ hostname ++ ":" ++ show portNum ++ "/"
      blogTrans b =
          b { baseUrl = url
            , processors = processors b ++ [serverProcessor]
            , outputFS = blogOutputFS serverConf
            }

      httpConfig = defaultConfig { srvHost = hostname
                                 , srvPort = portNum
                                 }
      cleanup = removeDirectoryRecursive (htmlOutputDirectory serverConf)

      handleError :: SomeException -> IO ()
      handleError e =
          putStrLn $ "Error running server on " ++ url ++ ": " ++ show e

  putStrLn $ "Web server listening on " ++ url

  -- Start the blog generation thread.
  _ <- forkIO $ (act serverConf blogTrans `catch` handleError)

  serverWith httpConfig (requestHandler outputDir)
                 `catch` handleError
                 `finally` cleanup

requestHandler :: FilePath -> SockAddr -> URL.URL -> Request BS.ByteString -> IO (Response BS.ByteString)
requestHandler docRoot _addr url _req = do
  -- Concatenate the url_path of the URL to the output directory.
  -- Then attempt to canonicalize the result.  If it succeeds and is
  -- not contained within the output directory, return a 404.

  let handleError :: SomeException -> IO (Response BS.ByteString)
      handleError = const $ return (resp404 url)

      mkResponse f = do
        putStrLn $ "Request: /" ++ URL.url_path url
        fileToResponse f

      serveFile path = do
        realPath <- canonicalizePath path
        if not (docRoot `isPrefixOf` realPath) then
            return (resp404 url) else
            do
              -- If the request was for a directory, rewrite it so we
              -- look for index.html instead
              e <- doesFileExist realPath
              if e then
                  mkResponse realPath else
                  serveFile (path </> "index.html")

  serveFile (docRoot </> URL.url_path url) `catch` handleError

resp404 :: URL.URL -> Response BS.ByteString
resp404 url =
    let msg = BSC.pack $ "Not found: " ++ URL.exportURL url
    in (err_response NotFound :: Response BS.ByteString)
           { rspHeaders = [ Header HdrContentType "text/plain"
                          , Header HdrContentLength $ show $ BS.length msg
                          ]
           , rspBody = msg
           }

fileToResponse :: FilePath -> IO (Response BS.ByteString)
fileToResponse f = do
  bytes <- BS.readFile f
  return $ (respond Found :: Response BS.ByteString)
             { rspHeaders = [ Header HdrContentLength $ show $ BS.length bytes
                            , Header HdrCacheControl "no-cache"
                            ]
             , rspBody = bytes
             }
