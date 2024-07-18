using ShaderLibrary
using ShaderLibrary: glyph_quads, Text, linear_index, image_index, GaussianBlurDirectionalComp, GaussianBlurComp, spherical_uv_mapping, scatter_light_sources, compute_lighting_from_sources, BRDFIntegration, cubemap_to_world, world_to_cubemap
using Test
using GeometryExperiments: Point2, Point3f
using Lava
using Accessors: @set, @reset, setproperties
using SPIRV.MathFunctions
using SPIRV: @compile, validate, F, U, πF, Vec2, Vec3, unwrap
using Erosion
using OpenType
using FileIO: load, save
using SPIRV
using ColorTypes: AbstractRGBA

import GLTF

include("utils.jl")

instance, device = init(; with_validation = true)
# instance, device = init(; with_validation = true, include_gpu_assisted_validation = true)
color = color_attachment(device, [1920, 1080])
parameters = ShaderParameters(color)

@testset "ShaderLibrary.jl" begin
    include("parsing.jl")
    include("scene.jl")
    include("render.jl")
    include("environment.jl")
    include("pbr.jl")
    include("compute.jl")
end;
