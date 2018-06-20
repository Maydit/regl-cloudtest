#define PI 3.141592
#define iSteps 16
#define cSteps 32
#define jSteps 8

precision highp float;

varying vec2 uv;

uniform sampler2D perlin;
uniform float viewportWidth, viewportHeight;
uniform mat4 invProjection, invView;


vec3 sampleAtmosphere(vec3 position, vec3 sunDirection);
vec2 ray_vs_sphere(vec3 pos, vec3 dir, float sr);
float testDensity(vec3 pos);
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
    const vec3 eyePos = vec3(0, 6371.01e3, 0);
    const float atmosphereStart = 6371e3;
    const float cloudStart = 6373e3;
    const float cloudEnd = 6377e3;
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

    //raytrace 4 sample before clouds, 24 in cloud, 4 after clouds.
    float iStepSize = (p.y - p.x) / float(iSteps / 2);
    float iTime = 0.0;

    vec3 totalRlh = vec3(0,0,0);
    vec3 totalMie = vec3(0,0,0);

    float iOdRlh = 0.0;
    float iOdMie = 0.0; 
    //16 samples before clouds
    vec3 intermediatePos = eyePos;
    for (int i = 0; i<iSteps; i++) {
        vec3 iPos = intermediatePos + r * (iTime + iStepSize * 0.5);
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
    p = ray_vs_sphere(eyePos, r, cloudEnd);
    p.y = min(p.y, ray_vs_sphere(eyePos, r, cloudStart).x);
    intermediatePos = eyePos + r * (p.y - p.x);
    //32 ? samples within clouds

    float T = 1.0;
    vec3 C = vec3(0,0,0);
    float alpha = 0.0;

    float cTime = 0.0;
    p = ray_vs_sphere(intermediatePos, r, cloudEnd);
    p.y = min(p.y, ray_vs_sphere(intermediatePos, r, cloudStart).x);
    float cStepSize = (p.y - p.x) / float(cSteps);
    for (int i=0;i<cSteps;i++) {
        vec3 iPos = intermediatePos + r * (cTime + cStepSize * 0.5);
        float density = testDensity(iPos);
        //if(density > 0.01) {
            float T_i = exp(-1.030725 * density * cStepSize);
            T *= T_i;
            //if(T < 0.001) break;
            float light = getLight(iPos,sunDir);
            C += T * light * density * cStepSize;
            alpha += (1. - T_i) * (1. - alpha);
        //}
    }
    
    vec3 ambientColor = vec3(135, 206, 235); //sky blue
    if(c > 0.0) {
        //facing sun, add sun
        float X = 1.0 + 0.0015 * tan(PI*c/2.0);
        ambientColor = X * sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
    } else {
        ambientColor = sunIntensity * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
    }
    return mix(ambientColor, C/(0.000001+alpha), alpha);
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
    float height = pos.y / float(6700e3);
    return mapped * height + 0.0001;
}

float getLight(vec3 pos, vec3 sunDir) {
    float T = 1.0;
    float sampleDistance = 111.1;
    for(int j=0;j<jSteps;j++) {
        vec3 currPos = pos + sunDir * (sampleDistance * (float(jSteps) + 0.5)); 
        float dens = testDensity(currPos);
        float T_i = exp(-1.030725 * dens * sampleDistance);
	    T *= T_i;
    }
    return T;
}