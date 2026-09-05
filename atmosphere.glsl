// Multi scattering from https://www.shadertoy.com/view/msXXDS

const float EXPOSURE = 0.05;
const float PI = 3.14159265358979323846;
const float INV_PI = 0.31830988618379067154;
const float INV_4PI = 0.07957747154594766788;

const int TRANSMITTANCE_STEPS = 32;
const int INSCATTERING_STEPS = 32;

const float PLANET_RADIUS = 6371.0;
const float ATMOSPHERE_THICKNESS = 100.0;
const float ATMOSPHERE_RADIUS = PLANET_RADIUS + ATMOSPHERE_THICKNESS;

const float MOLECULAR_HEIGHT_SCALE = 8.0;
const float AEROSOL_HEIGHT_SCALE = 1.2;
const float AEROSOL_TURBIDITY = 1.0;
const float AEROSOL_BASE_DENSITY = 1.0 * (1.2 / AEROSOL_HEIGHT_SCALE);

//const vec3 SUN_IRRADIANCE = (vec3(225, 210, 205) / vec3(255.0)) * 1360.0;
//const vec3 SUN_IRRADIANCE = vec3(214.937791, 190.765948, 184.144280);
const vec3 SUN_IRRADIANCE = vec3(215, 190, 185);
const vec3 RAYLEIGH_SCATTERING_BASE = mix(vec3(46.0, 95.0, 233.0), vec3(46.0, 89.0, 207.0), 0.7) / 255.0 * 0.03624;
const vec3 OZONE_ABSORPTION_BASE = vec3(200.0, 170.0, 0.0) / 255.0 * 0.0019;
const vec3 AEROSOL_SCATTERING_BASE = vec3(153.0, 202.0, 255.0) / 255.0 * 0.035;
const vec3 AEROSOL_ABSORPTION_BASE = vec3(1.0) * 0.0003;
const vec3 GROUND_ALBEDO = vec3(10.0, 45.0, 100.0) / 255.0;

float raySphereIntersect(vec3 origin, vec3 dir, float radius)
{
    float b = dot(origin, dir);
    float c = dot(origin, origin) - radius * radius;
    float disc = b * b - c;
    if (disc < 0.0) return -1.0;
    float sqrtDisc = sqrt(disc);
    float t0 = -b - sqrtDisc;
    float t1 = -b + sqrtDisc;
    if (t0 >= 0.0) return t0;
    if (t1 >= 0.0) return t1;
    return -1.0;
}

float distanceToTopAtmosphereBoundary(float r, float mu)
{
    float discriminant = r * r * (mu * mu - 1.0) + ATMOSPHERE_RADIUS * ATMOSPHERE_RADIUS;
    return clamp(-r * mu + sqrt(max(0.0, discriminant)), 0.0, 1e6);
}

bool rayIntersectsGround(float r, float mu)
{
    return mu < 0.0 && r * r * (mu * mu - 1.0) + PLANET_RADIUS * PLANET_RADIUS >= 0.0;
}

float hgPhase(float cosTheta, float g)
{
    float g2 = g * g;
    float denom = 1.0 + g2 + 2.0 * g * cosTheta;
    return INV_4PI * (1.0 - g2) / (denom * sqrt(denom));
}

float aerosolPhase(float cosTheta)
{
    return mix(hgPhase(cosTheta, 0.62), mix(hgPhase(cosTheta, 0.82), mix(hgPhase(cosTheta, 0.93), hgPhase(cosTheta, 0.97), 0.2), 0.4), 0.42) * 1.3;
}

float rayleighPhase(float cosTheta)
{
    return mix((1.0 / PI / 4.0) * 0.4 * -cosTheta + (1.0 / PI / 4.0) * 1.12, (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta), 0.8);
}

void getAtmosphereCoefficients(
    float h,
    out vec3 aerosolAbsorption,
    out vec3 aerosolScattering,
    out vec3 molecularAbsorption,
    out vec3 molecularScattering,
    out vec3 extinction
) {
    h = max(h, 0.0);
    float aerosolDensity = AEROSOL_BASE_DENSITY * exp(-h / AEROSOL_HEIGHT_SCALE) * aerosols;
    aerosolAbsorption = AEROSOL_ABSORPTION_BASE * aerosolDensity * AEROSOL_TURBIDITY;
    aerosolScattering = AEROSOL_SCATTERING_BASE * aerosolDensity * AEROSOL_TURBIDITY;
    molecularScattering = RAYLEIGH_SCATTERING_BASE * exp(-h / MOLECULAR_HEIGHT_SCALE) * air;
    float ozoneDensity = max(1.0 - abs(h - 22.35) / (35.66 * 0.5), 0.0) * ozone;
    molecularAbsorption = OZONE_ABSORPTION_BASE * ozoneDensity;
    extinction = aerosolAbsorption + aerosolScattering + molecularAbsorption + molecularScattering;
}

vec3 computeTransmittance(vec3 origin, vec3 rayDirection)
{
    float rayLength = raySphereIntersect(origin, rayDirection, ATMOSPHERE_RADIUS);
    if (rayLength < 0.0) return vec3(1.0);
    float dt = rayLength / float(TRANSMITTANCE_STEPS);
    vec3 opticalDepth = vec3(0.0);
    for (int i = 0; i < TRANSMITTANCE_STEPS; ++i) {
        float t = (float(i) + 0.5) * dt;
        vec3 p = origin + rayDirection * t;
        float h = length(p) - PLANET_RADIUS;
        vec3 aerosolAbsorption;
        vec3 aerosolScattering;
        vec3 molecularAbsorption;
        vec3 molecularScattering;
        vec3 extinction;
        getAtmosphereCoefficients(h, aerosolAbsorption, aerosolScattering, molecularAbsorption, molecularScattering, extinction);
        opticalDepth += extinction * dt;
    }
    return exp(-opticalDepth);
}

vec3 multiScattering(float cosTheta, float normalizedAlt, float r)
{
    float solidAngle = 2.0 * PI * (1.0 - sqrt(max(0.0, r * r - PLANET_RADIUS * PLANET_RADIUS)) / r);
    vec3 groundDirection = vec3(sqrt(max(0.0, 1.0 - cosTheta * cosTheta)), cosTheta, 0.0);
    vec3 groundOrigin = vec3(0.0, PLANET_RADIUS, 0.0);
    vec3 transToGround = computeTransmittance(groundOrigin, groundDirection);
    vec3 sampleOrigin = vec3(0.0, PLANET_RADIUS + normalizedAlt * ATMOSPHERE_THICKNESS, 0.0);
    vec3 transGroundToSample = computeTransmittance(groundOrigin, vec3(0.0, 1.0, 0.0)) / max(computeTransmittance(sampleOrigin, vec3(0.0, 1.0, 0.0)), vec3(1e-6));
    vec3 groundRadiance = (INV_4PI * solidAngle) * (GROUND_ALBEDO / PI) * transToGround * transGroundToSample * max(0.0, cosTheta);
    vec3 approxMulti = 0.015 * vec3(0.2, 0.35, 1.0) / (1.0 + 5.0 * exp(-17.92 * cosTheta));
    return groundRadiance + approxMulti;
}

vec3 computeInscattering(vec3 sunDirection, vec3 rayDirection)
{
    vec3 rayOrigin = vec3(0.0, PLANET_RADIUS + altitude, 0.0);
    vec3 sunDirN = normalize(sunDirection);
    float cosTheta = dot(rayDirection, sunDirN);
    float atmosphereDist = raySphereIntersect(rayOrigin, rayDirection, ATMOSPHERE_RADIUS);
    float groundDist = raySphereIntersect(rayOrigin, rayDirection, PLANET_RADIUS);
    float rayLength = 0.0;
    bool inside = length(rayOrigin) <= ATMOSPHERE_RADIUS;
    if (inside) {
        rayLength = (groundDist > 0.0) ? groundDist : atmosphereDist;
    } else if (atmosphereDist > 0.0) {
        rayOrigin += rayDirection * (atmosphereDist + 1e-4);
        float secondDist = raySphereIntersect(rayOrigin, rayDirection, ATMOSPHERE_RADIUS);
        rayLength = (groundDist > 0.0) ? (groundDist - atmosphereDist) : secondDist;
    }
    if (rayLength <= 0.0) return vec3(0.0);
    float dt = rayLength / float(INSCATTERING_STEPS);
    vec3 L = vec3(0.0);
    vec3 T = vec3(1.0);
    float rayleighPhaseVal = rayleighPhase(-cosTheta);
    float aerosolPhaseVal = aerosolPhase(-cosTheta);
    for (int i = 0; i < INSCATTERING_STEPS; ++i) {
        float t = (float(i) + 0.5) * dt;
        vec3 p = rayOrigin + rayDirection * t;
        float r = length(p);
        float h = r - PLANET_RADIUS;
        float normalizedH = h / ATMOSPHERE_THICKNESS;
        float sunCosTheta = dot(p / r, sunDirN);
        vec3 aerosolAbsorption;
        vec3 aerosolScattering;
        vec3 molecularAbsorption;
        vec3 molecularScattering;
        vec3 ext;
        getAtmosphereCoefficients(h, aerosolAbsorption, aerosolScattering, molecularAbsorption, molecularScattering, ext);
        vec3 transToSun = computeTransmittance(p, sunDirN);
        vec3 singleScatter = (molecularScattering * rayleighPhaseVal + aerosolScattering * aerosolPhaseVal) * transToSun;
        vec3 multiScatter = multiScattering(sunCosTheta, normalizedH, r) * (molecularScattering + aerosolScattering) * scatter_muti;
        vec3 source = SUN_IRRADIANCE * (singleScatter + multiScatter);
        vec3 stepT = exp(-ext * dt);
        vec3 integrated = (source - source * stepT) / max(ext, vec3(1e-6));
        L += T * integrated;
        T *= stepT;
    }
    return L;
}

vec3 getViewDirection(vec2 uv)
{
    float longitude = (uv.x - 0.5) * 2.0 * PI;
    float latitude = (0.5 - uv.y) * PI;
    float cosLatitude = cos(latitude);
    vec3 direction = vec3(cosLatitude * sin(longitude), sin(latitude), cosLatitude * cos(longitude));
    return normalize(direction);
}

vec3 getSunDirection(float elevation, float azimuth)
{
    float cosElevation = cos(elevation);
    return normalize(vec3(cosElevation * sin(azimuth), sin(elevation), cosElevation * cos(azimuth)));
}

void main()
{
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (pixel.x >= 1024 || pixel.y >= 1024) return;
    vec2 uv = (vec2(pixel) + vec2(0.5)) / vec2(1024.0, 1024.0);
    uv.y = 1.0 - uv.y;
    vec3 viewDirection = getViewDirection(uv);
    vec3 sunDirection = getSunDirection(sun_elevation, sun_rotation);
    vec3 radiance = computeInscattering(sunDirection, viewDirection);
    vec3 color = radiance * EXPOSURE;
    imageStore(img_output, pixel, vec4(color, 1.0));
}