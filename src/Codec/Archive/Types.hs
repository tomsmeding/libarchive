{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Codec.Archive.Types ( -- * Abstract data types
                             Archive
                           , ArchiveEntry
                           -- * Concrete (Haskell) data types
                           , Entry (..)
                           , EntryContent (..)
                           -- * Macros
                           , ExtractFlags (..)
                           , ReadResult (..)
                           , ArchiveFilter (..)
                           , FileType (..)
                           ) where

import           Data.Bits          ((.|.))
import qualified Data.ByteString    as BS
import           Data.Semigroup
import           Foreign.C.Types    (CInt)
import           System.Posix.Types (CMode (..))

-- | Abstract type
data Archive

-- | Abstract type
data ArchiveEntry

-- TODO: support everything here: http://hackage.haskell.org/package/tar/docs/Codec-Archive-Tar-Entry.html#t:EntryContent
data EntryContent = NormalFile !BS.ByteString
                  | Directory
                  | SymbolicLink !FilePath
                  | HardLink !FilePath

data Entry = Entry { filepath    :: !FilePath
                   , permissions :: !FileType
                   , content     :: !EntryContent
                   }

newtype FileType = FileType CMode
    deriving (Eq, Num)

-- TODO: make this a sum type
newtype ReadResult = ReadResult CInt
    deriving (Eq, Num)

newtype ExtractFlags = ExtractFlags CInt
    deriving (Eq, Num)

newtype ArchiveFilter = ArchiveFilter CInt
    deriving (Num)

instance Semigroup ExtractFlags where
    (<>) (ExtractFlags x) (ExtractFlags y) = ExtractFlags (x .|. y)

instance Monoid ExtractFlags where
    mempty = 0
    mappend = (<>)
