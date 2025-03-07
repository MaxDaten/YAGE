{-# OPTIONS_GHC -fno-warn-name-shadowing -fno-warn-orphans -fno-warn-type-defaults #-}
{-# LANGUAGE CPP                  #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE NamedFieldPuns       #-}
{-# LANGUAGE RecordWildCards      #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE TupleSections        #-}

module Yage.Rendering.Pipeline.Deferred.LightPass
  ( LightBuffer
  , Lights(..)
  , lightPass
  ) where

import Yage.Prelude hiding (forM_)
import Yage.Lens
import Yage.Math hiding (lookAt)
import Yage.GL

import Data.Foldable (forM_)
import Foreign.Ptr (nullPtr)

import Yage.Uniform as U
import Yage.Camera
import Yage.Light
import Yage.Viewport as VP
import Yage.Scene
import Yage.Transformation
import qualified Yage.Vertex as V
import Yage.Attribute
import Yage.Geometry3D

import Yage.Rendering.GL
import Yage.Rendering.Resources.GL
import Yage.Rendering.RenderSystem
import Yage.Rendering.RenderTarget

import Yage.Rendering.Pipeline.Deferred.BaseGPass
import Yage.Rendering.Pipeline.Deferred.Common

import Quine.GL.Uniform
import Quine.GL.Attribute hiding (normalize)
import Quine.GL.Program
import Quine.GL.Buffer
import Quine.GL.VertexArray
import Quine.StateVar
import Quine.GL.ProgramPipeline


#include "definitions.h"
#include "textureUnits.h"
#include "attributes.h"


-- | Uniform StateVars of the fragment shader
data FragmentShader = FragmentShader
  { gBuffer              :: UniformVar GBuffer
  , cameraPosition       :: UniformVar Vec3
  , zProjectionRatio     :: UniformVar Vec2
  , viewToWorld          :: UniformVar Mat4
  , fragLight            :: UniformVar Light
  }

-- | Uniform StateVars of the fragment shader
data VertexShader = VertexShader
  { vPosition            :: VertexAttribute
  , viewMatrix           :: UniformVar Mat4
  , vpMatrix             :: UniformVar Mat4
  , modelMatrix          :: UniformVar Mat4
  , viewToScreenMatrix   :: UniformVar Mat4
  , vertLight            :: UniformVar Light
  }

data PassRes = PassRes
  { vao         :: !VertexArray
  , pipe        :: !Pipeline
  , frag        :: !FragmentShader
  , vert        :: !VertexShader
  , lightsData  :: !(Lights LightData)
  }

type LightData      = RenderData Word32 (V.Position Vec3)
type LightBuffer    = Texture2D PixelRGB11_11_10F
type LightPassInput = (RenderTarget LightBuffer, Lights (Seq Light), Camera, GBuffer)
type LightPass m g  = PassGEnv g PassRes m LightPassInput LightBuffer

lightPass :: (MonadIO m, MonadThrow m, HasViewport g Int) => YageResource (LightPass m g)
lightPass = PassGEnv <$> passRes <*> pure runPass where
  passRes :: YageResource PassRes
  passRes = do
    vao <- glResource
    boundVertexArray $= vao

    pipeline <- [ $(embedShaderFile "res/glsl/pass/light.vert")
                , $(embedShaderFile "res/glsl/pass/light.frag")]
                `compileShaderPipeline` includePaths

    Just frag <- traverse fragmentUniforms =<< get (fragmentShader $ pipeline^.pipelineProgram)
    Just vert <- traverse vertexUniforms =<< get (vertexShader $ pipeline^.pipelineProgram)

    [pointData, spotData, dirData] <- mapM fromMesh [pointMesh, spotMesh, dirMesh]
    return $ PassRes vao pipeline frag vert (Lights pointData spotData dirData)

  runPass :: (MonadIO m, MonadThrow m, MonadReader (PassEnv g PassRes) m, HasViewport g Int) => RenderSystem m LightPassInput LightBuffer
  runPass = mkStaticRenderPass $ \(target, lights, cam, gBuffer) -> do
    PassRes{..} <- view localEnv
    boundFramebuffer RWFramebuffer $= (target^.framebufferObj)

    -- some state setting
    -- we dont want to write to the depth buffer
    -- glEnable GL_DEPTH_TEST
    --glColorMask GL_TRUE GL_TRUE GL_TRUE GL_TRUE
    glDisable GL_DEPTH_TEST
    glEnable GL_BLEND
    glBlendEquation GL_FUNC_ADD
    glBlendFunc GL_ONE GL_ONE
    glEnable GL_CULL_FACE
    glCullFace GL_FRONT
    glDepthMask GL_FALSE
    glDepthFunc GL_ALWAYS
    glFrontFace GL_CCW
    glCullFace GL_BACK

    VP.globalViewport $= target^.asRectangle
    glColorMask GL_TRUE GL_TRUE GL_TRUE GL_TRUE
    glClearColor 0 0 0 1
    glClear GL_COLOR_BUFFER_BIT

    -- set globals
    {-# SCC boundVertexArray #-} throwWithStack $ boundVertexArray $= vao
    boundProgramPipeline $= pipe^.pipelineProgram
    checkPipelineError pipe

    setupSceneGlobals vert frag cam gBuffer
    drawLightEntities vert frag lightsData lights
    return $ target^.renderTarget


setupSceneGlobals :: (MonadReader (PassEnv g l) m, HasViewport g Int, MonadIO m) => VertexShader -> FragmentShader -> Camera -> GBuffer -> m ()
setupSceneGlobals VertexShader{..} FragmentShader{..} cam@Camera{..} gbuff = do
  vp <- view $ globalEnv.viewport
  let Rectangle xy0 xy1 = fromIntegral <$> vp^.rectangle

  viewToScreenMatrix  $= orthographicMatrix (xy0^._x) (xy1^._x) (xy1^._y) (xy0^._y) 0.0 1.0
  vpMatrix            $= fmap realToFrac <$> viewprojectionM vp
  viewMatrix          $= fmap realToFrac <$> (cam^.cameraMatrix)
  zProjectionRatio    $= zRatio
  gBuffer             $= gbuff
  cameraPosition      $= realToFrac <$> cam^.position
  viewToWorld         $= fmap realToFrac <$> (cam^.inverseCameraMatrix)
 where
  viewprojectionM :: Viewport Int -> M44 Double
  viewprojectionM vp = projectionMatrix3D _cameraNearZ _cameraFarZ _cameraFovy (fromIntegral <$> vp^.rectangle) !*! (cam^.cameraMatrix)
  zRatio = realToFrac <$> V2 ((_cameraFarZ + _cameraNearZ) / (_cameraFarZ + _cameraNearZ)) (( 2.0 * _cameraNearZ * _cameraFarZ ) / ( _cameraFarZ - _cameraNearZ ))


-- | subject for instanced rendering
drawLightEntities :: MonadIO m => VertexShader -> FragmentShader -> Lights LightData -> Lights (Seq Light)-> m ()
drawLightEntities
 VertexShader{..}
 FragmentShader{..}
 Lights{_lightsPoint=pointData,_lightsSpot=spotData,_lightsDir=dirData}
 Lights{_lightsPoint=points,_lightsSpot=spots,_lightsDir=directionals} =
  forM_ [(points,pointData), (spots,spotData), (directionals,dirData)] $ \(lights,dats) -> do
    boundBufferAt ElementArrayBuffer $= dats^.indexBuffer
    boundBufferAt ArrayBuffer $= dats^.vertexBuffer
    vPosition $= Just ((Proxy :: Proxy (V.Position Vec3))^.V.positionlayout)

    forM_ lights $ \light -> do
      -- set shader
      modelMatrix $= (fmap realToFrac <$> (light^.transformation.transformationMatrix))
      vertLight $= light
      fragLight $= light
      -- render data (subject for instanced rendering)
      {-# SCC glDrawElements #-} throwWithStack $ glDrawElements (dats^.elementMode) (fromIntegral $ dats^.elementCount) (dats^.elementType) nullPtr


pointMesh, spotMesh, dirMesh :: Mesh (V.Position Vec3)
pointMesh = mkFromVerticesF "Pointligt" $ map V.Position . vertices . triangles $ geoSphere 2 1
spotMesh  = mkFromVerticesF "Spotlight" $ map V.Position . vertices . triangles $ cone 1 1 24
dirMesh   = mkFromVerticesF "DirectionalLight" $ V.Position <$> [0, 0, 0]

-- * Shader Interfaces

vertexUniforms :: (MonadIO m, Functor m, Applicative m) => Program -> m VertexShader
vertexUniforms prog = do
  boundAttributeLocation prog "vPosition" $= VPOSITION
  VertexShader (setVertexAttribute VPOSITION)
    <$> fmap (SettableStateVar.($=)) (programUniform programUniformMatrix4f prog "ViewMatrix")
    <*> fmap (SettableStateVar.($=)) (programUniform programUniformMatrix4f prog "VPMatrix")
    <*> fmap (SettableStateVar.($=)) (programUniform programUniformMatrix4f prog "ModelMatrix")
    <*> fmap (SettableStateVar.($=)) (programUniform programUniformMatrix4f prog "ViewToScreenMatrix")
    <*> (lightUniform prog "Light")

fragmentUniforms :: Program -> YageResource FragmentShader
fragmentUniforms prog = FragmentShader
  <$> gBufferUniform prog
  <*> fmap (SettableStateVar.($=)) (programUniform programUniform3f prog "CameraPosition")
  <*> fmap (SettableStateVar.($=)) (programUniform programUniform2f prog "ZProjRatio")
  <*> fmap (SettableStateVar.($=)) (programUniform programUniformMatrix4f prog "ViewToWorld")
  <*> lightUniform prog "Light"

gBufferUniform :: Program -> YageResource (UniformVar GBuffer)
gBufferUniform prog = do
  gbufferSampler <- mkGBufferSampler
  _aChannel <- samplerUniform prog (sampler2D G_CHANNEL_A gbufferSampler) "inChannelA"
  _bChannel <- samplerUniform prog (sampler2D G_CHANNEL_B gbufferSampler) "inChannelB"
  _cChannel <- samplerUniform prog (sampler2D G_CHANNEL_C gbufferSampler) "inChannelC"
  _dChannel <- samplerUniform prog (sampler2D G_CHANNEL_D gbufferSampler) "inChannelD"
  depthTexture <- samplerUniform prog (sampler2D G_DEPTH gbufferSampler) "DepthTexture"
  return $ SettableStateVar $ \gbuff -> do
    _aChannel  $= Just (gbuff^.aChannel)
    _bChannel  $= Just (gbuff^.bChannel)
    _cChannel  $= Just (gbuff^.cChannel)
    _dChannel  $= Just (gbuff^.dChannel)
    depthTexture $= Just (gbuff^.depthChannel)

-- * Sampler

mkGBufferSampler :: YageResource Sampler
mkGBufferSampler = throwWithStack $ do
  sampler <- glResource
  samplerParameteri sampler GL_TEXTURE_WRAP_S $= GL_CLAMP_TO_EDGE
  samplerParameteri sampler GL_TEXTURE_WRAP_T $= GL_CLAMP_TO_EDGE
  samplerParameteri sampler GL_TEXTURE_MIN_FILTER $= GL_LINEAR
  samplerParameteri sampler GL_TEXTURE_MAG_FILTER $= GL_LINEAR
  -- when gl_EXT_texture_filter_anisotropic $ samplerParameterf sampler GL_TEXTURE_MAX_ANISOTROPY_EXT $= 16
  return sampler
