using ShaderLibrary
using Test
using Lava
using Accessors: @set
using SPIRV.MathFunctions
using SPIRV: @compile, validate, F, U, Vec3, Vec2, unwrap
using OpenType
using FileIO: load, save

instance, device = init(; with_validation = true)
color = attachment_resource(device, nothing; format = RGBA{Float16}, samples = 4, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims = [1920, 1080])

@testset "ShaderLibrary.jl" begin
    include("transforms.jl")
    include("render.jl")
end;
