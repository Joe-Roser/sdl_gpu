# SDL GPU programming

Learning to use gpu programming with SDL
Learning foundational graphics ideas and prahics apis
Learning glsl

# Lesson 1
Pipeline for rendering:
- Create window and attach a device (gpu)
- Initialise all the pipelines required for project
- Every render:
    - Get a command buffer
    - Get a swapchain texture
    - For each render pass:
        - Get a render pass
        - Bind a pipeline
        - Bind vertex data
        - Bind uniform data
        - Make draw calls
    - Submit command buffer

# Lesson 2
Binding uniforms:
Uniforms are constant global values.
When loading shaders, set the number of uniform buffers to the ammount you need.
UNIFORM ALIGNMENT IS TO 16BIT BOUNDARIES
At the render pass, bind the uniform data to the shader pass.
on the shader side, use SDL to pick the set value and add the bindng value from the shader call to get the uniform out again.

Passing matricies should be done using column major order
The fourth dimension of a matrix is used to carry a unit that allows for translations and other non-linear transformations.
Apply model matrix, then projection. Usually, this is rotation first, then translation.

