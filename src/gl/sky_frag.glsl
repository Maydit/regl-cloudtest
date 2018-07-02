#define CLOUDS
#define SKY

#define PI 3.141592

//to change colors: ctrl + f
//MOON: mooncolordef
//SKY: skycolordef
//CLOUDS: cloudcolordef

//cloud definition. Higher is better.
#define cSteps 16 //in (1,100+), default 16
#define cjSteps 3 //in (0,15), default 3

#define iSteps 16
#define jSteps 8

precision highp float;

varying vec2 uv;

uniform float PASSED;

uniform sampler2D noiseSampler, moonSampler, starSampler;
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

vec2 paraboloid_to_uv(vec3 pos) {
    vec3 r = normalize(pos);
    float u = r.x / (2.0 * (1.0 + r.z)) + 0.5;
    float v = 1.0 - r.y / (2.0 * (1.0 + r.z)) + 0.5;
    return vec2(u,v);
}

float getBrightness(float timeOfDay) {
    //time goes 0.0 - 12.0 day 12.0 - 24.0 night -> 0.0
    float dayNightTransition = smoothstep(11.0, 13.0, timeOfDay) + 1.0 - smoothstep(-1.0, 1.0, timeOfDay) - smoothstep(23.0, 25.0, timeOfDay);
    return clamp(1.0 - 0.65 * dayNightTransition, 0.0, 1.0);
}

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

float getDensity(vec3 pos, float coverage, sampler2D nS) {
    pos.z -= time * 10.0; //wind
    vec3 h = pos * 0.00114 * 0.5; //scaling factor. Smaller = larger clouds
	float dens = fbm(h, nS);
	float cov = 1.0 - coverage;
	dens *= smoothstep (cov, cov + .05, dens);
	return smoothstep(0.3, 1.0, dens) * .9; //arbitrary choice of 0.3. 0.0 might look better.
}

float getLight(vec3 pos, vec3 sunDir, float absorbtion, float coverage, sampler2D nS) {
    float T = 1.0;
    float sampleDistance = 6.0 / float(cjSteps);
    float dither = hash(time * 100.0 + gl_FragCoord.x + gl_FragCoord.y * 1098.0);
    float cInit = dither * sampleDistance;
    for(int j = 0; j < cjSteps; j++) {
        vec3 currPos = pos + sunDir * (cInit + sampleDistance * (float(jSteps) + 0.5)); 
        float dens = getDensity(currPos, coverage, nS);
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

vec4 getAmbientColor( vec3 position, 
                      vec3 sunDirection, 
                      float viewportHeight) {
    //heights
    const vec3 eyePos = vec3(0, 6372e3, 0);
    const float atmosphereStart = 6371e3;
    const float atmosphereEnd = 6471e3;
    
    vec3 sunDir = normalize(sunDirection);
    vec3 r = normalize(position);
    float c = dot(r, sunDir);
    
    vec2 p = ray_vs_sphere(eyePos, r, atmosphereEnd);
    if (p.x > p.y) {
        return vec4(0, 0, 0, 1.0);
    }
    p.y = min(p.y, ray_vs_sphere(eyePos, r, atmosphereStart).x);
    vec3 ambientColor = vec3(0);

    #ifdef SKY
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
            //facing sun, add sun
            float X = 1.0 + 0.0015 * min(tan(PI*c/2.0),2.5e3);
            ambientColor = X * sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
        } else {
            ambientColor = sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
        } 
    #else
        //skycolordef
        //cheaper sky colors.
        //What to change to make the colors nicer:
        const vec3 duskColor = vec3(0.05, 0.05, 0.105);
        const vec3 sunriseColor = vec3(0.96, 0.69, 0.53);
        const vec3 topColor = vec3(0.78, 0.78, 0.7);
        const vec3 botColor = vec3(0.3, 0.4, 0.5);
        ambientColor = duskColor;
        if(sunDir.y > -0.1) {
            float screenHeight = (2.0 * gl_FragCoord.y - viewportHeight) / viewportHeight;
            ambientColor = mix(topColor, botColor, 0.5 * screenHeight + 0.5);
            vec3 sunriseCalcd = mix(sunriseColor, topColor, 0.5 * screenHeight + 0.5);
            ambientColor = mix(sunriseCalcd, ambientColor, smoothstep(0.0, 0.175, sunDir.y)); //sunrise
            if(sunDir.y < 0.0) {
                ambientColor = mix(duskColor, ambientColor, smoothstep(-0.1, 0.0, sunDir.y)); //beneath azimuth
            }
            //add sun
            if(c > 0.0) {
                float X = 1.0 + 0.0015 * min(tan(PI*c/2.0),2.5e3);
                ambientColor *= X;
            }
        }
    #endif
    return vec4(ambientColor, length(ambientColor));
}

//this outputs whether the part of the moon indicated by the
//direction and angle would face the sun in a certain lunar phase
//direction assumed to lie in xy plane
float getMoonColor(vec2 direction, float theta, float lunarPhase) {
    vec3 moonNormal = cos(theta) * vec3(0, 0, -1) + sin(theta) * vec3(direction.x, direction.y, 0);
    float lpDeg = mod(lunarPhase + 4.0, 8.0) / 8.0 * PI * 2.0;
    vec3 fakeSunDir = vec3(sin(lpDeg), 0, cos(lpDeg)); //arbitrary height that makes it look good
    float c = dot(moonNormal, fakeSunDir);
    return smoothstep(0.0,0.2,c);
}

vec4 getStars(vec3 r, sampler2D starSampler, vec3 moonDirection) {
    vec4 starsColor = vec4(0);
    float angle = timeOfDay / 24.0 * PI * 2.0;
    float c = cos(angle), s = sin(angle);
    r.xy = vec2(c * r.x + s * r.y, -s * r.x + c * r.y);
    r *= sign(r.y);
    vec2 uvParaboloid = paraboloid_to_uv(r) * 4.0;
    const float theta = PI / 4.125226;
    const mat2 rotation = mat2(cos(theta), -sin(theta), cos(theta), sin(theta));
    
    vec4 prelimAvg1 = texture2D(starSampler, uvParaboloid);
    vec2 uvTemp = (uvParaboloid + vec2(461.42452, 135.1234) / 512.) * rotation;
    vec4 prelimAvg2 = texture2D(starSampler, uvTemp);
    uvTemp = (uvTemp + vec2(207.1413, 377.136537) / 512.) * rotation;
    vec4 prelimAvg3 = texture2D(starSampler, uvTemp);
    
    starsColor = prelimAvg1 + prelimAvg2 + prelimAvg3;
    starsColor = vec4(vec3(starsColor.r), starsColor.w);
    float twinkle = clamp(0.0, 1.0, (fract(time * 0.01 + 1e6 * (texture2D(noiseSampler, uvParaboloid / 200.0, 1.0).r))));
    starsColor *= 1.0 - twinkle * twinkle;
    starsColor.w *= 0.7;
    return starsColor;
}

vec4 getNighttimeColor(vec3 r, vec3 moonDirection, float lunarPhase, sampler2D moonSampler, sampler2D starSampler) {
    const float moonContrast = 0.6;
    const float moonBrightness = 0.999;
    const float moonSize = .994; //bigger is smaller
    vec4 moonStarsColor = vec4(0);

    vec3 moonDir = normalize(moonDirection);
    if(moonDir == vec3(0,1,0)) {
        moonDir = normalize(vec3(0,1,0.000001)); //we will cross this with 0,1,0 later.
    }
    r = normalize(r);
    float sep = dot(r, moonDir);

    moonStarsColor = getStars(r, starSampler, moonDirection);

    //moon
    if(sep >= moonSize) { //ray facing moon
        //calc if part of moon faces sun
        float thetaNew = acos(sep) / acos(moonSize) * PI / 2.0;
        vec3 projection = normalize(r - sep * moonDir); //project r onto plane defined by moonDir
        vec3 up = vec3(0,1,0);
        vec3 b2 = normalize(cross(up, moonDir)); //generate orthonormal basis
        vec3 b3 = cross(b2, moonDir);
        vec2 direction = vec2(dot(b2,projection),dot(b3,projection)); //determine coordinates relative to that orthonormal basis
        vec2 uv2 = (thetaNew / PI * direction.yx) + vec2(0.5);
        vec4 moonColor = vec4(texture2D(moonSampler, uv2, 0.0).rgb,1.0);
        moonColor = mix(moonColor, vec4(1.0,1.0,1.0,1.0), 1.0 - moonContrast); //blend in some white
        moonColor *= vec4(vec3(moonBrightness), 1.0);
        moonColor.rgb *= clamp(vec3(getMoonColor(direction, thetaNew, lunarPhase)) + 0.35, 0.0, 1.0);
        moonColor.w *= smoothstep(0.0,moonSize - 0.01,sep);
        moonColor.w *= length(moonColor.rgb);
        moonStarsColor = moonColor;
    }

    return moonStarsColor;
}

vec3 sampleAtmosphere(  
                        vec3 position, 
                        float timeOfDay,
                        float lunarPhase,
                        float viewportHeight,
                        sampler2D moonSampler,
                        sampler2D starSampler,
                        sampler2D noiseSampler,
                        float time, 
                        float coverage, // 0.0 - 1.0
                        float absorbtion, // >= 1.0
                        float darkness, // 0.0 - 1.0
                        float height, // weird stuff happens below 2e3
                        float thickness,
                        bool clouds
                      ) {
    float angle = timeOfDay / 24.0 * 2.0 * PI;
    vec3 sunDirection = vec3(cos(angle), sin(angle), 0);
    vec3 moonDirection = vec3(-cos(angle), -sin(angle), 0);

    const vec3 eyePos = vec3(0, 6372e3, 0);
    const float atmosphereStart = 6371e3;
    float cloudStart = atmosphereStart + height;
    float cloudEnd = cloudStart + thickness;
    const float atmosphereEnd = 6471e3;

    vec3 moonDir = normalize(moonDirection);
    vec3 sunDir = normalize(sunDirection);
    vec3 r = normalize(position);
    vec4 preAmbientColor = getAmbientColor(r, sunDir, viewportHeight);
    vec4 nightColor = getNighttimeColor(r, moonDir, lunarPhase, moonSampler, starSampler);
    vec3 ambientColor = mix(preAmbientColor.rgb, nightColor.rgb, nightColor.w * (1.0 - smoothstep(0.0, 0.38, preAmbientColor.w)));

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
            float cInit = hash(time + gl_FragCoord.x + gl_FragCoord.y * 1098.0); //dithering
            cInit *= cStepSize;
            float sunBrightness = getBrightness(timeOfDay);
            for (int i = 0; i < cSteps; i++) {
                if(color.w > .99) break;
                float sampleDistance = cInit + float(i) * cStepSize;
                vec3 cloudPos = intermediatePos + r * sampleDistance - vec3(0, atmosphereStart, 0);
                float density = getDensity(cloudPos, coverage, noiseSampler);
                vec3 localColor = vec3(1.0);
                if(density > 0.001) {
                    float light = getLight(cloudPos, sunDir, absorbtion, coverage, noiseSampler);
                    localColor = mix(localColor * light, vec3(1.0, 1.0, 1.0), 1.0 - darkness); //cloudcolordef - vec3(1.0) specifically
                    //localColor *= light * cStepSize * (1.0 - darkness) * sunBrightness;
                    //darker at night
                    localColor *= sunBrightness;
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

    bool clouds = false;
    #ifdef CLOUDS
    clouds = true;
    #endif

    vec3 c = sampleAtmosphere(
                        position, 
                        timeOfDay,
                        lunarPhase,
                        viewportHeight,
                        moonSampler,
                        starSampler,
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