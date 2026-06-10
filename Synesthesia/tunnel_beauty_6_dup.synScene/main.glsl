vec4 iMouse = vec4(720, 720, 0.0, 0.0); 

vec3 tex3D( sampler2D tex, in vec3 p, in vec3 n ){
   
    n = max(abs(n), 0.001); // n = max((abs(n) - 0.2)*7., 0.001); // n = max(abs(n), 0.001), etc.
    n /= (n.x + n.y + n.z); 
    return (texture(tex, p.yz)*n.x + texture(tex, p.zx)*n.y + texture(tex, p.xy)*n.z).xyz;
    
}

vec3 filter_() {
  vec2 delta = 1. / RENDERSIZE;
  
  vec3 val = texture(toFilter, _uv).xyz;


  vec3 l = texture(toFilter, _uv + vec2(0., delta.y)).xyz;
  vec3 r = texture(toFilter, _uv - vec2(0., delta.y)).xyz;
  vec3 u = texture(toFilter, _uv + vec2(delta.x, 0.)).xyz;
  vec3 d = texture(toFilter, _uv - vec2(delta.x, 0.)).xyz;

  vec3 n = vec3(_rand(_uvc+fract(TIME))) - 0.5;
  
  vec3 bloom = max(val, max(max(l, r), max( u, d)));
  bloom = bloom  + l + r + u + d;
  bloom /= 5.; // orlando;
  return bloom + n/9.;

}
// Created by Stephane Cuillerdier - @Aiekick/2016
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.

// 2D path displacement.
vec2 path(in float x){
    
    //return vec2(0); // Trivial, straight path.
    //return vec2(cos(x*0.25)*1.8 + cos(x*0.15)*2., 0); // Perturbing "X" only.
    // return vec2(cos(x*0.25)*1.8 + cos(x*0.15)*1.5, sin(x*0.25)*1.2 + sin(x*0.15) + tan(x*0.5)); // Perturbing "X" and "Y."
    return vec2(cos(x*0.25)*1.8 + cos(x*0.15)*1.5, sin(x*0.25)*1.2 + sin(x*0.15)); // Perturbing "X" and "Y."

}

// Camera path. Arranged to coincide with the frequency of the tunnel.
vec3 camPath(float t){
  
    return vec3(path(t), t*15.0);
    
}

mat3 RotZ(float a)
{
    return mat3(cos(a),-sin(a),0.,sin(a),cos(a),0.,0.,0.,1.);
}

vec3 rotateX(vec3 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return vec3(p.x, c*p.y+s*p.z, -s*p.y+c*p.z);
}
vec3 rotateY(vec3 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return vec3(c*p.x-s*p.z, p.y, s*p.x+c*p.z);
}
vec3 rotateZ(vec3 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return vec3(c*p.x+s*p.y, -s*p.x+c*p.y, p.z);
}

float df(vec3 p)
{
	vec3 q = p;

  q.xy += cos(TIME * 1.0+syn_HighTime);
	q *= RotZ(q.z * 0.1);
  q += mix(vec3(0.0), sin(q.zxy * 0.5) * 0.5, simplify);
	q = mix(q, q*RotZ(q.z * 0.2), simplify);
  q = sin(q.zxy * 0.2) * 1.5;
  p += q;

	p = mix(p, p*RotZ(p.z * 0.045+q.x*churner), flatten);
  return diameter*40.0 - abs(p.y*0.5);
}

vec3 nor( vec3 pos, float prec )
{
	vec3 eps = vec3( prec, 0., 0. );
	vec3 nor = vec3(
	    df(pos+eps.xyy) - df(pos-eps.xyy),
	    df(pos+eps.yxy) - df(pos-eps.yxy),
	    df(pos+eps.yyx) - df(pos-eps.yyx) );
	return normalize(nor);
}

// return color from temperature 
//http://www.physics.sfasu.edu/astro/color/blackbody.html
//http://www.vendian.org/mncharity/dir3/blackbody/
//http://www.vendian.org/mncharity/dir3/blackbody/UnstableURLs/bbr_color.html
vec3 blackbody(float Temp)
{
	vec3 col = vec3(255.);
    col.x = 560100000. * pow(Temp,(-3. / 2.)) + 148.;
   	col.y = 100.04 * log(Temp) - 623.6;
   	if (Temp > 6500.) col.y = 35200000. * pow(Temp,(-3. / 2.)) + 184.;
   	col.z = 194.18 * log(Temp) - 1448.6;
   	col = clamp(col, 0., 255.)/255.;
    if (Temp < 10.) col *= Temp/10.;
   	return col;
}

// get density of the df at surfPoint
// ratio between constant step and df value
float SubDensity(vec3 surfPoint, float prec, float ms) 
{
	vec3 n;
	float s = 0.;
    const int iter = 10;
	for (int i=0;i<iter;i++)
	{
		n = nor(surfPoint,prec); 
		surfPoint = surfPoint - n * ms; 
		s += df(surfPoint);
	}
	
	return 1.-s/(ms*float(iter)); // s < 0. => inside df
}

float SubDensity(vec3 p, float s) 
{
	vec3 n = nor(p,s); 							// precise normale at surf point
	return df(p - n * s);						// ratio between df step and constant step
}

vec4 renderMainImage() {
	vec4 fragColor = vec4(0.0);
	vec2 fragCoord = _xy;

	vec2 g = fragCoord;
	vec2 si = RENDERSIZE.xy;
	vec2 uv = (g+g-si)/si.y;

	vec3 ro = vec3(0, 0, warp_time);
	ro.xy += vec2(sin(ro.z));
	vec3 cv = ro + vec3(0,0,1);
	vec3 cu = normalize(vec3(0,1,0));
	vec3 z = normalize(cv-ro);
	vec3 x = normalize(cross(cu,z));
	vec3 y = cross(z,x);
	float fov = .9+fov_in;
	vec3 rd = normalize(fov * (uv.x * x + uv.y * y) + z);
	rd = rotateX(rd, warp_pitch*PI);
	rd = rotateY(rd, -warp_yaw*PI);
	rd = rotateZ(rd, warp_roll);
	
	float perturbedAmt = pow(syn_Presence,1.5);

	float s = 1., d = 0.;
	for (int i=0; i<90; i++) 
	{
		ro = vec3(0, 0, warp_time);
		ro.xy += vec2(sin(d*0.25),cos(d*0.25))*5.0*perturbedAmt;
		if (log(d*d/s/1e5)>0.) break;
		d += (s=df(ro+rd*d))*.2;
	}
	
	vec3 p = ro + rd * d;											// surface point
	vec3 lid = normalize(ro-p); 									// light dir
	vec3 n = nor(p, 0.1);											// normal at surface point
	vec3 refl = reflect(rd,n);										// reflected ray dir at surf point 
	float diff = clamp( dot( n, lid ), 0.0, 1.0 ); 					// diffuse
	float fre = pow( clamp( 1. + dot(n,rd),0.0,1.0), 4. ); 			// fresnel
	float spe = pow(clamp( dot( refl, lid ), 0.0, 1.0 ),16.);		// specular
	vec3 col = vec3(.8,.5,.2);
    
    // here the magic happen
	float sss = df(p - n*pow(deeper_colors,2.0))/0.1;								// quick sss 0.001 of subsurface
	
	float sb = SubDensity(p, 0.01, 0.1);							// deep subdensity from 0.01 to 0.1 (10 iterations)
	vec3 bb = clamp(blackbody(200. * sb),0.,1.);					// blackbody color
	float sss2 = 0.8 - SubDensity(p, 3.); 							// one step sub density of df of 3 of subsurface

  fragColor.rgb = (diff + fre + bb * sss2 * .8 + col * sss * .2) * 0.25 + spe * 1.2;

  // fragColor.rgb*=0.5;
  if (sb>0.05){
  	fragColor.rgb*=mix(syn_BassPresence*_pulse(fract(TIME+p.z*0.01)*1.5, 0.8, 0.2),1.0,col_presence);
  }
  if (sb<0.05){
  	fragColor.rgb*=mix(syn_OnBeat,1.0,col_presence);
  }
  fragColor.rgb += tex3D(syn_Media, p*0.01+0.5, n)*syn_Presence*0.9*_pulse(fract(-syn_BPMSin4+p.z*0.01), 0.5, media_width);

	// vigneting from iq Shader Mike : https://www.shadertoy.com/view/MsXGWr
  vec2 q = g/si;
  fragColor.rgb *= 0.5 + 0.5*pow( 16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y), 0.55 );

	return fragColor; 
 } 


vec4 renderMain(){
	if(PASSINDEX == 0){
		return renderMainImage();
	}
	if (PASSINDEX == 1){
		// return texture()
		return vec4(filter_(), 1.0);
	}
}
