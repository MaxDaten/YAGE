{-# OPTIONS_GHC -fno-warn-warnings-deprecations #-}
{-# LANGUAGE Arrows                #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE TypeSynonymInstances  #-}
{-# LANGUAGE FlexibleInstances     #-}

module Main where

import Yage hiding ((</>))
import Yage.Wire hiding (unless, when)
import Yage.Lens
import Yage.Material
import Yage.Scene
import Yage.HDR
import Yage.GL
import Yage.Rendering.Pipeline.Deferred
import Yage.Rendering.Pipeline.Deferred.ScreenPass
import Yage.Rendering.Pipeline.Deferred.BaseGPass
import Yage.Formats.Ygm
import Yage.Resources
import System.FilePath
import Yage.Rendering.Resources.GL
import Foreign.Ptr
import Foreign.Storable
import Data.FileEmbed
import Data.Data
import qualified Data.ByteString.Char8 as Char8
import Quine.Monitor
import Quine.GL
import Quine.GL.Attribute
import Quine.GL.Buffer
import Quine.GL.Error
import Quine.GL.Program
import Quine.GL.Shader
import Quine.GL.Sampler
import Quine.GL.Types
import Quine.GL.Uniform
import Quine.GL.Texture hiding (Texture)
import Quine.GL.VertexArray
import Quine.GL.ProgramPipeline
import Yage.Rendering.GL
import Graphics.GL.Ext.EXT.TextureFilterAnisotropic

appConf :: ApplicationConfig
appConf = defaultAppConfig{ logPriority = WARNING }

winSettings :: WindowConfig
winSettings = WindowConfig
  { windowSize = (800, 600)
  , windowHints =
    [ WindowHint'ContextVersionMajor  4
    , WindowHint'ContextVersionMinor  1
    , WindowHint'OpenGLProfile        OpenGLProfile'Core
    , WindowHint'OpenGLForwardCompat  True
    , WindowHint'OpenGLDebugContext   True
    , WindowHint'sRGBCapable          True
    , WindowHint'RefreshRate          60
    ]
  }

data Configuration = Configuration
  { _mainAppConfig      :: ApplicationConfig
  , _mainWindowConfig   :: WindowConfig
  , _mainMonitorOptions :: MonitorOptions
  }

makeLenses ''Configuration

configuration :: Configuration
configuration = Configuration appConf winSettings (MonitorOptions "localhost" 8080 True False)

type GameEntity = DeferredEntity
type GameScene  = DeferredScene

data Game = Game
  { _mainViewport  :: Viewport Int
  , _gameScene     :: GameScene
  , _gameCamera    :: HDRCamera
  , _sceneRenderer :: RenderSystem Game ()
  }
makeLenses ''Game

instance HasCamera Game where
  camera = gameCamera.camera

instance HasEntities Game (Seq GameEntity) where
  entities = gameScene.entities

simScene :: YageWire t () GameScene
simScene = Scene
  <$> fmap singleton (acquireOnce testEntity)
  <*> pure emptyEnvironment

testEntity :: YageResource GameEntity
testEntity = Entity
  <$> (fromMesh =<< meshRes (loadYGM id ("res/sphere.ygm", mkSelection [])))
  <*> gBaseMaterialRes defaultGBaseMaterial
  <*> pure idTransformation

sceneWire :: YageWire t () Game
sceneWire = proc () -> do
  pipeline <- acquireOnce simplePipeline -< ()
  scene    <- simScene -< ()

  returnA -< Game (defaultViewport 800 600) scene (defaultHDRCamera $ def & position .~ V3 0 0 5) pipeline

simplePipeline :: YageResource (RenderSystem Game ())
simplePipeline = do
  -- Convert output linear RGB to SRGB
  throwWithStack $ glEnable GL_FRAMEBUFFER_SRGB
  throwWithStack $
    io (getDir "res/glsl") >>= \ ss -> buildNamedStrings ss ("/res/glsl"</>)

  baseSampler <- mkBaseSampler
  gBasePass   <- drawGBuffers
  screenQuadPass <- drawRectangle


  return $ do
    game <- ask
    screenQuadPass .
      dimap (,game^.camera, game^.mainViewport)
            (\base -> ([(1,baseSampler,base^.aChannel)], game^.mainViewport))
            gBasePass

mkBaseSampler :: YageResource Sampler
mkBaseSampler = throwWithStack $ do
  sampler <- glResource
  samplerParameteri sampler GL_TEXTURE_WRAP_S $= GL_CLAMP_TO_EDGE
  samplerParameteri sampler GL_TEXTURE_WRAP_T $= GL_CLAMP_TO_EDGE
  samplerParameteri sampler GL_TEXTURE_MIN_FILTER $= GL_LINEAR
  samplerParameteri sampler GL_TEXTURE_MAG_FILTER $= GL_LINEAR
  when gl_EXT_texture_filter_anisotropic $
    samplerParameterf sampler GL_TEXTURE_MAX_ANISOTROPY_EXT $= 16
  return sampler

main :: IO ()
main = yageMain "standalone" configuration sceneWire (1/60)

instance HasMonitorOptions Configuration where
  monitorOptions = mainMonitorOptions

instance HasWindowConfig Configuration where
  windowConfig = mainWindowConfig

instance HasApplicationConfig Configuration where
  applicationConfig = mainAppConfig

instance HasViewport Game Int where
  viewport = mainViewport

instance LinearInterpolatable Game where
  lerp _ _ = id

instance HasRenderSystem Game (ResourceT IO) Game () where
  renderSystem = sceneRenderer
