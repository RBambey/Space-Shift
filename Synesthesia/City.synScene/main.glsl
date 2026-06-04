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
const vec3  fogColor         = vec3( 0.34, 0.37, 0.4 );

const float windowSize       = 0.1;
const float windowDivergence = 0.2;
const vec3  windowColor      = vec3( 0.1, 0.2, 0.5 );

const float beaconProb       = 0.0003;
const float beaconFreq       = 0.6;
const vec3  beaconColor      = vec3( 1.5, 0.2, 0.0 );

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

// ---- Grid ray marcher ----
// Buildings tile the XZ plane; Y is height.

vec4 castRay( vec3 eye, vec3 ray ) {
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

        float prob = beaconProb * pow( height, 3.0 );
        vec2  h    = hash2( block );
        if ( h.x < prob ) {
            vec3  center = vec3( block.x + 0.5, height + 0.2, block.y + 0.5 );
            float bt     = dot( center - eye, ray );
            if ( bt < dist ) {
                vec3  bp   = eye + bt * ray;
                float bfog = ( exp( -bp.y / fogDistance ) - exp( -eye.y / fogDistance ) )
                           / ray.y;
                bfog  = exp( fogDensity * bfog );
                bt    = distance( center, bp );
                bfog *= pow( syn_BassLevel, 3.0 ) * 8.0;
                beacon += bfog * pow( clamp( 1.0 - 2.0 * bt, 0.0, 1.0 ), 4.0 );
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

    vec4 res = castRay( eye, ray );
    vec3 p   = eye + res.x * ray;

    // Window colors per building block
    vec2 block  = floor( p.xz );
    vec3 window = floor( p / windowSize );
    float wx = hash1( block, window.x );
    float wy = hash1( block, window.y );
    float wz = hash1( block, window.z );
    vec3 color = windowColor + windowDivergence * ( hash3( block ) - 0.5 );
    color *= smoothstep( 0.1, 0.9, fract( 2.5 * ( wx * wy * wz ) ) );

    // Street glow rising from ground (Y-up)
    vec3 streetLevel = streetColor * exp( -p.y / streetDistance );
    color += streetLevel;
    color = clamp( mix( 0.25 * streetLevel, color, res.z ), 0.0, 1.0 );

    // Exponential height fog
    float fog = ( exp( -p.y / fogDistance ) - exp( -eye.y / fogDistance ) ) / ray.y;
    fog = exp( fogDensity * fog );
    color = mix( fogColor, color, fog );

    color  = mix( fogColor, color, res.w );
    color += res.y * beaconColor;
    color += vec3( pow( res.y, 2.0 ) );

    return vec4( color, 1.0 );
}
