// BLACK HOLE REDUX — v1.0
// Based on "Retro 70s Gas Giant" (mrange / RBambey)
// Black hole visual: "Singularity" by @XorDev (shadertoy.com/view/tsBXW3)
// Gas giant and rings replaced with procedural black hole.

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

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/intersectors/
float ray_plane(vec3 ro, vec3 rd, vec4 p) {
  return -(dot(ro,p.xyz)+p.w)/dot(rd,p.xyz);
}

float beat() {
  return dot(pow(vec2(syn_BassLevel,syn_BassHits), vec2(bass_pow)), bass_mix);
}

float dfbm(vec3 p) {
  float
    d=p.y+.55   // higher base = terrain floor sits below water plane
  , a=0.55      // low amplitude = short peaks that just poke above water
  ;

  vec2
    D=vec2(0)
  , P=.42*p.xz  // higher frequency = denser, smaller features
  ;

  vec4
    o
  ;

  for(int j=0;j<7;++j) {
    o=cos(P.xxyy+vec4(11,0,11,0));
    p=o.yxx*o.zwz;
    D+=p.xy;
    d-=a*(1.+p.z)/(1.+5.*dot(D,D));
    P*=R;
    a*=.63;     // higher persistence = rougher, jagged silhouette
  }

  return d;
}

float df(vec3 p, out vec3 oo) {
  p.y=abs(p.y);
  oo=vec3(1e3,0,0);
  return dfbm(p);
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

// ---- Black hole — Singularity by @XorDev, adapted ----
// Bass: rim narrows on hits (brighter ring) + additive orange pulse.
vec3 blackHole(vec2 p) {
    float i = 0.2, a;
    vec2 d = vec2(-1.0, 1.0);
    vec2 b = p - i * d;
    vec2 c = p * mat2(1.0, 1.0, d / (0.1 + i / dot(b, b)));
    a = dot(c, c);
    vec2 v = c * mat2(cos(0.5 * log(a) + TIME * i + vec4(0.0, 33.0, 11.0, 0.0))) / i;
    vec2 w = vec2(0.0);

    for (; i++ < 9.0; w += 1.0 + sin(v))
        v += 0.7 * sin(v.yx * i + TIME) / i + 0.5;

    float rimWidth = 0.03 + abs(length(p) - 0.7) / (1.0 + syn_BassLevel * 5.0);
    i = length(sin(v / 0.3) * 0.4 + c * (3.0 + d));

    vec4 O = 1.0 - exp(-exp(c.x * vec4(0.6, -0.4, -1.0, 0.0))
                        / w.xyyx
                        / (2.0 + i * i / 4.0 - i)
                        / (0.5 + 1.0 / a)
                        / rimWidth);

    float pulse = exp(-pow(abs(length(p) - 0.7), 2.0) * 40.0) * syn_BassLevel * 1.5;
    O.rgb += vec3(1.0, 0.45, 0.1) * pulse;
    return clamp(O.rgb, 0.0, 1.5);
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

    // Soft horizon: blend sky into terrain over a band instead of hard cutoff at Rd.y=0
    float skyBlend = smoothstep(-0.06, 0.06, Rd.y);
    if (skyBlend > 0.001) {
      F=smoothstep(0.0,0.2,Rd.y);
      float rdyS = max(Rd.y, 0.0);  // clamp for below-horizon sky gradient
      Y=clamp((hsv2rgb(vec3(OFF-.4*rdyS,.5+1.*rdyS,3./(1.+800.*rdyS*rdyS*rdyS)))),0.,1.);
      L=dot(vec3(0.2126, 0.7152, 0.0722),Y);

      // Stars on the background sky
      Y+=pow(1.-L,4.)*stars(Rd);

      // Black hole — black disc occludes sky/stars, BH visual added on top
      vec3 bhWorldDir = normalize(GG.xyz);
      float bhDot = dot(Rd, bhWorldDir);
      if (bhDot > 0.05) {
          vec3 bhRight = normalize(cross(bhWorldDir, vec3(0.0, 1.0, 0.0)));
          vec3 bhUp    = normalize(cross(bhRight, bhWorldDir));
          vec2 bhP     = vec2(dot(Rd, bhRight), dot(Rd, bhUp)) / bhDot * 2.0 / bh_scale;
          float _cr = cos(bh_rotation * 6.28318);
          float _sr = sin(bh_rotation * 6.28318);
          bhP = vec2(_cr * bhP.x - _sr * bhP.y, _sr * bhP.x + _cr * bhP.y);
          float bhFade = smoothstep(3.0, 1.5, length(bhP));
          if (bhFade > 0.001) {
              float bhDiscFade = smoothstep(1.3, 0.8, length(bhP));
              Y = mix(Y, vec3(0.0), bhDiscFade);                      // tight black disc — event horizon only
              Y += blackHole(bhP) * disk_brightness * bhFade;         // BH visual extends full fade radius
          }
      }

      O = mix(O, O*Y, skyBlend);
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
    vec3 scene = texelFetch(BuffA, ivec2(_xy), 0).xyz;
    vec3 bloom = texelFetch(BuffD, ivec2(_xy), 0).xyz;
    vec3 MC    = hsv2rgb(vec3(OFF+.1, .7, 1.));

    vec3 c = scene;
    c -= (length(-1.+2.*_uv)+.2)*FC;
    c += bloom*MC*bloom_amount;
    c  = max(c, 0.);
    c  = tanh_approx(c);
    c  = sqrt(c);

    vec4 M = texture(syn_FinalPass, _uv);
    c = mix(c, M.xyz, motion_blur);

    return vec4(c, 1);
  }
}
