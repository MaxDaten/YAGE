{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# LANGUAGE TemplateHaskell        #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FunctionalDependencies #-}
module Yage.Viewport
  ( Viewport(..), HasViewport(..)
  , defaultViewport
  , globalViewport
  , viewportIndexed
  , projectionMatrix3D
  , orthographicMatrix
  , module Rectangle
  ) where

import Yage.Prelude
import Yage.Math
import qualified Yage.Rendering.GL as GL
import Yage.Lens
import Data.Data
import Foreign.Marshal.Array
import Quine.StateVar
import Yage.Geometry.D2.Rectangle as Rectangle

data Viewport a = Viewport
  { _viewportRectangle   :: !(Rectangle a)
    -- with top/left and width/height (gl convention)
  , _viewportPixelRatio  :: !(V2 Double)
  -- ^ usually 1:1, on retina displays 2:2
  , _viewportGamma       :: !Float
  -- ^ usually 2.2
  } deriving (Show,Eq,Functor,Data,Typeable,Generic)

makeClassy ''Viewport

instance HasRectangle (Viewport Int) Int where
    rectangle = viewportRectangle
    {-# INLINE rectangle #-}

-- | Creates a 'Viewport' from width and height with default 'Gamma'=2.2 and
-- a 'pixel ratio' of 1
defaultViewport :: Num a => a -> a -> Viewport a
defaultViewport w h = Viewport (Rectangle 0 (V2 w h)) 1 2.2

-- | Access to the unique global opengl viewport. setting it is equivalent to 'glViewport x y w h'
globalViewport :: StateVar (Rectangle Int)
globalViewport = StateVar g s where
  g = do
    [x,y,w,h] <- fmap fromIntegral <$> (allocaArray 4 $ \ptr -> GL.glGetIntegerv GL.GL_VIEWPORT ptr >> peekArray 4 ptr)
    return $ Rectangle (V2 x y) (V2 w h)
  s (Rectangle (V2 x y) (V2 w h)) = GL.glViewport (fromIntegral x) (fromIntegral y) (fromIntegral w) (fromIntegral h)


-- | Access to the indexed opengl viewport. Usefull for a geometry shader to emmit primitives to specific viewports.
viewportIndexed :: Int -> StateVar (Rectangle Float)
viewportIndexed idx = StateVar g s where
  g = do
    [x,y,w,h] <- fmap fromIntegral <$> (allocaArray 4 $ \ptr -> GL.glGetIntegeri_v GL.GL_VIEWPORT (fromIntegral idx) ptr >> peekArray 4 ptr)
    return $ Rectangle (V2 x y) (V2 w h)
  s (Rectangle (V2 x y) (V2 w h)) = GL.glViewportIndexedf (fromIntegral idx) (realToFrac x) (realToFrac y) (realToFrac w) (realToFrac h)


-- | creates the projectiom matrix for the given viewport
-- for Camera2D: create an orthographic matrix with origin at the
-- top left corner of the screen
-- for Camera3D: creates a perspective projection matrix
projectionMatrix3D :: (Conjugate a, Epsilon a, RealFloat a) => a -> a -> a -> Rectangle a -> M44 a
projectionMatrix3D zNear zFar fov (Rectangle _ wh) =
  perspective
    ( realToFrac fov )
    ( wh^._x / wh^._y )
    ( realToFrac $ zNear )
    ( realToFrac $ zFar )

-- | glOrtho convention
orthographicMatrix :: (Conjugate a, Epsilon a, RealFloat a)
                   => a -> a -> a -> a -> a -> a -> M44 a
orthographicMatrix l r b t n f =
    V4 ( V4 (2/(r-l)) 0        0             (-(r+l)/(r-l)) )
       ( V4 0        (2/(t-b)) 0             (-(t+b)/(t-b)) )
       ( V4 0        0         ((-2)/(f-n))  (-(f+n)/(f-n)) )
       ( V4 0        0         0             1              )

