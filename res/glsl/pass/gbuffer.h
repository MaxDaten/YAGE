/* # Buffer Encoding

   ## Normal Encoding
    - http://aras-p.info/texts/CompactNormalStorage.html
*/
#ifndef __GBUFFER_H__
#define __GBUFFER_H__

#include <common.h>

/*
    0 : simple z reconstruction
    1 : spherical map transformation (view space)
    2 : octahedron transformation (world space)
*/
#define NORMAL_ENCODING_TYPE 2

uniform sampler2D inChannelA;
uniform sampler2D inChannelB;
uniform sampler2D inChannelC;
uniform sampler2D inChannelD;
uniform sampler2D DepthTexture;
in vec3 VertexPosVS;

struct Surface
{
    vec3 Position;
    vec4 Albedo;
    vec3 Specular;
    vec3 Normal;
    float Metallic;
    float Roughness;
};


vec3 DecodeTextureNormal( vec3 TexNormal )
{
    return TexNormal * 2.0 - 1.0;

}


vec3 EncodeTextureNormal( vec3 Normal3d )
{
    return Normal3d.xyz * 0.5 + 0.5;
}


vec3 DecodeNormalZ( vec2 Normal )
{
    float NormalZ = sqrt( saturate ( 1.0 - dot( Normal, Normal ) ) );
    return vec3( Normal, NormalZ );
}


vec2 EncodeNormalSpheremap( vec3 Normal )
{
    return normalize( Normal.xy ) * sqrt( Normal.z );
}


vec3 DecodeNormalSpheremap( vec4 NormalEncoded )
{
    vec3 NN = NormalEncoded.xyz;

    NN.z      = dot( NN.xy, NN.xy );
    NN.xy     = normalize(NN.xy) * sqrt( 1 - NN.z * NN.z );
    return NN;
}

// [http://knarkowicz.wordpress.com/2014/04/16/octahedron-normal-vector-encoding/]
vec2 OctWrap( vec2 v )
{
    return ( 1.0 - abs( v.yx ) ) * vec2( v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0 );
}

vec2 EncodeNormalOctahedron( vec3 n )
{
    n.xy /= dot( vec3(1.0), abs(n));
    n.xy = n.z <= 0.0 ? OctWrap( n.xy ) : n.xy;
    // n.xy = n.xy;// * 0.5 + 0.5;
    return n.xy;
}

vec3 DecodeNormalOctahedron( const vec2 encN )
{
    vec3 n;
    n.z = 1.0 - dot( vec2(1.0), abs( encN ));
    n.xy = n.z < 0.0 ? OctWrap( encN.xy ) : encN.xy;
    n = normalize( n );
    return n;
}

vec2 EncodeNormalXY( vec3 Normal )
{
#if NORMAL_ENCODING_TYPE == 0
    return Normal.rg;
#elif NORMAL_ENCODING_TYPE == 1
    return EncodeNormalSpheremap( Normal );
#elif NORMAL_ENCODING_TYPE == 2
    return EncodeNormalOctahedron( Normal );
#endif
}


vec3 DecodeNormalXY( vec2 Normal )
{
#if NORMAL_ENCODING_TYPE == 0
    return DecodeNormalZ( Normal );
#elif NORMAL_ENCODING_TYPE == 1
    return DecodeNormalSpheremap( vec4(Normal, 0, 0) );
#elif NORMAL_ENCODING_TYPE == 2
    return DecodeNormalOctahedron( Normal );
#endif
}


void EncodeGBuffer( Surface surface, out vec4 outChannelA, out vec4 outChannelB, out vec4 outChannelC, out vec4 outChannelD )
{
    outChannelA.rgb   = surface.Albedo.rgb;
    outChannelA.a     = 1.0; // unused
    outChannelB.r     = surface.Roughness;
    outChannelB.g     = surface.Metallic;
    outChannelC.rgb   = surface.Normal;
    // outChannelC.rg    = EncodeNormalXY(surface.Normal);
    // outChannelC.b     = 1.0; // unused
    // outChannelC.a     = 1.0; // unused
    outChannelD.rgb   = surface.Position;
}

Surface DecodeGBuffer( vec2 uv )
{
      // the channel for albedo rgb + distance from View
    vec4 chA       = texture( inChannelA, uv ).rgba;
    vec4 chB       = texture( inChannelB, uv ).rgba;
    vec4 chC       = texture( inChannelC, uv ).rgba;
    vec4 chD       = texture( inChannelD, uv ).rgba;
    float bufferDepth  = texture( DepthTexture, uv ).r;

    Surface surface;

    // extrapolate the view space position of the pixel to the zFar plane
    vec4 position  = ViewToWorld * vec4(PositionVSFromDepth( bufferDepth, ZProjRatio, VertexPosVS ), 1.0);
    // surface.Position = position.xyz;
    surface.Position = chD.xyz;

    surface.Albedo    = vec4(chA.rgb, 1.0);
    surface.Roughness = max(chB.r, 0.02);
    surface.Specular  = vec3(0.5);
    surface.Normal    = chC.rgb;
    // surface.Normal    = normalize(DecodeNormalXY(chC.rg));
    surface.Metallic  = chB.g;

    surface.Specular = mix( 0.08 * surface.Specular, surface.Albedo.rgb, vec3(surface.Metallic));
    surface.Albedo   -= surface.Albedo * surface.Metallic;

    return surface;
}

/* __GBUFFER_H__ */
#endif
