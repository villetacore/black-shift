#version 120
uniform float time;
uniform float aspect;
uniform vec3 forward;
uniform vec3 right;
uniform vec3 up;
varying vec2 sampleUV;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void main(){
 vec2 uv=(floor(sampleUV*vec2(640,400))/vec2(640,400)*2.0-1.0)*0.60086;
 vec3 ray=normalize(forward+right*uv.x*aspect+up*uv.y);
 float elevation=max(ray.y,0.0);
 vec3 color=mix(vec3(0.40,0.34,0.25),vec3(0.10,0.16,0.19),sqrt(elevation));
 vec2 p=ray.xz/(0.22+elevation)*2.4+vec2(time*0.018,time*0.008);
 float clouds=noise(p)*0.55+noise(p*2.1)*0.3+noise(p*4.3)*0.15;
 color=mix(color,vec3(0.53,0.49,0.38),smoothstep(0.40,0.72,clouds)*smoothstep(0.0,0.15,elevation)*0.75);
 float sun=pow(max(dot(ray,normalize(vec3(-0.35,0.35,-0.5))),0.0),160.0);
 color+=vec3(0.27,0.19,0.08)*sun;
 gl_FragColor=vec4(floor(color*48.0)/48.0,1);
}
