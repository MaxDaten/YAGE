{-# OPTIONS_GHC -fno-warn-orphans     #-}
{-# LANGUAGE DataKinds, TypeOperators #-}
{-# LANGUAGE FlexibleContexts         #-}
{-# LANGUAGE DeriveDataTypeable       #-}
{-# LANGUAGE PackageImports           #-}
{-# LANGUAGE ScopedTypeVariables      #-}
module Yage.Geometry
    ( module Geometry
    , module Yage.Geometry
    ) where

import                  Yage.Prelude                     hiding (toList)
import                  Yage.Lens

import qualified        Data.Vector                      as V
import                  Data.Foldable                    (toList)

import "yage-geometry"  Yage.Geometry                    as Geometry

import                  Linear
import                  Yage.Rendering.Mesh

-- |
packGeos
  :: forall a v. ( Epsilon a, Floating a )
  => (Pos a -> Tex a -> TBN a -> v)
  -> TriGeo (Pos a)
  -> TriGeo (Tex a)
  -> TriGeo (TBN a)
  -> TriGeo v
packGeos vertexFormat posG texG tbnG
  | not compatibleSurfaces = error "packGeos: invalid surfaces"
  | otherwise = Geometry
      { _geoVertices = V.concatMap (V.concatMap (V.fromList . toList . fmap emitVertex)) surfacesIndices
      -- trivial indices, just like [[0..n], [n+1..m], ...]
      , _geoSurfaces = fst $ V.foldl' reindexSurfaces (V.empty, 0) surfacesIndices
      }
  where

  surfacesIndices = V.zipWith3 (\(GeoSurface p) (GeoSurface t) (GeoSurface n) -> V.zipWith3 mergeIndices p t n) (posG^.geoSurfaces) (texG^.geoSurfaces) (tbnG^.geoSurfaces)

  -- not the best implementation
  reindexSurfaces (surfsAccum, offset) surface =
    let surfLength = V.length surface
        mkTriangle i = Triangle (i*3+offset) (i*3+offset+1) (i*3+offset+2)
    in ( surfsAccum `V.snoc` ( GeoSurface $ V.generate surfLength mkTriangle ), offset + surfLength * 3 )

  emitVertex :: (Int, Int, Int) -> v
  emitVertex (vertIdx, texIdx, ntIdx) =
      vertexFormat (verts V.! vertIdx) (texs V.! texIdx) (norms V.! ntIdx)

  mergeIndices :: Triangle Int -> Triangle Int -> Triangle Int -> Triangle (Int, Int, Int)
  mergeIndices p tx tn  = (,,) <$> p <*> tx <*> tn

  verts = posG^.geoVertices
  texs  = texG^.geoVertices
  norms = tbnG^.geoVertices

  compatibleSurfaces =
      let posSurfaces  = posG^.geoSurfaces^..traverse.to (length.unGeoSurface)
          texSurfaces  = texG^.geoSurfaces^..traverse.to (length.unGeoSurface)
          normSurfaces = tbnG^.geoSurfaces^..traverse.to (length.unGeoSurface)
      in posSurfaces == texSurfaces && posSurfaces == normSurfaces


buildTriGeo
  :: ( Foldable f, HasTriangles t, Epsilon a, Floating a )
  => ( Pos a -> Tex a -> TBN a -> v )
  -> f (t (Pos a))
  -> f (t (Tex a))
  -> TriGeo v
buildTriGeo vertexFormat pos tex =
  let posGeo = makeSimpleTriGeoF pos
      texGeo = makeSimpleTriGeoF tex
  in packGeos vertexFormat posGeo texGeo $ calcTangentSpaces posGeo texGeo


-- buildMesh
--   :: ( Epsilon a, Floating a, HasTriangles t, HasSurfaces s, Storable (Vertex v)
--              , IElem (YPosition3 a) vert, IElem (YTexture2 a) vert ) =>
--           ( Pos a -> Tex a -> TBN a -> (Vertex v) ) -> ByteString -> s (t (Vertex vert)) -> Mesh (Vertex v)
-- buildMesh vertexFormat name geo =
--     let vs     = concatMap (concatMap (vertices . triangles) . getSurface) $ surfaces geo
--         posGeo = makeSimpleTriGeo $ V.map (rGet position3) $ V.fromList vs
--         texGeo = makeSimpleTriGeo $ V.map (rGet texture2)  $ V.fromList vs
--         tbnGeo = calcTangentSpaces posGeo texGeo

--         triGeo = packGeos vertexFormat posGeo texGeo tbnGeo
--     in meshFromTriGeo name triGeo
