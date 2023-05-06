using ShaderLibrary
using Accessors: @set
using SPIRV.MathFunctions
using SPIRV: @compile, validate, F, U, Vec3, Vec2, unwrap
using Test

@testset "ShaderLibrary.jl" begin
    include("transforms.jl")
end;
