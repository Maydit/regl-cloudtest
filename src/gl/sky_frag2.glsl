#define PI 3.141592

//cloud definition. Higher is better.
#define cSteps 16 //in (1,100+), default 16
#define cjSteps 3 //in (0,15), default 3

//#define EXPENSIVESKY //sky definition.
#define iSteps 16
#define jSteps 8

precision highp float;

varying vec2 uv;

uniform sampler2D perlin;
uniform float   time, 
                coverage, // 0.0 - 1.0
                absorbtion, // >= 1.0
                darkness, // 0.0 - 1.0
                height, // weird stuff happens below 2e3
                thickness; // ~10e2 - ~30e2
uniform float viewportWidth, viewportHeight;
uniform mat4 invProjection, invView;
uniform vec3 sunDirection;

// random/hash function              
float hash(float n) {
  return fract(cos(n) * 41415.92653);
}

//3d noise function from 2d texture -- iq
float noise(in vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	float a = texture2D(perlin, x.xy / 256.0 + (p.z + 0.0) * 120.7123, 0.0).x;
    float b = texture2D(perlin, x.xy / 256.0 + (p.z + 1.0) * 120.7123, 0.0).x;
	return mix(a, b, f.z);
}

// Fractional Brownian motion
float fbm(vec3 p) {
    float f = 0.5101 * noise(p); 
    p *= 2.02;
    f += 0.2473 * noise(p); 
    p *= 2.01;
    f += 0.1247 * noise(p); 
    p *= 2.04;
    f += 0.0614 * noise(p);
    return f;
}

float getDensity(vec3 pos) {
    pos.x += time * 10.0;
    vec3 h = pos * 0.00114 * 0.5; //scaling factor. Smaller = larger clouds
	float dens = fbm(h);
	float cov = 1.0 - coverage;
	dens *= smoothstep (cov, cov + .05, dens);
	return smoothstep(0.3, 1.0, dens) * .9; //arbitrary choice of 0.3. 0.0 might look better.
}

float getLight(vec3 pos, vec3 sunDir) {
    float T = 1.0;
    float sampleDistance = 5.0;
    for(int j = 0; j < cjSteps; j++) {
        vec3 currPos = pos + sunDir * sampleDistance * (float(jSteps) + 0.5); 
        float dens = getDensity(currPos);
        float T_i = exp(-absorbtion * dens * sampleDistance);
	    T *= T_i;
    }
    //take one more sample far away
    vec3 farPos = pos + sunDir * 111.1;
    float dens = getDensity(farPos);
    float T_i = exp(-absorbtion * dens * sampleDistance);
	T *= T_i;
    return T;
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

vec3 sampleAtmosphere(vec3 position, vec3 sunDirection) {
    //heights
    const vec3 eyePos = vec3(0, 6372e3, 0);
    const float atmosphereStart = 6371e3;
    float cloudStart = 6371e3 + height;
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

    vec3 ambientColor = vec3(135, 206, 235); //sky blue
    
    #ifdef EXPENSIVESKY
        const float sunIntensity = 33.0;
        const vec3 kRlh = vec3(5.5e-6, 13.0e-6, 22.4e-6);
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
        if(c > 0.0) {
            //facing sun, add sun
            float X = 1.0 + 0.0015 * tan(PI*c/2.0);
            ambientColor = X * sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
        } else {
            ambientColor = sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
        } 
    #else
        //cheaper sky colors.
        ambientColor = vec3(0.01, 0.01, 0.2);
        if(sunDir.y > -0.1) {
            float screenHeight = (2.0 * gl_FragCoord.y - viewportHeight) / viewportHeight;
            ambientColor = mix(vec3(0.78, 0.78, 0.7), vec3(0.3, 0.4, 0.5), 0.5 * screenHeight + 0.5);
            ambientColor = mix(vec3(1.0, 0.3, 0.0), ambientColor, smoothstep(0.0, 0.175, sunDir.y)); //sunrise
            if(sunDir.y < 0.0) {
                ambientColor = mix(vec3(0.01, 0.01, 0.2), ambientColor, smoothstep(-0.1, 0.0, sunDir.y)); //beneath azimuth
            }
            //add sun
            if(c > 0.0) {
                float X = 1.0 + 0.0015 * tan(PI*c/2.0);
                ambientColor *= X;
            }
        }
    #endif
    //go to edge of clouds
    p = ray_vs_sphere(eyePos, r, cloudStart);
    vec3 intermediatePos = eyePos + r * p.y;
    vec4 color = vec4(0);
    p = ray_vs_sphere(intermediatePos, r, cloudEnd);

    float distanceBias = pow(1.0 - 0.7 * r.y, 15.0); //horizon
    //only draw clouds above us and close-ish
    if(r.y > 0.0 && distanceBias < .98) {
        float cStepSize =  p.y / float(cSteps);
        float cInit = hash(time * 100.0 + gl_FragCoord.x + gl_FragCoord.y * 1098.0); //dithering
        cInit *= cStepSize;
        for (int i = 0; i < cSteps; i++) {
            if(color.w > .99) break;
            float sampleDistance = cInit + float(i) * cStepSize;
            vec3 cloudPos = intermediatePos + r * sampleDistance - vec3(0, atmosphereStart, 0);
            float density = getDensity(cloudPos);
            vec3 localColor = vec3(1.0);
            if(density > 0.01) {
                float light = getLight(cloudPos, sunDir);
                localColor = mix(vec3(1.0 - darkness), vec3(1.0), light);
                //add a little bit of color to the shadows
                localColor.r = mix(max(ambientColor, localColor), localColor, light).r;
                localColor.g = mix(max(ambientColor * 0.5, localColor), localColor, exp(-density * density)).g;
                //clouds should not be white at night
                localColor *= smoothstep(0.0, 1.0, ambientColor.b);
            }
            density = (1.0 - color.w) * density;
            color += vec4(localColor * density, density);
        }
        color.rgb /= (0.0001 + color.w);
    }
    return mix(ambientColor, color.rgb, color.w * (1.0-distanceBias));
}

void main() {
    vec4 farRay = invView * invProjection * vec4(uv, 1, 1);
    vec4 nearRay = invView * invProjection * vec4(uv, 0, 1);
    vec3 position = normalize(farRay.xyz * nearRay.w - nearRay.xyz * farRay.w);

    vec3 c = sampleAtmosphere(position, sunDirection);

    gl_FragColor = vec4(c, 1);
}