import glsl = require('glslify');

const regl = require('regl')({
  canvas: document.getElementById('regl-canvas'),
});

regl.clear({
  color: [0, 0, 0, 0.5],
  depth: 1
})

regl({
  frag: glsl('./gl/sky_frag.glsl'),
  vert: glsl('./gl/sky_vert.glsl'),
  uniforms: {
    viewportHeight: regl.context('viewportHeight'),
    viewportWidth: regl.context('viewportWidth'),
  },
  attributes: {
    position:
      [
        -4, 0,
        4, -4,
        4, 4,
      ],
  },
  count: 3,
  primitive: 'triangles',
  offset: 0,
  elements: null,
})();