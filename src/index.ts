import glsl = require('glslify');
import mat4 = require('gl-mat4');
import bunny = require('bunny');

const regl = require('regl')({
  canvas: document.getElementById('regl-canvas'),
});

const setup = regl({
  context: {
    view: ({tick}) => {
      const t = 0.01 * tick
      return mat4.lookAt([],
        [0, 0, 0],
        [-Math.sin(t*0.76), 0.6*Math.sin(t*0.51) + 0.4, -Math.cos(t*0.76)],
        [0, 1, 0])
        /*return mat4.lookAt([],
        [0, 0, 0],
        [0, 1, 0.01],
        [0, 1, 0])*/
    },
    projection: ({viewportWidth, viewportHeight}) =>
    mat4.perspective([],
      Math.PI / 4,
      viewportWidth / viewportHeight,
      0.01,
      1000)
  }
})
console.log("imageload begin");
require('resl')({
  manifest: {
    perlin: {
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
  onDone: ({perlin}) => {
    console.log("frame begin");
    regl.frame(() => {
      regl.clear({
        color: [0,0,0,255]
      })
      setup(() => {
        drawSky({perlin})
      })
    })
  }
})

const drawSky = regl({
  frag: glsl('./gl/sky_frag2.glsl'),
  vert: glsl('./gl/sky_vert.glsl'),
  uniforms: {
    time: ({tick}) => tick,
    perlin: regl.prop('perlin'),
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