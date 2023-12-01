using ShaderLibrary
using ShaderLibrary: glyph_quads, Text, read_lights, read_camera
using Test
using GeometryExperiments: Point2, Point3f
using Lava
using Accessors: @set, setproperties
using SPIRV.MathFunctions
using SPIRV: @compile, validate, F, U, Vec2, Vec3, unwrap
using Erosion
using OpenType
using FileIO: load, save
using SPIRV

import GLTF

include("utils.jl")

instance, device = init(; with_validation = true)
color = attachment_resource(device, nothing; name = :color_target, format = RGBA{Float16}, samples = 4, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims = [1920, 1080])
parameters = ShaderParameters(color)

@testset "ShaderLibrary.jl" begin
    include("scene.jl")
    include("pbr.jl")
    include("render.jl")
    # include("compute.jl")
end;
