pub const obj = struct {
    pub const ambulance_path = "assets/obj/ambulance.obj";
    pub const sedan_sports_path = "assets/obj/sedan-sports.obj";
    pub const tractor_police_path = "assets/obj/tractor-police.obj";
};

pub const shaders = struct {
    pub const vert = @embedFile("shaders/out/shader.vert.spv");
    pub const frag = @embedFile("shaders/out/shader.frag.spv");
};

pub const textures = struct {
    pub const cobblestone_path = "assets/textures/cobblestone.png";
    pub const colormap_path = "assets/textures/colormap.png";
};
