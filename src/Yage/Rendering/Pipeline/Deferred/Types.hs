{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE TemplateHaskell  #-}

module Yage.Rendering.Pipeline.Deferred.Types
  (
  -- * Primitives for Deferred Shading
    DeferredEntity
  , DeferredSky
  , DeferredEnvironment
  , DeferredScene
  -- * Deferred Context
  , DeferredMonad
  , DeferredSettings(..)
  , HasDeferredSettings(..)
  ) where

import Yage.Prelude hiding (FilePath)
import Yage.Lens
import Yage.Scene
import Yage.Viewport
import Yage.Vertex hiding (Texture)
import Yage.Rendering.Resources.GL
import Yage.Formats.Ygm
import Quine.GL.Types
import Data.Data

import Yage.Rendering.Pipeline.Deferred.BaseGPass (GBaseMaterial)
import Yage.Rendering.Pipeline.Deferred.SkyPass (SkyMaterial)

-- | An Entity suitable for deferred shading
type DeferredEntity      = Entity (RenderData Word32 YGMVertex) (GBaseMaterial Texture2D)
-- | Deferred sky-dome
type DeferredSky         = Entity (RenderData Word32 (Position Vec3)) (SkyMaterial TextureCube)
-- | Container for lights, environment maps and skies for deferred shading
type DeferredEnvironment = Environment Light DeferredSky
-- | Encapsulates entities and the environment for deferred shading
type DeferredScene       = Scene DeferredEntity DeferredEnvironment

-- * Context

data DeferredSettings = DeferredSettings
  { _activeVoxelAmbientOcclusion :: Bool
  -- ^ perform full scene voxelization and cone tracing for ambient occlusion approximation
  , _showDebugOverlay :: Bool
  -- ^ selects a overlay for debug issues (e.g. 3d page mask of the sparse voxelization)
  } deriving (Show,Read,Ord,Eq,Data,Typeable,Generic)

makeClassy ''DeferredSettings

instance Default DeferredSettings where
  def = DeferredSettings
    { _activeVoxelAmbientOcclusion = True
    , _showDebugOverlay = False
    }

-- | The context for a 'RenderSystem' with deferred shading capabilities
type DeferredMonad m env = (MonadResource m, MonadReader env m, HasViewport env Int)

