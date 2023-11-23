using ShaderLibrary
using ShaderLibrary: glyph_quads, Text
using Test
using GeometryExperiments: Point2, Point3f, load_mesh_gltf
using Lava
using Accessors: @set, setproperties
using SPIRV.MathFunctions
using SPIRV: @compile, validate, F, U, Vec3, Vec2, unwrap
using Erosion
using OpenType
using FileIO: load, save
using SPIRV

import GLTF

instance, device = init(; with_validation = true)
color = attachment_resource(device, nothing; name = :color_target, format = RGBA{Float16}, samples = 4, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims = [1920, 1080])
parameters = ShaderParameters(color)
include("utils.jl")

@testset "ShaderLibrary.jl" begin
    include("scene.jl")
    include("render.jl")
    # include("compute.jl")
end;
