#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution; // Size of the canvas
uniform vec2 u_heightmapSize; // Size of the heightmap
uniform vec2 u_cloudSize;     // Size of the cloud texture
uniform float u_time;      // Time for subtle global cloud drift if desired
uniform sampler2D u_heightmap;
uniform sampler2D u_cloudTexture;
uniform float u_cloudOpacity;
uniform vec3 u_lightDir;
uniform vec3 u_lightColor;
layout(location = 14) uniform float u_bgR;
layout(location = 15) uniform float u_bgG;
layout(location = 16) uniform float u_bgB;

out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / u_resolution;
    
    // Normalized coordinate for heightmap is simply uv
    vec2 hCoord = uv;
    
    // Finite difference step in normalized pixels:
    vec2 dx = vec2(1.0 / u_heightmapSize.x, 0.0);
    vec2 dy = vec2(0.0, 1.0 / u_heightmapSize.y);
    
    // Sample heightmap (R channel contains height)
    float hC = texture(u_heightmap, hCoord).r;
    float hL = texture(u_heightmap, clamp(hCoord - dx, vec2(0.0), vec2(1.0))).r;
    float hR = texture(u_heightmap, clamp(hCoord + dx, vec2(0.0), vec2(1.0))).r;
    float hU = texture(u_heightmap, clamp(hCoord - dy, vec2(0.0), vec2(1.0))).r;
    float hD = texture(u_heightmap, clamp(hCoord + dy, vec2(0.0), vec2(1.0))).r;
    
    // Compute gradient (derivative of height)
    vec2 grad = vec2(hR - hL, hD - hU) * 0.5;
    
    // Compute normal vector (scale gradient for desired specular intensity)
    float normalStrength = 20.0;
    vec3 normal = normalize(vec3(grad * normalStrength, 1.0));
    
    // Slowed down horizontal drift, with reduced distortion for high-detail textures
    vec2 cloudUV = uv + normal.xy * 0.03 + vec2(u_time * 0.008, 0.0);
    
    // Aspect ratio scaling to prevent vertical stretch
    vec2 screenRatio = u_resolution / u_resolution.x;
    vec2 cloudRatio = u_cloudSize / max(u_cloudSize.x, 1.0);
    vec2 uvScale = screenRatio / cloudRatio;
    
    // Cloud texture normalized coordinate.
    vec2 cCoord = fract(cloudUV * uvScale);
    vec4 rawCloud = texture(u_cloudTexture, cCoord); 
    
    // The new dense cloud texture has a pure black background. 
    // We use the red channel (brightness) as the density/alpha mask!
    float rawAlpha = rawCloud.r;

    // Crest-Peak Isolation
    float crestBand = smoothstep(0.75, 1.0, hC);
    float crestIntensity = pow(crestBand, 2.0); // Sharp falloff
    
    // --- True Volumetric God Rays (Light Shafts) ---
    // We trace rays TOWARDS the light source to see if light reaches us through the gaps.
    vec2 rayStep = normalize(u_lightDir.xy) * 0.015;
    vec2 samplePos = cloudUV;
    float accumulatedRays = 0.0;
    float decay = 1.0;
    
    // Raymarch towards the sun
    for(int i = 0; i < 10; i++) {
        samplePos += rayStep;
        float sampleAlpha = texture(u_cloudTexture, fract(samplePos * uvScale)).r;
        
        // ONLY the deep, thick middle of the boundaries (pure black) emit light.
        // Thin tangental boundaries (gray) will emit nothing.
        float sampleGap = smoothstep(0.15, 0.0, sampleAlpha);
        
        accumulatedRays += sampleGap * decay;
        decay *= 0.8; // Rays fade as they travel
    }
    
    // Scale down the accumulated rays
    float godRays = accumulatedRays * 0.3;
    
    // The user explicitly wants the darker parts (boundaries) to be brightened MORE than the clouds.
    // So we apply the rays heavily in the gaps (where alpha is 0), and fade them out over the clouds.
    float visibleRays = godRays * smoothstep(0.6, 0.0, rawAlpha);
    
    // Silver Lining: Edges directly facing the sun
    float rayA1 = texture(u_cloudTexture, fract((cloudUV + normalize(u_lightDir.xy) * 0.01) * uvScale)).r;
    float silverLining = max(0.0, rayA1 - rawAlpha) * 1.5;
    
    // Apply user-controlled opacity to the base cloud
    vec4 finalColor = vec4(rawCloud.rgb, rawAlpha);
    finalColor.a *= u_cloudOpacity;
    finalColor.rgb *= u_cloudOpacity; // premultiplied alpha
    
    // Apply the god rays and piercing light
    vec3 piercingLight = u_lightColor * (silverLining + visibleRays) * u_cloudOpacity;
    finalColor.rgb += piercingLight;
    
    // Slight tint of the background color applied to the wakes themselves
    vec3 bgColor = vec3(u_bgR, u_bgG, u_bgB);
    finalColor.rgb += bgColor * max(0.0, hC) * 0.45;
    
    // Add specular highlight for the crest (softened, slightly tinted by light color)
    vec3 specularWhite = mix(vec3(1.0), u_lightColor, 0.4);
    finalColor.rgb += specularWhite * crestIntensity * 0.15;
    
    // --- Blinn-Phong Sun/Moon Glitter ---
    vec3 viewDir = vec3(0.0, 0.0, 1.0);
    vec3 lightDir = normalize(u_lightDir);
    vec3 halfDir = normalize(lightDir + viewDir);
    
    // Specular calculation
    float NdotH = max(dot(normal, halfDir), 0.0);
    float shininess = 40.0; // Lower shininess for a broader, softer glary spread
    float specAmount = pow(NdotH, shininess);
    
    // Mask out the flat areas so only the ripples catch the glint
    float waveMask = smoothstep(0.05, 0.4, hC);
    
    // Apply soft highlight without glary bleeding
    vec3 specularGlint = u_lightColor * specAmount * waveMask * 1.5; 
    
    finalColor.rgb += specularGlint;
    
    // Boost alpha where the crest, glints, and piercing light are.
    float addedAlpha = crestIntensity * 0.5 + specAmount * waveMask + (silverLining + visibleRays) * u_cloudOpacity;
    finalColor.a = min(1.0, finalColor.a + addedAlpha);
    
    fragColor = finalColor;
}
