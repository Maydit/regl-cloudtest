import glsl = require('glslify');
import mat4 = require('gl-mat4');

const regl = require('regl')({
  canvas: document.getElementById('regl-canvas'),
});

const setup = regl({
  context: {
    view: ({tick}) => {
      const t = 0.005 * tick
        return mat4.lookAt([],
        [0, 0, 0],
        [0.707, 0.5 + 0.5 * Math.sin(t), 1.0],
        [0, 1, 0])
    },
    projection: ({viewportWidth, viewportHeight}) =>
    mat4.perspective([],
      Math.PI / 4,
      viewportWidth / viewportHeight,
      0.01,
      1000)
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
      setup(() => {
        drawSky({noise})
      })
    })
  }
})

const drawSky = regl({
  frag: glsl('./gl/sky_frag2.glsl'),
  vert: glsl('./gl/sky_vert.glsl'),
  uniforms: {
    time: ({tick}) => tick,
    noiseSampler: regl.prop('noise'),
    coverage: 0.5, 
    absorbtion: 1.207523, 
    darkness: 0.4,
    height: 5.5e3,
    thickness: 10e2,
    sunDirection: ({tick}) => [0.707,2 * Math.sin(tick * 0.001),1.0],
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