/*

This is an adaption of following JavaScript tutorial:
  https://codelabs.developers.google.com/your-first-webgpu-app#0

Note, that this has been tested in GM Beta with early open beta GMRT runtime.
  IDE v2024.800.0.597, Runtime v2024.800.0.620, GMRT 0.12.0

*/

// Setup WebGPU.
adapter = GPU.requestAdapter();
device = adapter.requestDevice();
format = GPU.getPreferredCanvasFormat();

// Setup Game of Life.
GRID_SIZE = 64;   // Play area.
CELL_SIZE = 0.8;  // Render size.
WORKGROUP_SIZE = 8;
rate = 15.0 / game_get_speed(gamespeed_fps);
step = 0.0;
swap = 0;


// Create grid-size uniform buffer.
uniformArray = [GRID_SIZE, GRID_SIZE];
uniformBuffer = device.createBuffer({
  label: "Grid Uniforms",
  size: 4 * array_length(uniformArray),
  usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
});


// Create cell vertex buffer.
// Quad, two triangles with XY positions.
vertices = [
  // 1. triangle.
  -CELL_SIZE, -CELL_SIZE, 
  +CELL_SIZE, -CELL_SIZE, 
  +CELL_SIZE, +CELL_SIZE,
  // 2. triangle.
  -CELL_SIZE, -CELL_SIZE,
  +CELL_SIZE, +CELL_SIZE, 
  -CELL_SIZE, +CELL_SIZE
];

vertexBuffer = device.createBuffer({
  label: "Cell vertices",
  size: 4 * array_length(vertices),
  usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST
});


vertexBufferLayout = {
  arrayStride: 8,
  attributes: [{
    shaderLocation: 0,
    format: "float32x2",
    offset: 0,
  }]
};


// Create cell-states storage buffers.
cellStates = new Buffer(GRID_SIZE * GRID_SIZE, buffer_u32); 
cellStateStorage = [
  device.createBuffer({
    label: "Cell State A",
    size: cellStates.bytes,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
  }),
  device.createBuffer({
    label: "Cell State B",
    size: cellStates.bytes,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
  }),
];
for(var i = 0; i < cellStates.count; i++)
{
  buffer_write(cellStates.buffer, buffer_u32, (random(1.0) > 0.6));
}


// Create shaders.
cellShaderModule = device.createShaderModule({
  label: "Cell shader",
  code: @'
  
    struct VertexInput {
      @location(0) pos: vec2f,
      @builtin(instance_index) instance: u32,
    };
    
    struct VertexOutput {
      @builtin(position) pos: vec4f,
      @location(0) cell: vec2f,
    };
    
    
    @group(0) @binding(0) var<uniform> grid: vec2f;
    @group(0) @binding(1) var<storage> cellState: array<u32>;
    
    
    @vertex
    fn mainVertex(input: VertexInput) -> VertexOutput
    {
      let i = f32(input.instance);
      let cell = vec2f(i % grid.x, floor(i / grid.x));
      let state = f32(cellState[input.instance]);
      
      let cellOffset = cell / grid * 2;
      let gridPos = (input.pos * state + 1) / grid - 1 + cellOffset;
      
      var output: VertexOutput;
      output.pos = vec4f(gridPos, 0, 1);
      output.cell = cell;
      return output;
    }
    
    
    @fragment
    fn mainFragment(input: VertexOutput) -> @location(0) vec4f
    {
      let c = input.cell / grid;
      return vec4f(c, 1-c.x, 1);
    }
    
  '
});


simulationShaderModule = device.createShaderModule({
  label: "Game of Life simulation shader",
  code: string_concat(@'
    
    @group(0) @binding(0) var<uniform> grid: vec2f;
    
    @group(0) @binding(1) var<storage> cellStateIn: array<u32>;
    @group(0) @binding(2) var<storage, read_write> cellStateOut: array<u32>;
    
    
    fn cellIndex(cell: vec2u) -> u32 
    {
      return (cell.y % u32(grid.y)) * u32(grid.x) + (cell.x % u32(grid.x));
    }
    
    
    fn cellActive(x: u32, y: u32) -> u32
    {
      return cellStateIn[cellIndex(vec2(x, y))];
    }
    
    
    @compute
    @workgroup_size(',WORKGROUP_SIZE,", ",WORKGROUP_SIZE,@')
    fn mainCompute(@builtin(global_invocation_id) cell: vec3u)
    {
      // Get count of alive neighbours.
      let activeNeighbours = (
          cellActive(cell.x + 1, cell.y + 1)
        + cellActive(cell.x + 1, cell.y + 0)
        + cellActive(cell.x + 1, cell.y - 1)
        + cellActive(cell.x + 0, cell.y - 1)
        + cellActive(cell.x - 1, cell.y - 1)
        + cellActive(cell.x - 1, cell.y + 0)
        + cellActive(cell.x - 1, cell.y + 1)
        + cellActive(cell.x - 0, cell.y + 1)
      );
      
      // Current cell index.
      let i = cellIndex(cell.xy);
      
      // Apply the Game of Life rules.
      switch(activeNeighbours)
      {
        case 2: {
          cellStateOut[i] = cellStateIn[i];
        }
        case 3: {
          cellStateOut[i] = 1;
        }
        default: {
          cellStateOut[i] = 0;
        }
      }
    }
  ')
});


// Create bindgroups.
bindGroupLayout = device.createBindGroupLayout({
  label: "Cell Bind Group Layout",
  entries: [{
    binding: 0,
    visibility: GPUShaderStage.COMPUTE | GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
    buffer: { type: "uniform" }
  }, {
    binding: 1,
    visibility: GPUShaderStage.COMPUTE | GPUShaderStage.VERTEX,
    buffer: { type: "read-only-storage" }
  }, {
    binding: 2,
    visibility: GPUShaderStage.COMPUTE,
    buffer: { type: "storage"}
  }]
});


bindGroups = [
  device.createBindGroup({
    label: "Cell renderer bind group A",
    layout: bindGroupLayout,
    entries: [{
      binding: 0,
      resource: { buffer: uniformBuffer }
    }, {
      binding: 1,
      resource: { buffer: cellStateStorage[0] }
    }, {
      binding: 2,
      resource: { buffer: cellStateStorage[1] }
    }]
  }), 
  device.createBindGroup({
    label: "Cell renderer bind group B",
    layout: bindGroupLayout,
    entries: [{
      binding: 0,
      resource: { buffer: uniformBuffer }
    }, {
      binding: 1,
      resource: { buffer: cellStateStorage[1] }
    }, {
      binding: 2,
      resource: { buffer: cellStateStorage[0] }
    }]
  })
];


// Create pipelines.
pipelineLayout = device.createPipelineLayout({
  label: "Cell Pipeline Layout",
  bindGroupLayouts: [ bindGroupLayout ]
});


cellPipeline = device.createRenderPipeline({
  label: "Cell pipeline",
  layout: pipelineLayout,
  vertex: {
    module: cellShaderModule,
    entryPoint: "mainVertex",
    buffers: [vertexBufferLayout]
  },
  fragment: {
    module: cellShaderModule,
    entryPoint: "mainFragment",
    primitive: {
      topology: "triangle-list",
    },
    targets: [{
      format: format
    }]
  }
});


simulationPipeline = device.createComputePipeline({
  label: "Simulation pipeline",
  layout: pipelineLayout,
  compute: {
    module: simulationShaderModule,
    entryPoint: "mainCompute"
  }
});


// Move GML data to the GPU buffers.
device.queue.writeBuffer(cellStateStorage[0], 0, cellStates.buffer);
device.queue.writeBuffer(cellStateStorage[1], 0, cellStates.buffer);
device.queue.writeBuffer(uniformBuffer, 0, uniformArray);
device.queue.writeBuffer(vertexBuffer, 0, vertices);


// Computing and rendering a frame.
frame = function()
{
  // WebGPU Rendering commands.
  var _encoder = device.createCommandEncoder();

  // Compute commands.
  step += rate;
  if (step > 1.0)
  {
    var _workgroupCount = ceil(GRID_SIZE / WORKGROUP_SIZE);
    var _computePass = _encoder.beginComputePass()
    _computePass.setPipeline(simulationPipeline);
    _computePass.setBindGroup(0, bindGroups[swap]);
    _computePass.dispatchWorkgroups(_workgroupCount, _workgroupCount);
    _computePass.end_();
    swap = swap ? 0 : 1;
    step -= 1.0;
  }

  // Rendering commands.
  var _renderPass = _encoder.beginRenderPass({
    colorAttachments: [{
      view: GPU.getCurrentTextureView(),
      loadOp: "clear",
      clearValue: { 
        r: 0.1 + 0.03 * dsin(current_time/10 + 0), 
        g: 0.1 + 0.03 * dsin(current_time/10 + 60), 
        b: 0.5 + 0.03 * dsin(current_time/10 + 120), 
        a: 1.0 
      },
      storeOp: "store"
    }]
  });
  _renderPass.setPipeline(cellPipeline);
  _renderPass.setVertexBuffer(0, vertexBuffer);
  _renderPass.setBindGroup(0, bindGroups[swap]);
  _renderPass.draw(array_length(vertices) / 2, GRID_SIZE * GRID_SIZE); // 6 vertices.
  _renderPass.end_();

  // Do it now!
  device.queue.submit([_encoder.finish()]);
}

