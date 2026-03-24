# SDL GPU programming

Learning to use gpu programming with SDL
Learning foundational graphics ideas and prahics apis
Learning glsl

# Dependencies
## Installed to system
- zig
- SDL3
- SDL3_Image
- glslc - for shaders

## In Assets
### textures/
- cobblestone.png
- colormap.png
### obj/
- sedan-sports.obj
- tractor-police.obj
- ambulance.obj

# Lessons
To see what I learnt, you can read [Lessons](Lessons.md), following along by commit.

# Cool Tools
All shaders can be built at runtime using `zig build shaders` or the `-Dsh` flag on any other build script. Build happens using glslc.
