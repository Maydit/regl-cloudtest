import glsl = require('glslify');
import mat4 = require('gl-mat4');

const regl = require('regl')({
  canvas: document.getElementById('regl-canvas'),
});

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
function lpChange(ev:any) {
  lunarPhase = ev.currentTarget.value / 100.0 * 8.0;
  console.log(lunarPhase);
}
function PASSEDf(ev:any) {
  PASSED = ev.currentTarget.value / 100.0;
  console.log(PASSED);
}



let coverage = 0.5;
let absorbtion = 1.207523; 
let darkness = 0.2;
let height = 5.5e3;
let thickness = 10e2;
let lunarPhase = 1.0;
let PASSED = 1.0;

const setup = regl({
  context: {
    timeOfDay: ({tick}) => (tick * 0.005) % 24.0,
    view: ({tick}) => {
        return mat4.lookAt([],
        [0, 0, 0],
        [0.5, 0.5, 0],
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
    },
    moon: {
      type: 'image',
      src: 'src/assets/moon.jpg',
      parser: (data) => regl.texture({
        data: data,
        wrap: 'clamp',
      })
    }
  },
  onDone: ({noise, moon}) => {
    regl.frame(() => {
      regl.clear({
        color: [0,0,0,255]
      })
      init_slider();
      setup(() => {
        drawSky({noise, moon, coverage, absorbtion, darkness, height, thickness, lunarPhase, PASSED})
      })
    })
  }
})

const drawSky = regl({
  frag: glsl('./gl/sky_frag.glsl'),
  vert: glsl('./gl/sky_vert.glsl'),
  uniforms: {
    PASSED: regl.prop('PASSED'),
    time: ({tick}) => tick,
    moonSampler: regl.prop('moon'),
    noiseSampler: regl.prop('noise'),
    coverage: regl.prop('coverage'), 
    absorbtion: regl.prop('absorbtion'), 
    darkness: regl.prop('darkness'),
    height: regl.prop('height'),
    thickness: regl.prop('thickness'),
    lunarPhase: regl.prop('lunarPhase'),
    timeOfDay: regl.context('timeOfDay'),
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
  document.getElementById('slider-lunarPhase').addEventListener('change', lpChange);
  document.getElementById('slider-PASSED').addEventListener('change', PASSEDf);
};