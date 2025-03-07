{-# LANGUAGE ExistentialQuantification           #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TypeFamilies           #-}
module Yage.Rendering.Resources.GL.Framebuffer
  ( Attachment
  , mkAttachment
  , createFramebuffer
  , attachFramebuffer
  , acquireFramebuffer
  ) where

import           Yage.Prelude hiding (mapM_)
import           Yage.Rendering.GL
import           Yage.Resources

import           Control.Exception
import           Control.Monad (zipWithM_)
import           Data.Foldable
import           Foreign.Marshal.Array

import           Quine.GL.Framebuffer
import           Quine.StateVar
import           Yage.Rendering.Resources.GL.Base
import GHC.Stack

data Attachment = forall a. (FramebufferAttachment a, Show a) => Attachment a
  deriving (Typeable)

deriving instance Show Attachment


-- | creates a 'Framebuffer' from a list of color attachments one optional depth and one optional
-- stencil attachment. The color attachments will be indexed from 'GL_COLOR_ATTACHMENT0' to
-- 'GL_COLOR_ATTACHMENT0' + n all color buffers are enabled for drawing and the first color attachment
-- for reading
createFramebuffer :: [Attachment] -> Maybe Attachment -> Maybe Attachment -> Acquire Framebuffer
createFramebuffer colors mDepth mStencil = throwWithStack $ do
  fb <- glResource :: Acquire Framebuffer
  attachFramebuffer fb colors mDepth mStencil

attachFramebuffer :: MonadIO m => Framebuffer -> [Attachment] -> Maybe Attachment -> Maybe Attachment -> m Framebuffer
attachFramebuffer fb colors mDepth mStencil = throwWithStack $ do
  throwWithStack $ boundFramebuffer RWFramebuffer $= fb
  throwWithStack $ zipWithM_ (\i (Attachment a) -> attach RWFramebuffer (GL_COLOR_ATTACHMENT0 + i) a) [0..] $ colors
  throwWithStack $ mapM_ (\(Attachment a)   -> attach RWFramebuffer GL_DEPTH_ATTACHMENT a) $ mDepth
  throwWithStack $ mapM_ (\(Attachment a)   -> attach RWFramebuffer GL_STENCIL_ATTACHMENT a) $ mStencil
  let cs =  (+) GL_COLOR_ATTACHMENT0 . fromIntegral <$> [0.. (length colors)-1]

  glDrawBuffer GL_NONE
  glReadBuffer GL_NONE
  io $ withArray cs $ \ptr -> do
    glDrawBuffers (fromIntegral $ length colors) ptr
  mapM_ glReadBuffer $ listToMaybe cs
  mErr <- checkFramebufferStatus RWFramebuffer
  case mErr of
    Just err  -> errorWithStackTrace (show err)
    _         -> return fb

acquireFramebuffer :: [Acquire Attachment] -> Maybe (Acquire Attachment) -> Maybe (Acquire Attachment) -> Acquire Framebuffer
acquireFramebuffer colorsA mDepthA mStencilA = throwWithStack $
  join $ liftM3 createFramebuffer (sequence colorsA) (sequence mDepthA) (sequence mStencilA)

-- | wraps an instance of 'FramebufferAttachment' into an 'Attachment' to allow a polymorphic
-- color attachment list
mkAttachment :: (FramebufferAttachment a, Show a) => a -> Attachment
mkAttachment = Attachment
