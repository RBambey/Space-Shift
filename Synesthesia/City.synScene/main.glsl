// ============================================================
//  CITY — v1.0
//  Created by RBambey
//  Grid marching from iq's "Grid of Cylinders"
//  https://www.shadertoy.com/view/4dSGW1
//  Flight controls from Ocean Planet by RBambey
//
//  Coordinate system: Y is up (buildings on XZ plane).
//  Original shader used Z-up; Y and Z are swapped throughout.
// ============================================================

const float streetDistance   = 0.6;
const vec3  streetColor      = vec3( 4.0, 8.0, 10.0 );

const float fogDensity       = 0.5;
const float fogDistance      = 4.0;
const vec3  fogColor         = vec3( 0.38, 0.32, 0.48 );  // horizon light-pollution glow
const vec3  zenithColor      = vec3( 0.04, 0.02, 0.09 );  // near-black night sky at top

const float windowSize       = 0.1;
const float windowDivergence = 0.2;
const vec3  windowColor      = vec3( 0.1, 0.2, 0.5 );


const float tau              = 6.283185;

// ---- Hash functions ----

float hash1( vec2 p2 ) {
    p2 = fract( p2 * vec2( 5.3983, 5.4427 ) );
    p2 += dot( p2.yx, p2.xy + vec2( 21.5351, 14.3137 ) );
    return fract( p2.x * p2.y * 95.4337 );
}

float hash1( vec2 p2, float p ) {
    vec3 p3 = fract( vec3( 5.3983 * p2.x, 5.4427 * p2.y, 6.9371 * p ) );
    p3 += dot( p3, p3.yzx + 19.19 );
    return fract( ( p3.x + p3.y ) * p3.z );
}

vec2 hash2( vec2 p2 ) {
    vec3 p3 = fract( vec3( 5.3983 * p2.x, 5.4427 * p2.y, 6.9371 * p2.x ) );
    p3 += dot( p3, p3.yzx + 19.19 );
    return fract( ( p3.xx + p3.yz ) * p3.zy );
}

vec2 hash2( vec2 p2, float p ) {
    vec3 p3 = fract( vec3( 5.3983 * p2.x, 5.4427 * p2.y, 6.9371 * p ) );
    p3 += dot( p3, p3.yzx + 19.19 );
    return fract( ( p3.xx + p3.yz ) * p3.zy );
}

vec3 hash3( vec2 p2 ) {
    vec3 p3 = fract( vec3( p2.xyx ) * vec3( 5.3983, 5.4427, 6.9371 ) );
    p3 += dot( p3, p3.yxz + 19.19 );
    return fract( ( p3.xxy + p3.yzz ) * p3.zyx );
}

float noise1( vec2 p ) {
    vec2 i = floor( p );
    vec2 f = fract( p );
    vec2 u = f * f * ( 3.0 - 2.0 * f );
    return mix( mix( hash1( i + vec2( 0.0, 0.0 ) ),
                     hash1( i + vec2( 1.0, 0.0 ) ), u.x ),
                mix( hash1( i + vec2( 0.0, 1.0 ) ),
                     hash1( i + vec2( 1.0, 1.0 ) ), u.x ), u.y );
}

// ---- Audio helpers ----

// beat(): combines sustained bass level + transient hits, shaped by bass_pow curve.
// bass_mix.x weights syn_BassLevel (sustained); bass_mix.y weights syn_BassHits (transients).
float beat() {
    return dot(
        pow( clamp( vec2( syn_BassLevel, syn_BassHits ), 0.0, 1.0 ), vec2( bass_pow ) ),
        bass_mix
    );
}

// freq(): sample FFT spectrum at normalized frequency x (0 = bass, 1 = treble).
float freq( float x ) {
    return textureLod( syn_Spectrum, x, 0.0 ).y;
}

// ---- Grid ray marcher ----
// Buildings tile the XZ plane; Y is height.

vec4 castRay( vec3 eye, vec3 ray, out vec3 antennaGlow ) {
    antennaGlow = vec3( 0.0 );
    vec2 block = floor( eye.xz );
    vec3 ri    = 1.0 / ray;
    vec3 rs    = sign( ray );
    vec3 side  = 0.5 + 0.5 * rs;
    vec2 ris   = ri.xz * rs.xz;
    vec2 dis   = ( block - eye.xz + 0.5 + rs.xz * 0.5 ) * ri.xz;

    float beacon = 0.0;

    for ( int i = 0; i < 200; ++i ) {
        vec2  lo0    = block + 0.01;
        vec2  hi0    = block + 0.69;
        float height = ( 0.5 + hash1( block ) )
                     * ( 2.0 + 4.0 * pow( noise1( 0.1 * block ), 2.5 ) );

        float dist = 500.0;
        float face = 0.0;

        for ( int j = 0; j < 3; ++j ) {
            float top = height * ( 1.0 - 0.1 * float( j ) );
            vec2  loB = lo0 + vec2( 0.3 ) * hash2( block, float( j ) );
            vec2  hiB = hi0 + vec2( 0.3 ) * hash2( block, float( j ) + 0.5 );
            // Y-up: footprint in XZ, height in Y
            vec3  lo  = vec3( loB.x, 0.0, loB.y );
            vec3  hi  = vec3( hiB.x, top, hiB.y );

            vec3  wall   = mix( hi, lo, side );
            vec3  t      = ( wall - eye ) * ri;
            vec3  dimHit = step( t.zxy, t ) * step( t.yzx, t );
            float maxT   = dot( dimHit, t );
            float maxFace = 1.0 - dimHit.y;  // dimHit.y == 1 → roof/floor hit

            vec3 p = eye + maxT * ray;
            dimHit += step( lo, p ) * step( p, hi );
            if ( dimHit.x * dimHit.y * dimHit.z > 0.5 && maxT < dist ) {
                dist = maxT;
                face = maxFace;
            }
        }

        // ---- Spectrum-analyzer antenna ----
        vec2  h            = hash2( block );
        float heightFactor = smoothstep( 2.0, 6.0, height );
        if ( h.x < antenna_probability * heightFactor ) {
            const float antennaLen = 0.5;       // mast height above building peak
            vec2  axisXZ = block + 0.5;         // building center in XZ
            vec2  eyeXZ  = eye.xz;
            vec2  rayXZ  = ray.xz;
            float lenSq  = max( dot( rayXZ, rayXZ ), 1e-8 );
            float ta     = dot( axisXZ - eyeXZ, rayXZ ) / lenSq;

            if ( ta > 0.0 && ta < dist ) {
                float hitY = eye.y + ta * ray.y;
                // s: 0 = antenna base (bass), 1 = antenna tip (treble)
                float s    = clamp( ( hitY - height ) / antennaLen, 0.0, 1.0 );

                // Sample FFT spectrum at this frequency band
                float fftVal = freq( s );
                float lit    = smoothstep( fft_limit, fft_limit + 0.2, fftVal );

                // Radial glow falloff from mast axis in XZ
                vec2  hitXZ  = eyeXZ + ta * rayXZ;
                float d2D    = length( axisXZ - hitXZ );
                float radial = exp( -d2D * d2D * 200.0 );

                // Fog attenuation at the antenna point
                vec3  ap   = eye + ta * ray;
                float afog = ( exp( -ap.y / fogDistance ) - exp( -eye.y / fogDistance ) )
                           / ray.y;
                afog = exp( fogDensity * afog );

                // Color: bass base = warm orange, treble tip = cool cyan
                vec3 antCol = mix( vec3( 1.0, 0.4, 0.0 ), vec3( 0.0, 0.8, 1.0 ), s );

                antennaGlow += lit * radial * afog * antCol * 3.0;
            }
        }

        if ( dist < 400.0 ) {
            return vec4( dist, beacon, face, 1.0 );
        }

        vec2 dimStep = step( dis.xy, dis.yx );
        dis   += dimStep * ris;
        block += dimStep * rs.xz;
    }

    if ( ray.y < 0.0 ) {
        return vec4( -eye.y * ri.y, beacon, 0.0, 1.0 );
    }

    return vec4( 0.0, beacon, 0.0, 0.0 );
}

// ================================================================
vec4 renderMain()
{
    // Ocean Planet 6-DOF flight camera
    vec3 eye    = vec3( cam_x, cam_y, cam_z );
    vec3 cRight = vec3( cam_rx, cam_ry, cam_rz );
    vec3 cUp    = vec3( cam_ux, cam_uy, cam_uz );
    vec3 cFwd   = vec3( cam_fx, cam_fy, cam_fz );
    vec2 sc     = ( _uv - 0.5 ) * vec2( RENDERSIZE.x / RENDERSIZE.y, 1.0 );
    vec3 ray    = normalize( cFwd + cRight * sc.x + cUp * sc.y );

    vec3 antennaGlow;
    vec4 res = castRay( eye, ray, antennaGlow );
    vec3 p   = eye + res.x * ray;

    // Window colors per building block
    vec2 block  = floor( p.xz );
    vec3 window = floor( p / windowSize );
    float wx = hash1( block, window.x );
    float wy = hash1( block, window.y );
    float wz = hash1( block, window.z );
    vec3 color = windowColor + windowDivergence * ( hash3( block ) - 0.5 );
    color *= smoothstep( 0.1, 0.9, fract( 2.5 * ( wx * wy * wz ) ) );

    // Street glow — bass-reactive via beat(): 30% ambient at silence, 100% at full beat
    float B          = beat();
    vec3 streetLevel = streetColor * exp( -p.y / streetDistance ) * ( 0.3 + B * 0.7 );
    color += streetLevel;
    color = clamp( mix( 0.25 * streetLevel, color, res.z ), 0.0, 1.0 );

    // Exponential height fog
    float fog = ( exp( -p.y / fogDistance ) - exp( -eye.y / fogDistance ) ) / ray.y;
    fog = exp( fogDensity * fog );
    color = mix( fogColor, color, fog );

    vec3  skyCol = mix( fogColor, zenithColor, pow( clamp( ray.y, 0.0, 1.0 ), 0.7 ) );
    color  = mix( skyCol, color, res.w );
    color += antennaGlow;
    float antLum = dot( antennaGlow, vec3( 0.2126, 0.7152, 0.0722 ) );
    color += vec3( antLum * antLum );   // white bloom from bright antenna segments

    return vec4( color, 1.0 );
}
