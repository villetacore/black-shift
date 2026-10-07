#version 120
uniform sampler2D scene;
uniform float time;
uniform float underwater;
uniform vec3 waterColor;
varying vec2 sampleUV;
void main(){
 vec2 uv=sampleUV;
 uv+=vec2(sin(uv.y*32.0+time*2.0),cos(uv.x*28.0+time*1.7))*0.0025*underwater;
 vec3 color=texture2D(scene,clamp(uv,vec2(0.001),vec2(0.999))).rgb;
 gl_FragColor=vec4(mix(color,color*waterColor+waterColor*0.25,underwater*0.65),1.0);
}
