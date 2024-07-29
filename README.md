**Game of Life in GameMaker using WebGPU.**

This is an adaption of following JavaScript tutorial:

https://codelabs.developers.google.com/your-first-webgpu-app#0


Note, that this has been tested in GM Beta with early open beta GMRT runtime.

GMRT is New Runtime for GameMaker, which for example provides support for WebGPU. 

Tested in version: IDE v2024.800.0.597, Runtime v2024.800.0.620, GMRT 0.12.0

https://gamemaker.io/en/blog/gmrt-open-beta


Example uses WebGPU to do rendering and the computation for simulation.

Most important take from this example, is that it uses compute shaders for simulation, which is brand new thing in GM.

Also noteworthy, it uses instanced rendering which is also new thing for GM.

https://github.com/YoYoGames/GMRT-Beta/blob/main/docs/webgpu/webgpu_api.md


Here is video how it looks like:

https://www.youtube.com/watch?v=UCIxRDJ4teI
