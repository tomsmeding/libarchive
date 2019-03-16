-- | This module contains higher-level functions for working with archives in
-- Haskell. See "Codec.Archive.Foreign" for direct bindings to
-- libarchive.
module Codec.Archive
    ( -- * High-level functionality
      unpackToDir
    , unpackArchive
    , entriesToFile
    , entriesToBS
    , readArchiveFile
    , readArchiveBS
    -- * Concrete (Haskell) types
    , Entry (..)
    , EntryContent (..)
    , Ownership (..)
    , Permissions
    , ModTime
    , Id
    , standardPermissions
    , executablePermissions
    ) where

import           Codec.Archive.Foreign
import           Codec.Archive.Pack
import           Codec.Archive.Types
import           Codec.Archive.Unpack
import           Control.Monad         (void)
import           Data.ByteString       (useAsCStringLen)
import qualified Data.ByteString       as BS
import           Foreign.C.String
import           Foreign.Ptr           (Ptr)

withArchiveRead :: (Ptr Archive -> IO a) -> Ptr Archive -> IO a
withArchiveRead fact a = do
    res <- fact a
    void $ archive_read_free a
    pure res

readArchiveFile :: FilePath -> IO [Entry]
readArchiveFile fp =
    archiveFile fp >>= withArchiveRead hsEntries

readArchiveBS :: BS.ByteString -> IO [Entry]
readArchiveBS bs =
    bsToArchive bs >>= withArchiveRead hsEntries

archiveFile :: FilePath -> IO (Ptr Archive)
archiveFile fp = withCString fp $ \cpath -> do
    a <- archive_read_new
    void $ archive_read_support_format_all a
    void $ archive_read_open_filename a cpath 10240
    pure a

unpackArchive :: FilePath -- ^ Filepath pointing to archive
              -> FilePath -- ^ Filepath to unpack to
              -> IO ()
unpackArchive tarFp dirFp = do
    a <- archiveFile tarFp
    unpackEntriesFp a dirFp
    void $ archive_read_free a

bsToArchive :: BS.ByteString -> IO (Ptr Archive)
bsToArchive bs = do
    a <- archive_read_new
    void $ archive_read_support_format_all a
    useAsCStringLen bs $
        \(charPtr, sz) ->
            void $ archive_read_open_memory a charPtr (fromIntegral sz)
    pure a

unpackToDir :: FilePath -- ^ Directory to unpack in
            -> BS.ByteString -- ^ 'ByteString' containing archive
            -> IO ()
unpackToDir fp bs = do
    a <- bsToArchive bs
    unpackEntriesFp a fp
    void $ archive_read_free a
