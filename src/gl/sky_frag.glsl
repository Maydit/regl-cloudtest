#define PI 3.141592
#define iSteps 16
#define jSteps 8

precision highp float;

varying vec2 uv;

uniform float viewportWidth, viewportHeight;
uniform mat4 invProjection, invView;

//DEF FUNCS
vec3 atmosphere(
    vec3 r, 
    vec3 eyePos, 
    vec3 sunDir, 
    float iSun, 
    float rPlanet, 
    float rAtmos, 
    vec3 kRlh, 
    float kMie, 
    float shRlh, 
    float shMie, 
    float g);
vec2 ray_vs_sphere(vec3 pos, vec3 dir, float sr);
vec3 sampleAtmosphere (
    vec3 ray,
    vec3 sunDirection);




void main() {
    vec4 farRay = invView * invProjection * vec4(uv, 1, 1);
    vec4 nearRay = invView * invProjection * vec4(uv, 0, 1);
    vec3 position = normalize(farRay.xyz * nearRay.w - nearRay.xyz * farRay.w);
    vec3 sunDirection = vec3(1.0,0.0,1.0);

    vec3 c = sampleAtmosphere(position, sunDirection);

    gl_FragColor = vec4(c, 1);
}

vec3 sampleAtmosphere (
    vec3 ray,
    vec3 sunDirection) {
    return atmosphere(
                    ray,
                    vec3(0, 6372e3, 0),
                    sunDirection,
                    33.0,
                    6371e3,
                    6471e3,
                    vec3(5.5e-6, 13.0e-6, 22.4e-6),
                    // vec3( 22.0e-6, 13.0e-6, 11.4e-6), // mars
                    21e-6,
                    8e3,
                    1.2e3,
                    0.758
                  );
}

vec3 atmosphere(
    vec3 r, 
    vec3 eyePos, 
    vec3 sunDir, 
    float iSun, 
    float rPlanet, 
    float rAtmos, 
    vec3 kRlh, 
    float kMie, 
    float shRlh, 
    float shMie, 
    float g) {
  sunDir = normalize(sunDir);
  r = normalize(r);

  vec2 p = ray_vs_sphere(eyePos, r, rAtmos);
  if (p.x > p.y) {
    return vec3(0, 0, 0);
  }

  p.y = min(p.y, ray_vs_sphere(eyePos, r, rPlanet).x);
  float iStepSize = (p.y - p.x) / float(iSteps);

  float iTime = 0.0;

  vec3 totalRlh = vec3(0,0,0);
  vec3 totalMie = vec3(0,0,0);

  float iOdRlh = 0.0;
  float iOdMie = 0.0;

  // compute phase of Rayleigh and Mie
  // c: Scattering angle
  float c = dot(r, sunDir);
  float gg = g*g;
  float cc = c*c;
  float pRlh = 3.0 / (16.0*PI) * (1.0+cc);
  float pMie = 3.0 / (8.0*PI) * ((1.0-gg) * (cc + 1.0)) / (pow(1.0 + gg - 2.0*c*g, 1.5) * (2.0 + gg));

  // samples
  // todo: add early exit
  for (int i = 0; i<iSteps; i++) {
    vec3 iPos = eyePos + r * (iTime + iStepSize * 0.5);
    float iHeight = length(iPos) - rPlanet;

    float optic_rlh = exp(-iHeight / shRlh) * iStepSize;
    float optic_mie = exp(-iHeight / shMie) * iStepSize;

    // Accumulate optical depth.
    iOdRlh += optic_rlh;
    iOdMie += optic_mie;

    float jStepSize = ray_vs_sphere(eyePos, r, rAtmos).y / float(jSteps);

    float jTime = 0.0;

    // Initialize optical depth accumulators for the secondary ray.
    float jOdRlh = 0.0;
    float jOdMie = 0.0;

    for (int j = 0; j < jSteps; j++) {
      vec3 jPos = iPos + sunDir * (jTime + jStepSize * 0.5);

      float jHeight = length(jPos) - rPlanet;

      jOdRlh += exp(-jHeight / shRlh) * jStepSize;
      jOdMie += exp(-jHeight / shMie) * jStepSize;

      jTime += jStepSize;
    }
    vec3 attn = exp(-(kMie * (iOdMie + jOdMie) + kRlh * (iOdRlh + jOdRlh)));

    totalRlh += optic_rlh * attn;
    totalMie += optic_mie * attn;

    iTime += iStepSize;
  }

  if (c > 0.0) {
    // make sun more bright than other place
    float X = 1.0 + 0.0015 * tan(PI*c/2.0);
    vec3 color = X * iSun * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
    return color;
  } else {
    return iSun * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
  }
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