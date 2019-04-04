module Codec.Archive.Unpack ( hsEntries
                            , unpackEntriesFp
                            , unpackArchive
                            , readArchiveFile
                            , readArchiveBS
                            , unpackToDir
                            ) where

import           Codec.Archive.Common
import           Codec.Archive.Foreign
import           Codec.Archive.Monad
import           Codec.Archive.Types
import           Control.Monad          (void, (<=<))
import           Control.Monad.IO.Class (MonadIO (..))
import           Data.ByteString        (useAsCStringLen)
import qualified Data.ByteString        as BS
import           Foreign.C.String
import           Foreign.Marshal.Alloc  (alloca, allocaBytes)
import           Foreign.Ptr            (Ptr)
import           Foreign.Storable       (Storable (..))
import           System.FilePath        ((</>))
import           System.IO.Unsafe       (unsafePerformIO)

-- | Read an archive contained in a 'BS.ByteString'. The format of the archive is
-- automatically detected.
--
-- @since 1.0.0.0
readArchiveBS :: BS.ByteString -> Either ArchiveResult [Entry]
readArchiveBS = unsafePerformIO . runArchiveM . (actFree hsEntries <=< bsToArchive)
{-# NOINLINE readArchiveBS #-}

bsToArchive :: BS.ByteString -> ArchiveM (Ptr Archive)
bsToArchive bs = do
    a <- liftIO archive_read_new
    ignore $ archive_read_support_format_all a
    useAsCStringLenArchiveM bs $
        \(buf, sz) ->
            handle $ archiveReadOpenMemory a buf (fromIntegral sz)
    pure a

-- | Read an archive from a file. The format of the archive is automatically
-- detected.
--
-- @since 1.0.0.0
readArchiveFile :: FilePath -> ArchiveM [Entry]
readArchiveFile = actFree hsEntries <=< archiveFile

archiveFile :: FilePath -> ArchiveM (Ptr Archive)
archiveFile fp = withCStringArchiveM fp $ \cpath -> do
    a <- liftIO archive_read_new
    ignore $ archive_read_support_format_all a
    handle $ archiveReadOpenFilename a cpath 10240
    pure a

-- | This is more efficient than
--
-- @
-- unpackToDir "llvm" =<< BS.readFile "llvm.tar"
-- @
unpackArchive :: FilePath -- ^ Filepath pointing to archive
              -> FilePath -- ^ Dirctory to unpack in
              -> ArchiveM ()
unpackArchive tarFp dirFp = do
    a <- archiveFile tarFp
    unpackEntriesFp a dirFp
    ignore $ archive_read_free a

readEntry :: Ptr Archive -> Ptr ArchiveEntry -> IO Entry
readEntry a entry =
    Entry
        <$> (peekCString =<< archive_entry_pathname entry)
        <*> readContents a entry
        <*> archive_entry_perm entry
        <*> readOwnership entry
        <*> readTimes entry

-- | Yield the next entry in an archive
getHsEntry :: MonadIO m => Ptr Archive -> m (Maybe Entry)
getHsEntry a = do
    entry <- liftIO $ getEntry a
    case entry of
        Nothing -> pure Nothing
        Just x  -> Just <$> liftIO (readEntry a x)

-- | Return a list of 'Entry's.
hsEntries :: MonadIO m => Ptr Archive -> m [Entry]
hsEntries a = do
    next <- getHsEntry a
    case next of
        Nothing -> pure []
        Just x  -> (x:) <$> hsEntries a

-- | Unpack an archive in a given directory
unpackEntriesFp :: Ptr Archive -> FilePath -> ArchiveM ()
unpackEntriesFp a fp = do
    res <- liftIO $ getEntry a
    case res of
        Nothing -> pure ()
        Just x  -> do
            preFile <- liftIO $ archive_entry_pathname x
            file <- liftIO $ peekCString preFile
            let file' = fp </> file
            liftIO $ withCString file' $ \fileC ->
                archive_entry_set_pathname x fileC
            void $ liftIO $ archive_read_extract a x archiveExtractTime
            liftIO $ archive_entry_set_pathname x preFile
            void $ liftIO $ archive_read_data_skip a
            unpackEntriesFp a fp

readBS :: Ptr Archive -> Int -> IO BS.ByteString
readBS a sz =
    allocaBytes sz $ \buff ->
        archive_read_data a buff (fromIntegral sz) *>
        BS.packCStringLen (buff, sz)

readContents :: Ptr Archive -> Ptr ArchiveEntry -> IO EntryContent
readContents a entry = go =<< archive_entry_filetype entry
    where go ft | ft == regular = NormalFile <$> (readBS a =<< sz)
                | ft == symlink = Symlink <$> (peekCString =<< archive_entry_symlink entry)
                | ft == directory = pure Directory
                | otherwise = error "Unsupported filetype"
          sz = fromIntegral <$> archive_entry_size entry

readOwnership :: Ptr ArchiveEntry -> IO Ownership
readOwnership entry =
    Ownership
        <$> (peekCString =<< archive_entry_uname entry)
        <*> (peekCString =<< archive_entry_gname entry)
        <*> archive_entry_uid entry
        <*> archive_entry_gid entry

readTimes :: Ptr ArchiveEntry -> IO ModTime
readTimes entry =
    (,) <$> archive_entry_mtime entry <*> archive_entry_mtime_nsec entry

-- | Get the next 'ArchiveEntry' in an 'Archive'
getEntry :: Ptr Archive -> IO (Maybe (Ptr ArchiveEntry))
getEntry a = alloca $ \ptr -> do
    let done ArchiveOk    = False
        done ArchiveRetry = False
        done _            = True
    stop <- done <$> archiveReadNextHeader a ptr
    if stop
        then pure Nothing
        else Just <$> peek ptr

unpackToDir :: FilePath -- ^ Directory to unpack in
            -> BS.ByteString -- ^ 'BS.ByteString' containing archive
            -> ArchiveM ()
unpackToDir fp bs = do
    a <- bsToArchive bs
    unpackEntriesFp a fp
    void $ liftIO $ archive_free a
