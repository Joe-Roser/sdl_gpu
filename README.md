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
        - Bind uniforms
        - Make draw calls
    - Submit command buffer


