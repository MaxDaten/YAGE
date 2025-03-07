{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# LANGUAGE Arrows #-}
module Yage.Wire.Movement where

import Yage.Prelude
import Yage.Lens
import Yage.Transformation

import Yage.Math
import Yage.UI

import Yage.Wire.Types
import Yage.Wire.Analytic
import Yage.Wire.Input

import FRP.Netwire as Netwire hiding (loop, left, right)

import Yage.Camera

{--
-- Movement
--}


smoothTranslation :: (Real t) =>
                  V3 Double -> Double -> Double -> Key -> YageWire t (V3 Double) (V3 Double)
smoothTranslation dir acc att key =
    let trans = integral 0 . arr (signorm dir ^*) . velocity acc att key
    in proc inTransV -> do
        transV <- trans -< ()
        returnA -< inTransV + transV

velocity :: (Floating b, Ord b, Real t)
         => b -> b -> Key -> YageWire t a b
velocity !acc !att !trigger =
    integrateAttenuated att 0 . (pure acc . whileKeyDown trigger <|> 0)


smoothRotationByKey :: (Real t) =>
                    Double -> Double -> V3 Double -> Key -> YageWire t (Quaternion Double) (Quaternion Double)
smoothRotationByKey acc att !axis !key =
    let angleVel    = velocity acc att key
        rot         = axisAngle axis <$> integral 0 . angleVel
    in proc inQ -> do
        rotQ    <- rot -< ()
        returnA -<  inQ * rotQ -- * conjugate rotQ

---------------------------------------------------------------------------------------------------


rotationByVelocity :: (Real t) => V3 Double -> V3 Double -> YageWire t (V2 Double) (Quaternion Double)
rotationByVelocity !xMap !yMap =
    let applyOrientations   = arr (axisAngle xMap . (^._x)) &&& arr (axisAngle yMap . (^._y))
        combineOrientations = arr (\(!qu, !qr) -> qu * qr)
    in combineOrientations . applyOrientations . integral 0


-- | planar movement in a 3d space
wasdMovement :: (Real t, Num a) => V2 a -> YageWire t () (V3 a)
wasdMovement (V2 xVel zVel) =
    let pos = V3 ( whileKeyDown Key'D . pure xVel ) ( hold . never ) ( whileKeyDown Key'S . pure zVel ) <&> (<|> 0)
        neg = V3 ( whileKeyDown Key'A . pure xVel ) ( hold . never ) ( whileKeyDown Key'W . pure zVel ) <&> (<|> 0)
    in wire3d $ liftA2 (+) (pos) (negate <$> neg)




wire3d :: V3 (YageWire t a b) -> YageWire t a (V3 b)
wire3d (V3 xw yw zw) = V3 <$> xw <*> yw <*> zw



translationWire :: Num a =>
    M33 a ->
    -- ^ the orthogonal basis
    V3 (YageWire t () a) ->
    -- ^ the signal source for each basis component
    YageWire t () (V3 a)
    -- ^ the resulting translation in the space
translationWire basis = liftA2 (!*) (pure basis) . wire3d


-- | relative to local space
fpsCameraMovement :: Real t =>
    V3 Double ->
    -- ^ starting position
    YageWire t () (V3 Double) ->
    -- ^ the source of the current translation velocity
    YageWire t Camera Camera
    -- ^ updates the camera translation
fpsCameraMovement startPos movementSource =
    proc cam -> do
        trans       <- movementSource    -< ()
        worldTrans  <- integral startPos -< (cam^.cameraOrientation) `rotate` trans
        returnA -< cam & position .~ worldTrans


-- | look around like in fps
fpsCameraRotation :: Real t => YageWire t () (V2 Double) -> YageWire t Camera Camera
fpsCameraRotation velocitySource =
  proc cam -> do
    velV <- velocitySource -< ()
    x    <- integralWith (flip fmod) 0    -< (velV^._x, 2*pi)
    y    <- integralWith ymod 0           -< (velV^._y, (-pi/2,pi/2))
    returnA -< cam `pitch` y `yaw` x
  where ymod (l,u) x = clamp x l u

-- | rotation about focus point
-- http://gamedev.stackexchange.com/a/20769
arcBallRotation :: Real t => YageWire t () (V2 Double) -> YageWire t (V3 Double, Camera) Camera
arcBallRotation velocitySource =
  proc (focusPoint, cam) -> do
    let focusToCam = cam^.position - focusPoint
    velV <- velocitySource -< ()
    x    <- integral 0             -< velV^._x
    y    <- integralWith ymod 0    -< (velV^._y, (-pi/2,pi/2))

    let rotCam = cam `pitch` y `yaw` x
        pos    = (rotCam^.orientation) `rotate` (focusToCam + focusPoint)
    returnA -< rotCam & position     .~ pos
  where ymod (l,u) x = clamp x l u
