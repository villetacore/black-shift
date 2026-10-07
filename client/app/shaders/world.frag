#version 120
// Shared by the world, props, actors and effects. Material 8 (team light strips) is tinted;
// materials 8 and 15+ are emissive.
uniform sampler2D materialTexture;
uniform vec3 camera;
uniform vec3 teamTint;
uniform float glow;
uniform float time;
uniform bool liquid;
uniform vec2 flow;
uniform float brightness;
uniform bool bakedLighting;
varying vec3 worldPosition;
varying vec3 worldNormal;
varying vec2 textureUV;
varying float surface;
varying float bakedShade;
void main() {
  float mat=floor(surface+0.5);
  // Each material is bound as its own texture with its own mip chain: no atlas bleeding.
  vec3 tex=texture2D(materialTexture,textureUV).rgb;
  bool emissive=abs(mat-8.0)<0.1||mat>14.5;
  if(abs(mat-8.0)<0.1)tex*=teamTint;
  vec3 n=normalize(worldNormal);
  float diffuse=max(dot(n,normalize(vec3(-0.35,0.85,-0.5))),0.0);
  float shade=0.20+0.32*diffuse;
  // Pools of tungsten light aligned to the visible overhead fixtures.
  vec2 fixture=vec2(3.0+4.0*floor((worldPosition.x-3.0)/4.0+0.5),
                    4.0+5.0*floor((worldPosition.z-4.0)/5.0+0.5));
  vec3 toLight=vec3(fixture.x,4.15,fixture.y)-worldPosition;
  float lamp=1.6/(1.0+0.38*dot(toLight,toLight));
  lamp*=0.3+0.7*max(dot(n,normalize(toLight)),0.0);
  vec3 color=tex*(emissive?1.2:shade)*brightness;
  if(!emissive)color+=tex*lamp*vec3(1.0,0.79,0.48);
  float cyanLight=0.34/(1.0+0.12*pow(length(worldPosition-vec3(3.0,1.5,12.5)),2.0));
  float amberLight=0.30/(1.0+0.12*pow(length(worldPosition-vec3(21.0,1.5,12.5)),2.0));
  color+=tex*(cyanLight*vec3(0.0,0.55,0.48)+amberLight*vec3(0.85,0.27,0.07));
  // Static world geometry replaces dynamic shading with light baked on the CPU.
  if(bakedLighting && !emissive)color=tex*bakedShade*vec3(1.0,0.88,0.69);
  color=mix(color,teamTint,glow);
  float fog=clamp(1.0-exp(-length(worldPosition-camera)*0.027),0.0,0.73);
  color=mix(color,vec3(0.055,0.044,0.025),fog*0.65);
  float alpha=1.0;
  if(liquid){
    vec2 p=worldPosition.xz-flow*time;
    vec2 warped=p*0.32+vec2(sin(p.y*2.0+time),cos(p.x*2.3-time))*0.045;
    float grain=texture2D(materialTexture,warped).r;
    float ripple=sin(p.x*4.0+p.y*2.0+time*1.8)*sin(p.y*3.0-time*1.2);
    float fresnel=pow(1.0-abs(normalize(camera-worldPosition).y),3.0);
    color=teamTint*(0.75+grain*0.45)+vec3(0.19,0.20,0.16)*fresnel+ripple*0.035;
    alpha=0.76+fresnel*0.19;
  }
  gl_FragColor=vec4(clamp(color,0.0,1.0),alpha);
}
