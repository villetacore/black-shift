#version 120
attribute vec3 position;
attribute vec3 normal;
attribute vec2 uv;
attribute float material;
uniform mat4 model;
uniform mat4 viewProjection;
uniform mat3 normalMatrix;
varying vec3 worldPosition;
varying vec3 worldNormal;
varying vec2 textureUV;
varying float surface;
varying float bakedShade;
void main() {
  vec4 world=model*vec4(position,1.0);
  worldPosition=world.xyz;
  // World geometry stores baked illumination in the length of its normal.
  bakedShade=length(normal);
  worldNormal=normalize(normalMatrix*normal);
  textureUV=uv;
  surface=material;
  gl_Position=viewProjection*world;
}
