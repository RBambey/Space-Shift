//Cloud Ten by nimitz (twitter: @stormoid)

float time = script_time * 0.0002;  // cam_z (via script_time) → city UV scroll

float sunPos = sun_position-0.3;

float depthOfCross = -10;

mat2 mm2(in float a){float c = cos(a), s = sin(a);return mat2(c,s,-s,c);}
float noise(float t){return texture(colornoise,vec2(t,.0)/vec2(256,256)).x;}

float noise(in vec3 x) //3d noise from iq
{
    vec3 p = floor(x);
    vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	vec2 uv = (p.xy+vec2(37.0,17.0)*p.z) + f.xy;
	vec2 rg = 2.0*(texture( colornoise, (uv+ 0.5)/256.0, -100.0 ).yx)*1.1;
	return mix( rg.x, rg.y, f.z );
}

float fbm(in vec3 x)
{
    float rz = 0.;
    float a = .35;
    for (int i = 0; i<2; i++)
    {
        rz += noise(x)*a;
        a*=.35;
        x*= 4.;
    }
    return rz;
}

float path(in float x){ return sin(x*0.01-3.1415)*28.+6.5; }
float map(vec3 p){
    return p.y*0.07 + (fbm(p*0.3)-0.1) + sin(p.x*0.24 + sin(p.z*.01)*7.)*0.22+0.15 + sin(p.z*0.08)*0.05;
}

float soundClouds(vec3 p){
    return p.y*0.07 + (fbm(p*0.3+0.1*TIME)-0.1) + sin(p.x*0.24 + cos(p.z*0.05)*7.)*0.22+0.15 + sin(p.z*0.08)*0.05;
}

float marchToFindBkg(in vec3 ro, in vec3 rd)
{
    float precis = .3;
    float h= 1.;
    float d = 0.;
    for( int i=0; i<10; i++ )
    {
        if( abs(h)<precis || d>70. ) break;
        d += h;
        vec3 pos = ro+rd*d;
        pos.y += .5;
	    float res = soundClouds(pos)*7.;
        h = res;
    }
	return d;
}

vec3 lgt = vec3(0);
float mapV( vec3 p ){ return clamp(-soundClouds(p), 0., 1.);}
vec4 marchAboveClouds(in vec3 ro, in vec3 rd, in float t, in vec3 bgc)
{
    vec4 rz = vec4( 0.0 );
    
    for( int i=0; i<70; i++ )
    {
        if(rz.a > 0.99 || t > 200.) break;
        
        vec3 pos = ro + t*rd;
        float den = mapV(pos);
        
        vec4 col = vec4(mix( vec3(.8,.75,.85), vec3(.0), den ),den);
        col.xyz *= mix(bgc*bgc*2.5,  mix(vec3(0.1,0.2,0.55),vec3(.8,.85,.9),sunPos*0.4), clamp( -(den*40.+0.)*pos.y*.03-sunPos*0.5, 0., 1. ) );
        col.rgb += clamp((1.-den*6.) + pos.y*0.13 +.55, 0., 1.)*0.35*mix(bgc,vec3(1),0.7); //Fringes
        col += clamp(den*pos.y*.15, -.02, .0); //Depth occlusion
        col *= smoothstep(0.2+sunPos*0.05,.0,mapV(pos+1.*lgt))*.85+0.15; //Shadows
        
        col.a *= .9;
        col.rgb *= col.a;
        rz = rz + col*(1.0 - rz.a);

        t += max(.4,(2.-den*30.)*t*0.011);
    }

    return clamp(rz, 0., 1.);
}

vec4 marchBelowClouds(in vec3 ro, in vec3 rd, in float t, in vec3 bgc)
{
    vec4 rz = vec4( 0.0 );
    
    for( int i=0; i<70; i++ )
    {
        if(rz.a > 0.99 || t > 200.) break;
        
        vec3 pos = ro + t*rd;
        float den = mapV(pos);
        
        vec4 col = vec4(mix( vec3(.8,.75,.85), vec3(.0), den ),den);
        col.xyz *= mix(bgc*bgc*2.5,  mix(vec3(0.1,0.2,0.55),vec3(.8,.85,.9),sunPos*0.4), clamp( -(den*40.+0.)*pos.y*.03-sunPos*0.5, 0., 1. ) );
        col.rgb += clamp((1.-den*6.) + pos.y*0.13 +.55, 0., 1.)*0.35*mix(bgc,vec3(1),0.7); //Fringes
        col += clamp(den*pos.y*.15, -.02, .0); //Depth occlusion
        col *= smoothstep(0.2+sunPos*0.05,.0,mapV(pos+1.*lgt))*.85+0.15; //Shadows
        
        col.a *= .9;
        col.rgb *= col.a;
        rz = rz + col*(1.0 - rz.a);

        t += max(.4,(2.-den*30.)*t*0.011);
    }

    return clamp(rz, 0., 1.);
}

float pent(in vec2 p){
    vec2 q = abs(p);
    return max(max(q.x*1.176-p.y*0.385, q.x*0.727+p.y), -p.y*1.237)*1.;
}

vec3 flare(vec2 p, vec2 pos) //Inspired by mu6k's lens flare (https://www.shadertoy.com/view/4sX3Rs)
{
	vec2 q = p-pos;
    vec2 pds = p*(length(p))*0.75;
	float a = atan(q.x,q.y);

    float rz = .55*(pow(abs(fract(a*.8+.12)-0.5),3.)*(noise(a*15.)*0.9+.1)*exp2((-dot(q,q)*4.))); //Spokes

    rz += max(1.0/(1.0+32.0*pent(pds+0.8*pos)),.0)*00.2; //Projected ghost (main lens)
    vec2 p2 = mix(p,pds,-.5); //Reverse distort
	rz += max(0.01-pow(pent(p2 + 0.4*pos),2.2),.0)*3.0;
	rz += max(0.01-pow(pent(p2 + 0.2*pos),5.5),.0)*3.0;
	rz += max(0.01-pow(pent(p2 - 0.1*pos),1.6),.0)*4.0;
    rz += max(0.01-pow(pent(-(p2 + 1.*pos)),2.5),.0)*5.0;
    rz += max(0.01-pow(pent(-(p2 - .5*pos)),2.),.0)*4.0;
    rz += max(0.01-pow(pent(-(p2 + .7*pos)),5.),.0)*3.0;

    return vec3(clamp(rz,0.,1.));
}

mat3 rot_x(float a){float sa = sin(a); float ca = cos(a); return mat3(1.,.0,.0,    .0,ca,sa,   .0,-sa,ca);}
mat3 rot_y(float a){float sa = sin(a); float ca = cos(a); return mat3(ca,.0,sa,    .0,1.,.0,   -sa,.0,ca);}
mat3 rot_z(float a){float sa = sin(a); float ca = cos(a); return mat3(ca,sa,.0,    -sa,ca,.0,  .0,.0,1.);}


//PATTERNS

vec2 createTronGrid(vec2 fragCoord)
{
  fragCoord = fract(fragCoord);
  float gridSeed = .5;
  float iterationShade = 0;
  float backgroundOnOff = 0.0;
  float fractalZoom;
  float fragX;

  const int iter = 5;
  for(int i = 0; i < iter; i ++)
  {
    // fractalZoom = 0.5 + (gridSeed - 0.5) * 0.9 * bassHits; //bassShake
    fractalZoom = 0.5 + (gridSeed - 0.5) * 0.9;
    fragX = fragCoord.x - fractalZoom;
    backgroundOnOff += pow(clamp(1.0 - abs(fragX), 0.0, 1.0), 200.0);
    if(fragX > 0.0) {
      fragCoord.x = (fragCoord.x - fractalZoom) / (1.0 - fractalZoom);
      iterationShade += 1.0;
    }
    else {
      gridSeed = fract(gridSeed * 1239.528);
      fragCoord.x = fragCoord.x / fractalZoom;
    }
    fragCoord = fragCoord.yx;
  }
  iterationShade /= float(iter);
  return vec2(backgroundOnOff, iterationShade);
}

const int MAGIC_BOX_ITERS = 15;
const float MAGIC_BOX_MAGIC = 0.55;

float magicBox(vec3 p) {
    // The fractal lives in a 1x1x1 box with mirrors on all sides.
    // Take p anywhere in space and calculate the corresponding position
    // inside the box, 0<(x,y,z)<1
    p = 1.0 - abs(1.0 - mod(p, 2.0));
    
    float lastLength = length(p);
    float tot = 0.0;
    // This is the fractal.  More iterations gives a more detailed
    // fractal at the expense of more computation.
    for (int i=0; i < MAGIC_BOX_ITERS; i++) {
      // The number subtracted here is a "magic" paremeter that
      // produces rather different fractals for different values.
      p = abs(p)/(lastLength*lastLength) - MAGIC_BOX_MAGIC;
      float newLength = length(p);
      tot += abs(newLength-lastLength);
      lastLength = newLength;
    }

    return tot;
}

// A random 3x3 unitary matrix, used to avoid artifacts from slicing the
// volume along the same axes as the fractal's bounding box.
const mat3 M = mat3(0.28862355854826727, 0.6997227302779844, 0.6535170557707412,
                    0.06997493955670424, 0.6653237235314099, -0.7432683571499161,
                    -0.9548821651308448, 0.26025457467376617, 0.14306504491456504);


float stars(vec2 posIn)
{
    // uv are screen coordinates, uniformly scaled to go from 0..1 vertically
    vec2 uv = posIn;

    // Rotate uv onto the random axes given by M, and scale
    // it down a bit so we aren't looking at the entire
    // 1x1x1 fractal volume.  Making the coefficient smaller
    // "zooms in", which may reduce large-scale repetition
    // but requires more fractal iterations to get the same
    // level of detail.
    vec3 p = 0.5*M*vec3(uv, 0.0);
    
    float result = magicBox(p);
    // Scale to taste.  Also consider non-linear mappings.
    result *= 0.03;
    
    return result;
}

vec4 pass0(){
    vec2 q = _xy.xy / RENDERSIZE.xy;

    bool aboveClouds = cam_y >= depthOfCross;

    vec2 p = q - 0.5;
    float asp = RENDERSIZE.x/RENDERSIZE.y;
    p.x *= asp;

    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    const float zoom = 0.5;
    vec3 rd = normalize(cFwd * zoom + cRight * p.x + cUp * p.y);
    vec3 col = vec3(0.);

    lgt = normalize(vec3(-0.3,sunPos+0.1,1.));
    float rdl = clamp(dot(rd, lgt), 0., 1.);

    vec3 hor = mix( vec3(.9,.6,.7)*0.35, vec3(.5,0.05,0.05), rdl );
    hor = mix(hor, vec3(.5,.8,1),sunPos);
    col += mix( vec3(.2,.2,.6), hor, exp2(-(1.+ 3.*(1.-rdl))*max(abs(rd.y),0.)) )*.6;
    col += .8*vec3(1.,.9,.9)*exp2(rdl*650.-650.);
    col += .3*vec3(1.,1.,0.1)*exp2(rdl*100.-100.);
    float midBoost = 1.0 + mid_glow * syn_MidLevel * 3.0;
    col += .5*vec3(1.,.7,0.)*exp2(rdl*50.-50.) * midBoost;
    col += .4*vec3(1.,0.,0.05)*exp2(rdl*10.-10.) * midBoost;
    vec3 bgc = col;

    float rz = marchToFindBkg(ro,rd); //determine if we're in "cloud zone" or bkg zone

    if (aboveClouds == true){

        if (rz < 70.)
        {
            vec4 res = marchAboveClouds(ro, rd, rz-5., bgc);
            col = col*(1.0-res.w) + res.xyz;
        }

        vec3 sunCam = vec3(dot(lgt, cRight), dot(lgt, cUp), dot(lgt, cFwd));
        col += 1.4*vec3(0.7,0.7,0.4)*max(flare(p, sunCam.xy/sunCam.z*zoom)*sunCam.z, 0.0);
    } 
    else {

        if (rz < 70.)
        {
            vec4 res = marchBelowClouds(ro, rd, rz-5., bgc);
            col = col*(1.0-res.w) + res.xyz;
        }
    }

    col = clamp(col, 0., 1.);
    col = col*0.5 + 0.5*col*col*(3.0-2.0*col); //saturation
    col = pow(col, vec3(0.416667))*1.055 - 0.055; //sRGB
    col *= pow( 16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y), 0.12 ); //Vign

    return vec4( col, 1.0 );
}

vec4 pass1(){
    if (city_fps < 0.01){
        return texture(buffer1, _uv);
    }

    vec3 col = texture(buffer1,_uv).rgb;
    //Perspective projection to get "ground" coordinates.
    vec2 uv = _uv;
    float perspv = 1.0;
    float f = 30.;
    uv-= vec2(0.5, 0.25);
    uv.y*= RENDERSIZE.y/RENDERSIZE.x;
    // Rotate city grid to match camera yaw so it stays fixed in world space
    float cameraYaw = atan(cam_fx, cam_fz);
    uv = _rotate(uv, -cameraYaw);
    uv.y/= RENDERSIZE.y/RENDERSIZE.x;
    uv*= exp(0.0555*f);
    float uvy = gl_FragCoord.y/RENDERSIZE.y;
    perspv = 1.-uvy*1.3;
    uv/= perspv;
    uv += vec2(0.5, 0.25);
    // Offset by camera world XZ position projected into camera-aligned UV space
    float cosY = cos(cameraYaw), sinY = sin(cameraYaw);
    uv += vec2( cam_x * cosY + cam_z * sinY,
               -cam_x * sinY + cam_z * cosY) * 0.00004;

    float briMod = smoothstep(0.12, 0.48, perspv);

    vec2 tronData = createTronGrid(uv);
    vec2 space = vec2(syn_HighPresence*0.2,0.0);
    tronData = mix(tronData, space, flip_side);
    float cityLights = tronData.x;
    cityLights += pow(stars(uv),3.0+flip_side*1.0);
    cityLights = clamp(cityLights, 0.0, 1.0);

    vec3 oCol = mix(vec3(0.8, 0.5, 0.2), vec3(syn_BassPresence*0.3+0.5,syn_BassPresence*0.1+0.5,0.5), flip_side);
    vec3 bCol = vec3(0.5, 0.5, 0.67)*1.5;
    float medFBM = _fbm(uv*10.0);

    vec3 finalCol = mix(oCol, bCol, medFBM);
    float bassBoost = 1.0 + bass_city * pow(clamp(syn_BassLevel, 0.0, 1.0), 1.5) * 4.0;
    finalCol *= cityLights * briMod * bassBoost;

    finalCol = pow(finalCol,vec3(1.5));
    float anotherFBM = ((pow(_fbm(uv+vec2(0.0,time*2.0)),2.0)*4.0));
    finalCol *= anotherFBM;

    vec3 mixedCol = col+smoothstep(0.2, 8, clamp(depthOfCross-cam_y-anotherFBM*2.0,0.2,8.0))*finalCol*(1.0-length(col))*3.0;

    mixedCol = mix(col, mixedCol, city_fps);

    return vec4(mixedCol,1.0);
}

vec4 pass2(){
    vec2 pos = _uvc;
    pos = _rotate(pos, PI*flip_side);
    pos = (pos*vec2(1.0,RENDERSIZE.x/RENDERSIZE.y)+1.0)*0.5;
    vec4 col = texture(cityClouds, clamp(pos,0.0,1.0));
    float underwaterBri = pow(length(col)*0.7,4.0);
    float bri2 = clamp(1.0-underwaterBri, 0.0, 0.5);
    if (bri2 < 0.2){
        bri2 = 0.4;
        underwaterBri=0.4;
    }
    col = mix(col, vec4(0.2,0.5,0.8,1.0)*pow(_uv.y*3.0*underwaterBri*bri2,2.5)*7.0, flip_side*clamp(cam_y+15, 0, 1));
    float mask = 1.0;
    if(_isMediaActive()){
        mask = _loadMediaAsMask().r;
    }
    col *= mask;

    return col;
}

vec4 renderMain () {
  if (PASSINDEX == 0) {
    return pass0();
  } else if (PASSINDEX == 1) {
    return pass1();
  } else if (PASSINDEX == 2) {
    return pass2();
  }

}
