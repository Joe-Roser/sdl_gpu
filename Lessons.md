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

# Lesson 3
Vertex Attributes:
Vertex attributes are values specific to the point defined.
In the pipeline:
- The GPU gets all the vertecies and defines the triangle
- The GPU rasterises this, so generates all the relevant pixels
- At the same time, for each pixel, the attribute is a weighted average of its distance to the corners and their colour
- The fragment shader then uses these values
You can use the `flat` keyword in glsl to stop the weighting of this value as its passed out of the rasterisation stage. This means all verticies will get the value of the first vertex.
On Defining Vertex Attributes:
- Define the desired vertex attributes
- Make buffer descriptions and attributes
    - These describe what the attribute looks like in an opaque way, and then describes the internal structure of it
- Add these to the pipeline info

On Using Vertex Attributes:
- Create a Vertex Buffer
- Upload the attributes
    - Create a transfer buffer
    - Map it to memory
    - Copy vertex data to it
    - Start a copy pass
    - Upload transfer buffer to the gpu, into the vertex buffer
- Bind the vertex buffer

You can either upload once and reuse, or upload whenever you want.
Because uploading the vbuf to the GPU requires gpu stuff, you need the command buffer.
The binding of the vbuf should be done each draw

Dont forget to clean up

# Extra Research -- The Swaapchain
The swapchain is a set of images or textures that the GPU uses to display frames
The GPU renders into one image whilst another is being shown, then the shown one is "swapped".
There can be many images ready to go, hence "chain".
Without this, youd get screentearing, and the GPU and CPU may desync.

# Lesson 4
When you have lots of shared verticies to generate more complex geometries, you might want to save space and reuse vertices. This is done using an index bufer
- Make a index array
- Make an index buffer
- Upload the index buffer - This is done in the same way that the vertex buffer is uploaded
    - Make a transfer buffer
    - Map it to memory
    - Copy data
    - Do a copy pass from the transfer buffer to the index buffer
    - This can all be done in the same pass as uploading the vertex buffer if smart
- Bind the index buffer

# Lesson 5
Here we wanted to parse in a texture, and then render it to the quad we made previously.
Used SDL3_Image to do this, which made it slightly simpler.

To use a texture on a GPU primative:
- Load the image
- Get dimensions and bytes per pixel
- Create a GPU texture
- Transfer to the GPU
(All the previous steps can be done by SDL3_Image using IMMG_LoadGPUTexture())
- Create a texture sampler
- Tell SDL in create_shader that the fragment is using a sampler
- Add the texture coordinates to the vertesies and update the vertex buffer description
- Bind the ampler to the fragment shader for the render pass

In shaders
Remember to pass the texture coordinates to the fragment shader
Remember to set the uniform and vertex data inputs in the fragment shader
Use the texture function with the sampler and the coordinates inf the fragment shader, optional tinting by multiplying the output by colours passed in.

