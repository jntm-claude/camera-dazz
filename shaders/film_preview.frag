#version 460 core
#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

// The engine supplies the input size and first sampler to ImageFilter shaders.
uniform vec2 uSize;
uniform float uLutStrength;
uniform float uContrast;
uniform float uSaturation;
uniform float uBlackLift;
uniform float uHighlightRolloff;
uniform float uWarmth;
uniform float uGrainStrength;
uniform float uVignetteStrength;
uniform float uSeed;
uniform sampler2D uInput;
uniform sampler2D uLut;

vec3 sampleLut(vec3 source) {
  vec3 color = clamp(source, 0.0, 1.0);
  float blue = color.b * 63.0;
  float lowBlue = floor(blue);
  float highBlue = ceil(blue);
  vec2 lowTile = vec2(mod(lowBlue, 8.0), floor(lowBlue / 8.0));
  vec2 highTile = vec2(mod(highBlue, 8.0), floor(highBlue / 8.0));
  vec2 inset = vec2(0.5 / 512.0);
  vec2 span = vec2(0.125 - 1.0 / 512.0);
  vec2 lowUv = lowTile * 0.125 + inset + span * color.rg;
  vec2 highUv = highTile * 0.125 + inset + span * color.rg;
  vec3 lowColor = texture(uLut, lowUv).rgb;
  vec3 highColor = texture(uLut, highUv).rgb;
  return mix(lowColor, highColor, fract(blue));
}

float filmCurve(float value) {
  float smoothValue = value * value * (3.0 - 2.0 * value);
  float result = mix(value, smoothValue, clamp(uContrast, -1.0, 1.0));
  if (result > 0.52 && uHighlightRolloff > 0.0) {
    float t = clamp((result - 0.52) / 0.48, 0.0, 1.0);
    float exponent = 1.0 - clamp(uHighlightRolloff, 0.0, 0.8) * 0.72;
    result = 0.52 + 0.48 * (1.0 - pow(1.0 - t, exponent));
  }
  result += uBlackLift * pow(1.0 - result, 2.0);
  return clamp(result, 0.0, 1.0);
}

float randomNoise(vec2 position) {
  vec3 p3 = fract(vec3(position.xyx) * 0.1031 + uSeed * 0.0001);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 inputUv = uv;
#ifdef IMPELLER_TARGET_OPENGLES
  inputUv.y = 1.0 - inputUv.y;
#endif

  vec4 source = texture(uInput, inputUv);
  vec3 color = mix(source.rgb, sampleLut(source.rgb), clamp(uLutStrength, 0.0, 1.0));
  color = vec3(filmCurve(color.r), filmCurve(color.g), filmCurve(color.b));

  float luminance = dot(color, vec3(0.299, 0.587, 0.114));
  color = vec3(luminance) + (color - vec3(luminance)) * uSaturation;
  color.r += uWarmth * (0.65 + luminance * 0.35);
  color.g += uWarmth * 0.18;
  color.b -= uWarmth * (0.75 - luminance * 0.15);

  vec2 centered = (uv - vec2(0.5)) * 2.0;
  float radiusSquared = dot(centered, centered) * 0.5;
  float vignette = smoothstep(0.43 * 0.43, 1.0, radiusSquared) *
      clamp(uVignetteStrength, 0.0, 0.8);
  color *= 1.0 - vignette;

  float grain = randomNoise(floor(FlutterFragCoord().xy)) * 2.0 - 1.0;
  float grainWeight = 0.32 + 0.68 *
      (1.0 - smoothstep(0.48, 0.96, luminance));
  color += vec3(grain * uGrainStrength * 0.055 * grainWeight);

  fragColor = vec4(clamp(color, 0.0, 1.0), source.a);
}
