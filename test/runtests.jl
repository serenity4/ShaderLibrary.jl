using ShaderLibrary
using ShaderLibrary: glyph_quads, Text, linear_index, image_index, GaussianBlurDirectionalComp, GaussianBlurComp, spherical_uv_mapping, scatter_light_sources, compute_lighting_from_sources, BRDFIntegration, cubemap_to_world, world_to_cubemap, pixel_size
using Swizzles
using FixedPointNumbers
using Test
using Lava
using Accessors: @set, @reset, setproperties
using SPIRV.MathFunctions
using SPIRV: SPIRV, @compile, validate, F, U, πF, Vec2, Vec3, unwrap
using Erosion
using ImageTransformations: imresize
using OpenType
using FileIO: load, save
using SPIRV
using ColorTypes: AbstractRGBA
using StyledStrings: @styled_str

import GLTF

include("utils.jl")

instance, device = init(; with_validation = true, device_specific_features = [:sample_rate_shading])
# instance, device = init(; with_validation = true, include_gpu_assisted_validation = true)
color = color_attachment(device, [1920, 1080]; samples = 4)
parameters = ShaderParameters(color; color_clear = [ClearValue((0.08, 0.05, 0.1, 1.0))])

@testset "ShaderLibrary.jl" begin
  include("parsing.jl")
  include("scene.jl")
  include("render.jl")
  include("environment.jl")
  include("pbr.jl")
  include("compute.jl")
  include("cache.jl")
end;
