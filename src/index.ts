import glsl = require('glslify');
import mat4 = require('gl-mat4');

const regl = require('regl')({
  canvas: document.getElementById('regl-canvas'),
});

function getSunDir(tick) {
  return [0.707, 0.5, 1.0];
  return [0.707 + 2 * Math.sin(tick * 0.005),1.8 + 2 * Math.sin(tick * 0.002 + Math.PI),1.0 + 2 * Math.cos(tick * 0.005)];
}
function heightChange(ev:any) {
  height = ev.currentTarget.value * 1000.0;
  console.log(height);
}
function absChange(ev:any) {
  absorbtion = 1 + ev.currentTarget.value / 50.0;
  console.log(absorbtion);
}
function thicknessChange(ev:any) {
  thickness = ev.currentTarget.value * 100.0;
  console.log(thickness);
}
function darknessChange(ev:any) {
  darkness = ev.currentTarget.value / 100.0;
  console.log(darkness);
}
function coverageChange(ev:any) {
  coverage = ev.currentTarget.value / 100.0;
  console.log(coverage);
}



let coverage = 0.5;
let absorbtion = 1.207523; 
let darkness = 0.2;
let height = 5.5e3;
let thickness = 10e2;

const setup = regl({
  context: {
    sunDirection: ({tick}) => getSunDir(tick),
    view: ({tick}) => {
        return mat4.lookAt([],
        [0, 0, 0],
        getSunDir(30),
        [0, 1, 0])
    },
    projection: ({viewportWidth, viewportHeight}) =>
    mat4.perspective([],
      Math.PI / 4,
      viewportWidth / viewportHeight,
      0.01,
      1000),
  }
})
require('resl')({
  manifest: {
    noise: {
      type: 'image',
      src: 'src/assets/cloudnoise.png',
      parser: (data) => regl.texture({
        data: data,
        min: 'linear',
        mag: 'linear',
        wrap: 'repeat',
      })
    }
  },
  onDone: ({noise}) => {
    regl.frame(() => {
      regl.clear({
        color: [0,0,0,255]
      })
      init_slider();
      setup(() => {
        drawSky({noise, coverage, absorbtion, darkness, height, thickness})
      })
    })
  }
})

const drawSky = regl({
  frag: glsl('./gl/sky_frag.glsl'),
  vert: glsl('./gl/sky_vert.glsl'),
  uniforms: {
    time: ({tick}) => tick,
    noiseSampler: regl.prop('noise'),
    coverage: regl.prop('coverage'), 
    absorbtion: regl.prop('absorbtion'), 
    darkness: regl.prop('darkness'),
    height: regl.prop('height'),
    thickness: regl.prop('thickness'),
    sunDirection: regl.context('sunDirection'),
    viewportHeight: regl.context('viewportHeight'),
    viewportWidth: regl.context('viewportWidth'),
    invView: ({view}) => mat4.invert([], view),
    invProjection: ({projection}) => mat4.invert([], projection)
  },
  attributes: {
    position:
      [
        -4, 0,
        4, -4,
        4, 4,
      ],
  },
  count: 3
})

function init_slider() {
  document.getElementById('slider-height').addEventListener('change', heightChange);
  document.getElementById('slider-thickness').addEventListener('change', thicknessChange);
  document.getElementById('slider-absorbtion').addEventListener('change', absChange);
  document.getElementById('slider-coverage').addEventListener('change', coverageChange);
  document.getElementById('slider-darkness').addEventListener('change', darknessChange);
};