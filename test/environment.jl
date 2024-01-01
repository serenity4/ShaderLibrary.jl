@testset "Environment" begin
  images = [load(asset("cubemap", face)) for face in ("px.png", "nx.png", "py.png", "ny.png", "pz.png", "nz.png")]
  images = convert.(Matrix{RGBA{Float16}}, images)
  cubemap = CubeMap(images)
  env = Environment(device, cubemap)
  @test isa(env, Environment)
end;
