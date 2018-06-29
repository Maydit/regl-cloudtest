#define CLOUDS

#define PI 3.141592

//to change colors: ctrl + f
//MOON: mooncolordef
//SKY: skycolordef
//CLOUDS: cloudcolordef

//cloud definition. Higher is better.
#define cSteps 32 //in (1,100+), default 16
#define cjSteps 3 //in (0,15), default 3

#define iSteps 16
#define jSteps 8

precision highp float;

varying vec2 uv;

uniform float PASSED;

uniform sampler2D noiseSampler, moonSampler;
uniform float   time, 
                coverage, // 0.0 - 1.0
                absorbtion, // >= 1.0
                darkness, // 0.0 - 1.0
                height, // weird stuff happens below 2e3
                thickness, // ~10e2 - ~30e2
                lunarPhase, //0.0 - 7.9...
                timeOfDay; //0.0 - 24.0
uniform float viewportWidth, viewportHeight;
uniform mat4 invProjection, invView;

// random/hash function              
float hash(float n) {
  return fract(cos(n) * 41415.92653);
}

//3d noise function from 2d texture -- iq
float noise(in vec3 x, sampler2D noiseSampler) {
    vec3 p = floor(x);
    vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	float a = texture2D(noiseSampler, x.xy / 256.0 + (p.z + 0.0) * 120.7123, 0.0).x;
    float b = texture2D(noiseSampler, x.xy / 256.0 + (p.z + 1.0) * 120.7123, 0.0).x;
	return mix(a, b, f.z);
}

// Fractional Brownian motion
float fbm(vec3 p, sampler2D nS) {
    float f = 0.5101 * noise(p, nS); 
    p *= 2.02;
    f += 0.2473 * noise(p, nS); 
    p *= 2.01;
    f += 0.1247 * noise(p, nS); 
    p *= 2.04;
    f += 0.0614 * noise(p, nS);
    return f;
}

float getDensity(vec3 pos, sampler2D nS) {
    pos.x += time * 10.0;
    vec3 h = pos * 0.00114 * 0.5; //scaling factor. Smaller = larger clouds
	float dens = fbm(h, nS);
	float cov = 1.0 - coverage;
	dens *= smoothstep (cov, cov + .05, dens);
	return smoothstep(0.3, 1.0, dens) * .9; //arbitrary choice of 0.3. 0.0 might look better.
}

float getLight(vec3 pos, vec3 sunDir, sampler2D nS) {
    float T = 1.0;
    float sampleDistance = 6.0 / float(cjSteps);
    float dither = hash(time * 100.0 + gl_FragCoord.x + gl_FragCoord.y * 1098.0);
    float cInit = dither * sampleDistance;
    for(int j = 0; j < cjSteps; j++) {
        vec3 currPos = pos + sunDir * (cInit + sampleDistance * (float(jSteps) + 0.5)); 
        float dens = getDensity(currPos, nS);
        float T_i = exp(-absorbtion * dens * sampleDistance);
	    T *= T_i;
    }
    return T * .9;
}

vec2 ray_vs_sphere(vec3 pos, vec3 dir, float sr) {
    float a = dot(dir, dir);
    float b = 2.0 * dot(dir, pos);
    float c = dot(pos, pos) - (sr * sr);
    float det = (b * b) - 4.0 * a * c;
    // det < 0 indicate no intersect
    if (det < 0.0) {
        return vec2(1e5, -1e5);
    }
    return vec2(
        (-b - sqrt(det))/(2.0*a),
        (-b + sqrt(det))/(2.0*a)
    );
}

vec3 getAmbientColor(vec3 position, vec3 sunDirection) {
    //heights
    const vec3 eyePos = vec3(0, 6372e3, 0);
    const float atmosphereStart = 6371e3;
    float cloudStart = atmosphereStart + height;
    float cloudEnd = cloudStart + thickness;
    const float atmosphereEnd = 6471e3;
    
    vec3 sunDir = normalize(sunDirection);
    vec3 r = normalize(position);
    float c = dot(r, sunDir);
    
    vec2 p = ray_vs_sphere(eyePos, r, atmosphereEnd);
    if (p.x > p.y) {
        return vec3(0, 0, 0);
    }
    p.y = min(p.y, ray_vs_sphere(eyePos, r, atmosphereStart).x);
    vec3 ambientColor = vec3(0);
        const float sunIntensity = 33.0;
        const vec3 kRlh = vec3(5.5e-6, 13.0e-6, 22.4e-6); //skycolordef
        const vec3 kMie = vec3(21e-6, 21e-6, 21e-6);
        const float shRlh = 8e3;
        const float shMie = 1.2e3;
        const float g = 0.758;
        
        float gg = g*g;
        float cc = c*c;
        float pRlh = 3.0 / (16.0*PI) * (1.0+cc);
        float pMie = 3.0 / (8.0*PI) * ((1.0-gg) * (cc + 1.0)) / (pow(1.0 + gg - 2.0*c*g, 1.5) * (2.0 + gg));
        
        float iStepSize = (p.y - p.x) / float(iSteps);
        float iTime = 0.0;

        vec3 totalRlh = vec3(0,0,0);
        vec3 totalMie = vec3(0,0,0);

        float iOdRlh = 0.0;
        float iOdMie = 0.0;

        for (int i = 0; i<iSteps; i++) {
            vec3 iPos = eyePos + r * (iTime + iStepSize * 0.5);
            float iHeight = length(iPos) - atmosphereStart;
            float optic_rlh = exp(-iHeight / shRlh) * iStepSize;
            float optic_mie = exp(-iHeight / shMie) * iStepSize;
            iOdRlh += optic_rlh;
            iOdMie += optic_mie;
            //accumulators for inner sampling
            float jStepSize = ray_vs_sphere(eyePos, r, atmosphereEnd).y / float(jSteps);
            float jTime = 0.0;
            float jOdRlh = 0.0;
            float jOdMie = 0.0;
            //shadow resampling
            for (int j = 0; j < jSteps; j++) {
                vec3 jPos = iPos + sunDir * (jTime + jStepSize * 0.5);
                float jHeight = length(jPos) - atmosphereStart;
                jOdRlh += exp(-jHeight / shRlh) * jStepSize;
                jOdMie += exp(-jHeight / shMie) * jStepSize;
                jTime += jStepSize;
            }
            vec3 attn = exp(-(kMie * (iOdMie + jOdMie) + kRlh * (iOdRlh + jOdRlh)));
            totalRlh += optic_rlh * attn;
            totalMie += optic_mie * attn;
            iTime += iStepSize;
        }
    if(c > 0.0) {
        float factor = tan(PI * c / 2.0) * c / 0.5;
        factor = min(factor, 4.0 / 0.0015);
        float X = 1.0 + 0.0015 * factor;
        ambientColor = X * sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
    } else {
        ambientColor = sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
    }
    return ambientColor;
}

//this outputs whether the part of the moon indicated by the
//direction and angle would face the sun in a certain lunar phase
//direction assumed to lie in xy plane
float getMoonColor(vec2 direction, float theta, float lunarPhase) {
    vec3 moonNormal = cos(theta) * vec3(0, 0, -1) + sin(theta) * vec3(direction.x, direction.y, 0);
    float lpDeg = mod(lunarPhase, 8.0) / 8.0 * PI * 2.0;
    vec3 fakeSunDir = vec3(sin(lpDeg), 0, cos(lpDeg)); //arbitrary height that makes it look good
    float c = dot(moonNormal, fakeSunDir);
    return smoothstep(0.0,0.05,c);
}

vec3 getNighttimeColor(vec3 r, vec3 moonDirection, float lunarPhase, sampler2D moonSampler) {
    const float moonContrast = 0.6;
    const float moonBrightness = 0.5;
    const float moonSize = .99; //bigger is smaller
    vec3 moonDir = normalize(moonDirection);
    if(moonDir == vec3(0,1,0)) {
        moonDir = normalize(vec3(0,1,0.000001)); //we will cross this with 0,1,0 later.
    }
    r = normalize(r);
    float sep = dot(r, moonDir);

    if(sep >= moonSize) { //ray facing moon
        //calc if part of moon faces sun
        float thetaNew = acos(sep) / acos(moonSize) * PI / 2.0;
        vec3 projection = normalize(r - sep * moonDir); //project r onto plane defined by moonDir
        vec3 up = vec3(0,1,0);
        vec3 b2 = normalize(cross(up, moonDir)); //generate orthonormal basis
        vec3 b3 = cross(b2, moonDir);
        vec2 direction = vec2(dot(b2,projection),dot(b3,projection)); //determine coordinates relative to that orthonormal basis
        vec2 uv2 = (thetaNew / PI * direction.yx) + vec2(0.5);
        vec3 moonColor = vec3(texture2D(moonSampler, uv2, 0.0).r);
        moonColor = mix(moonColor, vec3(1.0,1.0,1.0), 1.0 - moonContrast); //blend in some white
        moonColor *= vec3(getMoonColor(direction, thetaNew, lunarPhase));
        moonColor *= vec3(1.0,0.9,0.4); //mooncolordef
        moonColor *= vec3(moonBrightness);
        return smoothstep(0.0,0.005,(sep-moonSize)) * moonColor;
    } return vec3(0);
}

vec3 sampleAtmosphere(  
                        vec3 position, 
                        vec3 sunDirection,
                        bool day,
                        float lunarPhase,
                        float viewportHeight,
                        sampler2D noiseSampler,
                        float time, 
                        float coverage, // 0.0 - 1.0
                        float absorbtion, // >= 1.0
                        float darkness, // 0.0 - 1.0
                        float height, // weird stuff happens below 2e3
                        float thickness,
                        bool clouds
                      ) {
    const vec3 eyePos = vec3(0, 6372e3, 0);
    const float atmosphereStart = 6371e3;
    float cloudStart = atmosphereStart + height;
    float cloudEnd = cloudStart + thickness;
    const float atmosphereEnd = 6471e3;

    vec3 sunDir = normalize(sunDirection);
    vec3 r = normalize(position);

    vec3 ambientColor = getAmbientColor(r, sunDir);
    if(!day) {
        ambientColor = getNighttimeColor(r, sunDir, lunarPhase, moonSampler);
    }

    vec4 color = vec4(0);
    float distanceBias = pow(1.0 - 0.7 * r.y, 15.0); //horizon
    if(clouds) {
        //go to edge of clouds
        vec2 p = ray_vs_sphere(eyePos, r, cloudStart);
        vec3 intermediatePos = eyePos + r * p.y;
        p = ray_vs_sphere(intermediatePos, r, cloudEnd);
        //only draw clouds above us and close-ish
        if(r.y > 0.0 && distanceBias < .98) {
            float cStepSize =  p.y / float(cSteps);
            float cInit = hash(time * 100.0 + gl_FragCoord.x + gl_FragCoord.y * 1098.0); //dithering
            cInit *= cStepSize;
            for (int i = 0; i < cSteps; i++) {
                if(color.w > .99) break;
                float sampleDistance = cInit + float(i) * cStepSize;
                vec3 cloudPos = intermediatePos + r * sampleDistance - vec3(0, atmosphereStart, 0);
                float density = getDensity(cloudPos, noiseSampler);
                vec3 localColor = vec3(1.0);
                if(density > 0.001) {
                    float light = getLight(cloudPos, sunDir, noiseSampler);
                    localColor = mix(localColor * light, vec3(1.0, 1.0, 1.0), 1.0 - darkness); //cloudcolordef - vec3(1.0) specifically
                    //localColor *= light * cStepSize * (1.0 - darkness);
                    //clouds should not be white at night
                    localColor *= smoothstep(0.0, 1.0, length(ambientColor));
                }
                density = (1.0 - color.w) * density;
                color += vec4(localColor * density, density);
            }
            color.rgb /= (0.0001 + color.w);
        }
    }
    return mix(ambientColor, color.rgb, color.w * (1.0-distanceBias));
}

void main() {
    vec4 farRay = invView * invProjection * vec4(uv, 1, 1);
    vec4 nearRay = invView * invProjection * vec4(uv, 0, 1);
    vec3 position = normalize(farRay.xyz * nearRay.w - nearRay.xyz * farRay.w);

    float angle = timeOfDay / 24.0 * 2.0 * PI;

    vec3 sunDirection = vec3(cos(angle), sin(angle), 0);
    bool day = true;
    if(sunDirection.y < -0.1) {
        day = false;
        sunDirection = vec3(-cos(angle), -sin(angle), 0);
    }

    bool clouds = false;
    #ifdef CLOUDS
    clouds = true;
    #endif

    vec3 c = sampleAtmosphere(
                        position, 
                        sunDirection,
                        day,
                        lunarPhase,
                        viewportHeight,
                        noiseSampler,
                        time, 
                        coverage, // 0.0 - 1.0
                        absorbtion, // >= 1.0
                        darkness, // 0.0 - 1.0
                        height, // weird stuff happens below 2e3
                        thickness,
                        clouds
                      );

    gl_FragColor = vec4(c, 1);
}