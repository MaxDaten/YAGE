/*
    The BRDF for the physically based pipeline

    # References
    - [http://seblagarde.wordpress.com/2011/08/17/feeding-a-physical-based-lighting-mode/]
    - [https://de45xmedrsdbp.cloudfront.net/Resources/files/2013SiggraphPresentationsNotes-26915738.pdf]
    - [Lengyel 2004] : Mathematics for 3d Game Programming & Computer Graphics
*/
#ifndef __BRDF_H__
#define __BRDF_H__


struct LightData
{
    vec4    LightPosition;
    // cos inner angle, cos outer angle, radius
    vec3    LightConeAnglesAndRadius;
    // direction in light space
    vec3    LightDirection;
    // hdr color with open range [0..], negative values not supported
    vec3    LightColor;
};


bool IsSpotlight( LightData light )
{
    return light.LightConeAnglesAndRadius.y > 0;
}

bool IsPositionalLight( LightData light )
{
    return light.LightPosition.w == 1;
}

bool IsPointlight( LightData light)
{
    return light.LightConeAnglesAndRadius.y == 0;
}

vec3 DiffuseLambert( vec3 diffuseColor )
{
    return diffuseColor / PI;
}


vec3 Diffuse( vec3 diffuseColor )
{
    return DiffuseLambert( diffuseColor );
}

// GGX / Trowbridge-Reitz
// [Walter et al. 2007, "Microfacet models for refraction through rough surfaces"]
float D_GGX( float m2, float NoH )
{
    float d = ( NoH * m2 - NoH ) * NoH + 1;
    return m2 / ( PI * d * d );
}


/*
    # Microsurface'ed Normal Distribution Function

    Scattering with microsurfaces.
*/
float SpecularNDF( float Roughness4, float NoH )
{
    return D_GGX( Roughness4, NoH );
}


// [Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"]
// [Lagarde 2012, "Spherical Gaussian approximation for Blinn-Phong, Phong and Fresnel"]
vec3 FresnelSchlick( vec3 F0, float F90, float VoH )
{
    // gauss approximation
    return F0 + ( F90 - F0 ) * pow(1.0 - VoH, 5.0);
    // return F0 + ( 1 - F0 ) * exp2( (-5.55473 * VoH - 6.98316) * VoH );
}


/*
    # The Fresnel Factor

    The fraction of transmitted (and probably absorbed) energy to reflected energy
    [Lengyel 2004, 6.9.3]
*/
vec3 Fresnel( vec3 F0, float F90, float VoH )
{
    return FresnelSchlick( F0, F90, VoH);
}


// [Karis 2013, "Real Shading in Unreal Engine 4"]
float GeometricSchlick( float a, float NoV, float NoL )
{
    // float k = a * 0.5;
    float k = square( a + 1 ) / 8.0;
    float GV = NoV * (1 - k) + k;
    float GL = NoL * (1 - k) + k;
    return 0.25 / ( GV * GL );
    // float GV = NoV / (NoV * (1 - k) + k);
    // float GL = NoL / (NoL * (1 - k) + k);
    // return GV * GL;
}


float GeometricSmithJointApprox( float a, float NoV, float NoL )
{
    float GV = NoL * ( NoV * ( 1 - a) + a);
    float GL = NoV * ( NoL * ( 1 - a) + a);
    return 0.5 / ( GV * GL );
}


// [Lagarde & Rousiers 2014, Moving Frostbite to Physically Based Rendering, S.12]
float GeometricSmith( float a, float NoV, float NoL )
{
    float a2 = a * a;
    float GL = NoV * sqrt( (-NoL * a2 + NoL) * NoL + a2 );
    float GV = NoL * sqrt( (-NoV * a2 + NoV) * NoV + a2 );
    return 0.5 / ( GV + GL );
}


/*
    # The Geometric Attenuation

    Approximation of self shadowing due the microsurfaces

    Vis = G / ( 4*NoL*NoV )
    [Lazarov 2011, "Physically Based Lighting in Black Ops"]
*/
float Geometric( float a, float NoV, float NoL)
{
    // return GeometricSchlick( a, NoV, NoL );
    return GeometricSmith( a, NoV, NoL );
    // return max(NoV, NoL);
    // return GeometricSmithJointApprox( a, NoV, NoL );
}


/*
    https://www.unrealengine.com/blog/physically-based-shading-on-mobile
*/
vec2 EnvironmentBRDFApprox( float Roughness, float NoV )
{
    const vec4 c0 = vec4( -1, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(  1,  0.0425,   1.04, -0.04);
    vec4 r = Roughness * c0 + c1;
    float a004 = min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
    vec2 AB = vec2( -1.04, 1.04 ) * a004 + r.zw;
    return AB;
}

/*
    # The preintegrated Environment BRDF
*/
vec2 EnvironmentBRDF( float Roughness, float NoV )
{
    return EnvironmentBRDFApprox( Roughness, NoV);
}

// __BRDF_H__
#endif
