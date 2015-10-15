{-# LANGUAGE OverloadedStrings #-}

module Compile where

import Control.Monad
import System.Directory (createDirectoryIfMissing)
import System.FilePath (dropExtension, splitFileName)
import System.Posix.Types (EpochTime)
import System.Posix.Files
import Data.List (isSuffixOf)

import Prelude hiding (readFile, writeFile)
import Data.Text (Text, unpack)
import Data.Text.IO (readFile, writeFile)
import System.IO.Error

import CMark

import Parser
import RecursiveContents

stSRCDIR :: FilePath
stSRCDIR = "data"

stDSTDIR :: FilePath
stDSTDIR = "output"

stTPL_PATH :: FilePath
stTPL_PATH = "tpl/"

compile :: IO ()
compile = do
    (mainTpl, mainTplMTime) <- getTemplate (stTPL_PATH ++ "main.html")
    files <- getRecursiveContents stSRCDIR
    forM_ files $ \ path -> if not (isMd path) then return () else do
        let
            commonPath = dropExtension $ drop (length stSRCDIR) path
            dir = fst $ splitFileName commonPath
            targetPath = stDSTDIR ++ commonPath ++ ".html"
        mtime <- getMTime path
        fullText <- readFile path
        (headers, content) <- maybeAct (source fullText) $ do
            print path
            error "source file header parsing failed"
        checkPublicity headers $ do
            (tpl, tplMTime) <- case (lookup "template" headers) of
                Nothing -> return (mainTpl, mainTplMTime)
                Just v -> getTemplate (stTPL_PATH ++ unpack v)
            let
                maxMTime = max mtime tplMTime
                doTheCopy = do
                    createDirectoryIfMissing True $ stDSTDIR ++ dir
                    writeOut maxMTime
                        targetPath tpl headers content
            targetMTime <- tryIOError $ getMTime targetPath
            case targetMTime of
                Left _ -> doTheCopy
                Right t ->  if t < maxMTime then doTheCopy else return ()
  where
    checkPublicity headers action = case lookup "publicity" headers of
        Nothing -> action
        Just v -> if v == "hidden" then return () else action
    isMd path = (".md" :: FilePath) `isSuffixOf` path
    maybeAct m a = maybe a return m

getTemplate :: FilePath -> IO ([Template], EpochTime)
getTemplate path = do
    tpl <- fmap template $ readFile path
    mtime <- getMTime path
    return (tpl, mtime)

writeOut
    :: EpochTime -> FilePath -> [Template] -> [(Text, Text)]
    -> Text
    -> IO ()
writeOut mtime path tpl headers content = do
    putStrLn path
    writeFile path $ mconcat $ map segConvert tpl
    setFileTimes path mtime mtime
  where
    segConvert seg = case seg of
        TextSegment t -> t
        Variable var -> if var == "content"
            then commonmarkToHtml [optSmart] content
            else maybe (noSuchHeader var) id (lookup var headers)
    noSuchHeader var = error $ "var " ++ show var ++ " not found in headers"

getMTime :: FilePath -> IO EpochTime
getMTime = fmap modificationTime . getFileStatus
