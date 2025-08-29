include("init.jl")

@testset "ShaderLibrary.jl" begin
  include("parsing.jl")
  include("scene.jl")
  include("render.jl")
  include("environment.jl")
  include("pbr.jl")
  include("compute.jl")
  include("cache.jl")
end;
