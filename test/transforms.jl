@testset "Transforms" begin
  @testset "Plane" begin
    n = zero(Vec3)
    p = Plane(n)
    @test norm(p.u) == norm(p.v) == 1
    @test Plane((1, 0, 0)) == Plane((0, 0, 1), (0, -1, 0))
    @test Plane((0, 0, 1)) == Plane((0, -1, 0), (1, 0, 0))
  end

  @testset "Rotation" begin
    rot = Rotation()
    @test iszero(rot)
    plane = Plane((1, 0, 0), (0, 1, 0))
    rot = Rotation(plane, (45F)°)
    p = Vec3(0.2, 0.2, 1.0)
    p′ = apply_rotation(p, rot)
    @test p′.z == p.z
    @test p′.xy ≈ Vec2(0, 0.2sqrt(2))
    @test apply_rotation(p, Rotation(plane, 0)) == p
    rot = Rotation(Plane(Tuple(rand(3))), 1.5)
    @test apply_rotation(p, rot) ≉ p
    @test apply_rotation(apply_rotation(p, rot), inv(rot)) ≈ p

    @test unwrap(validate(@compile apply_rotation(::Vec3, ::Rotation)))
  end

  @testset "Camera" begin
    f = 0.35
    camera = Camera(f, 0, 10, Transform())
    p = Vec3(0.4, 0.5, 1.7)
    p′ = project(p, camera)
    @test camera.near_clipping_plane < p′.z < camera.far_clipping_plane
    p.z = camera.near_clipping_plane
    @test project(p, camera).z == 0
    p.z = camera.far_clipping_plane
    @test project(p, camera).z == 1

    @test unwrap(validate(@compile project(::Vec3, ::Camera)))
  end
end;
