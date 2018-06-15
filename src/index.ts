const regl = require('regl')({
  canvas: document.getElementById('regl-canvas'),
});

regl.clear({
  color: [0, 0, 0, 0.5],
  depth: 1
})

regl({
  frag: 
  `
    precision mediump float;
    uniform vec4 u_color;
    void main() {
      gl_FragColor = u_color;
    }
  `,
  vert:
  `
    precision mediump float;
    attribute vec2 a_position;
    void main() {
      gl_Position = vec4(a_position, 0, 1);
    }
  `,
  attributes: {
    a_position: [[-0.5, 0], [0, -0.5], [0, 0.5], [0.5, 0], [0.2, -0.5], [0.2, 0.5]]
  },
  uniforms: {
    u_color: [0, 1, 0, 1],
  },
  count: 6,
})();