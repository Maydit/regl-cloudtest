const regl = require('regl')({
    canvas: document.getElementById('regl-canvas'),
  });
  
  regl.clear({
    color: [0, 0, 0, 0.5],
    depth: 1
  })
 