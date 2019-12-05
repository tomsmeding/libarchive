module Codec.Archive.Roundtrip ( itPacksUnpacks
                               , itPacksUnpacksViaFS
                               , roundtrip
                               ) where

import           Codec.Archive
import           Control.Composition        (thread, (.@))
import           Control.Monad.Except       (liftEither)
import           Control.Monad.IO.Class     (liftIO)
import qualified Data.ByteString            as BS
import qualified Data.ByteString.Lazy       as BSL
import           Data.List                  (intersperse, sort)
import           System.Directory           (withCurrentDirectory)
import           System.Directory.Recursive (getDirRecursive)
import           System.IO.Temp             (withSystemTempDirectory)
import           Test.Hspec

newtype TestEntries = TestEntries [Entry]
    deriving (Eq)

instance Show TestEntries where
    showsPrec _ (TestEntries entries) = ("(TestEntries [" ++) . joinBy (", "++) (map showsEntry entries) . ("])" ++) where
        showsEntry entry = ("Entry " ++) .
            ("{filepath=" ++) . shows (filepath entry) .
            (", content=" ++) . showsContent (content entry) .
            (", permissions=" ++) . shows (permissions entry) .
            (", ownership=" ++) . shows (ownership entry) .
            (", time=" ++) . shows (time entry) .
            ("}" ++)
        showsContent (NormalFile bytes) = ("(NormalFile $ " ++) . shows (BS.take 10 bytes) . (" <> undefined)" ++)
        showsContent Directory          = ("Directory" ++)
        showsContent (Symlink target)   = ("(Symlink " ++) . shows target . (')':)
        showsContent (Hardlink target)  = ("(Hardlink " ++) . shows target . (')':)
        joinBy :: ShowS -> [ShowS] -> ShowS
        joinBy sep = thread . intersperse sep

roundtrip :: FilePath -> IO (Either ArchiveResult BSL.ByteString)
roundtrip = fmap (fmap entriesToBSL . readArchiveBSL) . BSL.readFile

itPacksUnpacks :: [Entry] -> Spec
itPacksUnpacks entries = parallel $ it "packs/unpacks successfully without loss" $
    let
        packed = entriesToBSL entries
        unpacked = readArchiveBSL packed
    in
        (TestEntries <$> unpacked) `shouldBe` Right (TestEntries entries)

itPacksUnpacksViaFS :: [Entry] -> Spec
itPacksUnpacksViaFS entries = parallel $ unpackedFromFS $ it "packs/unpacks on filesystem successfully without loss" $ \unpacked ->
        fmap (fmap stripDotSlash . testEntries) unpacked `shouldBe` Right (testEntries entries)

    where

        -- Use this to test content as well
        -- testEntries = TestEntries . sortOn filepath . map (stripOwnership . stripPermissions)
        testEntries = sort . map filepath
        unpackedFromFS = around $ \action ->
            withSystemTempDirectory "spec-" $ \tmpdir -> do
            unpacked <- {- withCurrentDirectory tmpdir . -} runArchiveM $ do
                entriesToDir tmpdir entries
                packed <- liftIO . withCurrentDirectory tmpdir $ do
                    files <- getDirRecursive "."
                    packFiles files
                liftEither $ readArchiveBSL packed

            action unpacked

        stripDotSlash :: FilePath -> FilePath
        stripDotSlash ('.':'/':fp) = fp
        stripDotSlash fp           = fp

-- TODO: expose something like this via archive_write_disk
-- entriesToDir :: Foldable t => FilePath -> t Entry -> ArchiveM ()
entriesToDir :: FilePath -> [Entry] -> ArchiveM ()
entriesToDir = entriesToBSL .@ unpackToDirLazy