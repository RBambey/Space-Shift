// This file is released under CC0 1.0 Universal (Public Domain Dedication).
// To the extent possible under law, Mårten Rånge has waived all copyright
// and related or neighboring rights to this work.
// See <https://creativecommons.org/publicdomain/zero/1.0/> for details.
// Original: Entombed Silicon Dreams by mrange
// Adapted by RBambey — free-fly camera, retro 70s palette

// License: WTFPL, author: sam hocevar, found: https://stackoverflow.com/a/17897228/418488
const vec4 hsv2rgb_K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);

// License: WTFPL, author: sam hocevar, found: https://stackoverflow.com/a/17897228/418488
#define HSV2RGB(c)  (c.z * mix(hsv2rgb_K.xxx, clamp(abs(fract(c.xxx + hsv2rgb_K.xyz) * 6.0 - hsv2rgb_K.www) - hsv2rgb_K.xxx, 0.0, 1.0), c.y))

// License: WTFPL, author: sam hocevar, found: https://stackoverflow.com/a/17897228/418488
vec3 hsv2rgb(vec3 c) {
  vec3 p = abs(fract(c.xxx + hsv2rgb_K.xyz) * 6.0 - hsv2rgb_K.www);
  return c.z * mix(hsv2rgb_K.xxx, clamp(p - hsv2rgb_K.xxx, 0.0, 1.0), c.y);
}


const float
  TAU=2.*PI
, PI_2=.5*PI
, ZZ =11.
;

const vec2
  PA=vec2(6,1.41)
, PB=vec2(.056,.035)
;

const mat2
  R=mat2(1.2,1.6,-1.6,1.2)
;

// License: Unknown, author: Unknown, found: don't remember
float hash(vec2 co) {
  return fract(sin(dot(co.xy ,vec2(12.9898,58.233))) * 13758.5453);
}

// License: Unknown, author: Claude Brezinski, found: https://mathr.co.uk/blog/2017-09-06_approximating_hyperbolic_tangent.html
vec3 tanh_approx(vec3 x) {
  vec3
    x2 = x*x
  ;
  return clamp(x*(27.0 + x2)/(27.0+9.0*x2), -1.0, 1.0);
}

// License: MIT, author: Pascal Gilcher, found: https://www.shadertoy.com/view/flSXRV
float atan_approx(float y, float x) {
  float cosatan2 = x / (abs(x) + abs(y));
  float t = PI_2 - cosatan2 * PI_2;
  return y < 0.0 ? -t : t;
}

float acos_approx(float x) {
  return atan_approx(sqrt(max(.0, 1. - x*x)), x);
}

vec3 to_spherical(vec3 p) {
  float
    r = length(p)
  ;
  return vec3(r, acos_approx(p.z/r), atan_approx(p.y, p.x));
}

vec3 stars(vec3 Rd) {
  float
    Z=TAU/200.
  ;

  vec3
    col=vec3(0)
  ;

  float
    a=1.
  ;
  for(int i=0;i<3;++i) {
    Rd=Rd.zxy;
    vec2
      s=to_spherical(Rd).yz
    , n=floor(s/Z+.5)
    , c=s-Z*n
    ;

    float
      h=sin(s.x)
    , h0=hash(n+123.4*float(i+1))
    , h1=fract(8667.*h0)
    , h2=fract(9677.*h0)
    , h3=fract(9977.*h0)
    ;
    c.y*=h;

    col += a*hsv2rgb(vec3(-.4*h1,sqrt(h3),step(h0,.1*h)*h1*vec3(7e-6)/(7e-8+dot(c,c))));
    Z*=.5;
    a*=.5;
  }
  return col;
}


// License: MIT, author: Inigo Quilez, found: https://www.iquilezles.org/www/articles/spherefunctions/spherefunctions.htm
float ray_sphere(vec3 ro, vec3 rd, vec4 sph) {
  vec3
    oc=ro - sph.xyz
    ;
  float
    b=dot(oc, rd)
  , c=dot(oc, oc)- sph.w*sph.w
  , h=b*b-c
  ;
  h=sqrt(h);
  return -b-h;
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/intersectors/
float ray_plane(vec3 ro, vec3 rd, vec4 p) {
  return -(dot(ro,p.xyz)+p.w)/dot(rd,p.xyz);
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/distfunctions/
float doctahedron(vec3 p, float s) {
  p = abs(p);
  return (p.x+p.y+p.z-s)*0.57735027;
}

float beat() {
  return dot(pow(vec2(syn_BassLevel,syn_BassHits), vec2(bass_pow)), bass_mix);
}

float freq(float x, float m) {
  vec2 t=textureLod(syn_Spectrum,x,0).yz;
  return mix(t.x,t.y*.3,m);
}

float dfbm(vec3 p) {
  float
    d=p.y+.6
  , a=1.5
  ;

  vec2
    D=vec2(0)
  , P=.23*p.xz
  ;

  vec4
    o
  ;

  for(int j=0;j<7;++j) {
    o=cos(P.xxyy+vec4(11,0,11,0));
    p=o.yxx*o.zwz;
    D+=p.xy;
    d-=a*(1.+p.z)/(1.+3.*dot(D,D));
    P*=R;
    a*=.55;
  }

  return d;
}

float dpyramid(vec3 p, out vec3 oo) {
  vec2
    n=floor(p.xz/ZZ+.5)
  ;
  p.xz-=n*ZZ;

  float
    h0=hash(n)
  , h1=fract(9677.*h0)
  , h =.3*ZZ*h0*h0+0.1
  , d =doctahedron(p,h)
  ;

  oo=vec3(1e3,0,0);
  if(h1>tomb_probability) return 1e3;
  oo=vec3(d,h0,h);
  return d;
}

float df(vec3 p, out vec3 oo) {
  p.y=abs(p.y);

  float
    d0=dfbm(p)
  , d1=dpyramid(p,oo)
  , d
  ;
  d=d0;
  d=min(d,d1);
  return d;
}

float fbm(float x) {
  float
    a=1.
  , h=0.
  ;

  for(int i=0;i<5;++i) {
    h+=a*sin(x);
    x*=2.03;
    x+=123.4;
    a*=.55;
  }

  return abs(h);
}

vec3 gb(sampler2D pp, ivec2 dir, ivec2 xy) {
  const float blurriness = 200.;
  ivec2 sz = textureSize(pp, 0) - 1;
  vec3 col = texelFetch(pp, xy, 0).xyz;
  float w, ws = 1., I;
  for(int i = 1; i < 25; ++i) {
    I = float(i);
    w = exp(-(I*I)/blurriness);
    ivec2 off = i * dir;
    col += w*(texelFetch(pp, clamp(xy-off, ivec2(0), sz), 0).xyz + texelFetch(pp, clamp(xy+off, ivec2(0), sz), 0).xyz);
    ws += 2.*w;
  }
  col /= ws;
  return col;
}

vec4 renderMain() {

  if (PASSINDEX == 0) {
    float
        d=1.
      , z=0.
      , B=beat()
      , F
      , L
      ;

    vec3
        oo
      , O=vec3(0)
      , p
      ;

    vec4
        M
      ;

    vec3 P      = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 Rd     = normalize(uv.x * cRight + uv.y * cUp + fov * 0.5 * cFwd);
    vec3 Y = (1.+Rd.x)*BY;
    vec3 S = (1.+Rd.y)*BW*Y;

    for(int i=0;i<50&&d>1e-5&&z<2e2;++i) {
      p=z*Rd+P;
      d=df(p,oo);
      if(p.y>0.) {
        O+=BG+min(d,9.)*Y;
      } else {
        O+=S;
        oo.x*=9.;
      }

      O+=
          B
        * smoothstep(oo.z*.78,oo.z*.8,abs(p.y))
        / max(oo.x+oo.x*oo.x*oo.x*oo.x*9.,1e-2)
        * BF
        ;

      z+=d*.7;
    }

    O*=9E-3;

    if(Rd.y>0.0) {
      M=GG;
      S=M.xyz+P;
      M.xyz=S;
      z=d=ray_sphere(P,Rd,M);

      F=smoothstep(0.0,0.2,Rd.y);
      Y=clamp((hsv2rgb(vec3(OFF-.4*Rd.y,.5+1.*Rd.y,3./(1.+800.*Rd.y*Rd.y*Rd.y)))),0.,1.);
      L=dot(vec3(0.2126, 0.7152, 0.0722),Y);
      if(z>0.) {
        p=P+Rd*z;
        vec3 sphN=normalize(p-M.xyz);
        Y+=
            max(dot(LD,sphN),0.)
          * F
          * smoothstep(1.0,.89,1.+dot(Rd,sphN))
          * fbm(2e-2*dot(p-S,RN))
          ;
      }
      M=vec4(RN,-dot(RN,S));
      z=ray_plane(P,Rd,M);
      if(z>0.&&(d>0.&&z<d||isnan(d))) {
        p=P+Rd*z;
        z=distance(S,p);
        Y+=
            F
          * smoothstep(GG.w*1.41,GG.w*1.46,z)
          * smoothstep(GG.w*2.,GG.w*1.95,z)
          * (
              smoothstep(
                 fft_limit
              ,  1.01
              ,  freq(1.5*abs(z-GG.w*1.48)/GG.w,smoothstep(1.,1.1,1.-abs(dot(Rd,RN))+.2)))
              *  hsv2rgb(vec3(OFF-.7+z/GG.w,.9,9.))
          +   abs(dot(LD,RN))*fbm(.035*z)
          )
          ;
      }

      if(isnan(d)) {
        Y+=pow(1.-L,4.)*stars(Rd);
      }

      O*=Y;
    }

    return vec4(O, 1);


  } else if (PASSINDEX == 1) {
    vec3 c = texelFetch(BuffA, ivec2(_xy), 0).xyz;
    c *= smoothstep(.2, .5, dot(vec3(0.2126, 0.7152, 0.0722), c));
    return vec4(c, 1);


  } else if (PASSINDEX == 2) {
    return vec4(gb(BuffB, ivec2(3, 0), ivec2(_xy)), 1);


  } else if (PASSINDEX == 3) {
    vec3 b = gb(BuffC, ivec2(0, 3), ivec2(_xy));
    vec3 p = texelFetch(BuffB, ivec2(_xy), 0).xyz;
    return vec4(mix(b, p, .95), 1);


  } else {
    vec2 p2 = _uvc * 2.;
    vec3 scene = texelFetch(BuffA, ivec2(_xy), 0).xyz;
    vec3 bloom = texelFetch(BuffD, ivec2(_xy), 0).xyz;
    vec3 MC    = hsv2rgb(vec3(OFF+.1, .7, 1.));

    vec3 c = scene;
    c -= (length(-1.+2.*_uv)+.2)*FC;
    c += bloom*MC*bloom_amount;
    c  = max(c, 0.);
    c  = tanh_approx(c);
    c  = sqrt(c);

    vec4 M;

    M = _loadMedia(c.rg*media_displace);
    c = mix(c, M.xyz, (p2.y+.5)*M.w*media_opacity);

    M = texture(syn_FinalPass, _uv);
    c = mix(c, M.xyz, motion_blur);

    return vec4(c, 1);
  }
}
