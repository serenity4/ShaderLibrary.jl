@testset "Scene" begin
  @testset "Camera" begin
    camera = Camera(; focal_length = 0.35, far_clipping_plane = 10)
    p = Vec3(0.4, 0.5, 1.7)
    p′ = project(p, camera)
    @test isa(p′, Vec3)
    @test camera.near_clipping_plane < -p′.z < camera.far_clipping_plane
    p.z = -camera.near_clipping_plane
    @test project(p, camera).z == 0
    p.z = -camera.far_clipping_plane
    @test project(p, camera).z == 1
    p.z = -(camera.near_clipping_plane + camera.far_clipping_plane) / 2
    @test project(p, camera).z == 0.5

    ir = @compile project(::Vec3, ::Camera)
    @test unwrap(validate(ir))
  end
end;
