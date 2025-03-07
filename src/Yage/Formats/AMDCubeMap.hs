module Yage.Formats.AMDCubeMap where

import               Yage.Prelude                       hiding ( toList, left, right )
import               Yage.Rendering.GL

import               System.Directory
import               Data.List                          ( (!!) )
import               Data.Foldable                      ( toList )
import               GHC.Exts                           ( groupWith )
import               Text.Regex.Posix
import               Text.Read

import               Yage.Resources

data LoadCubeMapException = LoadCubeMapException String deriving ( Show, Typeable )
instance Exception LoadCubeMapException

type GLFaceTarget = GLenum
data CubeMapSelection = CubeMapSelection
    { selectionDirectory       :: FilePath
    , selectionFiles           :: FilePath -> Bool
    , selectionLevelAndSide    :: FilePath -> (Int, GLFaceTarget)
    -- ^ a projection from FilePath to mipmap level and cube face
    }

amdSeperateFiles :: FilePath -> Text -> CubeMapSelection
amdSeperateFiles dir ext = CubeMapSelection
    { selectionDirectory     = dir
    , selectionFiles         = matchFiles
    , selectionLevelAndSide  = matchLevelAndSide
    }
    where
    matchFiles f = (fpToString f) =~ ("^[[:alnum:]]*_m[[:digit:]]{1,2}_c[[:digit:]]{1,2}\\." ++unpack ext++"$")
    matchLevelAndSide f =
        let sub :: String
            sub = (fpToString f) =~ (asString "_m[[:digit:]]{1,2}_c[[:digit:]]{1,2}\\.")
            nums :: [Int]
            nums = (concatMap . map) read (sub =~ (asString "[[:digit:]]{1,2}") :: [[String]])
        in (nums!!0, toCubeSide $ nums !! 1)
    toCubeSide i = toList glFaceTargets !! i


singleCubemapMipFiles :: MonadIO m => CubeMapSelection -> m (MipmapChain (Cubemap FilePath))
singleCubemapMipFiles CubeMapSelection{..} = do
  selectedFiles <- io $ filter selectionFiles . map fromString <$> getDirectoryContents (fpToString selectionDirectory)

  let mipmaps   = groupWith (fst.selectionLevelAndSide) selectedFiles
      cubes     = map (cubeFromList.sortWith (snd.selectionLevelAndSide)) $ mipmaps
      mMipCubes :: Maybe (MipmapChain (Cubemap FilePath))
      mMipCubes = mipMapChain $ map (fmap (mappend selectionDirectory)) cubes

  case mMipCubes of
    Nothing -> io $ throwIO $ LoadCubeMapException $ "at least one complete cube map with base texture for MipMapChain required!"
    Just mipCubes  -> return $ mipCubes
  where
  cubeFromList [right,left,top,bottom,front,back] = Cubemap right left top bottom front back
  cubeFromList _ = error "singleCubemapMipFiles: invalid pattern"

