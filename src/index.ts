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
        [30 * Math.cos(t), 2.5, 30 * Math.sin(t)],
        [0, 2.5, 0],
        [0, 1, 0])
    },
    projection: ({viewportWidth, viewportHeight}) =>
    mat4.perspective([],
      Math.PI / 4,
      viewportWidth / viewportHeight,
      0.01,
      1000),
    invView: (view) => mat4.invert([], view),
    invProjection: (projection) => mat4.invert([], projection)
  }
})

regl.frame(() => {
  regl.clear({
    color: [0,0,0,1]
  })
  setup(() => {
    drawSky()
    drawBunny()
  })
})

const drawBunny = regl({
  vert: `
  precision mediump float;
  attribute vec3 position;
  uniform mat4 model, view, projection;
  void main() {
    gl_Position = projection * view * model * vec4(position, 1);
  }`,
  frag: `
  precision mediump float;
  void main() {
    gl_FragColor = vec4(0, 1, 1, 1);
  }`,
  uniforms: {
    model: mat4.identity([]),
    view: regl.context('view'),
    projection: regl.context('projection')
  },
  attributes: {
    position: bunny.positions,
  },
  elements: bunny.cells
})

const drawSky = regl({
  frag: glsl('./gl/sky_frag.glsl'),
  vert: glsl('./gl/sky_vert.glsl'),
  uniforms: {
    viewportHeight: regl.context('viewportHeight'),
    viewportWidth: regl.context('viewportWidth'),
    invView: regl.context('invView'),
    invProjection: regl.context('invProjetion')
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