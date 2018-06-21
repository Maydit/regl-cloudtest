#define PI 3.141592
#define iSteps 16
#define jSteps 8
#define cSteps 32 //in (1,100+), default 8
#define cjSteps 3 //in (0,15), default 3
#define COVERAGE 0.5 //in (0.0,1.0), default 0.5
#define ABSORB 1.207523 // must be >= 1.0, default 1.207523
#define DARKNESS 0.5 // in (0.0,1.0), default 0.88

precision highp float;

varying vec2 uv;

uniform sampler2D perlin;
uniform float time;
uniform float viewportWidth, viewportHeight;
uniform mat4 invProjection, invView;


vec3 sampleAtmosphere(vec3 position, vec3 sunDirection);
vec2 ray_vs_sphere(vec3 pos, vec3 dir, float sr);
float hash( float n );
float getDensity(vec3 pos);
float getLightDensity(vec3 pos);
float getLight(vec3 pos, vec3 sunDir);


void main() {
    vec4 farRay = invView * invProjection * vec4(uv, 1, 1);
    vec4 nearRay = invView * invProjection * vec4(uv, 0, 1);
    vec3 position = normalize(farRay.xyz * nearRay.w - nearRay.xyz * farRay.w);
    vec3 sunDirection = vec3(0.707, 0.707, 1.0);

    vec3 c = sampleAtmosphere(position, sunDirection);

    gl_FragColor = vec4(c, 1);
}

vec3 sampleAtmosphere(vec3 position, vec3 sunDirection) {
    const float sunIntensity = 33.0;
    //heights
    const vec3 eyePos = vec3(0, 6372e3, 0);
    const float atmosphereStart = 6371e3;
    const float cloudStart = 6376.5e3;
    const float cloudEnd = cloudStart + 1e2;
    const float atmosphereEnd = 6471e3;
    //
    const vec3 kRlh = vec3(5.5e-6, 13.0e-6, 22.4e-6);
    const vec3 kMie = vec3(21e-6, 21e-6, 21e-6);
    //
    const float shRlh = 8e3;
    const float shMie = 1.2e3;
    const float g = 0.758;
    //
    vec3 sunDir = normalize(sunDirection);
    vec3 r = normalize(position);

    vec2 p = ray_vs_sphere(eyePos, r, atmosphereEnd);
    if (p.x > p.y) {
        return vec3(0, 0, 0);
    }
    p.y = min(p.y, ray_vs_sphere(eyePos, r, atmosphereStart).x);

    float c = dot(r, sunDir);
    float gg = g*g;
    float cc = c*c;
    float pRlh = 3.0 / (16.0*PI) * (1.0+cc);
    float pMie = 3.0 / (8.0*PI) * ((1.0-gg) * (cc + 1.0)) / (pow(1.0 + gg - 2.0*c*g, 1.5) * (2.0 + gg));

    //raytrace in atmosphere
    float iStepSize = (p.y - p.x) / float(iSteps);
    float iTime = 0.0;

    vec3 totalRlh = vec3(0,0,0);
    vec3 totalMie = vec3(0,0,0);

    float iOdRlh = 0.0;
    float iOdMie = 0.0; 
    //16 samples before clouds
    for (int i = 0; i<iSteps; i++) {
        vec3 iPos = eyePos + r * (iTime + iStepSize * 0.5);
        float iHeight = length(iPos) - atmosphereStart;
        float optic_rlh = exp(-iHeight / shRlh) * iStepSize;
        float optic_mie = exp(-iHeight / shMie) * iStepSize;
        iOdRlh += optic_rlh;
        iOdMie += optic_mie;
        float jStepSize = ray_vs_sphere(eyePos, r, atmosphereEnd).y / float(jSteps);
        float jTime = 0.0;
        float jOdRlh = 0.0;
        float jOdMie = 0.0;
        //shadow resampling
        for (int j = 0; j < jSteps; j++) {
            vec3 jPos = iPos + sunDir * (jTime + jStepSize * 0.5);
            float jHeight = length(jPos) - atmosphereStart;
            float jDens = 0.0;
            jOdRlh += exp(-jHeight / shRlh) * jStepSize;
            jOdMie += exp(-jHeight / shMie) * jStepSize;
            jTime += jStepSize;
        }
        vec3 attn = exp(-(kMie * (iOdMie + jOdMie) + kRlh * (iOdRlh + jOdRlh)));
        totalRlh += optic_rlh * attn;
        totalMie += optic_mie * attn;
        iTime += iStepSize;
    }

    //go to edge of clouds
    p = ray_vs_sphere(eyePos, r, cloudStart);
    vec3 intermediatePos = eyePos + r * p.y;
    vec4 C = vec4(0,0,0,0);
    p = ray_vs_sphere(intermediatePos, r, cloudEnd);
    float distanceBias = atan(p.y); //suuuper far clouds
    //only draw clouds above
    if(r.y > 0.0 && distanceBias > 0.01) {
        float cStepSize =  p.y / float(cSteps);
        float cInit = hash(time*100.0+gl_FragCoord.x+gl_FragCoord.y*1000.0);
        cInit *= cStepSize;
        for (int i=0;i<cSteps;i++) {
            if(C.w > .99) break;
            float sampleDistance = cInit + float(i) * cStepSize;
            vec3 iPos = intermediatePos + r * sampleDistance;
            vec3 adjPos = iPos - vec3(0,atmosphereStart-1e3,0);
            float density = getDensity(adjPos);
            float light = getLight(adjPos,sunDir);
            vec3 localcolor = mix(vec3(1.0-float(DARKNESS)), vec3(1.0,1.0,1.0), light);
            density = (1.0-C.w)*density;
            C += vec4(localcolor*density, density);
        }
        C.rgb /= (0.0001+C.w);
    }
    
    vec3 ambientColor = vec3(135, 206, 235); //sky blue
    if(c > 0.0) {
        //facing sun, add sun
        //float X = 1.0 + 0.0015 * tan(PI*c/2.0);
        float X = 1.0 + 0.0015 * smoothstep(0.7, 1.0, c);
        ambientColor = X * sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
    } else {
        ambientColor = sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
    }
    float t = pow(1.0-0.7*r.y, 15.0)*(distanceBias); //horizon
    return mix(ambientColor, C.rgb, C.w*(1.0-t));
}




vec2 ray_vs_sphere(vec3 pos, vec3 dir, float sr) {
    float a = dot(dir, dir);
    float b = 2.0 * dot(dir, pos);
    float c = dot(pos, pos) - (sr * sr);
    float det = (b*b) - 4.0*a*c;
    // det < 0 indicate no intersect
    if (det < 0.0) {
        return vec2(1e5, -1e5);
    }
    return vec2(
        (-b - sqrt(det))/(2.0*a),
        (-b + sqrt(det))/(2.0*a)
    );
}

float testDensity(vec3 pos) {
    vec2 uv = floor(pos.xz * 1e-3);
    float mapped = mod(uv.x + uv.y, 2.0);
    float height = pos.y / 100.0;
    return mapped * height + 0.0001;
}

// random/hash function              
float hash( float n )
{
  return fract(cos(n)*41415.92653);
}

//3d noise function from 2d texture -- iq
float noise( in vec3 x )
{
    vec3 p = floor(x);
    vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	
	float a = texture2D( perlin, x.xy/256.0 + (p.z+0.0)*120.7123, 0.0 ).x;
    float b = texture2D( perlin, x.xy/256.0 + (p.z+1.0)*120.7123, 0.0 ).x;
	return mix( a, b, f.z );
}

// Fractional Brownian motion
float fbm( vec3 p )
{
    float 
    f = 0.5101*noise( p ); p *= 2.02;
    f += 0.2473*noise( p ); p *= 2.01;
    f += 0.1247*noise( p ); p *= 2.04;
    f += 0.0614*noise( p );
    return f;
}

float getDensity(vec3 pos) {
    pos.x += time*10.0;
    vec3 h = pos * 0.00114 * 0.5;
	float dens = fbm(h);
	float cov = 1. - COVERAGE;
	dens *= smoothstep (cov, cov + .05, dens);
	return smoothstep(0.4, 1.0, dens)*.9;
}

float getLight(vec3 pos, vec3 sunDir) {
    float T = 1.0;
    float sampleDistance = 2.5;
    for(int j=0;j<cjSteps;j++) {
        vec3 currPos = pos + sunDir * (sampleDistance * (float(jSteps) + 0.5)); 
        float dens = getDensity(currPos);
        float T_i = exp(-ABSORB * dens * sampleDistance);
	    T *= T_i;
    }
    //take one more sample far away
    vec3 farPos = pos + sunDir * 111.1;
    float dens = getDensity(farPos);
    float T_i = exp(-ABSORB * dens * sampleDistance);
	T *= T_i;

    return T;
}